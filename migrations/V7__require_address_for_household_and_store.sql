ALTER TABLE profile
ADD CONSTRAINT chk_profile_required_address
CHECK (
    type NOT IN ('HOUSEHOLD', 'STORE')
    OR address_id IS NOT NULL
);
