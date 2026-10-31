# Pipeline_silver_gold — Silver e Gold

Arquivos-fonte do **ETL pipeline** (Lakeflow) `Pipeline_silver_gold`, que é a **Task 2** do Job
`Job_NexUs_BI` (roda depois da ingestão Bronze). Cada tabela é uma *materialized view*
(`CREATE OR REFRESH MATERIALIZED VIEW`): o pipeline descobre sozinho a ordem pelas dependências
e recalcula tudo a cada execução.

## Job `Job_NexUs_BI`

Executa a pipeline inteira sem abrir notebook, manualmente (**Run now**) ou agendado.

| Ordem | Task | Tipo | O que roda |
|---|---|---|---|
| 1 | `ingestao_bronze` | Notebook (serverless) | `databricks/ingestao/01_ingestao_bronze.sql` |
| 2 | `Transformation_silver_gold` | ETL pipeline (depende da task 1) | `Pipeline_silver_gold` = `02_silver.sql` + `03_gold.sql` |

- **Agendamento:** todo dia às 07:00, fuso `America/Sao_Paulo` (1 foto diária da despensa; poupa a cota da Free Edition).
- **Full refresh:** desligado — o pipeline só recalcula o que mudou.
- Silver e Gold ficam **no mesmo pipeline**: uma tabela só pode pertencer a um pipeline, e a Free
  Edition permite 1 pipeline ativo por tipo. O próprio pipeline ordena Silver -> Gold pelas dependências.
- Na pasta `transformations` do pipeline só podem existir os arquivos com `CREATE OR REFRESH ...`;
  consultas soltas (`SELECT`) quebram a inicialização — conferências vão no SQL Editor.
- 1ª execução com sucesso: 25/10/2026 (Bronze 2 min 22 s + pipeline 4 min 22 s = 6 min 45 s).

## 02_silver.sql — limpeza e padronização (`workspace.silver`)

Lê `workspace.bronze.*` e entrega dados limpos, com tipos certos e regras de qualidade.

### Qual foto da Bronze cada tabela usa

| Tabela Silver | Fotos usadas | Por quê |
|---|---|---|
| `dim_alimento`, `dim_localidade`, `dim_perfil` | só a mais recente | cadastro atual |
| `fato_movimento` | só a mais recente | cada foto já tem o histórico inteiro e evento não muda; usar todas multiplicaria o histórico |
| `fato_estoque`, `fato_estoque_minimo` | **todas** | histórico diário do estado da despensa (D3–D8 por dia) |
| `kpi_cards_gabarito` | todas | conferência da Gold, dia a dia |
| `ref_uf` | — | tabela fixa das 27 UFs |

### Etapas de limpeza

| # | Problema | Tratamento |
|---|---|---|
| 1 | Linha repetida (mesma chave gravada 2x) | `ROW_NUMBER()` por chave (e por data da foto nos fatos de estado); fica a gravação mais recente (`_ingerido_em`). |
| 2 | Datas como inteiro `AAAAMMDD`, `-1` = sem data | `try_to_date(...)` → `DATE`; `-1` vira `NULL`. |
| 3 | Tipos genéricos da federação (`DECIMAL` sem escala, `LONG`) | `CAST` para `DECIMAL(12,2)` / `DECIMAL(12,3)` / `INT`. |
| 4 | Textos com espaço, maiúsculas/minúsculas misturadas, vazios | `TRIM`, `UPPER`/`LOWER`, `NULLIF('', ...)`; vazio vira "Não informado(a)" / "Sem marca". |
| 5 | Chave órfã (fato aponta para alimento/perfil/cidade que não existe na dimensão da mesma foto) | Vira `-1`. Cada dimensão tem a linha `-1 = Não informado`, então JOIN nunca perde linha. |
| 6 | UF inválida ou ausente | Validada contra `ref_uf`; fora da lista vira `N/I`. Região vem da `ref_uf` (fonte única). |
| 7 | "Hoje" do Neon (momento da cópia) | `dias_ate_vencer`, `status_validade` e `vida_util_dias` **recalculados** com a data da foto (`data_referencia`). |
| 8 | Quantidade nula nos eventos; tipo de evento em dois vocabulários (antigo `item_consumed`/`item_expired` e V11 `CONSUMED`/`DISCARDED`) | `COALESCE(..., 0)`; tipo padronizado para `CONSUMED`/`DISCARDED`. |
| 9 | Coordenadas | Latitude/longitude do endereço **não** vêm (dado pessoal); o mapa usa a capital da UF (`ref_uf`). |

