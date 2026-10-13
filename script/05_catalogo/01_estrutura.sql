-- =============================================================================
-- NexUs — Catálogo de metadados (1/3): estrutura
-- Recria o schema `catalogo` do zero: tabelas catalogo.objeto e catalogo.coluna
-- e a view catalogo.vw_dicionario_dados. Apaga os dados do catálogo, então rode
-- 02 e 03 em seguida. Não altera nenhuma tabela do app.
-- =============================================================================
BEGIN;

DROP SCHEMA IF EXISTS catalogo CASCADE;
CREATE SCHEMA catalogo;
COMMENT ON SCHEMA catalogo IS 'Catálogo de metadados do NexUs: descrição, tipo, chaves e classificação LGPD de cada dado.';

CREATE TABLE catalogo.objeto (
    id             SERIAL PRIMARY KEY,
    banco          VARCHAR(20)  NOT NULL CHECK (banco IN ('POSTGRESQL', 'MONGODB')),
    schema_nome    VARCHAR(63),
    objeto_nome    VARCHAR(63)  NOT NULL,
    tipo_objeto    VARCHAR(20)  NOT NULL CHECK (tipo_objeto IN ('TABELA', 'VIEW', 'COLLECTION')),
    descricao      TEXT         NOT NULL,
    CONSTRAINT uq_catalogo_objeto UNIQUE (banco, schema_nome, objeto_nome),
    CONSTRAINT ck_catalogo_objeto_schema CHECK ((banco = 'POSTGRESQL') = (schema_nome IS NOT NULL))
);

CREATE TABLE catalogo.coluna (
    id                  SERIAL PRIMARY KEY,
    objeto_id           INTEGER      NOT NULL REFERENCES catalogo.objeto(id) ON DELETE CASCADE,
    coluna_nome         VARCHAR(100) NOT NULL,
    posicao             INTEGER      NOT NULL CHECK (posicao > 0),
    tipo_dado           VARCHAR(100) NOT NULL,
    aceita_nulo         BOOLEAN      NOT NULL,
    valor_padrao        TEXT,
    chave               VARCHAR(20),
    referencia          VARCHAR(100),
    classificacao_lgpd  VARCHAR(10)  NOT NULL DEFAULT 'INTERNO'
                        CHECK (classificacao_lgpd IN ('INTERNO', 'PESSOAL', 'SENSIVEL', 'SIGILOSO')),
    descricao           TEXT         NOT NULL,
    CONSTRAINT uq_catalogo_coluna UNIQUE (objeto_id, coluna_nome),
    CONSTRAINT uq_catalogo_coluna_posicao UNIQUE (objeto_id, posicao)
);

COMMENT ON TABLE catalogo.objeto IS 'Tabelas, views e collections do NexUs.';
COMMENT ON COLUMN catalogo.objeto.id IS 'Identificador do objeto no catálogo.';
COMMENT ON COLUMN catalogo.objeto.banco IS 'POSTGRESQL ou MONGODB.';
COMMENT ON COLUMN catalogo.objeto.schema_nome IS 'Schema do PostgreSQL (public, bi, bi_hist); nulo para MongoDB.';
COMMENT ON COLUMN catalogo.objeto.objeto_nome IS 'Nome da tabela, view ou collection.';
COMMENT ON COLUMN catalogo.objeto.tipo_objeto IS 'TABELA, VIEW ou COLLECTION.';
COMMENT ON COLUMN catalogo.objeto.descricao IS 'O que o objeto guarda (e o grão, nas tabelas fato).';

COMMENT ON TABLE catalogo.coluna IS 'Colunas (PostgreSQL) e campos (MongoDB) de cada objeto do catálogo.';
COMMENT ON COLUMN catalogo.coluna.id IS 'Identificador da coluna no catálogo.';
COMMENT ON COLUMN catalogo.coluna.objeto_id IS 'Objeto dono da coluna (FK catalogo.objeto.id).';
COMMENT ON COLUMN catalogo.coluna.coluna_nome IS 'Nome da coluna; no MongoDB, campos aninhados usam ponto (ex.: items.food_id).';
COMMENT ON COLUMN catalogo.coluna.posicao IS 'Ordem da coluna no objeto.';
COMMENT ON COLUMN catalogo.coluna.tipo_dado IS 'Tipo do dado no banco de origem.';
COMMENT ON COLUMN catalogo.coluna.aceita_nulo IS 'Verdadeiro se a coluna aceita nulo (MongoDB: campo opcional).';
COMMENT ON COLUMN catalogo.coluna.valor_padrao IS 'Valor padrão (DEFAULT) da coluna.';
COMMENT ON COLUMN catalogo.coluna.chave IS 'PK, FK e/ou UK.';
COMMENT ON COLUMN catalogo.coluna.referencia IS 'Destino da FK (tabela.coluna). No MongoDB, referência lógica sem FK.';
COMMENT ON COLUMN catalogo.coluna.classificacao_lgpd IS 'INTERNO, PESSOAL (identifica pessoa), SENSIVEL (saúde/religião) ou SIGILOSO (credencial).';
COMMENT ON COLUMN catalogo.coluna.descricao IS 'Significado da coluna.';

-- Dicionário completo: uma linha por coluna, com o objeto dono.
CREATE VIEW catalogo.vw_dicionario_dados AS
SELECT o.banco, o.schema_nome, o.objeto_nome, o.tipo_objeto, o.descricao AS descricao_objeto,
       c.posicao, c.coluna_nome, c.tipo_dado, c.aceita_nulo, c.valor_padrao, c.chave, c.referencia,
       c.classificacao_lgpd, c.descricao AS descricao_coluna
FROM catalogo.objeto o
JOIN catalogo.coluna c ON c.objeto_id = o.id;

COMMENT ON VIEW catalogo.vw_dicionario_dados IS 'Dicionário de dados completo: uma linha por coluna, com o objeto dono.';

COMMIT;
