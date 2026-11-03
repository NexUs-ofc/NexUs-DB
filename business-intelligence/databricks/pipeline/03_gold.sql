-- 03 · Gold: star schema + KPIs -> workspace.gold
-- Arquivo-fonte do ETL pipeline Pipeline_silver_gold. Documentação: databricks/pipeline/README.md
--
-- Regra oficial: proporções por UNIDADES (embalagens), não por registros — um descarte de 1
-- unidade não pesa o mesmo que um consumo de 10. A versão por lote/operação fica como complemento
-- e é a que se compara com o gabarito do banco (bi.vw_kpi_cards conta operações).
-- Tabelas kpi_* trazem os KPIs prontos (cards com meta/desvio, mensal, UF, categoria, diário).
-- ultima_foto = 1 marca a foto mais recente da despensa (estado "de hoje").

-- ===================================================================== DIMENSÕES
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_alimento
COMMENT 'Dimensão alimento (com categoria)' AS
SELECT * FROM workspace.silver.dim_alimento;

CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_localidade
COMMENT 'Dimensão localidade: cidade, UF, região e coordenadas da capital da UF' AS
SELECT * FROM workspace.silver.dim_localidade;

CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_perfil
COMMENT 'Dimensão perfil: tipo, status, login, tempo de casa e origem (APP / SIMULADO_BI)' AS
SELECT * FROM workspace.silver.dim_perfil;

CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.dim_tempo
COMMENT 'Calendário gerado das datas dos fatos (compra/entrada até o último evento/foto)' AS
WITH limites AS (
  SELECT LEAST((SELECT MIN(data_compra)  FROM workspace.silver.fato_movimento),
               (SELECT MIN(data_entrada) FROM workspace.silver.fato_estoque))    AS inicio,
         GREATEST((SELECT MAX(data_evento)     FROM workspace.silver.fato_movimento),
                  (SELECT MAX(data_referencia) FROM workspace.silver.fato_estoque)) AS fim
)
SELECT data,
       CAST(date_format(data, 'yyyyMMdd') AS INT) AS sk_data,
       YEAR(data)                     AS ano,
       MONTH(data)                    AS mes,
       date_format(data, 'yyyy-MM')   AS ano_mes,
       QUARTER(data)                  AS trimestre,
       DAYOFWEEK(data)                AS dia_semana,
       CAST(DAYOFWEEK(data) IN (1, 7) AS INT) AS fim_de_semana
FROM limites LATERAL VIEW explode(sequence(inicio, fim, INTERVAL 1 DAY)) t AS data;

-- ===================================================================== FATOS
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.fato_estoque
COMMENT '1 linha = 1 lote (saldo > 0) em cada foto diária. Flags 0/1 por lote; unidades = quantidade' AS
SELECT data_referencia,
       date_format(data_referencia, 'yyyy-MM')                       AS ano_mes_referencia,
       CAST(data_referencia = MAX(data_referencia) OVER () AS INT)   AS ultima_foto,
       id_item, sk_alimento, sk_perfil, sk_localidade,
       data_entrada, data_validade, quantidade,
       tem_validade,
       1 - tem_validade                                              AS sem_validade,
       dias_ate_vencer,
       CASE WHEN tem_validade = 1 THEN vida_util_dias END            AS vida_util_dias,
       status_validade,
       CASE WHEN tem_validade = 1 THEN CAST(status_validade = 'VENCIDO'  AS INT) END AS vencido,
       CASE WHEN tem_validade = 1 THEN CAST(status_validade = 'VENCE_7D' AS INT) END AS vence_7d,
       CASE WHEN tem_validade = 1 THEN CAST(dias_ate_vencer <= 30        AS INT) END AS em_risco_30d
FROM workspace.silver.fato_estoque;

