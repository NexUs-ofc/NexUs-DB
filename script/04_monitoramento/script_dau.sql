-- =============================================================================
-- NexUs-DB | Monitoramento | DAU (Daily Active Users)
-- -----------------------------------------------------------------------------
-- Registra, no máximo, uma linha por usuário (profile) por dia em que ele
-- acessa o app ou faz login. A regra vive no banco (função + UPSERT), seguindo
-- o padrão do projeto (regras em funções no banco). Para registrar um acesso:
--     SELECT register_daily_activity(<profile_id>);
-- É idempotente: pode ser executado mais de uma vez sem erro nem perda de dados.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Tabela
-- -----------------------------------------------------------------------------
-- user_id = profile.id (o "usuário" do NexUs é o profile).
-- activity_date é o dia no fuso de negócio (America/Sao_Paulo), não em UTC:
-- um acesso às 22h de Brasília conta para o mesmo dia, e não para o seguinte.
CREATE TABLE IF NOT EXISTS daily_active_users (
    activity_date DATE      NOT NULL,
    user_id       INTEGER   NOT NULL REFERENCES profile(id) ON DELETE CASCADE,
    first_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_daily_active_users PRIMARY KEY (activity_date, user_id)
);

-- A PK começa por activity_date (boa para "DAU do dia X").
-- Este índice atende consultas por usuário e o ON DELETE CASCADE de profile.
CREATE INDEX IF NOT EXISTS idx_daily_active_users_user_id
    ON daily_active_users (user_id);

COMMENT ON TABLE daily_active_users IS
    'Uma linha por usuário (profile) ativo por dia. Alimentada por register_daily_activity().';
COMMENT ON COLUMN daily_active_users.activity_date IS
    'Dia da atividade no fuso America/Sao_Paulo.';
COMMENT ON COLUMN daily_active_users.first_seen_at IS
    'Momento do primeiro acesso/login do usuário naquele dia.';

-- -----------------------------------------------------------------------------
-- 2. Função de registro (UPSERT)
-- -----------------------------------------------------------------------------
-- Chamar a cada acesso ou login. Retorna TRUE no primeiro acesso do dia e
-- FALSE nos seguintes (o ON CONFLICT DO NOTHING ignora a duplicata).
-- É seguro sob concorrência: dois logins simultâneos geram uma única linha.
--
-- p_activity_date é opcional; informe-o apenas para backfill/testes.
CREATE OR REPLACE FUNCTION register_daily_activity(
    p_user_id       INTEGER,
    p_activity_date DATE DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::DATE
) RETURNS BOOLEAN AS $$
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'user_id is required to register daily activity';
    END IF;

    INSERT INTO daily_active_users (activity_date, user_id)
    VALUES (p_activity_date, p_user_id)
    ON CONFLICT (activity_date, user_id) DO NOTHING;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION register_daily_activity(INTEGER, DATE) IS
    'Registra o acesso/login do usuário no DAU (INSERT ... ON CONFLICT DO NOTHING). TRUE = primeiro acesso do dia.';

-- -----------------------------------------------------------------------------
-- 3. View de consulta (métrica DAU por dia)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_dau AS
SELECT
    activity_date,
    COUNT(*) AS dau
FROM daily_active_users
GROUP BY activity_date;

COMMIT;

-- =============================================================================
-- Testes rápidos (opcional — rodar à parte, depois do script acima)
-- =============================================================================
-- SELECT register_daily_activity(1);   -- TRUE  (primeiro acesso do dia)
-- SELECT register_daily_activity(1);   -- FALSE (já registrado hoje)
-- SELECT * FROM daily_active_users ORDER BY activity_date DESC, user_id;
-- SELECT * FROM vw_dau ORDER BY activity_date DESC;
--
-- DAU por tipo de perfil nos últimos 30 dias:
-- SELECT d.activity_date, p.type, COUNT(*) AS dau
--   FROM daily_active_users d
--   JOIN profile p ON p.id = d.user_id
--  WHERE d.activity_date >= CURRENT_DATE - 30
--  GROUP BY d.activity_date, p.type
--  ORDER BY d.activity_date DESC, p.type;
