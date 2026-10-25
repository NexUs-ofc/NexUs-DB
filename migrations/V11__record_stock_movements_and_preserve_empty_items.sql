ALTER TABLE public.pantry_item
    DROP CONSTRAINT pantry_item_quantity_check;

ALTER TABLE public.pantry_item
    ADD CONSTRAINT pantry_item_quantity_check CHECK (quantity >= 0);

CREATE SCHEMA IF NOT EXISTS bi_hist;

CREATE TABLE IF NOT EXISTS bi_hist.registro_estoque (
    id SERIAL PRIMARY KEY,
    pantry_item_id INTEGER NOT NULL REFERENCES public.pantry_item(id) ON DELETE RESTRICT,
    event_type VARCHAR(30) NOT NULL CHECK (event_type IN ('CONSUMED', 'DISCARDED')),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    event_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estimated_loss DECIMAL(10,2)
);

DO $$
DECLARE
    movement RECORD;
    item_id INTEGER;
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'bi_hist' AND table_name = 'registro_estoque' AND column_name = 'profile_id'
    ) THEN
        IF EXISTS (
            SELECT 1 FROM bi_hist.registro_estoque
            WHERE (event_type = 'item_consumed' AND (consumed_quantity <= 0 OR discarded_quantity <> 0))
               OR (event_type = 'item_expired' AND (discarded_quantity <= 0 OR consumed_quantity <> 0))
        ) THEN
            RAISE EXCEPTION 'Historico inconsistente: revise o tipo e as quantidades antes de migrar';
        END IF;

        ALTER TABLE bi_hist.registro_estoque
            ADD COLUMN pantry_item_id INTEGER REFERENCES public.pantry_item(id) ON DELETE RESTRICT,
            ADD COLUMN quantity INTEGER;

        FOR movement IN
            SELECT id, profile_id, food_id, purchase_date, expiry_date
            FROM bi_hist.registro_estoque ORDER BY id
        LOOP
            INSERT INTO public.pantry_item (food_id, profile_id, quantity, expiry_date, created_at)
            VALUES (movement.food_id, movement.profile_id, 0, movement.expiry_date, movement.purchase_date)
            RETURNING id INTO item_id;

            UPDATE bi_hist.registro_estoque SET pantry_item_id = item_id WHERE id = movement.id;
        END LOOP;

        ALTER TABLE bi_hist.registro_estoque DROP CONSTRAINT registro_estoque_event_type_check;

        UPDATE bi_hist.registro_estoque
        SET quantity = CASE WHEN event_type = 'item_consumed' THEN consumed_quantity ELSE discarded_quantity END,
            event_type = CASE WHEN event_type = 'item_consumed' THEN 'CONSUMED' ELSE 'DISCARDED' END;

        ALTER TABLE bi_hist.registro_estoque
            ALTER COLUMN pantry_item_id SET NOT NULL,
            ALTER COLUMN quantity SET NOT NULL,
            ALTER COLUMN event_date SET DEFAULT CURRENT_TIMESTAMP,
            ALTER COLUMN estimated_loss DROP NOT NULL,
            ALTER COLUMN estimated_loss DROP DEFAULT,
            ADD CONSTRAINT registro_estoque_quantity_check CHECK (quantity > 0),
            ADD CONSTRAINT registro_estoque_event_type_check CHECK (event_type IN ('CONSUMED', 'DISCARDED'));
    END IF;

    IF to_regclass('bi.fato_movimento') IS NOT NULL THEN
        EXECUTE $view$
            CREATE OR REPLACE VIEW bi.fato_movimento AS
            SELECT r.id AS id_movimento, i.food_id AS sk_alimento, i.profile_id AS sk_perfil,
                   COALESCE(p.address_id, -1) AS sk_localidade,
                   TO_CHAR(r.event_date, 'YYYYMMDD')::int AS sk_data_evento,
                   TO_CHAR(i.created_at, 'YYYYMMDD')::int AS sk_data_compra,
                   COALESCE(TO_CHAR(i.expiry_date, 'YYYYMMDD')::int, -1) AS sk_data_validade,
                   r.event_type AS tipo_evento,
                   (r.event_type = 'DISCARDED')::int AS expirado,
                   (r.event_type = 'CONSUMED')::int AS consumido,
                   CASE WHEN r.event_type = 'CONSUMED' THEN r.quantity ELSE 0 END AS qtd_consumida,
                   CASE WHEN r.event_type = 'DISCARDED' THEN r.quantity ELSE 0 END AS qtd_descartada,
                   r.estimated_loss AS perda_estimada,
                   r.event_date::date - i.created_at::date AS dias_em_casa
            FROM bi_hist.registro_estoque r
            JOIN public.pantry_item i ON i.id = r.pantry_item_id
            JOIN public.profile p ON p.id = i.profile_id
        $view$;
    END IF;

    IF to_regclass('bi.dim_tempo') IS NOT NULL THEN
        EXECUTE $view$
            CREATE OR REPLACE VIEW bi.dim_tempo AS
            SELECT TO_CHAR(d, 'YYYYMMDD')::int AS sk_data, d::date AS data,
                   EXTRACT(YEAR FROM d)::int AS ano, EXTRACT(MONTH FROM d)::int AS mes,
                   TO_CHAR(d, 'YYYY-MM') AS ano_mes, EXTRACT(QUARTER FROM d)::int AS trimestre,
                   EXTRACT(ISODOW FROM d)::int AS dia_semana,
                   EXTRACT(ISODOW FROM d) IN (6, 7) AS fim_de_semana
            FROM generate_series(
                LEAST((SELECT MIN(created_at)::date FROM public.profile),
                      (SELECT MIN(billing_period_start) FROM public.payment), CURRENT_DATE),
                GREATEST((SELECT MAX(expiry_date) FROM public.pantry_item), CURRENT_DATE + 365),
                INTERVAL '1 day') AS d
            UNION ALL SELECT -1, NULL, NULL, NULL, 'N/I', NULL, NULL, NULL
        $view$;
    END IF;

    IF to_regclass('bi.fato_estoque') IS NOT NULL THEN
        EXECUTE $view$
            CREATE OR REPLACE VIEW bi.fato_estoque AS
            SELECT i.id AS id_item, i.food_id AS sk_alimento, i.profile_id AS sk_perfil,
                   COALESCE(p.address_id, -1) AS sk_localidade,
                   TO_CHAR(i.created_at, 'YYYYMMDD')::int AS sk_data_entrada,
                   COALESCE(TO_CHAR(i.expiry_date, 'YYYYMMDD')::int, -1) AS sk_data_validade,
                   i.quantity AS quantidade, (i.expiry_date IS NOT NULL)::int AS tem_validade,
                   i.expiry_date - CURRENT_DATE AS dias_ate_vencer,
                   i.expiry_date - i.created_at::date AS vida_util_dias,
                   CASE WHEN i.expiry_date IS NULL THEN 'SEM_VALIDADE'
                        WHEN i.expiry_date < CURRENT_DATE THEN 'VENCIDO'
                        WHEN i.expiry_date <= CURRENT_DATE + 7 THEN 'VENCE_7D'
                        WHEN i.expiry_date <= CURRENT_DATE + 30 THEN 'VENCE_30D'
                        ELSE 'OK' END AS status_validade
            FROM public.pantry_item i JOIN public.profile p ON p.id = i.profile_id
            WHERE i.quantity > 0
        $view$;
    END IF;
