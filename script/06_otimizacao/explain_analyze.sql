-- =============================================================================
-- NexUs — Otimização: teste com EXPLAIN ANALYZE dos índices da V8
-- Mede 5 consultas do app com volume alto, SEM os índices (removidos temporariamente)
-- e COM os índices da V8, para mostrar o ganho de cada um.
--
-- NUNCA rodar no banco de produção. Use uma cópia restaurada do backup cujo nome
-- tenha "teste" (ver doc/evidencias/backup_restore.log):
--   psql -d nexus_teste -e -f script/06_otimizacao/explain_analyze.sql > doc/evidencias/explain_analyze.log 2>&1
--
-- Trava: o script para se o nome do banco não tiver "teste".
-- Além disso, tudo roda numa transação que termina em ROLLBACK: os dados de teste e
-- a remoção temporária dos índices são desfeitos no fim.
-- =============================================================================
\pset pager off

SELECT current_database() LIKE '%teste%' AS banco_de_teste \gset
\if :banco_de_teste
\else
    \echo 'ERRO: rode só em um banco de teste (o nome precisa conter "teste"). Nada foi executado.'
    \quit
\endif

\timing on

BEGIN;
SET LOCAL nexus.carga_em_lote = 'on';   -- a carga de teste não conta no DAU

-- --------------------------------------------- 1. Volume
-- 20 mil casas, 2 mil empresas com 24 mensalidades cada, 100 mil alimentos e 400 mil itens
INSERT INTO address (neighborhood, street, number, cep, city, state)
SELECT 'Bairro ' || g, 'Rua Teste ' || g, g::text, lpad(g::text, 8, '0'),
       'Cidade ' || (g % 300), (ARRAY['SP','RJ','MG','BA','PR'])[1 + g % 5]
FROM generate_series(1, 20000) g;

INSERT INTO profile (address_id, email, name, type)
SELECT id, 'Casa' || id || '@Teste.local', 'Casa teste ' || id, 'HOUSEHOLD'
FROM address WHERE street LIKE 'Rua Teste %';

INSERT INTO profile (email, name, type)
SELECT 'empresa' || g || '@teste.local', 'Empresa teste ' || g, 'COMPANY'
FROM generate_series(1, 2000) g;

INSERT INTO company (plan_id, cnpj, profile_id)
SELECT (SELECT min(id) FROM plan), lpad((90000000000000 + p.id)::text, 14, '0'), p.id
FROM profile p WHERE p.email LIKE 'empresa%@teste.local';

-- 24 meses por empresa: os antigos pagos, 2% pendentes já vencidos, o mês atual pendente (vence dia 28)
INSERT INTO payment (due_date, billing_period_start, billing_period_end, payment_status,
                     company_id, plan_id, amount, paid_at)
SELECT m.inicio + CASE WHEN m.n = 0 THEN 27 ELSE 9 END, m.inicio, (m.inicio + INTERVAL '1 month - 1 day')::date,
       CASE WHEN m.n = 0 THEN 'PENDING'
            WHEN (c.id + m.n) % 50 = 0 THEN 'PENDING'
            ELSE 'PAID' END::payment_status_enum,
       c.id, c.plan_id, 99.90,
       CASE WHEN m.n > 0 AND (c.id + m.n) % 50 <> 0 THEN m.inicio + 5 END
FROM company c
JOIN profile p ON p.id = c.profile_id AND p.email LIKE 'empresa%@teste.local'
CROSS JOIN LATERAL (
    SELECT n, (date_trunc('month', CURRENT_DATE) - n * INTERVAL '1 month')::date AS inicio
    FROM generate_series(0, 23) n
) m;

INSERT INTO food (name, category_id, product_brand, package_quantity, unit_of_measure, gtin)
SELECT (ARRAY['Arroz integral', 'Feijão carioca', 'Leite integral', 'Café torrado', 'Macarrão espaguete',
              'Azeite de oliva', 'Açúcar refinado', 'Farinha de trigo', 'Molho de tomate', 'Iogurte natural'])
       [1 + g % 10] || ' ' || g,
       (SELECT min(id) FROM category), 'Marca ' || (g % 50), 1, 'unit', '3' || lpad(g::text, 12, '0')
FROM generate_series(1, 100000) g;

CREATE TEMP TABLE casas ON COMMIT DROP AS
    SELECT row_number() OVER (ORDER BY id) AS n, id FROM profile WHERE email LIKE 'Casa%@Teste.local';