### Regras de qualidade (expectations)

`ON VIOLATION DROP ROW` = a linha é descartada (dado inutilizável).
Sem `ON VIOLATION` = a linha fica e o pipeline só **registra** quantas violaram (aparece na aba
*Data quality* do pipeline).

| Tabela | Descarta a linha | Só alerta |
|---|---|---|
| `dim_alimento` | `sk_alimento` nula | alimento sem nome |
| `dim_localidade` | `sk_localidade` nula | UF `N/I` |
| `dim_perfil` | `sk_perfil` nula | tipo ou origem desconhecidos |
| `fato_estoque` | `id_item` ou data de entrada nulos | quantidade ≤ 0; validade antes da entrada |
| `fato_movimento` | id nulo, tipo de evento inválido, data do evento nula | evento antes da compra; operação sem quantidade |
| `fato_estoque_minimo` | chave nula; mínimo ≤ 0 | estoque negativo |

### Status de validade (recalculado por foto)

| status | regra (d = data_referencia) | KPI |
|---|---|---|
| `SEM_VALIDADE` | validade nula | D8 |
| `VENCIDO` | validade < d | D3 |
| `VENCE_7D` | d ≤ validade ≤ d + 7 | D4 |
| `VENCE_30D` | d + 7 < validade ≤ d + 30 | D5 (com VENCIDO e VENCE_7D) |
| `OK` | validade > d + 30 | — |

## 03_gold.sql — star schema e KPIs (`workspace.gold`)

Lê `workspace.silver.*`. É a **base final**: o dashboard só usa tabelas daqui.

### Star schema

| Tabela | Tipo | 1 linha = |
|---|---|---|
| `dim_alimento`, `dim_localidade`, `dim_perfil` | dimensão | alimento / cidade / perfil (com linha -1) |
| `dim_tempo` | dimensão | 1 dia (calendário gerado das datas dos fatos) |
| `fato_estoque` | fato de estado | 1 lote na despensa em cada foto diária |
| `fato_movimento` | fato de evento | 1 lote consumido ou descartado vencido |
| `fato_estoque_minimo` | fato de estado | 1 household × alimento monitorado por foto |
| `fato_minimo_casa` | fato de estado (agregado) | 1 household com mínimo por foto |

**Colunas-indicador:** os fatos têm colunas 0/1 (nulas quando não se aplicam). A média da coluna
já é o KPI e respeita qualquer filtro do dashboard:

| KPI | Cálculo no dashboard |
|---|---|
| D1 | `AVG(expirado)` em `fato_movimento` |
| D3 | `AVG(vencido)` em `fato_estoque` (`ultima_foto = 1`) — nulo para lote sem validade, então o denominador é "lotes com validade" |
| D4 | `AVG(vence_7d)` em `fato_estoque` (`ultima_foto = 1`) |
| D6 | `AVG(abaixo)` em `fato_minimo_casa` (`ultima_foto = 1`) |
| D7 | `AVG(vida_util_dias)` em `fato_estoque` (`ultima_foto = 1`) |
| D8 | `AVG(sem_validade)` em `fato_estoque` (`ultima_foto = 1`) |

### Tabelas de KPI

