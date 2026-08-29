CREATE OR REPLACE FUNCTION validate_profile_reference_type() RETURNS TRIGGER AS $$
DECLARE
    actual_type profile_type_enum;
    expected_type profile_type_enum;
BEGIN
    SELECT type
      INTO actual_type
      FROM profile
     WHERE id = NEW.profile_id;

    IF actual_type IS NULL THEN
        RAISE EXCEPTION 'profile % does not exist', NEW.profile_id;
    END IF;

    expected_type := TG_ARGV[0]::profile_type_enum;

    IF actual_type <> expected_type THEN
        RAISE EXCEPTION
            'profile_id must reference a profile of type %, received %',
            expected_type,
            actual_type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION prevent_profile_type_change() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.type IS DISTINCT FROM NEW.type THEN
        RAISE EXCEPTION 'profile type cannot be changed after creation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
