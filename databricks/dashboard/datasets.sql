-- Datasets do dashboard NexUs BI (AI/BI Dashboard). Todos leem SÓ workspace.gold.
-- Cada bloco = 1 dataset (aba Data -> Add SQL dataset). Nome sugerido no comentário.
-- Filtros com o MESMO nome de coluna em todos os datasets: regiao, uf, categoria, origem, ano_mes.
--
-- ds_estoque e ds_movimento estão no grão de UNIDADE (1 linha = 1 embalagem, via explode):
-- assim AVG(coluna 0/1) já é o KPI oficial por unidades e responde a qualquer filtro.

-- ============================================================ ds_cards
SELECT ordem, codigo, kpi, valor, unidade, meta, desvio, situacao, valor_por_lote, detalhe,
       tipo_indicador, base_dados, data_referencia
FROM workspace.gold.kpi_cards
ORDER BY ordem;

-- ============================================================ ds_estoque  (1 linha = 1 unidade na despensa hoje)
-- D3 = AVG(vencido) | D4 = AVG(vence_7d) | D8 = AVG(sem_validade) | lotes = COUNT(DISTINCT id_item)
SELECT e.id_item, e.status_validade, e.sem_validade, e.vencido, e.vence_7d, e.em_risco_30d,
       e.dias_ate_vencer, e.vida_util_dias,
       a.alimento, a.categoria, l.cidade, l.uf, l.regiao, p.tipo AS tipo_perfil, p.origem
FROM workspace.gold.fato_estoque e
JOIN workspace.gold.dim_alimento   a ON a.sk_alimento   = e.sk_alimento
JOIN workspace.gold.dim_localidade l ON l.sk_localidade = e.sk_localidade
JOIN workspace.gold.dim_perfil     p ON p.sk_perfil     = e.sk_perfil
LATERAL VIEW explode(sequence(1, e.quantidade)) u AS n
WHERE e.ultima_foto = 1;

-- ============================================================ ds_movimento  (1 linha = 1 unidade que saiu; simulado)
-- D1 = AVG(descartado) | D2 = AVG(esquecido) | operações = COUNT(DISTINCT id_movimento)
SELECT m.id_movimento, m.data_evento, m.ano_mes_evento AS ano_mes, m.tipo_evento,
       m.descartado, m.esquecido, m.momento_descarte, m.dias_apos_vencimento,
       m.dias_em_casa, m.faixa_uso_app, m.meses_de_uso,
       a.alimento, a.categoria, l.uf, l.regiao, p.tipo AS tipo_perfil, p.origem
FROM workspace.gold.fato_movimento m
JOIN workspace.gold.dim_alimento   a ON a.sk_alimento   = m.sk_alimento
JOIN workspace.gold.dim_localidade l ON l.sk_localidade = m.sk_localidade
JOIN workspace.gold.dim_perfil     p ON p.sk_perfil     = m.sk_perfil
LATERAL VIEW explode(sequence(1, m.unidades)) u AS n;

-- ============================================================ ds_minimo  (1 linha = 1 household com mínimo)
-- D6 = AVG(abaixo) | % itens abaixo = SUM(itens_abaixo) / SUM(itens_monitorados)
SELECT c.itens_monitorados, c.itens_abaixo, c.abaixo, l.uf, l.regiao, p.origem
FROM workspace.gold.fato_minimo_casa c
JOIN workspace.gold.dim_localidade l ON l.sk_localidade = c.sk_localidade
JOIN workspace.gold.dim_perfil     p ON p.sk_perfil     = c.sk_perfil
WHERE c.ultima_foto = 1 AND c.sk_localidade <> -1;

-- ============================================================ ds_mensal
SELECT ano_mes, mes_completo, d1_pct, d1_operacoes_pct, d1_media_movel_3m, d1_variacao_pp,
       unidades_descartadas, unidades_descartadas_acumuladas, ranking_desperdicio, d2_esquecidos_pct,
       meta_d1, situacao_d1
FROM workspace.gold.kpi_desperdicio_mensal
ORDER BY ano_mes;

-- ============================================================ ds_aprendizado
SELECT faixa_uso_app, households, unidades_movimentadas, d1_pct, d2_esquecidos_pct, variacao_vs_inicio_pp
FROM workspace.gold.kpi_aprendizado
ORDER BY faixa_uso_app;

-- ============================================================ ds_momento_descarte
SELECT momento_descarte, unidades_descartadas, pct_unidades, dias_apos_vencimento_medio, dias_apos_vencimento_mediana
FROM workspace.gold.kpi_momento_descarte
ORDER BY momento_descarte;

-- ============================================================ ds_uf
SELECT uf, nome_uf, regiao, capital, latitude, longitude, lotes, unidades, unidades_em_risco,
       pct_em_risco, d5_ranking_pct, lotes_em_risco, d3_vencidos_pct, d4_vencem_7d_pct,
       d8_sem_validade_pct, d6_abaixo_minimo_pct, d1_pct
FROM workspace.gold.kpi_uf
WHERE lotes >= 30;   -- mesma regra do card D5: UF com amostra pequena distorce o %

-- ============================================================ ds_categoria
SELECT categoria, d9_indice_desperdicio, d9_ranking, unidades_descartadas, pct_do_desperdicio,
       pareto_acumulado_pct, d1_pct, d2_esquecidos_pct, d7_vida_util_mediana, d7_vida_util_media,
       households_com_categoria
FROM workspace.gold.kpi_categoria
WHERE categoria <> 'Não informada'
  AND unidades_descartadas > 0       -- categorias do seed sem nenhum descarte poluem o gráfico
ORDER BY pct_do_desperdicio DESC;

-- ============================================================ ds_estado_diario
SELECT data_referencia, d3_vencidos_pct, d4_vencem_7d_pct, d6_abaixo_minimo_pct, d8_sem_validade_pct
FROM workspace.gold.kpi_estado_diario
ORDER BY data_referencia;

-- ============================================================ ds_conferencia
SELECT * FROM workspace.gold.kpi_conferencia;
