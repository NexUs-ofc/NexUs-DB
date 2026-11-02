# Business Intelligence — NexUs

Índice central de tudo o que foi entregue na frente de Business Intelligence do projeto
NexUs: pipeline no Databricks, evidências de execução e o relatório gerencial.

## Onde está cada coisa

| O quê | Caminho | Status |
|---|---|---|
| Código do pipeline (Bronze, Silver, Gold) | [`databricks/`](../databricks) | ✅ completo, mesclado na `main` (PR #19) |
| Datasets do dashboard | [`databricks/dashboard/datasets.sql`](../databricks/dashboard/datasets.sql) | ✅ completo |
| Relatório gerencial (PDF) | [`relatorio-gerencial/`](relatorio-gerencial) | ✅ completo |
| Evidências do dashboard (prints) | [`evidencias/dashboard/`](evidencias/dashboard) | parcial — ver checklist |
| Evidências do Job (prints) | [`evidencias/jobs/`](evidencias/jobs) | parcial — ver checklist |
| Evidências do pipeline (grafo, conferência) | [`evidencias/pipeline/`](evidencias/pipeline) | pendente |

> O código do pipeline continua em `databricks/` (não foi movido para dentro desta pasta)
> porque o Databricks lê os notebooks e o pipeline diretamente deste caminho do repositório
> (Git folder sincronizado). Mover esses arquivos quebraria a ligação com o Job/pipeline já
> configurado no workspace. Esta pasta `business-intelligence/` centraliza só as evidências
> e os entregáveis finais (relatório); o código-fonte permanece em `databricks/`.

## Checklist de evidências (para a entrega)

### Dashboard (`evidencias/dashboard/`)
- [x] `dashboard-visao-geral.png` — página 1, cards e tabela de metas/desvios
- [x] `dashboard-desperdicio-evolucao-mensal.png` — D1 mensal + média móvel
- [x] `dashboard-desperdicio-momento-histograma.png` — momento do descarte + histograma
- [x] `dashboard-desperdicio-categoria-boxplot.png` — Pareto por categoria + boxplot
- [x] `dashboard-despensa-mapa-uf.png` — mapa e ranking de risco por UF
- [x] `dashboard-despensa-status-histograma-boxplot.png` — status de validade, histograma e boxplot de vida útil
- [ ] `filtros-interativos.png` — página 1 com um filtro ativo (ex.: Região = Norte)
- [ ] `dashboard-definition.lvdash.json` — export do dashboard (menu `...` → *Export* → *JSON*)

### Jobs (`evidencias/jobs/`)
- [x] `job-execucao-sucesso.png` — execução Succeeded com os tempos (Task 1 + Task 2)
- [x] `job-historico-agendamento.png` — histórico de runs + agendamento 07:00 America/Sao_Paulo
- [ ] `job-configuracao-tasks.png` — aba *Tasks* do Job (configuração estática das 2 tasks)

### Pipeline (`evidencias/pipeline/`)
- [ ] `pipeline-grafo.png` — aba *Graph* do `Pipeline_silver_gold` (Silver → Gold)
- [ ] `kpi-conferencia.png` — resultado de `SELECT * FROM workspace.gold.kpi_conferencia`

## Demandas oficiais × entrega

| Demanda | Onde está |
|---|---|
| Visualização (dashboard) | `evidencias/dashboard/` |
| Relatório Gerencial | `relatorio-gerencial/Relatorio_Gerencial_NexUs_BI.pdf` |
| Job e Pipelines | `databricks/` (código) + `evidencias/jobs/` e `evidencias/pipeline/` (evidências) |
