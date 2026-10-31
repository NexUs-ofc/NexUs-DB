# Ingestão Bronze — `01_ingestao_bronze.sql`

Notebook SQL que copia o star schema do banco do app (PostgreSQL no Neon) para a camada
Bronze do Databricks. É a **Task 1** (`ingestao_bronze`) do Job `Job_NexUs_BI`; a Task 2 roda o pipeline `Pipeline_silver_gold`
(ver `databricks/pipeline/README.md`).

## Fonte

- Views `bi.*` do banco do NexUs (Neon), lidas pela **Lakehouse Federation**:
  connection `neon_nexus` → foreign catalog `nexus_pg`.
- Usuário `databricks_bi`, **somente leitura** e só no schema `bi` (não enxerga as tabelas do app).
- Nenhuma senha no código: a credencial fica guardada na connection do Unity Catalog.

## Regra da Bronze

Guarda os dados **como vieram** das views (sem limpeza; isso é papel da Silver), mais 3 colunas de controle:

| Coluna | Conteúdo |
|---|---|
| `_data_referencia` | dia da extração, no horário de Brasília |
| `_ingerido_em` | data e hora da gravação |
| `_origem` | view de onde a linha veio (ex.: `nexus_pg.bi.fato_estoque`) |

## Histórico sem duplicar

Cada execução grava **1 snapshot por dia**. Rodar de novo no mesmo dia apaga e regrava só o
snapshot daquele dia (`DELETE ... WHERE _data_referencia = data_ref` + `INSERT`) — o notebook é
**idempotente**. Os dias anteriores ficam preservados, o que dá histórico real dos KPIs de estado
(vencidos, a vencer, sem validade, mínimo).

"Hoje" = data de Brasília (`SET TIME ZONE 'America/Sao_Paulo'`). O Neon está em GMT e viraria o
dia 3 horas antes.

## Por que fora do ETL pipeline

- O ETL pipeline (Lakeflow) não lê foreign catalogs diretamente.
- Materialized views do pipeline **substituem** o conteúdo a cada execução; a Bronze precisa
  **acumular** snapshots.

Por isso a Bronze é uma task de notebook separada, que roda antes do pipeline (Silver → Gold).

## Tabelas geradas (`workspace.bronze`)

| Tabela | 1 linha = | Usada para |
|---|---|---|
| `dim_alimento` | 1 alimento (com categoria) | dimensão |
| `dim_localidade` | 1 cidade (só cidade, UF, região — **sem latitude/longitude**, que é dado pessoal; o mapa usa coordenadas da capital da UF, definidas na Silver) | dimensão |
| `dim_perfil` | 1 perfil (tipo, status, origem APP / SIMULADO_BI) | dimensão e filtro de origem |
| `fato_estoque` | 1 lote hoje na despensa | D3, D4, D5, D7, D8 |
| `fato_movimento` | 1 item consumido ou descartado vencido | D1, D9 |
| `fato_estoque_minimo` | 1 household × alimento com mínimo > 0 | D6 |
| `vw_kpi_cards` | 1 KPI calculado pelo banco | **gabarito** para validar a Gold (não entra no cálculo) |

## Schemas

Este notebook cria os 3 schemas (`bronze`, `silver`, `gold`) com `CREATE SCHEMA IF NOT EXISTS`.
Silver e Gold ficam aqui porque os arquivos do ETL pipeline só aceitam definições de
tabelas/views, não `CREATE SCHEMA` — e como esta é a primeira task do Job, os schemas sempre
existem quando o pipeline roda.

## Formato do arquivo

O arquivo é um notebook SQL exportado do Databricks:

- `-- Databricks notebook source` (1ª linha) faz o Databricks importar como **notebook**, não como arquivo texto.
- `-- COMMAND ----------` separa as **células**.

## Como conferir

1. A última célula mostra quantas linhas cada tabela recebeu hoje.
2. Rodar o notebook 2 vezes e consultar:
   ```sql
   SELECT _data_referencia, COUNT(*) FROM workspace.bronze.fato_estoque GROUP BY 1;
   ```
   Deve voltar **1 linha** por dia (sem duplicação).
