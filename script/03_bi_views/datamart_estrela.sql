-- =============================================================================
-- NexUs — Data Mart (Star Schema) para ferramentas de BI
-- Dimensões: dim_tempo, dim_alimento, dim_localidade, dim_perfil, dim_empresa
-- Fatos:     fato_estoque, fato_movimento, fato_estoque_minimo, fato_pagamento, fato_cadastro
-- KPIs:      vw_kpi_cards (D1..D9 com meta e desvio) + uma view de detalhe por KPI
-- Volume:    vw_volume_tabelas (meta de >= 500 registros por tabela)
-- Estrela: fatos apontam direto para as dimensões; dimensões não se ligam entre si.
-- Chave -1 = "não informado". Nenhuma view expõe nome, e-mail, telefone ou rua.
-- Só mexe nos schemas bi e bi_hist (somente leitura sobre as tabelas do app).
-- =============================================================================
DROP SCHEMA IF EXISTS bi CASCADE;
CREATE SCHEMA bi;

-- Histórico de consumo/descarte (item_consumed / item_expired). Preenchido pelo
-- dataload BI; criado aqui também para o script rodar mesmo antes da carga.
CREATE SCHEMA IF NOT EXISTS bi_hist;
CREATE TABLE IF NOT EXISTS bi_hist.registro_estoque (
    id                 SERIAL PRIMARY KEY,
    profile_id         INTEGER NOT NULL REFERENCES profile(id) ON DELETE CASCADE,
    food_id            INTEGER NOT NULL REFERENCES food(id),
    event_type         VARCHAR(30) NOT NULL CHECK (event_type IN ('item_consumed', 'item_expired')),
    event_date         TIMESTAMP NOT NULL,
    purchase_date      TIMESTAMP NOT NULL,
    expiry_date        DATE,
    consumed_quantity  INTEGER NOT NULL DEFAULT 0 CHECK (consumed_quantity >= 0),
    discarded_quantity INTEGER NOT NULL DEFAULT 0 CHECK (discarded_quantity >= 0),
    estimated_loss     DECIMAL(10,2) NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------- DIMENSÕES
CREATE VIEW bi.dim_tempo AS
SELECT TO_CHAR(d, 'YYYYMMDD')::int AS sk_data, d::date AS data,
       EXTRACT(YEAR FROM d)::int AS ano, EXTRACT(MONTH FROM d)::int AS mes, TO_CHAR(d, 'YYYY-MM') AS ano_mes,
       EXTRACT(QUARTER FROM d)::int AS trimestre, EXTRACT(ISODOW FROM d)::int AS dia_semana,
       EXTRACT(ISODOW FROM d) IN (6, 7) AS fim_de_semana
FROM generate_series(
        LEAST((SELECT MIN(created_at)::date FROM profile), (SELECT MIN(billing_period_start) FROM payment), CURRENT_DATE),
        GREATEST((SELECT MAX(expiry_date) FROM pantry_item), (SELECT MAX(expiry_date) FROM bi_hist.registro_estoque),
                 CURRENT_DATE + 365),
        INTERVAL '1 day') AS d
UNION ALL SELECT -1, NULL, NULL, NULL, 'N/I', NULL, NULL, NULL;

CREATE VIEW bi.dim_alimento AS            -- categoria desnormalizada
SELECT f.id AS sk_alimento, f.name AS alimento, f.product_brand AS marca,
       f.package_quantity AS embalagem, f.unit_of_measure::text AS unidade,
       f.name || ' ' || COALESCE(f.product_brand, '') || ' ' || TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM f.package_quantity::text))
              || f.unit_of_measure::text AS descricao,
       c.category_name AS categoria
FROM food f JOIN category c ON c.id = f.category_id;

CREATE VIEW bi.dim_localidade AS
SELECT id AS sk_localidade, city AS cidade, state AS uf,
       CASE WHEN state IN ('AC','AP','AM','PA','RO','RR','TO') THEN 'Norte'
            WHEN state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Nordeste'
            WHEN state IN ('DF','GO','MT','MS') THEN 'Centro-Oeste'
            WHEN state IN ('ES','MG','RJ','SP') THEN 'Sudeste'
            WHEN state IN ('PR','RS','SC') THEN 'Sul'
            ELSE 'N/I' END AS regiao,
       latitude, longitude,
       (latitude BETWEEN -34 AND 5.5 AND longitude BETWEEN -74 AND -34.5) AS geo_valida
