# Data Mart (Star Schema)

`datamart_estrela.sql` cria o schema `bi` com views para ferramentas de BI.
Rodar no pgAdmin (Query Tool) no banco do app, **depois** do dataload BI; só mexe nos schemas `bi` e `bi_hist`.

A V11 adapta as views existentes ao histórico ligado a pantry_item e exclui saldo zero do fato de estoque. O Core grava movimentos reais e o dataload grava simulações no mesmo contrato. As fórmulas dos KPIs permanecem contando operações, não unidades; sua revisão fica para outra etapa.

| Tipo | Views |
|---|---|
| Dimensões | `dim_tempo`, `dim_alimento` (com categoria), `dim_localidade` (cidade, UF, região), `dim_perfil`, `dim_empresa` (com plano) |
| Fatos | `fato_estoque` (1 item hoje na despensa), `fato_movimento` (1 item consumido ou descartado), `fato_estoque_minimo` (household × alimento), `fato_pagamento` (1 cobrança), `fato_cadastro` (1 perfil) |
| Evolução | `kpi_d1_evolucao_mensal`: running total da perda, variação mês a mês (`LAG`), média móvel e `RANK` |
| Cards | `vw_kpi_cards`: valor, meta, desvio e situação de D1–D9 (+ financeiro e base ativa) |
| Volume | `vw_volume_tabelas`: registros por tabela e se atinge 500 (company/store limitadas pelos profiles) |

## KPIs de desperdício

| KPI | Fórmula | View de detalhe |
|---|---|---|
| D1 — Taxa de desperdício | item_expired / (item_expired + item_consumed) | `kpi_d1_desperdicio_mensal` (mês × região, com totais) |
| D3 — % itens vencidos na despensa | vencidos / itens com validade | `kpi_d3_d4_d8_validade_uf` |
| D4 — % a vencer em 7 dias | validade em até 7 dias / itens com validade | `kpi_d3_d4_d8_validade_uf` |
| D5 — Ranking de vencimento | DENSE_RANK por UF de (vencidos + a vencer em 30 dias) | `kpi_d5_ranking_vencimento_uf` |
| D6 — Estoque abaixo do mínimo | households abaixo / households com mínimo configurado | `kpi_d6_estoque_minimo_uf` |
| D7 — Vida útil no cadastro | expiry_date − created_at (dias) | `kpi_d7_vida_util_categoria` |
| D8 — % itens sem validade | COUNT(expiry_date IS NULL) / COUNT(*) | `kpi_d3_d4_d8_validade_uf` |
| D9 — Índice de desperdício por categoria | expirados da categoria / households com a categoria | `kpi_d9_desperdicio_categoria` |

Linhas com UF/categoria/mês vazios (NULL) nas views de detalhe são o total geral.

```sql
SELECT * FROM bi.vw_kpi_cards;
SELECT * FROM bi.vw_volume_tabelas;
SELECT * FROM bi.kpi_d5_ranking_vencimento_uf ORDER BY ranking;
```

`dim_perfil.origem` separa dados do app (`APP`) dos simulados pelo dataload BI (`SIMULADO_BI`), para filtrar no dashboard.
