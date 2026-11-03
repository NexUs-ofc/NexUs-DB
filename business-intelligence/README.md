# Business Intelligence — NexUs

Índice central de tudo o que foi entregue na frente de Business Intelligence do projeto
NexUs: pipeline no Databricks, evidências de execução e o relatório gerencial.

## Onde está cada coisa

| O quê | Caminho | Status |
|---|---|---|
| Código do pipeline (Bronze, Silver, Gold) | [`databricks/`](databricks) | ✅ completo, mesclado na `main` (PR #19) |
| Datasets do dashboard + export JSON | [`databricks/dashboard/`](databricks/dashboard) | ✅ completo |
| Relatório gerencial (PDF + HTML) | [`relatorio-gerencial/`](relatorio-gerencial) | ✅ completo |
| Evidências do dashboard (prints) | [`evidencias/dashboard/`](evidencias/dashboard) | ✅ completo |
| Evidências do Job (prints) | [`evidencias/jobs/`](evidencias/jobs) | ✅ completo |
| Evidências do pipeline (resultado gerado) | [`evidencias/pipeline/`](evidencias/pipeline) | ✅ completo |

## Estrutura

```
business-intelligence/
├── README.md                  ← este índice
├── databricks/                ← código que roda no Databricks
│   ├── ingestao/              ← Task 1 do Job: Bronze
│   ├── pipeline/              ← Task 2 do Job: Silver → Gold (Pipeline_silver_gold)
│   └── dashboard/             ← datasets SQL + export JSON do dashboard
├── evidencias/
│   ├── dashboard/             ← prints do dashboard
│   ├── jobs/                  ← prints do Job (configuração, execução, histórico)
│   └── pipeline/              ← prints do pipeline (grafo, conferência dos KPIs)
└── relatorio-gerencial/       ← relatório gerencial em PDF
```

> O Job lê o notebook do workspace (`Workspace/Users/.../01_ingestao_bronze`), não deste
> repositório: mover os arquivos aqui não afeta o Job. O repositório guarda a versão de referência do código.

## Checklist de evidências (para a entrega)

### Dashboard (`evidencias/dashboard/`)
- [x] `dashboard-visao-geral.png` — página 1, cards e tabela de metas/desvios
- [x] `dashboard-desperdicio-evolucao-mensal.png` — D1 mensal + média móvel
- [x] `dashboard-desperdicio-momento-histograma.png` — momento do descarte + histograma
- [x] `dashboard-desperdicio-categoria-boxplot.png` — Pareto por categoria + boxplot
- [x] `dashboard-despensa-mapa-uf.png` — mapa e ranking de risco por UF
- [x] `dashboard-despensa-status-histograma-boxplot.png` — status de validade, histograma e boxplot de vida útil
- [x] `filtro-regiao-norte.png` — filtros em uso: Região = Norte (todos os cards recalculados)
- [x] `filtro-categoria-hortifruti.png` — filtros em uso: Categoria = Frutas, Verduras e Legumes
- [x] [`../databricks/dashboard/dashboard-definition.lvdash.json`](databricks/dashboard/dashboard-definition.lvdash.json) — export do dashboard (3 páginas, 8 datasets)

### Jobs (`evidencias/jobs/`)
- [x] `job-execucao-sucesso.png` — execução Succeeded com os tempos (Task 1 + Task 2)
- [x] `job-historico-agendamento.png` — histórico de runs + agendamento 07:00 America/Sao_Paulo
- [x] `job-configuracao-tasks.png` — aba *Tasks* do Job (configuração da task de ingestão)
- [x] `job-primeira-execucao-manual.png` — 1ª execução com sucesso, disparo manual (25/10)

### Pipeline (`evidencias/pipeline/`)
- [x] `kpi-conferencia.png` — resultado gerado: Gold × banco, 8 KPIs com resultado OK

## Demandas oficiais × entrega

| Demanda | Onde está |
|---|---|
| Visualização (dashboard) | `evidencias/dashboard/` |
| Relatório Gerencial | `relatorio-gerencial/Relatorio_Gerencial_NexUs_BI.pdf` |
| Job e Pipelines | [`databricks/`](databricks) (código) + `evidencias/jobs/` e `evidencias/pipeline/` (evidências) |