FROM address
UNION ALL SELECT -1, 'N/I', 'NI', 'N/I', NULL, NULL, FALSE;

CREATE VIEW bi.dim_perfil AS
SELECT p.id AS sk_perfil, p.type::text AS tipo, p.status::text AS status,
       (SELECT provider::text FROM auth_method a WHERE a.profile_id = p.id ORDER BY a.created_at, a.id LIMIT 1) AS login,
       TO_CHAR(p.created_at, 'YYYY-MM') AS ano_mes_cadastro,
       CASE WHEN CURRENT_DATE - p.created_at::date < 90 THEN '0-3 meses'
            WHEN CURRENT_DATE - p.created_at::date < 180 THEN '3-6 meses'
            ELSE '6+ meses' END AS tempo_de_casa,
       CASE WHEN p.email LIKE '%@bi.nexus.local' THEN 'SIMULADO_BI' ELSE 'APP' END AS origem
FROM profile p;

CREATE VIEW bi.dim_empresa AS             -- plano desnormalizado
SELECT c.id AS sk_empresa, pl.plan_name AS plano, pl.plan_price AS preco_plano, pl.store_limit AS limite_lojas,
       (SELECT COUNT(*) FROM store s WHERE s.company_id = c.id) AS qtd_lojas
FROM company c JOIN plan pl ON pl.id = c.plan_id;

-- -------------------------------------------------------------------- FATOS
CREATE VIEW bi.fato_estoque AS            -- grão: 1 item hoje na despensa
SELECT i.id AS id_item, i.food_id AS sk_alimento, i.profile_id AS sk_perfil,
       COALESCE(p.address_id, -1) AS sk_localidade,
       TO_CHAR(i.created_at, 'YYYYMMDD')::int AS sk_data_entrada,
       COALESCE(TO_CHAR(i.expiry_date, 'YYYYMMDD')::int, -1) AS sk_data_validade,
       i.quantity AS quantidade,
       (i.expiry_date IS NOT NULL)::int AS tem_validade,
       i.expiry_date - CURRENT_DATE AS dias_ate_vencer,
       i.expiry_date - i.created_at::date AS vida_util_dias,                         -- D7
       CASE WHEN i.expiry_date IS NULL THEN 'SEM_VALIDADE'
            WHEN i.expiry_date < CURRENT_DATE THEN 'VENCIDO'
            WHEN i.expiry_date <= CURRENT_DATE + 7 THEN 'VENCE_7D'
            WHEN i.expiry_date <= CURRENT_DATE + 30 THEN 'VENCE_30D'
            ELSE 'OK' END AS status_validade
FROM pantry_item i JOIN profile p ON p.id = i.profile_id;

CREATE VIEW bi.fato_movimento AS          -- grão: 1 item consumido ou descartado (histórico)
SELECT r.id AS id_movimento, r.food_id AS sk_alimento, r.profile_id AS sk_perfil,
       COALESCE(p.address_id, -1) AS sk_localidade,
       TO_CHAR(r.event_date, 'YYYYMMDD')::int AS sk_data_evento,
       TO_CHAR(r.purchase_date, 'YYYYMMDD')::int AS sk_data_compra,
       COALESCE(TO_CHAR(r.expiry_date, 'YYYYMMDD')::int, -1) AS sk_data_validade,
       r.event_type AS tipo_evento,
       (r.event_type = 'item_expired')::int AS expirado,
       (r.event_type = 'item_consumed')::int AS consumido,
       r.consumed_quantity AS qtd_consumida, r.discarded_quantity AS qtd_descartada,
       r.estimated_loss AS perda_estimada,
       r.event_date::date - r.purchase_date::date AS dias_em_casa
FROM bi_hist.registro_estoque r JOIN profile p ON p.id = r.profile_id;

