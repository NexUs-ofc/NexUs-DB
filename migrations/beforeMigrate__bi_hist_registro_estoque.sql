-- Callback do Flyway: roda antes de cada `migrate` e não entra no histórico de versões.
--
-- A V11 converte bi_hist.registro_estoque, que nos ambientes antigos era criada fora das
-- migrations. Em um banco novo essa tabela não existia e a V11 falhava. Aqui ela é criada,
-- vazia e no layout anterior à V11, para que a V11 a converta como em qualquer ambiente.
--
-- Em bancos que já têm a tabela (em qualquer layout) os dois comandos não fazem nada.
-- Sem FKs de propósito: o callback roda antes da V1, quando profile e food ainda não
-- existem; a V11 remove essas colunas e cria a FK para pantry_item.
CREATE SCHEMA IF NOT EXISTS bi_hist;

CREATE TABLE IF NOT EXISTS bi_hist.registro_estoque (
    id SERIAL PRIMARY KEY,
    profile_id INTEGER NOT NULL,
    food_id INTEGER NOT NULL,
    event_type VARCHAR(30) NOT NULL CHECK (event_type IN ('item_consumed', 'item_expired')),
    event_date TIMESTAMP NOT NULL,
    purchase_date TIMESTAMP NOT NULL,
    expiry_date DATE,
    consumed_quantity INTEGER NOT NULL DEFAULT 0 CHECK (consumed_quantity >= 0),
    discarded_quantity INTEGER NOT NULL DEFAULT 0 CHECK (discarded_quantity >= 0),
    estimated_loss DECIMAL(10,2) NOT NULL DEFAULT 0
);