-- Movimentos (V11: 1 linha = 1 operação, com a quantidade movimentada).
-- Enriquecido com: momento do descarte em relação à validade e meses de uso do app no evento.
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.fato_movimento
COMMENT '1 linha = 1 operação de consumo ou descarte (dados simulados). descartado = expirado; unidades = embalagens movimentadas' AS
SELECT m.id_movimento, m.sk_alimento, m.sk_perfil, m.sk_localidade,
       m.data_evento, YEAR(m.data_evento) AS ano, MONTH(m.data_evento) AS mes, m.ano_mes_evento,
       m.data_compra, m.data_validade, m.tipo_evento,
       m.expirado                                   AS descartado,
       m.expirado, m.consumido,
       m.qtd_consumida, m.qtd_descartada,
       m.qtd_consumida + m.qtd_descartada           AS unidades,
       m.dias_em_casa,
       CASE WHEN m.expirado = 1 AND m.data_validade IS NOT NULL
            THEN DATEDIFF(m.data_evento, m.data_validade) END             AS dias_apos_vencimento,
       CASE WHEN m.expirado = 0                         THEN NULL
            WHEN m.data_validade IS NULL                THEN '4 · Sem validade'
            WHEN m.data_evento <  m.data_validade       THEN '1 · Antes de vencer'
            WHEN DATEDIFF(m.data_evento, m.data_validade) <= 7 THEN '2 · Até 7 dias após vencer'
            ELSE '3 · Esquecido (+7 dias após vencer)' END              AS momento_descarte,
       CASE WHEN m.expirado = 1 AND m.data_validade IS NOT NULL
            THEN CAST(DATEDIFF(m.data_evento, m.data_validade) > 7 AS INT) END AS esquecido,
       CAST(FLOOR(months_between(m.data_evento, to_date(p.ano_mes_cadastro, 'yyyy-MM'))) AS INT) AS meses_de_uso,
       CASE WHEN p.ano_mes_cadastro IS NULL THEN 'N/I'
            WHEN months_between(m.data_evento, to_date(p.ano_mes_cadastro, 'yyyy-MM')) < 3  THEN '1 · 0–2 meses'
            WHEN months_between(m.data_evento, to_date(p.ano_mes_cadastro, 'yyyy-MM')) < 6  THEN '2 · 3–5 meses'
            WHEN months_between(m.data_evento, to_date(p.ano_mes_cadastro, 'yyyy-MM')) < 9  THEN '3 · 6–8 meses'
            ELSE '4 · 9+ meses' END                                       AS faixa_uso_app
FROM workspace.silver.fato_movimento m
LEFT JOIN workspace.silver.dim_perfil p ON p.sk_perfil = m.sk_perfil;

CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.fato_estoque_minimo
COMMENT '1 linha = 1 household x alimento monitorado por foto diária. AVG(abaixo_minimo) = % itens monitorados abaixo' AS
SELECT data_referencia,
       CAST(data_referencia = MAX(data_referencia) OVER () AS INT) AS ultima_foto,
       sk_perfil, sk_alimento, sk_localidade, estoque, minimo, abaixo_minimo
FROM workspace.silver.fato_estoque_minimo;

CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.fato_minimo_casa
COMMENT '1 linha = 1 household com mínimo configurado por foto diária. AVG(abaixo) = D6' AS
SELECT data_referencia,
       CAST(data_referencia = MAX(data_referencia) OVER () AS INT) AS ultima_foto,
       sk_perfil,
       MIN(sk_localidade)    AS sk_localidade,
       COUNT(*)              AS itens_monitorados,
       SUM(abaixo_minimo)    AS itens_abaixo,
       MAX(abaixo_minimo)    AS abaixo
FROM workspace.silver.fato_estoque_minimo
GROUP BY data_referencia, sk_perfil;