CREATE VIEW bi.fato_estoque_minimo AS     -- grão: household × alimento monitorado
SELECT s.profile_id AS sk_perfil, s.food_id AS sk_alimento, COALESCE(p.address_id, -1) AS sk_localidade,
       COALESCE(e.qtd, 0) AS estoque, s.minimum_quantity AS minimo,
       (COALESCE(e.qtd, 0) < s.minimum_quantity)::int AS abaixo_minimo
FROM pantry_product_setting s
JOIN profile p ON p.id = s.profile_id
LEFT JOIN (SELECT profile_id, food_id, SUM(quantity) AS qtd FROM pantry_item GROUP BY 1, 2) e
       ON e.profile_id = s.profile_id AND e.food_id = s.food_id
WHERE s.minimum_quantity > 0;

CREATE VIEW bi.fato_pagamento AS          -- grão: 1 cobrança mensal
SELECT pg.id AS id_pagamento, pg.company_id AS sk_empresa, COALESCE(p.address_id, -1) AS sk_localidade,
       TO_CHAR(pg.billing_period_start, 'YYYYMMDD')::int AS sk_data_competencia,
       COALESCE(TO_CHAR(pg.paid_at, 'YYYYMMDD')::int, -1) AS sk_data_pagamento,
       pg.payment_status::text AS status, pg.amount AS valor,
       (pg.payment_status = 'PAID' AND pg.paid_at::date <= pg.due_date)::int AS pago_no_prazo
FROM payment pg JOIN company c ON c.id = pg.company_id JOIN profile p ON p.id = c.profile_id;

CREATE VIEW bi.fato_cadastro AS           -- grão: 1 perfil
SELECT id AS sk_perfil, COALESCE(address_id, -1) AS sk_localidade,
       TO_CHAR(created_at, 'YYYYMMDD')::int AS sk_data_cadastro, 1 AS qtd
FROM profile;

-- ----------------------------------------------------- KPIs DE DESPERDÍCIO (detalhe)
-- D1 — Taxa de desperdício = item_expired / (item_expired + item_consumed), por mês e região
CREATE VIEW bi.kpi_d1_desperdicio_mensal AS
SELECT t.ano_mes, l.regiao,
       SUM(m.expirado) AS itens_expirados, SUM(m.consumido) AS itens_consumidos,
       ROUND(100.0 * SUM(m.expirado) / NULLIF(COUNT(*), 0), 2) AS taxa_desperdicio_pct,
       SUM(m.perda_estimada) AS perda_estimada_rs
FROM bi.fato_movimento m
JOIN bi.dim_tempo t ON t.sk_data = m.sk_data_evento
JOIN bi.dim_localidade l ON l.sk_localidade = m.sk_localidade
GROUP BY GROUPING SETS ((t.ano_mes, l.regiao), (t.ano_mes), (l.regiao), ());

-- D3, D4, D8 — situação da validade dos itens hoje na despensa, por UF
CREATE VIEW bi.kpi_d3_d4_d8_validade_uf AS
SELECT l.uf, l.regiao,
       COUNT(*) AS itens, SUM(e.tem_validade) AS itens_com_validade,
       COUNT(*) FILTER (WHERE e.status_validade = 'VENCIDO') AS itens_vencidos,
       COUNT(*) FILTER (WHERE e.dias_ate_vencer BETWEEN 0 AND 7) AS itens_vencem_7d,
       COUNT(*) FILTER (WHERE e.tem_validade = 0) AS itens_sem_validade,
       ROUND(100.0 * COUNT(*) FILTER (WHERE e.status_validade = 'VENCIDO') / NULLIF(SUM(e.tem_validade), 0), 2) AS d3_vencidos_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE e.dias_ate_vencer BETWEEN 0 AND 7) / NULLIF(SUM(e.tem_validade), 0), 2) AS d4_vencem_7d_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE e.tem_validade = 0) / COUNT(*), 2) AS d8_sem_validade_pct
FROM bi.fato_estoque e JOIN bi.dim_localidade l ON l.sk_localidade = e.sk_localidade
GROUP BY ROLLUP ((l.uf, l.regiao));

