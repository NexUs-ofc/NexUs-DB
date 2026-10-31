CREATE SCHEMA bi_hist;

CREATE TABLE bi_hist.registro_estoque (
    id SERIAL PRIMARY KEY,
    profile_id INTEGER NOT NULL REFERENCES public.profile(id) ON DELETE CASCADE,
    food_id INTEGER NOT NULL REFERENCES public.food(id),
    event_type VARCHAR(30) NOT NULL CHECK (event_type IN ('item_consumed', 'item_expired')),
    event_date TIMESTAMP NOT NULL,
    purchase_date TIMESTAMP NOT NULL,
    expiry_date DATE,
    consumed_quantity INTEGER NOT NULL DEFAULT 0 CHECK (consumed_quantity >= 0),
    discarded_quantity INTEGER NOT NULL DEFAULT 0 CHECK (discarded_quantity >= 0),
    estimated_loss DECIMAL(10,2) NOT NULL DEFAULT 0
);