-- ===================================================================== KPIs
-- D1 mensal (EVENTO). Window functions: média móvel 3m (AVG OVER), variação (LAG),
-- acumulado (SUM OVER) e ranking (DENSE_RANK).
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.kpi_desperdicio_mensal
COMMENT 'D1 por mês do evento (oficial por unidades + por operações), média móvel 3m, variação, acumulado e ranking. Dados simulados' AS
WITH m AS (
  SELECT ano_mes_evento AS ano_mes,
         COUNT(*)              AS operacoes,
         SUM(expirado)         AS operacoes_descarte,
         SUM(qtd_descartada)   AS unidades_descartadas,
         SUM(unidades)         AS unidades_movimentadas,
         SUM(esquecido)        AS descartes_esquecidos,
         SUM(CASE WHEN data_validade IS NOT NULL THEN expirado END) AS descartes_com_validade
  FROM workspace.gold.fato_movimento
  GROUP BY ano_mes_evento
),
t AS (SELECT *, 100.0 * unidades_descartadas / NULLIF(unidades_movimentadas, 0) AS d1 FROM m)
SELECT ano_mes,
       CAST(ano_mes < date_format(current_date(), 'yyyy-MM') AS INT)                AS mes_completo,
       operacoes, operacoes_descarte, unidades_descartadas, unidades_movimentadas,
       ROUND(d1, 2)                                                                  AS d1_pct,
       ROUND(100.0 * operacoes_descarte / operacoes, 2)                              AS d1_operacoes_pct,
       ROUND(AVG(d1) OVER (ORDER BY ano_mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS d1_media_movel_3m,
       ROUND(d1 - LAG(d1) OVER (ORDER BY ano_mes), 2)                                AS d1_variacao_pp,
       SUM(unidades_descartadas) OVER (ORDER BY ano_mes)                             AS unidades_descartadas_acumuladas,
       DENSE_RANK() OVER (ORDER BY d1 DESC)                                          AS ranking_desperdicio,
       ROUND(100.0 * descartes_esquecidos / NULLIF(descartes_com_validade, 0), 2)    AS d2_esquecidos_pct,
       15                                                                            AS meta_d1,
       CASE WHEN d1 <= 15 THEN 'DENTRO_DA_META' ELSE 'FORA_DA_META' END              AS situacao_d1
FROM t;

-- Curva de aprendizado: o desperdício cai com o tempo de uso do app?
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.kpi_aprendizado
COMMENT 'D1 (unidades) e D2 por faixa de meses de uso do app no momento do evento. Dados simulados' AS
SELECT faixa_uso_app,
       COUNT(DISTINCT sk_perfil)                                              AS households,
       SUM(unidades)                                                          AS unidades_movimentadas,
       ROUND(100.0 * SUM(qtd_descartada) / NULLIF(SUM(unidades), 0), 2)       AS d1_pct,
       ROUND(100.0 * AVG(esquecido), 2)                                       AS d2_esquecidos_pct,
       ROUND(100.0 * SUM(qtd_descartada) / NULLIF(SUM(unidades), 0), 2)
         - FIRST_VALUE(ROUND(100.0 * SUM(qtd_descartada) / NULLIF(SUM(unidades), 0), 2))
             OVER (ORDER BY faixa_uso_app)                                    AS variacao_vs_inicio_pp
FROM workspace.gold.fato_movimento
WHERE faixa_uso_app <> 'N/I'
GROUP BY faixa_uso_app;

-- Momento do descarte em relação à validade (por que o alimento foi para o lixo?)
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.kpi_momento_descarte
COMMENT 'Unidades descartadas por momento do descarte (antes de vencer / até 7d / esquecido / sem validade). Dados simulados' AS
SELECT momento_descarte,
       COUNT(*)              AS operacoes,
       SUM(qtd_descartada)   AS unidades_descartadas,
       ROUND(100.0 * SUM(qtd_descartada) / SUM(SUM(qtd_descartada)) OVER (), 2) AS pct_unidades,
       ROUND(AVG(dias_apos_vencimento), 1)            AS dias_apos_vencimento_medio,
       percentile_approx(dias_apos_vencimento, 0.5)   AS dias_apos_vencimento_mediana
FROM workspace.gold.fato_movimento
WHERE expirado = 1
GROUP BY momento_descarte;

-- Estado da despensa por dia (uma linha por foto). Mensal = último dia do mês.
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.kpi_estado_diario
COMMENT 'D3, D4, D6, D7, D8 por foto diária (oficial por unidades; por lote como complemento)' AS
WITH e AS (
  SELECT data_referencia,
         COUNT(*)            AS lotes,
         SUM(quantidade)     AS unidades,
         ROUND(100.0 * SUM(vencido  * quantidade) / NULLIF(SUM(tem_validade * quantidade), 0), 2) AS d3_vencidos_pct,
         ROUND(100.0 * SUM(vence_7d * quantidade) / NULLIF(SUM(tem_validade * quantidade), 0), 2) AS d4_vencem_7d_pct,
         ROUND(100.0 * SUM(sem_validade * quantidade) / NULLIF(SUM(quantidade), 0), 2)           AS d8_sem_validade_pct,
         ROUND(100.0 * AVG(vencido), 2)      AS d3_lotes_pct,
         ROUND(100.0 * AVG(vence_7d), 2)     AS d4_lotes_pct,
         ROUND(100.0 * AVG(sem_validade), 2) AS d8_lotes_pct,
         ROUND(AVG(vida_util_dias), 1)       AS d7_vida_util_media
  FROM workspace.gold.fato_estoque GROUP BY data_referencia
),
c AS (
  SELECT data_referencia, ROUND(100.0 * AVG(abaixo), 2) AS d6_abaixo_minimo_pct,
         ROUND(100.0 * SUM(itens_abaixo) / SUM(itens_monitorados), 2) AS d6_itens_abaixo_pct
  FROM workspace.gold.fato_minimo_casa WHERE sk_localidade <> -1 GROUP BY data_referencia
)
SELECT e.*, c.d6_abaixo_minimo_pct, c.d6_itens_abaixo_pct,
       date_format(e.data_referencia, 'yyyy-MM') AS ano_mes,
       CAST(e.data_referencia = MAX(e.data_referencia) OVER (PARTITION BY date_format(e.data_referencia, 'yyyy-MM')) AS INT) AS ultimo_dia_do_mes
FROM e LEFT JOIN c ON c.data_referencia = e.data_referencia;

-- Por UF: risco (D5) em unidades e em %, para não favorecer UFs grandes.
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.kpi_uf
COMMENT 'Por UF: D3, D4, D8, D5 (% em risco e ranking), D6, D1 (unidades); coordenadas da capital para o mapa' AS
WITH est AS (
  SELECT l.uf,
         COUNT(*)                                     AS lotes,
         SUM(e.quantidade)                            AS unidades,
         SUM(e.em_risco_30d * e.quantidade)           AS unidades_em_risco,
         SUM(e.em_risco_30d)                          AS lotes_em_risco,
         ROUND(100.0 * SUM(e.vencido  * e.quantidade) / NULLIF(SUM(e.tem_validade * e.quantidade), 0), 2) AS d3_vencidos_pct,
         ROUND(100.0 * SUM(e.vence_7d * e.quantidade) / NULLIF(SUM(e.tem_validade * e.quantidade), 0), 2) AS d4_vencem_7d_pct,
         ROUND(100.0 * SUM(e.sem_validade * e.quantidade) / NULLIF(SUM(e.quantidade), 0), 2)            AS d8_sem_validade_pct,
         ROUND(100.0 * SUM(e.em_risco_30d * e.quantidade) / NULLIF(SUM(e.tem_validade * e.quantidade), 0), 2) AS pct_em_risco
  FROM workspace.gold.fato_estoque e JOIN workspace.gold.dim_localidade l ON l.sk_localidade = e.sk_localidade
  WHERE e.ultima_foto = 1 GROUP BY l.uf
),
casa AS (
  SELECT l.uf, COUNT(*) AS households_com_minimo, ROUND(100.0 * AVG(c.abaixo), 2) AS d6_abaixo_minimo_pct
  FROM workspace.gold.fato_minimo_casa c JOIN workspace.gold.dim_localidade l ON l.sk_localidade = c.sk_localidade
  WHERE c.ultima_foto = 1 GROUP BY l.uf
),
mov AS (
  SELECT l.uf, SUM(m.unidades) AS unidades_movimentadas,
         ROUND(100.0 * SUM(m.qtd_descartada) / NULLIF(SUM(m.unidades), 0), 2) AS d1_pct
  FROM workspace.gold.fato_movimento m JOIN workspace.gold.dim_localidade l ON l.sk_localidade = m.sk_localidade
  GROUP BY l.uf
)
SELECT r.uf, r.nome_uf, r.regiao, r.capital, r.latitude, r.longitude,
       COALESCE(est.lotes, 0) AS lotes, COALESCE(est.unidades, 0) AS unidades,
       COALESCE(est.lotes_em_risco, 0) AS lotes_em_risco, COALESCE(est.unidades_em_risco, 0) AS unidades_em_risco,
       est.pct_em_risco,
       DENSE_RANK() OVER (ORDER BY COALESCE(est.pct_em_risco, -1) DESC)      AS d5_ranking_pct,
       DENSE_RANK() OVER (ORDER BY COALESCE(est.lotes_em_risco, 0) DESC)     AS d5_ranking_lotes,
       est.d3_vencidos_pct, est.d4_vencem_7d_pct, est.d8_sem_validade_pct,
       casa.households_com_minimo, casa.d6_abaixo_minimo_pct,
       mov.unidades_movimentadas, mov.d1_pct
FROM workspace.silver.ref_uf r
LEFT JOIN est  ON est.uf  = r.uf
LEFT JOIN casa ON casa.uf = r.uf
LEFT JOIN mov  ON mov.uf  = r.uf;

-- Por categoria: D9, D1, Pareto do desperdício e vida útil (para o scatter "perecível desperdiça mais?").
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.kpi_categoria
COMMENT 'Por categoria: D9 (unidades descartadas / casas), D1, Pareto (% acumulado), D7 e % esquecido' AS
WITH casas AS (     -- household teve a categoria: no histórico ou na despensa atual
  SELECT a.categoria, COUNT(DISTINCT u.sk_perfil) AS households_com_categoria
  FROM (SELECT sk_perfil, sk_alimento FROM workspace.gold.fato_movimento
        UNION SELECT sk_perfil, sk_alimento FROM workspace.gold.fato_estoque WHERE ultima_foto = 1) u
  JOIN workspace.gold.dim_alimento a ON a.sk_alimento = u.sk_alimento
  GROUP BY a.categoria
),
mov AS (
  SELECT a.categoria,
         SUM(m.expirado)        AS operacoes_descarte,
         SUM(m.qtd_descartada)  AS unidades_descartadas,
         SUM(m.unidades)        AS unidades_movimentadas,
         ROUND(100.0 * SUM(m.qtd_descartada) / NULLIF(SUM(m.unidades), 0), 2) AS d1_pct,
         ROUND(100.0 * AVG(m.esquecido), 2) AS d2_esquecidos_pct,
         ROUND(AVG(m.dias_em_casa), 1)      AS dias_em_casa_medio
  FROM workspace.gold.fato_movimento m JOIN workspace.gold.dim_alimento a ON a.sk_alimento = m.sk_alimento
  GROUP BY a.categoria
),
est AS (
  SELECT a.categoria, COUNT(*) AS lotes_na_despensa,
         ROUND(AVG(e.vida_util_dias), 1) AS d7_vida_util_media,
         median(e.vida_util_dias)        AS d7_vida_util_mediana
  FROM workspace.gold.fato_estoque e JOIN workspace.gold.dim_alimento a ON a.sk_alimento = e.sk_alimento
  WHERE e.ultima_foto = 1 GROUP BY a.categoria
)
SELECT c.categoria, c.households_com_categoria,
       COALESCE(mov.unidades_descartadas, 0) AS unidades_descartadas,
       ROUND(COALESCE(mov.unidades_descartadas, 0) / c.households_com_categoria, 3) AS d9_indice_desperdicio,
       ROUND(COALESCE(mov.operacoes_descarte, 0) / c.households_com_categoria, 3)   AS d9_operacoes,
       DENSE_RANK() OVER (ORDER BY COALESCE(mov.unidades_descartadas, 0) / c.households_com_categoria DESC) AS d9_ranking,
       ROUND(100.0 * COALESCE(mov.unidades_descartadas, 0) / SUM(COALESCE(mov.unidades_descartadas, 0)) OVER (), 2) AS pct_do_desperdicio,
       ROUND(100.0 * SUM(COALESCE(mov.unidades_descartadas, 0)) OVER (ORDER BY COALESCE(mov.unidades_descartadas, 0) DESC, c.categoria
                                                                     ROWS UNBOUNDED PRECEDING)
             / SUM(COALESCE(mov.unidades_descartadas, 0)) OVER (), 2)              AS pareto_acumulado_pct,
       mov.unidades_movimentadas, mov.d1_pct, mov.d2_esquecidos_pct, mov.dias_em_casa_medio,
       est.lotes_na_despensa, est.d7_vida_util_media, est.d7_vida_util_mediana
FROM casas c
LEFT JOIN mov ON mov.categoria = c.categoria
LEFT JOIN est ON est.categoria = c.categoria;

-- Cards: valor oficial (unidades), meta, desvio, situação; valor_por_lote = regra do banco.
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.kpi_cards
COMMENT 'Cards D1-D9: valor oficial (unidades), meta, desvio, situação, valor por lote/operação (regra do banco) e tipo' AS
WITH est AS (SELECT * FROM workspace.gold.fato_estoque WHERE ultima_foto = 1),
k AS (
  SELECT 1 AS ordem, 'D1' AS codigo, 'Taxa de desperdício (unidades descartadas ÷ unidades que saíram)' AS kpi,
         100.0 * SUM(qtd_descartada) / NULLIF(SUM(unidades), 0) AS valor, '%' AS unidade, 15 AS meta, TRUE AS menor_melhor,
         100.0 * AVG(expirado) AS valor_por_lote, CAST(NULL AS STRING) AS detalhe,
         'EVENTO' AS tipo_indicador, 'SIMULADO' AS base_dados
  FROM workspace.gold.fato_movimento
  UNION ALL
  SELECT 2, 'D2', 'Descarte por esquecimento (+7 dias após vencer)', 100.0 * SUM(esquecido * qtd_descartada)
           / NULLIF(SUM(CASE WHEN esquecido IS NOT NULL THEN qtd_descartada END), 0), '%', CAST(NULL AS INT), TRUE,
         100.0 * AVG(esquecido), NULL, 'EVENTO', 'SIMULADO'
  FROM workspace.gold.fato_movimento
  UNION ALL
  SELECT 3, 'D3', '% unidades vencidas na despensa',
         100.0 * SUM(vencido * quantidade) / NULLIF(SUM(tem_validade * quantidade), 0), '%', 5, TRUE,
         100.0 * AVG(vencido), NULL, 'ESTADO', 'APP + SIMULADO'
  FROM est
  UNION ALL
  SELECT 4, 'D4', '% unidades que vencem em 7 dias',
         100.0 * SUM(vence_7d * quantidade) / NULLIF(SUM(tem_validade * quantidade), 0), '%', 10, TRUE,
         100.0 * AVG(vence_7d), NULL, 'ESTADO', 'APP + SIMULADO'
  FROM est
  UNION ALL
  SELECT 5, 'D5', '% em risco (≤ 30 dias) na UF nº 1', MAX(pct_em_risco), '%', CAST(NULL AS INT), TRUE,
         CAST(max_by(lotes_em_risco, pct_em_risco) AS DOUBLE), max_by(uf, pct_em_risco), 'ESTADO', 'APP + SIMULADO'
  FROM workspace.gold.kpi_uf WHERE lotes >= 30
  UNION ALL
  SELECT 6, 'D6', 'Households com algum item abaixo do mínimo', 100.0 * AVG(abaixo), '%', 30, TRUE,
         100.0 * SUM(itens_abaixo) / SUM(itens_monitorados), 'complemento: % itens monitorados abaixo', 'ESTADO', 'APP + SIMULADO'
  FROM workspace.gold.fato_minimo_casa WHERE ultima_foto = 1 AND sk_localidade <> -1
  UNION ALL
  SELECT 7, 'D7', 'Vida útil no cadastro (mediana por unidade, dias)', percentile(vida_util_dias, 0.5, quantidade), 'dias', CAST(NULL AS INT), FALSE,
         AVG(vida_util_dias), 'complemento: média por lote (regra do banco)', 'ESTADO', 'APP + SIMULADO'
  FROM est
  UNION ALL
  SELECT 8, 'D8', '% unidades sem validade',
         100.0 * SUM(sem_validade * quantidade) / NULLIF(SUM(quantidade), 0), '%', 10, TRUE,
         100.0 * AVG(sem_validade), NULL, 'ESTADO', 'APP + SIMULADO'
  FROM est
  UNION ALL
  SELECT 9, 'D9', 'Maior índice de desperdício por categoria (unidades/casa)', MAX(d9_indice_desperdicio), 'unid./casa',
         CAST(NULL AS INT), TRUE, max_by(d9_operacoes, d9_indice_desperdicio), max_by(categoria, d9_indice_desperdicio),
         'EVENTO', 'SIMULADO'
  FROM workspace.gold.kpi_categoria
)
SELECT ordem, codigo, kpi,
       CAST(ROUND(valor, 2) AS DECIMAL(14,2))                   AS valor,
       unidade, meta,
       CAST(ROUND(valor - meta, 2) AS DECIMAL(14,2))            AS desvio,
       CASE WHEN meta IS NULL THEN 'SEM_META'
            WHEN (valor <= meta) = menor_melhor THEN 'DENTRO_DA_META'
            ELSE 'FORA_DA_META' END                             AS situacao,
       CAST(ROUND(valor_por_lote, 2) AS DECIMAL(14,2))          AS valor_por_lote,
       detalhe, tipo_indicador, base_dados,
       (SELECT MAX(data_referencia) FROM workspace.gold.fato_estoque) AS data_referencia
FROM k;

-- Conferência: a versão por lote/operação da Gold x gabarito do banco (bi.vw_kpi_cards).
-- D5 e D9 mudaram de regra (% e unidades), então são conferidos pelas colunas equivalentes.
CREATE OR REFRESH MATERIALIZED VIEW workspace.gold.kpi_conferencia
COMMENT 'Gold (regra por lote/operação) x gabarito do banco na foto mais recente: OK / DIFERENTE' AS
WITH gold AS (
  SELECT codigo, valor_por_lote AS valor FROM workspace.gold.kpi_cards WHERE codigo IN ('D1', 'D3', 'D4', 'D8')
  UNION ALL SELECT 'D6', valor FROM workspace.gold.kpi_cards WHERE codigo = 'D6'
  UNION ALL SELECT 'D7', CAST(valor_por_lote AS DECIMAL(14,2)) FROM workspace.gold.kpi_cards WHERE codigo = 'D7'
  UNION ALL SELECT 'D5', CAST(MAX(lotes_em_risco) AS DECIMAL(14,2)) FROM workspace.gold.kpi_uf
  UNION ALL SELECT 'D9', CAST(MAX(d9_operacoes) AS DECIMAL(14,2)) FROM workspace.gold.kpi_categoria
)
SELECT g.codigo, g.valor AS valor_gold_regra_banco, b.valor AS valor_banco,
       g.valor - b.valor AS diferenca,
       CASE WHEN b.valor IS NULL THEN 'SEM_GABARITO'
            WHEN ABS(g.valor - b.valor) <= 0.01 THEN 'OK' ELSE 'DIFERENTE' END AS resultado,
       b.data_referencia
FROM gold g
LEFT JOIN workspace.silver.kpi_cards_gabarito b
       ON b.codigo = g.codigo
      AND b.data_referencia = (SELECT MAX(data_referencia) FROM workspace.gold.fato_estoque);