END;
$$;

ALTER TABLE bi_hist.registro_estoque
    DROP COLUMN IF EXISTS profile_id,
    DROP COLUMN IF EXISTS food_id,
    DROP COLUMN IF EXISTS purchase_date,
    DROP COLUMN IF EXISTS expiry_date,
    DROP COLUMN IF EXISTS consumed_quantity,
    DROP COLUMN IF EXISTS discarded_quantity;

CREATE INDEX IF NOT EXISTS ix_registro_estoque_item_data
    ON bi_hist.registro_estoque (pantry_item_id, event_date, id);

COMMENT ON TABLE bi_hist.registro_estoque IS
    'Movimentos de saida registrados pelo Core na mesma transacao da baixa do saldo. Uma linha por operacao.';
COMMENT ON COLUMN bi_hist.registro_estoque.pantry_item_id IS
    'Lote movimentado. Perfil, alimento, entrada e validade sao obtidos por pantry_item, preservado com saldo zero.';
COMMENT ON COLUMN bi_hist.registro_estoque.event_type IS
    'CONSUMED: consumo; DISCARDED: descarte, mesmo sem vencimento. Correcoes nao geram movimentos.';
COMMENT ON COLUMN bi_hist.registro_estoque.quantity IS
    'Quantidade positiva de embalagens movimentadas, nunca o saldo restante.';
COMMENT ON COLUMN bi_hist.registro_estoque.estimated_loss IS
    'Perda monetaria quando conhecida. Valores legados preservados; o Core nao estima perdas sem preco de compra.';
COMMENT ON COLUMN public.pantry_item.quantity IS
    'Saldo nao negativo. Zero preserva o lote e seu historico, mas e omitido do estoque disponivel.';
