-- Desvincula a dimensão de BI antes de remover o limite do plano.
-- Mantém a coluna legada da view como NULL para preservar seus consumidores.
DO $$
BEGIN
    IF to_regclass('bi.dim_empresa') IS NOT NULL THEN
        EXECUTE $view$
CREATE OR REPLACE VIEW bi.dim_empresa AS
SELECT c.id AS sk_empresa, pl.plan_name AS plano, pl.plan_price AS preco_plano,
       NULL::INTEGER AS limite_lojas,
       (SELECT COUNT(*) FROM public.store s WHERE s.company_id = c.id) AS qtd_lojas
FROM public.company c JOIN public.plan pl ON pl.id = c.plan_id;
$view$;
    END IF;
END;
$$;

ALTER TABLE public.plan DROP COLUMN store_limit;
