-- =============================================================================
-- NexUs — Monitoramento: DAU (Daily Active Users)
-- Usuário = profile.id. Dia = data no fuso America/Sao_Paulo.
-- A PK (activity_date, user_id) garante 1 linha por usuário por dia: repetir o
-- registro no mesmo dia não duplica a contagem.
-- Registro automático: login (auth-api chama register_daily_activity) e
-- trigger em pantry_item (o household mexeu na despensa).
-- Pode rodar de novo quando quiser (idempotente). Fora do Flyway.
-- =============================================================================
BEGIN;

CREATE TABLE IF NOT EXISTS daily_active_users (
    activity_date DATE      NOT NULL,
    user_id       INTEGER   NOT NULL REFERENCES profile(id) ON DELETE CASCADE,
    first_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_daily_active_users PRIMARY KEY (activity_date, user_id)
);

-- Registra o usuário como ativo no dia de p_moment; mantém o primeiro acesso do dia.
-- Retorna TRUE no 1º registro do usuário no dia (xmax = 0 indica linha recém-inserida).
CREATE OR REPLACE FUNCTION register_daily_activity(
    p_user_id INTEGER,
    p_moment  TIMESTAMPTZ DEFAULT now()
) RETURNS BOOLEAN
LANGUAGE sql
AS $$
    INSERT INTO daily_active_users (activity_date, user_id, first_seen_at)
    VALUES ((p_moment AT TIME ZONE 'America/Sao_Paulo')::DATE,
            p_user_id,
            p_moment AT TIME ZONE 'America/Sao_Paulo')
    ON CONFLICT (activity_date, user_id)
    DO UPDATE SET first_seen_at = LEAST(daily_active_users.first_seen_at, EXCLUDED.first_seen_at)
    RETURNING (xmax = 0);
$$;

-- Item novo conta no dia em que entrou na despensa; alteração conta no dia de hoje.
-- created_at no futuro (dado inconsistente) conta como hoje: o DAU nunca registra um dia que ainda não chegou.
-- Opcional: uma carga em lote pode rodar SET nexus.carga_em_lote = 'on' para não contar como acesso.
CREATE OR REPLACE FUNCTION fn_dau_pantry_item() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('nexus.carga_em_lote', TRUE) = 'on' THEN
        RETURN NULL;
    END IF;
    PERFORM register_daily_activity(
        NEW.profile_id,
        CASE WHEN TG_OP = 'INSERT' THEN LEAST(NEW.created_at::TIMESTAMPTZ, now()) ELSE now() END);
    RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER trg_dau_pantry_item
    AFTER INSERT OR UPDATE ON pantry_item
    FOR EACH ROW EXECUTE FUNCTION fn_dau_pantry_item();

CREATE OR REPLACE VIEW vw_dau AS
SELECT activity_date, COUNT(*) AS dau
FROM daily_active_users
GROUP BY activity_date;

COMMIT;
