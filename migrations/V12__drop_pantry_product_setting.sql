-- Remove a configuração de estoque mínimo e suas dependências conhecidas.
-- Preserva os demais indicadores e o painel de volume quando o BI já existe.
DO $$
BEGIN
    IF to_regclass('bi.vw_kpi_cards') IS NOT NULL THEN
        EXECUTE $view$
CREATE OR REPLACE VIEW bi.vw_kpi_cards AS
WITH k (ordem, codigo, kpi, valor, unidade, meta, menor_melhor) AS (
    SELECT 1, 'D1', 'Taxa de desperdício', 100.0 * AVG(expirado), '%', 15, TRUE FROM bi.fato_movimento
    UNION ALL
    SELECT 3, 'D3', '% itens vencidos na despensa', 100.0 * AVG((status_validade = 'VENCIDO')::int), '%', 5, TRUE
      FROM bi.fato_estoque WHERE tem_validade = 1
    UNION ALL
    SELECT 4, 'D4', '% a vencer em 7 dias', 100.0 * AVG((dias_ate_vencer BETWEEN 0 AND 7)::int), '%', 10, TRUE
      FROM bi.fato_estoque WHERE tem_validade = 1
    UNION ALL
    SELECT 5, 'D5', 'Itens em risco na UF nº 1 do ranking', MAX(itens_em_risco), 'itens', NULL, TRUE
      FROM bi.kpi_d5_ranking_vencimento_uf
    UNION ALL
    SELECT 7, 'D7', 'Vida útil no cadastro (média)', AVG(vida_util_dias), 'dias', NULL, FALSE
      FROM bi.fato_estoque WHERE tem_validade = 1
    UNION ALL
    SELECT 8, 'D8', '% itens sem validade', 100.0 * AVG(1 - tem_validade), '%', 10, TRUE FROM bi.fato_estoque
    UNION ALL
    SELECT 9, 'D9', 'Maior índice de desperdício por categoria', MAX(d9_indice_desperdicio), 'itens/household', NULL, TRUE
      FROM bi.kpi_d9_desperdicio_categoria
    UNION ALL
    SELECT 20, 'F1', '% inadimplência', 100.0 * AVG((status = 'OVERDUE')::int), '%', 8, TRUE
      FROM bi.fato_pagamento WHERE status IN ('PAID', 'OVERDUE')
    UNION ALL
    SELECT 21, 'F2', '% pagos no prazo', 100.0 * AVG(pago_no_prazo), '%', 90, FALSE
      FROM bi.fato_pagamento WHERE status = 'PAID'
    UNION ALL
    SELECT 22, 'U1', '% households ativos', 100.0 * AVG((status = 'ACTIVE')::int), '%', 85, FALSE
      FROM bi.dim_perfil WHERE tipo = 'HOUSEHOLD'
)
SELECT codigo, kpi, ROUND(valor, 2) AS valor, unidade, meta, ROUND(valor - meta, 2) AS desvio,
       CASE WHEN meta IS NULL THEN 'SEM_META'
            WHEN (valor <= meta) = menor_melhor THEN 'DENTRO_DA_META'
            ELSE 'FORA_DA_META' END AS situacao
FROM k ORDER BY ordem;
$view$;
    END IF;

    IF to_regclass('bi.vw_volume_tabelas') IS NOT NULL THEN
        EXECUTE $view$
CREATE OR REPLACE VIEW bi.vw_volume_tabelas AS
SELECT tabela, registros,
       CASE WHEN tabela IN ('category', 'plan') THEN 'DOMINIO_FIXO'
            WHEN registros >= 500 THEN 'OK'
            WHEN tabela IN ('company', 'store') THEN 'LIMITADO_PELOS_PROFILES'
            ELSE 'ABAIXO_DE_500' END AS situacao
FROM (VALUES
    ('address', (SELECT COUNT(*) FROM address)),
    ('auth_method', (SELECT COUNT(*) FROM auth_method)),
    ('category', (SELECT COUNT(*) FROM category)),
    ('company', (SELECT COUNT(*) FROM company)),
    ('food', (SELECT COUNT(*) FROM food)),
    ('pantry_item', (SELECT COUNT(*) FROM pantry_item)),
    ('payment', (SELECT COUNT(*) FROM payment)),
    ('plan', (SELECT COUNT(*) FROM plan)),
    ('profile', (SELECT COUNT(*) FROM profile)),
    ('profile_phone', (SELECT COUNT(*) FROM profile_phone)),
    ('store', (SELECT COUNT(*) FROM store)),
    ('bi_hist.registro_estoque', (SELECT COUNT(*) FROM bi_hist.registro_estoque))
) AS v (tabela, registros);
$view$;
    END IF;
END;
$$;

DROP VIEW IF EXISTS bi.kpi_d6_estoque_minimo_uf;
DROP VIEW IF EXISTS bi.fato_estoque_minimo;
DROP FUNCTION IF EXISTS public.fn_get_items_below_minimum(INTEGER);
DROP TABLE public.pantry_product_setting;
