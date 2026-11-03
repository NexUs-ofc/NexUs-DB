-- Databricks notebook source
-- 01 · Ingestão Bronze: views bi.* do NexUs (Neon, via nexus_pg) -> workspace.bronze
-- Documentação: databricks/ingestao/README.md

-- COMMAND ----------

-- "Hoje" no fuso de Brasília (o Neon está em GMT e viraria o dia 3 h antes)
SET TIME ZONE 'America/Sao_Paulo';
DECLARE OR REPLACE VARIABLE data_ref DATE DEFAULT current_date();
SELECT data_ref AS data_referencia, current_timestamp() AS agora_brasilia;

-- COMMAND ----------

-- Schemas da arquitetura medalhão. Silver e Gold também são criados aqui porque os arquivos
-- do ETL pipeline só aceitam definições de tabelas/views, não CREATE SCHEMA.
CREATE SCHEMA IF NOT EXISTS workspace.bronze COMMENT 'Dados brutos: snapshots diários das views bi.* do NexUs';
CREATE SCHEMA IF NOT EXISTS workspace.silver COMMENT 'Dados tratados: tipos, limpeza, regras de qualidade';
CREATE SCHEMA IF NOT EXISTS workspace.gold   COMMENT 'Dados de negócio: star schema, KPIs e histórico';

-- COMMAND ----------

-- dim_alimento: produto, marca, embalagem, unidade, descrição e categoria
CREATE TABLE IF NOT EXISTS workspace.bronze.dim_alimento
COMMENT 'Snapshot diário de nexus_pg.bi.dim_alimento'
AS SELECT *, CAST(NULL AS DATE) AS _data_referencia, CAST(NULL AS TIMESTAMP) AS _ingerido_em, CAST(NULL AS STRING) AS _origem
   FROM nexus_pg.bi.dim_alimento WHERE 1 = 0;

DELETE FROM workspace.bronze.dim_alimento WHERE _data_referencia = data_ref;

INSERT INTO workspace.bronze.dim_alimento
SELECT *, data_ref, current_timestamp(), 'nexus_pg.bi.dim_alimento' FROM nexus_pg.bi.dim_alimento;

-- COMMAND ----------

-- dim_localidade: SÓ cidade, UF e região. Latitude/longitude do endereço não são trazidas
-- (localização da casa = dado pessoal; o mapa usa coordenadas da UF, definidas na Silver)
CREATE TABLE IF NOT EXISTS workspace.bronze.dim_localidade
COMMENT 'Snapshot diário de nexus_pg.bi.dim_localidade (sem latitude/longitude)'
AS SELECT sk_localidade, cidade, uf, regiao,
          CAST(NULL AS DATE) AS _data_referencia, CAST(NULL AS TIMESTAMP) AS _ingerido_em, CAST(NULL AS STRING) AS _origem
   FROM nexus_pg.bi.dim_localidade WHERE 1 = 0;

DELETE FROM workspace.bronze.dim_localidade WHERE _data_referencia = data_ref;

INSERT INTO workspace.bronze.dim_localidade
SELECT sk_localidade, cidade, uf, regiao, data_ref, current_timestamp(), 'nexus_pg.bi.dim_localidade'
FROM nexus_pg.bi.dim_localidade;

-- COMMAND ----------

-- dim_perfil: tipo, status, login, mês de cadastro, tempo de casa e origem (APP / SIMULADO_BI)
CREATE TABLE IF NOT EXISTS workspace.bronze.dim_perfil
COMMENT 'Snapshot diário de nexus_pg.bi.dim_perfil'
AS SELECT *, CAST(NULL AS DATE) AS _data_referencia, CAST(NULL AS TIMESTAMP) AS _ingerido_em, CAST(NULL AS STRING) AS _origem
   FROM nexus_pg.bi.dim_perfil WHERE 1 = 0;

DELETE FROM workspace.bronze.dim_perfil WHERE _data_referencia = data_ref;

INSERT INTO workspace.bronze.dim_perfil
SELECT *, data_ref, current_timestamp(), 'nexus_pg.bi.dim_perfil' FROM nexus_pg.bi.dim_perfil;

-- COMMAND ----------