CREATE TEMP TABLE alimentos ON COMMIT DROP AS
    SELECT row_number() OVER (ORDER BY id) AS n, id FROM food WHERE gtin LIKE '3%' AND product_brand LIKE 'Marca %';

INSERT INTO pantry_item (food_id, profile_id, quantity, expiry_date, created_at)
SELECT a.id, c.id, 1 + g % 5,
       CASE WHEN g % 20 = 0 THEN NULL ELSE CURRENT_DATE - 90 + (g % 400) END,
       now() - (g % 365) * INTERVAL '1 day'
FROM generate_series(1, 400000) g
JOIN casas c ON c.n = 1 + g % 20000
JOIN alimentos a ON a.n = 1 + (g * 7) % 100000;

ANALYZE address; ANALYZE profile; ANALYZE company; ANALYZE payment; ANALYZE food; ANALYZE pantry_item;

SELECT (SELECT count(*) FROM pantry_item) AS itens_despensa, (SELECT count(*) FROM profile) AS perfis,
       (SELECT count(*) FROM payment) AS pagamentos, (SELECT count(*) FROM food) AS alimentos;

-- Valores usados nas consultas
SELECT max(id) AS casa FROM profile WHERE email LIKE 'Casa%@Teste.local' \gset
SELECT email AS email_login FROM profile WHERE id = :casa \gset

-- --------------------------------------------- 2. SEM os índices da V8 (removidos até o ROLLBACK TO SAVEPOINT)
SAVEPOINT sem_indices;
DROP INDEX idx_pantry_expiry_id, idx_pantry_profile_expiry_id, idx_pantry_profile_food_expiry,
           idx_payment_company_due, idx_payment_company_status_due, idx_payment_pending_due,
           idx_food_name_lower_trgm, idx_food_name, idx_profile_email_lower;
ANALYZE pantry_item; ANALYZE payment; ANALYZE food; ANALYZE profile;

\echo '=== Q1 SEM índice: vencimentos dos próximos 7 dias (fn_get_expiring_products)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT profile_id, id, expiry_date FROM pantry_item
WHERE expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
ORDER BY expiry_date, id;

\echo '=== Q2 SEM índice: despensa de uma casa ordenada por validade (tela principal do app)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pantry_item WHERE profile_id = :casa
ORDER BY expiry_date ASC NULLS LAST, id DESC;

\echo '=== Q3 SEM índice: mensalidades pendentes vencidas (sp_update_overdue_payments)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, company_id, due_date FROM payment
WHERE payment_status = 'PENDING' AND due_date < CURRENT_DATE;

\echo '=== Q4 SEM índice: busca de alimento por trecho do nome (busca do app)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name FROM food WHERE lower(name) LIKE '%arroz integral 49%';

\echo '=== Q5 SEM índice: login por e-mail sem diferenciar maiúsculas'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, type, status FROM profile WHERE lower(email) = lower(:'email_login');

ROLLBACK TO SAVEPOINT sem_indices;   -- os índices da V8 voltam

-- --------------------------------------------- 3. COM os índices da V8
ANALYZE pantry_item; ANALYZE payment; ANALYZE food; ANALYZE profile;

\echo '=== Q1 COM idx_pantry_expiry_id'
EXPLAIN (ANALYZE, BUFFERS)
SELECT profile_id, id, expiry_date FROM pantry_item
WHERE expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
ORDER BY expiry_date, id;

\echo '=== Q2 COM idx_pantry_profile_expiry_id'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pantry_item WHERE profile_id = :casa
ORDER BY expiry_date ASC NULLS LAST, id DESC;

\echo '=== Q3 COM idx_payment_pending_due'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, company_id, due_date FROM payment
WHERE payment_status = 'PENDING' AND due_date < CURRENT_DATE;

\echo '=== Q4 COM idx_food_name_lower_trgm'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name FROM food WHERE lower(name) LIKE '%arroz integral 49%';

\echo '=== Q5 COM idx_profile_email_lower'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, type, status FROM profile WHERE lower(email) = lower(:'email_login');

-- --------------------------------------------- 4. Desfaz tudo
ROLLBACK;
SELECT count(*) AS itens_despensa_apos_rollback FROM pantry_item;
SELECT count(*) AS indices_v8_presentes FROM pg_indexes
WHERE indexname IN ('idx_pantry_expiry_id', 'idx_pantry_profile_expiry_id', 'idx_payment_pending_due',
                    'idx_food_name_lower_trgm', 'idx_profile_email_lower');
