-- V13 — correções de integridade, auditoria e cobrança.
--
-- 1. Histórico de estoque acompanha a exclusão do lote (ON DELETE CASCADE).
-- 2. Logs de auditoria só são gravados pelos triggers e com dados sensíveis mascarados.
-- 3. O job de inadimplência só reativa perfis que ele mesmo bloqueou (billing_block).
-- 4. fn_get_items_below_minimum valida o parâmetro como as demais rotinas da V8.

-- -------------------------------------------------------------------------------------------
-- 1. bi_hist.registro_estoque: RESTRICT -> CASCADE
-- Com RESTRICT, excluir um perfil com histórico falhava: profile -> pantry_item é CASCADE,
-- mas o histórico bloqueava a exclusão do lote. O histórico pertence ao lote e sai com ele.
DO $$
DECLARE
    v_fk TEXT;
BEGIN
    SELECT c.conname INTO v_fk
    FROM pg_constraint c
    WHERE c.conrelid = 'bi_hist.registro_estoque'::regclass
      AND c.confrelid = 'public.pantry_item'::regclass
      AND c.contype = 'f';

    IF v_fk IS NOT NULL THEN
        EXECUTE format('ALTER TABLE bi_hist.registro_estoque DROP CONSTRAINT %I', v_fk);
    END IF;
END;
$$;

ALTER TABLE bi_hist.registro_estoque
    ADD CONSTRAINT registro_estoque_pantry_item_id_fkey
    FOREIGN KEY (pantry_item_id) REFERENCES public.pantry_item(id) ON DELETE CASCADE;

-- -------------------------------------------------------------------------------------------
-- 2a. Dados sensíveis não vão para o log em claro.
-- O catálogo classifica profile.dietary_restrictions como SENSIVEL ("nunca vai para logs").
-- No log fica só o hash MD5 do valor: dá para saber que mudou, não o que é.
CREATE OR REPLACE FUNCTION auditoria.fn_mascarar(p_dados JSONB) RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_dados ? 'dietary_restrictions'
            THEN jsonb_set(p_dados, '{dietary_restrictions}',
                           to_jsonb('md5:' || md5((p_dados -> 'dietary_restrictions')::text)))
        ELSE p_dados
    END;
$$;

CREATE OR REPLACE FUNCTION auditoria.fn_registrar_alteracao() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_antigo JSONB;
    v_novo   JSONB;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_antigo := auditoria.fn_mascarar(to_jsonb(OLD));
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_novo := auditoria.fn_mascarar(to_jsonb(NEW));
    END IF;

    EXECUTE format(
        'INSERT INTO auditoria.%I (tabela, operacao, registro_id, dados_antigos, dados_novos, usuario)
         VALUES ($1, $2, $3, $4, $5, $6)',
        'log_' || TG_TABLE_NAME)
    USING TG_TABLE_NAME, TG_OP, (COALESCE(v_novo, v_antigo) ->> 'id')::INTEGER,
          v_antigo, v_novo, CURRENT_USER;

    RETURN NULL;  -- trigger AFTER: o retorno é ignorado
END;
$$;

-- Logs já gravados antes da V13 também deixam de guardar o valor em claro.
UPDATE auditoria.log_profile
SET dados_antigos = auditoria.fn_mascarar(dados_antigos),
    dados_novos   = auditoria.fn_mascarar(dados_novos)
WHERE dados_antigos ? 'dietary_restrictions' OR dados_novos ? 'dietary_restrictions';

-- 2b. Ninguém grava log "à mão".
-- O usuário do serviço precisa de INSERT nas filhas para o trigger funcionar, e com isso
-- podia inserir logs falsos (outro usuário, outra data). Este trigger recusa INSERT que
-- não venha de um trigger (pg_trigger_depth() >= 2: o trigger auditado + este), recusa
-- qualquer INSERT direto na tabela pai e sobrescreve usuário e horário com os reais.
CREATE OR REPLACE FUNCTION auditoria.fn_proteger_log() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_TABLE_NAME = 'log_alteracao' OR pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'auditoria.%: logs só podem ser gravados pelos triggers de auditoria', TG_TABLE_NAME
            USING ERRCODE = '42501';
    END IF;

    NEW.usuario := CURRENT_USER;
    NEW.alterado_em := clock_timestamp();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_proteger_log_alteracao
    BEFORE INSERT ON auditoria.log_alteracao
    FOR EACH ROW EXECUTE FUNCTION auditoria.fn_proteger_log();

