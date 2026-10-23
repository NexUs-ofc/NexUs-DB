-- Auditoria de profile e payment: registra OLD, NEW, TG_OP e CURRENT_USER.
-- Herança de tabelas: auditoria.log_alteracao é a tabela pai e cada tabela
-- auditada tem uma filha (log_profile, log_payment). Consultar a pai retorna
-- todos os logs; cada filha pode ter índices e retenção próprios.
CREATE SCHEMA IF NOT EXISTS auditoria;

CREATE TABLE IF NOT EXISTS auditoria.log_alteracao (
    id            BIGSERIAL,
    tabela        VARCHAR(63) NOT NULL,
    operacao      VARCHAR(6)  NOT NULL CHECK (operacao IN ('INSERT', 'UPDATE', 'DELETE')),
    registro_id   INTEGER,
    dados_antigos JSONB,
    dados_novos   JSONB,
    usuario       VARCHAR(63) NOT NULL,
    alterado_em   TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- A PK não é herdada (colunas, defaults e CHECKs são), por isso cada filha declara a sua.
CREATE TABLE IF NOT EXISTS auditoria.log_profile (
    PRIMARY KEY (id)
) INHERITS (auditoria.log_alteracao);

CREATE TABLE IF NOT EXISTS auditoria.log_payment (
    PRIMARY KEY (id)
) INHERITS (auditoria.log_alteracao);

-- Função genérica: grava na filha log_<tabela>. OLD é nulo no INSERT e NEW é nulo no DELETE.
CREATE OR REPLACE FUNCTION auditoria.fn_registrar_alteracao() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_antigo JSONB;
    v_novo   JSONB;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_antigo := to_jsonb(OLD);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_novo := to_jsonb(NEW);
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

CREATE OR REPLACE TRIGGER trg_audit_profile
    AFTER INSERT OR UPDATE OR DELETE ON profile
    FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar_alteracao();

CREATE OR REPLACE TRIGGER trg_audit_payment
    AFTER INSERT OR UPDATE OR DELETE ON payment
    FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar_alteracao();
