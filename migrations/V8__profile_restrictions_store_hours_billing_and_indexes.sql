-- Restrições são uma lista de códigos no perfil; o catálogo permanece no frontend.
ALTER TABLE profile
    ADD COLUMN dietary_restrictions TEXT[] NOT NULL DEFAULT '{}'::TEXT[];

-- Um único horário de abertura e fechamento vale para todos os dias da loja.
ALTER TABLE store
    ADD COLUMN opening_time TIME WITHOUT TIME ZONE,
    ADD COLUMN closing_time TIME WITHOUT TIME ZONE,
    ADD CONSTRAINT chk_store_business_hours CHECK (
        (opening_time IS NULL AND closing_time IS NULL)
        OR (
            opening_time IS NOT NULL
            AND closing_time IS NOT NULL
            AND closing_time > opening_time
        )
    );

-- Trigramas aceleram buscas por trecho; PostGIS permite consultas geográficas por raio.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS postgis;

-- Listagem do estoque por validade e consultas por perfil/alimento/validade.
CREATE INDEX IF NOT EXISTS idx_pantry_profile_expiry_id
    ON pantry_item (profile_id, expiry_date ASC NULLS LAST, id DESC);
CREATE INDEX IF NOT EXISTS idx_pantry_profile_food_expiry
    ON pantry_item (profile_id, food_id, expiry_date);

-- Varreduras globais de vencimento usam intervalos de data e ordenação por data/ID.
CREATE INDEX IF NOT EXISTS idx_pantry_expiry_id
    ON pantry_item (expiry_date, id)
    WHERE expiry_date IS NOT NULL;

-- Histórico financeiro, verificação de inadimplência e busca de pendências vencidas.
CREATE INDEX IF NOT EXISTS idx_payment_company_due
    ON payment (company_id, due_date DESC);
CREATE INDEX IF NOT EXISTS idx_payment_company_status_due
    ON payment (company_id, payment_status, due_date DESC);
CREATE INDEX IF NOT EXISTS idx_payment_pending_due
    ON payment (due_date)
    WHERE payment_status = 'PENDING';

-- Uma cobrança por empresa/competência garante idempotência também sob concorrência.
CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_company_period
    ON payment (company_id, billing_period_start);

-- Listagem de lojas por empresa e busca de e-mail sem distinguir maiúsculas/minúsculas.
CREATE INDEX IF NOT EXISTS idx_store_company
    ON store (company_id);
CREATE INDEX IF NOT EXISTS idx_profile_email_lower
    ON profile (lower(email));

-- A IA já usa LOWER; padronizar a consulta do Core permite compartilhar o mesmo GIN.
CREATE INDEX IF NOT EXISTS idx_food_name_lower_trgm
    ON food USING GIN (lower(name) gin_trgm_ops);

-- Listagem alfabética do catálogo e nomes de categoria únicos sem distinguir caixa.
CREATE INDEX IF NOT EXISTS idx_food_name
    ON food (name);
CREATE UNIQUE INDEX IF NOT EXISTS uq_category_name_lower
    ON category (lower(category_name));

-- O GiST atende ST_DWithin na mesma expressão; o B-tree permite juntar endereço ao perfil.
CREATE INDEX IF NOT EXISTS idx_address_geography
    ON address USING GIST (
        (
            ST_SetSRID(
                ST_MakePoint(
                    longitude::double precision,
                    latitude::double precision
                ),
                4326
            )::geography
        )
    )
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profile_address
    ON profile (address_id)
    WHERE address_id IS NOT NULL;

