CREATE TRIGGER trg_pantry_household_type
    BEFORE INSERT OR UPDATE OF profile_id ON pantry_item
    FOR EACH ROW EXECUTE FUNCTION validate_profile_reference_type('HOUSEHOLD');

CREATE TRIGGER trg_pantry_product_setting_household_type
    BEFORE INSERT OR UPDATE OF profile_id ON pantry_product_setting
    FOR EACH ROW EXECUTE FUNCTION validate_profile_reference_type('HOUSEHOLD');

CREATE TRIGGER trg_company_profile_type
    BEFORE INSERT OR UPDATE OF profile_id ON company
    FOR EACH ROW EXECUTE FUNCTION validate_profile_reference_type('COMPANY');

CREATE TRIGGER trg_store_profile_type
    BEFORE INSERT OR UPDATE OF profile_id ON store
    FOR EACH ROW EXECUTE FUNCTION validate_profile_reference_type('STORE');

CREATE TRIGGER trg_profile_type_lock
    BEFORE UPDATE ON profile
    FOR EACH ROW EXECUTE FUNCTION prevent_profile_type_change();