CREATE OR REPLACE TRIGGER trg_proteger_log_profile
    BEFORE INSERT ON auditoria.log_profile
    FOR EACH ROW EXECUTE FUNCTION auditoria.fn_proteger_log();

CREATE OR REPLACE TRIGGER trg_proteger_log_payment
    BEFORE INSERT ON auditoria.log_payment
    FOR EACH ROW EXECUTE FUNCTION auditoria.fn_proteger_log();

-- Log não se altera nem se apaga: só o dono do schema (retenção) pode.
REVOKE UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA auditoria FROM PUBLIC;

DO $$
DECLARE
    v_grant RECORD;
BEGIN
    FOR v_grant IN
        SELECT DISTINCT g.grantee, g.table_name
        FROM information_schema.role_table_grants g
        JOIN pg_class c ON c.relname = g.table_name
        JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = g.table_schema
        WHERE g.table_schema = 'auditoria'
          AND g.privilege_type IN ('UPDATE', 'DELETE', 'TRUNCATE')
          AND g.grantee <> pg_get_userbyid(c.relowner)
          AND g.grantee <> 'PUBLIC'
    LOOP
        EXECUTE format('REVOKE UPDATE, DELETE, TRUNCATE ON auditoria.%I FROM %I',
                       v_grant.table_name, v_grant.grantee);
    END LOOP;
END;
$$;