-- D5 — Ranking de vencimento: DENSE_RANK por UF de (vencidos + a vencer em 30 dias)
CREATE VIEW bi.kpi_d5_ranking_vencimento_uf AS
SELECT l.uf, l.regiao,
       COUNT(*) FILTER (WHERE e.status_validade = 'VENCIDO') AS itens_vencidos,
       COUNT(*) FILTER (WHERE e.dias_ate_vencer BETWEEN 0 AND 30) AS itens_vencem_30d,
       COUNT(*) FILTER (WHERE e.dias_ate_vencer <= 30) AS itens_em_risco,
       DENSE_RANK() OVER (ORDER BY COUNT(*) FILTER (WHERE e.dias_ate_vencer <= 30) DESC) AS ranking
FROM bi.fato_estoque e JOIN bi.dim_localidade l ON l.sk_localidade = e.sk_localidade
GROUP BY l.uf, l.regiao;

-- D6 — Estoque abaixo do mínimo: households abaixo / households com mínimo configurado
CREATE VIEW bi.kpi_d6_estoque_minimo_uf AS
WITH casa AS (
    SELECT sk_perfil, MIN(sk_localidade) AS sk_localidade, MAX(abaixo_minimo) AS abaixo
    FROM bi.fato_estoque_minimo GROUP BY sk_perfil
)
SELECT l.uf, l.regiao,
       COUNT(*) AS households_com_minimo, SUM(c.abaixo) AS households_abaixo,
       ROUND(100.0 * SUM(c.abaixo) / COUNT(*), 2) AS d6_abaixo_minimo_pct
FROM casa c JOIN bi.dim_localidade l ON l.sk_localidade = c.sk_localidade
GROUP BY ROLLUP ((l.uf, l.regiao));

-- D7 — Vida útil no cadastro (dias) = expiry_date − created_at, por categoria
CREATE VIEW bi.kpi_d7_vida_util_categoria AS
SELECT a.categoria, COUNT(*) AS itens_com_validade,
       ROUND(AVG(e.vida_util_dias), 1) AS vida_util_media_dias,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY e.vida_util_dias) AS vida_util_mediana_dias,
       MIN(e.vida_util_dias) AS vida_util_min_dias, MAX(e.vida_util_dias) AS vida_util_max_dias
FROM bi.fato_estoque e JOIN bi.dim_alimento a ON a.sk_alimento = e.sk_alimento
WHERE e.tem_validade = 1
GROUP BY ROLLUP (a.categoria);

-- D9 — Índice de desperdício por categoria = expirados da categoria / households com a categoria
CREATE VIEW bi.kpi_d9_desperdicio_categoria AS
WITH uso AS (                                   -- household teve a categoria (histórico ou despensa)
    SELECT sk_perfil, sk_alimento, expirado FROM bi.fato_movimento
    UNION ALL SELECT sk_perfil, sk_alimento, 0 FROM bi.fato_estoque
)
SELECT a.categoria,
       SUM(u.expirado) AS itens_expirados,
       COUNT(DISTINCT u.sk_perfil) AS households_com_categoria,
       ROUND(SUM(u.expirado)::numeric / NULLIF(COUNT(DISTINCT u.sk_perfil), 0), 3) AS d9_indice_desperdicio,
       DENSE_RANK() OVER (ORDER BY SUM(u.expirado)::numeric / NULLIF(COUNT(DISTINCT u.sk_perfil), 0) DESC) AS ranking
FROM uso u JOIN bi.dim_alimento a ON a.sk_alimento = u.sk_alimento
GROUP BY a.categoria;

