CREATE TYPE profile_type_enum AS ENUM ('HOUSEHOLD', 'ADMIN', 'COMPANY', 'STORE');
CREATE TYPE unit_of_measure_enum AS ENUM ('g', 'kg', 'ml', 'l', 'unit');
CREATE TYPE payment_status_enum AS ENUM ('PENDING', 'PAID', 'OVERDUE', 'CANCELLED');
CREATE TYPE profile_status_enum AS ENUM ('ACTIVE', 'INACTIVE', 'BLOCKED');
CREATE TYPE auth_provider_enum AS ENUM ('GOOGLE', 'PASSWORD');