-- -------------------------------------------------------------------------------------------
-- 3. Bloqueio por inadimplência registrado.
-- Antes, sp_update_overdue_payments reativava qualquer empresa BLOCKED sem pendência,
-- inclusive uma bloqueada manualmente por outro motivo. Agora só reativa quem está aqui.
CREATE TABLE IF NOT EXISTS billing_block (
    profile_id INTEGER PRIMARY KEY REFERENCES profile(id) ON DELETE CASCADE,
    company_id INTEGER NOT NULL REFERENCES company(id) ON DELETE CASCADE,
    blocked_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_billing_block_company
    ON billing_block (company_id);

COMMENT ON TABLE billing_block IS
    'Perfis (empresa e lojas) bloqueados por inadimplência pelo sp_update_overdue_payments. Bloqueio manual não entra aqui.';

-- Bloqueios existentes que têm inadimplência são tratados como bloqueio por cobrança.
INSERT INTO billing_block (profile_id, company_id)
SELECT c.profile_id, c.id
FROM company c
JOIN profile pr ON pr.id = c.profile_id
WHERE pr.status = 'BLOCKED'
  AND EXISTS (SELECT 1 FROM payment pa WHERE pa.company_id = c.id AND pa.payment_status = 'OVERDUE')
UNION ALL
SELECT s.profile_id, s.company_id
FROM store s
JOIN profile sp ON sp.id = s.profile_id
WHERE sp.status = 'BLOCKED'
  AND EXISTS (SELECT 1 FROM payment pa WHERE pa.company_id = s.company_id AND pa.payment_status = 'OVERDUE')
ON CONFLICT (profile_id) DO NOTHING;

CREATE OR REPLACE PROCEDURE sp_update_overdue_payments(
    p_grace_days INTEGER DEFAULT 0,
    INOUT p_overdue_count INTEGER DEFAULT NULL,
    INOUT p_blocked_count INTEGER DEFAULT NULL,
    INOUT p_unblocked_count INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_grace_days IS NULL OR p_grace_days < 0 THEN
        RAISE EXCEPTION 'A tolerância deve ser um número de dias não negativo: %', p_grace_days
            USING ERRCODE = '22023';
    END IF;

    UPDATE payment
    SET payment_status = 'OVERDUE', updated_at = CURRENT_TIMESTAMP
    WHERE payment_status = 'PENDING'
      AND due_date < CURRENT_DATE - p_grace_days;
    GET DIAGNOSTICS p_overdue_count = ROW_COUNT;

    -- Bloqueia empresa e lojas ACTIVE com pendência OVERDUE e registra o motivo.
    WITH defaulters AS (
        SELECT c.id AS company_id, c.profile_id
        FROM company c
        JOIN profile pr ON pr.id = c.profile_id
        WHERE pr.status IN ('ACTIVE', 'BLOCKED')
          AND EXISTS (
              SELECT 1 FROM payment pa
              WHERE pa.company_id = c.id AND pa.payment_status = 'OVERDUE'
          )
    ), blocked_stores AS (
        UPDATE profile sp
        SET status = 'BLOCKED'
        FROM store s
        JOIN defaulters d ON d.company_id = s.company_id
        WHERE sp.id = s.profile_id AND sp.status = 'ACTIVE'
        RETURNING sp.id AS profile_id, s.company_id
    ), blocked_companies AS (
        UPDATE profile pr
        SET status = 'BLOCKED'
        FROM defaulters d
        WHERE pr.id = d.profile_id AND pr.status = 'ACTIVE'
        RETURNING pr.id AS profile_id, d.company_id
    ), registered AS (
        INSERT INTO billing_block (profile_id, company_id)
        SELECT profile_id, company_id FROM blocked_stores
        UNION ALL
        SELECT profile_id, company_id FROM blocked_companies
        ON CONFLICT (profile_id) DO NOTHING
        RETURNING 1
    )
    SELECT COUNT(*) INTO p_blocked_count FROM blocked_companies;

    -- Reativa só os perfis bloqueados por cobrança cuja empresa não tem mais OVERDUE.
    -- Perfis que mudaram de status depois do bloqueio (ex.: INACTIVE) só saem do registro.
    WITH released AS (
        DELETE FROM billing_block b
        WHERE NOT EXISTS (
            SELECT 1 FROM payment pa
            WHERE pa.company_id = b.company_id AND pa.payment_status = 'OVERDUE'
        )
        RETURNING b.profile_id
    ), reactivated AS (
        UPDATE profile p
        SET status = 'ACTIVE'
        FROM released r
        WHERE p.id = r.profile_id AND p.status = 'BLOCKED'
        RETURNING p.type
    )
    SELECT COUNT(*) FILTER (WHERE type = 'COMPANY') INTO p_unblocked_count FROM reactivated;
END;
$$;

-- -------------------------------------------------------------------------------------------
-- 4. fn_get_items_below_minimum: mesmo contrato, agora com validação do parâmetro.
CREATE OR REPLACE FUNCTION fn_get_items_below_minimum(
    p_profile_id INTEGER DEFAULT NULL
)
RETURNS TABLE (
    profile_id INTEGER,
    food_id INTEGER,
    food_name VARCHAR,
    minimum_quantity INTEGER,
    current_quantity INTEGER,
    missing_quantity INTEGER
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_profile_id IS NOT NULL AND p_profile_id <= 0 THEN
        RAISE EXCEPTION 'Perfil inválido: %', p_profile_id
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT s.profile_id,
           s.food_id,
           f.name,
           s.minimum_quantity,
           COALESCE(stock.total, 0)::INTEGER,
           (s.minimum_quantity - COALESCE(stock.total, 0))::INTEGER
    FROM pantry_product_setting s
    JOIN food f ON f.id = s.food_id
    LEFT JOIN (
        SELECT pi.profile_id, pi.food_id, SUM(pi.quantity) AS total
        FROM pantry_item pi
        WHERE (p_profile_id IS NULL OR pi.profile_id = p_profile_id)
          AND (pi.expiry_date IS NULL OR pi.expiry_date >= CURRENT_DATE)
        GROUP BY pi.profile_id, pi.food_id
    ) stock ON stock.profile_id = s.profile_id AND stock.food_id = s.food_id
    WHERE (p_profile_id IS NULL OR s.profile_id = p_profile_id)
      AND COALESCE(stock.total, 0) < s.minimum_quantity
    ORDER BY s.profile_id,
             (s.minimum_quantity - COALESCE(stock.total, 0)) DESC,
             f.name;
END;
$$;