-- --------------------------------------------------------------------- CARDS
CREATE VIEW bi.vw_kpi_cards AS
WITH k (ordem, codigo, kpi, valor, unidade, meta, menor_melhor) AS (
    SELECT 1, 'D1', 'Taxa de desperdício', 100.0 * AVG(expirado), '%', 15, TRUE FROM bi.fato_movimento
    UNION ALL
    SELECT 3, 'D3', '% itens vencidos na despensa', 100.0 * AVG((status_validade = 'VENCIDO')::int), '%', 5, TRUE
      FROM bi.fato_estoque WHERE tem_validade = 1
    UNION ALL
    SELECT 4, 'D4', '% a vencer em 7 dias', 100.0 * AVG((dias_ate_vencer BETWEEN 0 AND 7)::int), '%', 10, TRUE
      FROM bi.fato_estoque WHERE tem_validade = 1
    UNION ALL
    SELECT 5, 'D5', 'Itens em risco na UF nº 1 do ranking', MAX(itens_em_risco), 'itens', NULL, TRUE
      FROM bi.kpi_d5_ranking_vencimento_uf
    UNION ALL
    SELECT 6, 'D6', 'Estoque abaixo do mínimo', d6_abaixo_minimo_pct, '%', 30, TRUE
      FROM bi.kpi_d6_estoque_minimo_uf WHERE uf IS NULL
    UNION ALL
    SELECT 7, 'D7', 'Vida útil no cadastro (média)', AVG(vida_util_dias), 'dias', NULL, FALSE
      FROM bi.fato_estoque WHERE tem_validade = 1
    UNION ALL
    SELECT 8, 'D8', '% itens sem validade', 100.0 * AVG(1 - tem_validade), '%', 10, TRUE FROM bi.fato_estoque
    UNION ALL
    SELECT 9, 'D9', 'Maior índice de desperdício por categoria', MAX(d9_indice_desperdicio), 'itens/household', NULL, TRUE
      FROM bi.kpi_d9_desperdicio_categoria
    UNION ALL
    SELECT 20, 'F1', '% inadimplência', 100.0 * AVG((status = 'OVERDUE')::int), '%', 8, TRUE
      FROM bi.fato_pagamento WHERE status IN ('PAID', 'OVERDUE')
    UNION ALL
    SELECT 21, 'F2', '% pagos no prazo', 100.0 * AVG(pago_no_prazo), '%', 90, FALSE
      FROM bi.fato_pagamento WHERE status = 'PAID'
    UNION ALL
    SELECT 22, 'U1', '% households ativos', 100.0 * AVG((status = 'ACTIVE')::int), '%', 85, FALSE
      FROM bi.dim_perfil WHERE tipo = 'HOUSEHOLD'
)
SELECT codigo, kpi, ROUND(valor, 2) AS valor, unidade, meta, ROUND(valor - meta, 2) AS desvio,
       CASE WHEN meta IS NULL THEN 'SEM_META'
            WHEN (valor <= meta) = menor_melhor THEN 'DENTRO_DA_META'
            ELSE 'FORA_DA_META' END AS situacao
FROM k ORDER BY ordem;

-- ------------------------------------------------------------- TESTE DE VOLUME
-- category e plan são tabelas de domínio (17 categorias e 3 planos fixos do produto).
-- company e store: cada empresa/loja também é um profile; com ~500 profiles no total elas
-- ficam com uma fração deles (households são a maioria, pois alimentam os KPIs D1..D9).
CREATE VIEW bi.vw_volume_tabelas AS
SELECT tabela, registros,
       CASE WHEN tabela IN ('category', 'plan') THEN 'DOMINIO_FIXO'
            WHEN registros >= 500 THEN 'OK'
            WHEN tabela IN ('company', 'store') THEN 'LIMITADO_PELOS_PROFILES'
            ELSE 'ABAIXO_DE_500' END AS situacao
FROM (VALUES
    ('address', (SELECT COUNT(*) FROM address)),
    ('auth_method', (SELECT COUNT(*) FROM auth_method)),
    ('category', (SELECT COUNT(*) FROM category)),
    ('company', (SELECT COUNT(*) FROM company)),
    ('food', (SELECT COUNT(*) FROM food)),
    ('pantry_item', (SELECT COUNT(*) FROM pantry_item)),
    ('pantry_product_setting', (SELECT COUNT(*) FROM pantry_product_setting)),
    ('payment', (SELECT COUNT(*) FROM payment)),
    ('plan', (SELECT COUNT(*) FROM plan)),
    ('profile', (SELECT COUNT(*) FROM profile)),
    ('profile_phone', (SELECT COUNT(*) FROM profile_phone)),
    ('store', (SELECT COUNT(*) FROM store)),
    ('bi_hist.registro_estoque', (SELECT COUNT(*) FROM bi_hist.registro_estoque))
) AS v (tabela, registros);