-- fato_estoque: 1 linha = 1 lote hoje na despensa (D3, D4, D5, D7, D8)
CREATE TABLE IF NOT EXISTS workspace.bronze.fato_estoque
COMMENT 'Snapshot diário de nexus_pg.bi.fato_estoque'
AS SELECT *, CAST(NULL AS DATE) AS _data_referencia, CAST(NULL AS TIMESTAMP) AS _ingerido_em, CAST(NULL AS STRING) AS _origem
   FROM nexus_pg.bi.fato_estoque WHERE 1 = 0;

DELETE FROM workspace.bronze.fato_estoque WHERE _data_referencia = data_ref;

INSERT INTO workspace.bronze.fato_estoque
SELECT *, data_ref, current_timestamp(), 'nexus_pg.bi.fato_estoque' FROM nexus_pg.bi.fato_estoque;

-- COMMAND ----------

-- fato_movimento: 1 linha = 1 item consumido ou descartado vencido (D1, D9)
CREATE TABLE IF NOT EXISTS workspace.bronze.fato_movimento
COMMENT 'Snapshot diário de nexus_pg.bi.fato_movimento'
AS SELECT *, CAST(NULL AS DATE) AS _data_referencia, CAST(NULL AS TIMESTAMP) AS _ingerido_em, CAST(NULL AS STRING) AS _origem
   FROM nexus_pg.bi.fato_movimento WHERE 1 = 0;

DELETE FROM workspace.bronze.fato_movimento WHERE _data_referencia = data_ref;

INSERT INTO workspace.bronze.fato_movimento
SELECT *, data_ref, current_timestamp(), 'nexus_pg.bi.fato_movimento' FROM nexus_pg.bi.fato_movimento;

-- COMMAND ----------

-- fato_estoque_minimo: 1 linha = household x alimento com mínimo > 0 (D6)
CREATE TABLE IF NOT EXISTS workspace.bronze.fato_estoque_minimo
COMMENT 'Snapshot diário de nexus_pg.bi.fato_estoque_minimo'
AS SELECT *, CAST(NULL AS DATE) AS _data_referencia, CAST(NULL AS TIMESTAMP) AS _ingerido_em, CAST(NULL AS STRING) AS _origem
   FROM nexus_pg.bi.fato_estoque_minimo WHERE 1 = 0;

DELETE FROM workspace.bronze.fato_estoque_minimo WHERE _data_referencia = data_ref;

INSERT INTO workspace.bronze.fato_estoque_minimo
SELECT *, data_ref, current_timestamp(), 'nexus_pg.bi.fato_estoque_minimo' FROM nexus_pg.bi.fato_estoque_minimo;

-- COMMAND ----------

CREATE TABLE IF NOT EXISTS workspace.bronze.vw_kpi_cards
COMMENT 'Snapshot diário de nexus_pg.bi.vw_kpi_cards (KPIs calculados pelo banco, data GMT do Neon)'
AS SELECT *, CAST(NULL AS DATE) AS _data_referencia, CAST(NULL AS TIMESTAMP) AS _ingerido_em, CAST(NULL AS STRING) AS _origem
   FROM nexus_pg.bi.vw_kpi_cards WHERE 1 = 0;

DELETE FROM workspace.bronze.vw_kpi_cards WHERE _data_referencia = data_ref;

INSERT INTO workspace.bronze.vw_kpi_cards
SELECT *, data_ref, current_timestamp(), 'nexus_pg.bi.vw_kpi_cards' FROM nexus_pg.bi.vw_kpi_cards;

-- COMMAND ----------

SELECT 'dim_alimento' AS tabela, COUNT(*) AS linhas_hoje FROM workspace.bronze.dim_alimento WHERE _data_referencia = data_ref
UNION ALL SELECT 'dim_localidade', COUNT(*) FROM workspace.bronze.dim_localidade WHERE _data_referencia = data_ref
UNION ALL SELECT 'dim_perfil', COUNT(*) FROM workspace.bronze.dim_perfil WHERE _data_referencia = data_ref
UNION ALL SELECT 'fato_estoque', COUNT(*) FROM workspace.bronze.fato_estoque WHERE _data_referencia = data_ref
UNION ALL SELECT 'fato_movimento', COUNT(*) FROM workspace.bronze.fato_movimento WHERE _data_referencia = data_ref
UNION ALL SELECT 'fato_estoque_minimo', COUNT(*) FROM workspace.bronze.fato_estoque_minimo WHERE _data_referencia = data_ref
UNION ALL SELECT 'vw_kpi_cards', COUNT(*) FROM workspace.bronze.vw_kpi_cards WHERE _data_referencia = data_ref;