| Tabela | Conteúdo | Tipo |
|---|---|---|
| `kpi_cards` | D1, D3–D9: valor, meta, desvio, situação, complemento (por unidades / % itens / % em risco) | cards |
| `kpi_desperdicio_mensal` | D1 por mês: média móvel 3m, variação (LAG), unidades descartadas acumuladas (SUM OVER), ranking | EVENTO |
| `kpi_estado_diario` | D3, D4, D6, D7, D8 por foto diária (`ultimo_dia_do_mes` para visão mensal) | ESTADO |
| `kpi_uf` | por UF: D3, D4, D8, D5 (ranking + % em risco), D6, D1, coordenadas da capital | mapa / barras |
| `kpi_categoria` | por categoria: D9 (+ ranking), D1, D7 (média e mediana) | barras |
| `kpi_conferencia` | Gold × gabarito do banco na mesma data (`OK` / `DIFERENTE`) | validação |

### Evento × estado

- **Evento** (D1, D9): agrupado pelo **mês do evento** — histórico mensal legítimo.
- **Estado** (D3–D8): agrupado pela **data da foto**. O histórico começa no dia da primeira
  ingestão (25/10/2026) e cresce 1 ponto por dia; a foto atual nunca é apresentada como se fosse
  o estado de meses passados.

### Metas (as mesmas do banco)

D1 ≤ 15% · D3 ≤ 5% · D4 ≤ 10% · D6 ≤ 30% · D8 ≤ 10%. D5, D7 e D9: sem meta.
`desvio = valor − meta`; `situacao` = DENTRO_DA_META / FORA_DA_META / SEM_META.

### D2

Não existe definição de D2 no projeto — registrado como "não definido".

### Sem estimativa de preço

O app não registra preço de compra; o valor `estimated_loss` só existia na simulação (preço de
referência fixo no `bi.py`). Por decisão do time, **nenhuma estimativa em R$** entra na Silver, na
Gold ou no dashboard.

## Revisão de 26/10: unidades e análises novas

**Regra oficial por unidades (embalagens).** Atende à crítica de que contar registros distorce:
um consumo de 10 unidades e um descarte de 1 davam 50%; por unidades dá 9,09%. A V11 tornou isso
ainda mais importante, pois um lote pode ter várias operações parciais. A versão por lote/operação
continua calculada (`valor_por_lote`) e é a que a `kpi_conferencia` compara com o banco, que conta
operações.

| KPI | Fórmula oficial (Gold) |
|---|---|
| D1 Taxa de desperdício | Σ unidades descartadas ÷ Σ unidades que saíram (consumidas + descartadas) |
| D2 Descarte por esquecimento (**novo**) | Σ unidades descartadas mais de 7 dias após vencer ÷ Σ unidades descartadas com validade |
| D3 % vencidos | Σ unidades de lotes vencidos ÷ Σ unidades com validade (saldo > 0) |
| D4 % vencem em 7 dias | Σ unidades com 0 ≤ dias até vencer ≤ 7 ÷ Σ unidades com validade |
| D5 Risco por UF | % das unidades vencidas ou vencendo em ≤ 30 dias, por UF (ranking pelo %, UF com ≥ 30 lotes) |
| D6 Abaixo do mínimo | households com ≥ 1 item abaixo do mínimo ÷ households com mínimo (complemento: % itens) |
| D7 Vida útil | mediana de (validade − entrada), em dias (complemento: média) |
| D8 % sem validade | Σ unidades sem validade ÷ Σ unidades |
| D9 Desperdício por categoria | Σ unidades descartadas da categoria ÷ households com a categoria |

Tabelas novas:

| Tabela | Pergunta |
|---|---|
| `kpi_aprendizado` | O desperdício cai com o tempo de uso do app? (D1 e D2 por faixa de meses de uso no momento do evento) |
| `kpi_momento_descarte` | Quando o alimento vai para o lixo: antes de vencer, logo após ou esquecido? |
| `kpi_categoria.pareto_acumulado_pct` | Poucas categorias concentram a maior parte do desperdício? (Pareto) |

No `fato_movimento`: `unidades`, `dias_apos_vencimento`, `momento_descarte`, `esquecido`,
`meses_de_uso`, `faixa_uso_app`. Os padrões dessas análises foram **programados na simulação**
(aprendizado, esquecimento): o dashboard mostra que o BI os detecta; não são descobertas sobre usuários reais.