-- Produtos de perfis ativos com validade dentro da janela inclusiva solicitada.
CREATE OR REPLACE FUNCTION fn_get_expiring_products(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    profile_id INTEGER,
    item_id INTEGER,
    food_name VARCHAR,
    expiry_date DATE
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_start_date IS NULL OR p_end_date IS NULL OR p_start_date > p_end_date THEN
        RAISE EXCEPTION 'Intervalo de datas inválido: % até %', p_start_date, p_end_date
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT pi.profile_id, pi.id, f.name, pi.expiry_date
    FROM pantry_item pi
    JOIN food f ON f.id = pi.food_id
    JOIN profile pr ON pr.id = pi.profile_id
    WHERE pi.expiry_date BETWEEN p_start_date AND p_end_date
      AND pr.status = 'ACTIVE'
    ORDER BY pi.expiry_date, pi.id;
END;
$$;

-- Calcula faltas incluindo alimentos sem estoque e excluindo lotes já vencidos.
-- O filtro de perfil também limita a agregação do estoque quando informado.
CREATE OR REPLACE FUNCTION fn_get_items_below_minimum(
    p_profile_id INTEGER DEFAULT NULL
)
RETURNS TABLE (
    profile_id INTEGER,
    food_id INTEGER,
    food_name VARCHAR,
    minimum_quantity INTEGER,
    current_quantity INTEGER,
    missing_quantity INTEGER
)
LANGUAGE sql
STABLE
AS $$
    SELECT s.profile_id,
           s.food_id,
           f.name,
           s.minimum_quantity,
           COALESCE(stock.total, 0)::INTEGER,
           (s.minimum_quantity - COALESCE(stock.total, 0))::INTEGER
    FROM pantry_product_setting s
    JOIN food f ON f.id = s.food_id
    LEFT JOIN (
        SELECT pi.profile_id, pi.food_id, SUM(pi.quantity) AS total
        FROM pantry_item pi
        WHERE (p_profile_id IS NULL OR pi.profile_id = p_profile_id)
          AND (pi.expiry_date IS NULL OR pi.expiry_date >= CURRENT_DATE)
        GROUP BY pi.profile_id, pi.food_id
    ) stock ON stock.profile_id = s.profile_id AND stock.food_id = s.food_id
    WHERE (p_profile_id IS NULL OR s.profile_id = p_profile_id)
      AND COALESCE(stock.total, 0) < s.minimum_quantity
    ORDER BY s.profile_id,
             (s.minimum_quantity - COALESCE(stock.total, 0)) DESC,
             f.name;
$$;

-- Gera pendências mensais para empresas ativas ou bloqueadas, sem duplicar competência.
CREATE OR REPLACE PROCEDURE sp_generate_monthly_payments(
    p_reference_date DATE DEFAULT CURRENT_DATE,
    p_due_day INTEGER DEFAULT 10,
    INOUT p_created_count INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_period_start DATE := date_trunc('month', p_reference_date)::DATE;
    v_period_end DATE := (date_trunc('month', p_reference_date)
                         + INTERVAL '1 month - 1 day')::DATE;
BEGIN
    IF p_reference_date IS NULL THEN
        RAISE EXCEPTION 'A data de referência é obrigatória'
            USING ERRCODE = '22023';
    END IF;
    IF p_due_day IS NULL OR p_due_day NOT BETWEEN 1 AND 28 THEN
        RAISE EXCEPTION 'O dia de vencimento deve estar entre 1 e 28: %', p_due_day
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO payment (
        due_date, billing_period_start, billing_period_end,
        payment_status, company_id, plan_id, amount
    )
    SELECT v_period_start + (p_due_day - 1),
           v_period_start,
           v_period_end,
           'PENDING',
           c.id,
           p.id,
           p.plan_price
    FROM company c
    JOIN plan p ON p.id = c.plan_id
    JOIN profile pr ON pr.id = c.profile_id
    WHERE pr.status <> 'INACTIVE'
      AND NOT EXISTS (
          SELECT 1 FROM payment pa
          WHERE pa.company_id = c.id
            AND pa.billing_period_start = v_period_start
      )
    ON CONFLICT (company_id, billing_period_start) DO NOTHING;

    GET DIAGNOSTICS p_created_count = ROW_COUNT;
END;
$$;

-- Marca pendências vencidas e bloqueia a empresa e suas lojas; quitar reativa as bloqueadas.
-- As contagens de bloqueio/reativação representam empresas, sem incluir lojas.
CREATE OR REPLACE PROCEDURE sp_update_overdue_payments(
    p_grace_days INTEGER DEFAULT 0,
    INOUT p_overdue_count INTEGER DEFAULT NULL,
    INOUT p_blocked_count INTEGER DEFAULT NULL,
    INOUT p_unblocked_count INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_grace_days IS NULL OR p_grace_days < 0 THEN
        RAISE EXCEPTION 'A tolerância deve ser um número de dias não negativo: %', p_grace_days
            USING ERRCODE = '22023';
    END IF;

    UPDATE payment
    SET payment_status = 'OVERDUE', updated_at = CURRENT_TIMESTAMP
    WHERE payment_status = 'PENDING'
      AND due_date < CURRENT_DATE - p_grace_days;
    GET DIAGNOSTICS p_overdue_count = ROW_COUNT;

    WITH defaulters AS (
        SELECT c.id AS company_id, c.profile_id
        FROM company c
        JOIN profile pr ON pr.id = c.profile_id
        WHERE pr.status IN ('ACTIVE', 'BLOCKED')
          AND EXISTS (
              SELECT 1 FROM payment pa
              WHERE pa.company_id = c.id AND pa.payment_status = 'OVERDUE'
          )
    ), blocked_stores AS (
        UPDATE profile sp
        SET status = 'BLOCKED'
        FROM store s
        JOIN defaulters d ON d.company_id = s.company_id
        WHERE sp.id = s.profile_id AND sp.status = 'ACTIVE'
        RETURNING sp.id
    ), blocked_companies AS (
        UPDATE profile pr
        SET status = 'BLOCKED'
        FROM defaulters d
        WHERE pr.id = d.profile_id AND pr.status = 'ACTIVE'
        RETURNING pr.id
    )
    SELECT COUNT(*) INTO p_blocked_count FROM blocked_companies;

    WITH settled AS (
        SELECT c.id AS company_id, c.profile_id
        FROM company c
        JOIN profile pr ON pr.id = c.profile_id
        WHERE pr.status IN ('ACTIVE', 'BLOCKED')
          AND NOT EXISTS (
              SELECT 1 FROM payment pa
              WHERE pa.company_id = c.id AND pa.payment_status = 'OVERDUE'
          )
    ), unblocked_stores AS (
        UPDATE profile sp
        SET status = 'ACTIVE'
        FROM store s
        JOIN settled st ON st.company_id = s.company_id
        WHERE sp.id = s.profile_id AND sp.status = 'BLOCKED'
        RETURNING sp.id
    ), unblocked_companies AS (
        UPDATE profile pr
        SET status = 'ACTIVE'
        FROM settled st
        WHERE pr.id = st.profile_id AND pr.status = 'BLOCKED'
        RETURNING pr.id
    )
    SELECT COUNT(*) INTO p_unblocked_count FROM unblocked_companies;
END;
$$;
