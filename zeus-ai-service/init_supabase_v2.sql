-- ============================================================
-- Zeus Insurance App - Comprehensive Market Data & Quotation System
-- ============================================================

-- 1. Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Drop old tables/views to avoid conflicts during re-initialization
DROP VIEW IF EXISTS vw_quotation_details CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS quotations CASCADE;
DROP TABLE IF EXISTS plan_premiums CASCADE;
DROP TABLE IF EXISTS plan_coverages CASCADE;
DROP TABLE IF EXISTS insurance_plans CASCADE;
DROP TABLE IF EXISTS car_models CASCADE;
DROP TABLE IF EXISTS car_brands CASCADE;
DROP TABLE IF EXISTS policy_documents CASCADE;
DROP TABLE IF EXISTS chat_sessions CASCADE;

-- ============================================================
-- 2. Core Relational Tables
-- ============================================================
CREATE TABLE car_brands (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE car_models (
    id SERIAL PRIMARY KEY,
    brand_id INT REFERENCES car_brands(id),
    name VARCHAR(100) NOT NULL,
    sub_model VARCHAR(100),
    year INT NOT NULL,
    estimated_price NUMERIC(12, 2) NOT NULL
);

CREATE TABLE insurance_plans (
    id SERIAL PRIMARY KEY,
    plan_type VARCHAR(50) NOT NULL,
    plan_name VARCHAR(100) NOT NULL,
    insurer_name VARCHAR(100) NOT NULL
);

CREATE TABLE plan_coverages (
    id SERIAL PRIMARY KEY,
    plan_id INT REFERENCES insurance_plans(id),
    coverage_type VARCHAR(100) NOT NULL,
    coverage_limit NUMERIC(12, 2)
);

CREATE TABLE plan_premiums (
    id SERIAL PRIMARY KEY,
    plan_id INT REFERENCES insurance_plans(id),
    car_model_id INT REFERENCES car_models(id),
    base_premium NUMERIC(12, 2) NOT NULL,
    deductible NUMERIC(12, 2) DEFAULT 0
);

-- ============================================================
-- 3. Quotation & Order Management Tables
-- ============================================================
CREATE TABLE quotations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL,
    car_model_id INT REFERENCES car_models(id),
    plan_id INT REFERENCES insurance_plans(id),
    customer_name VARCHAR(200),
    customer_email VARCHAR(200),
    customer_phone VARCHAR(50),
    car_estimated_price NUMERIC(12, 2) NOT NULL,
    base_premium NUMERIC(12, 2) NOT NULL,
    deductible NUMERIC(12, 2) NOT NULL,
    total_premium NUMERIC(12, 2) NOT NULL,
    quotation_number VARCHAR(50) UNIQUE NOT NULL,
    valid_until TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) DEFAULT 'draft', -- draft, sent, accepted, expired
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quotation_id UUID REFERENCES quotations(id),
    order_number VARCHAR(50) UNIQUE NOT NULL,
    payment_status VARCHAR(50) DEFAULT 'pending', -- pending, paid, failed, refunded
    payment_method VARCHAR(50),
    payment_date TIMESTAMPTZ,
    policy_number VARCHAR(50) UNIQUE,
    policy_start_date DATE,
    policy_end_date DATE,
    policy_status VARCHAR(50) DEFAULT 'inactive', -- inactive, active, cancelled, expired
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 4. Advanced RAG Table
-- ============================================================
CREATE TABLE policy_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_type VARCHAR(50),
    section VARCHAR(50),
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::JSONB,
    embedding VECTOR(2000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS policy_documents_embedding_idx
    ON policy_documents
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- ============================================================
-- 5. Session Table
-- ============================================================
CREATE TABLE chat_sessions (
    id BIGSERIAL PRIMARY KEY,
    session_id UUID NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('user', 'ai')),
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 6. Read-Only View: vw_quotation_details
-- ============================================================
CREATE VIEW vw_quotation_details AS
SELECT 
    cb.name AS brand,
    cm.name AS model,
    cm.sub_model,
    cm.year,
    cm.estimated_price AS car_estimated_price,
    ip.plan_type,
    ip.plan_name,
    ip.insurer_name,
    pp.base_premium,
    pp.deductible,
    cm.id AS car_model_id,
    ip.id AS plan_id
FROM car_models cm
JOIN car_brands cb ON cm.brand_id = cb.id
JOIN plan_premiums pp ON pp.car_model_id = cm.id
JOIN insurance_plans ip ON pp.plan_id = ip.id;

-- ============================================================
-- 7. RLS Policies
-- ============================================================
ALTER TABLE car_brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE car_models ENABLE ROW LEVEL SECURITY;
ALTER TABLE insurance_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_coverages ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_premiums ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE quotations ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read on car_brands" ON car_brands FOR SELECT USING (true);
CREATE POLICY "Allow public read on car_models" ON car_models FOR SELECT USING (true);
CREATE POLICY "Allow public read on insurance_plans" ON insurance_plans FOR SELECT USING (true);
CREATE POLICY "Allow public read on plan_coverages" ON plan_coverages FOR SELECT USING (true);
CREATE POLICY "Allow public read on plan_premiums" ON plan_premiums FOR SELECT USING (true);
CREATE POLICY "Allow public read on policy_documents" ON policy_documents FOR SELECT USING (true);
CREATE POLICY "Allow service role full access to policy_documents" ON policy_documents FOR ALL USING (true);
CREATE POLICY "Allow service role full access to chat_sessions" ON chat_sessions FOR ALL USING (true);
CREATE POLICY "Allow service role full access to quotations" ON quotations FOR ALL USING (true);
CREATE POLICY "Allow service role full access to orders" ON orders FOR ALL USING (true);

-- ============================================================
-- 8. RPC Function for Semantic Search
-- ============================================================
CREATE OR REPLACE FUNCTION match_documents(
    query_embedding VECTOR(2000),
    match_threshold FLOAT DEFAULT 0.4,
    match_count INT DEFAULT 5,
    filter_section VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    plan_type VARCHAR,
    section VARCHAR,
    content TEXT,
    metadata JSONB,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        pd.id,
        pd.plan_type,
        pd.section,
        pd.content,
        pd.metadata,
        1 - (pd.embedding <=> query_embedding) AS similarity
    FROM policy_documents pd
    WHERE 1 - (pd.embedding <=> query_embedding) > match_threshold
      AND (filter_section IS NULL OR pd.section = filter_section)
    ORDER BY pd.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- ============================================================
-- 9. Comprehensive Mock Data - Car Brands & Models
-- ============================================================
INSERT INTO car_brands (name) VALUES 
    ('Honda'), ('Toyota'), ('Mazda'), ('Isuzu'), ('Mitsubishi'),
    ('Nissan'), ('Ford'), ('Chevrolet'), ('MG'), ('BYD'),
    ('GWM'), ('Tesla'), ('BMW'), ('Mercedes-Benz'), ('Audi'),
    ('Porsche'), ('Volvo'), ('Subaru'), ('Suzuki'), ('Hyundai');

-- Honda Models (10 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Honda'), 'Civic', 'Type R', 2024, 2350000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'Civic', 'e:HEV RS', 2024, 1699000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'Civic', 'EL', 2024, 1099000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'City', 'SV', 2024, 699000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'City', 'RS', 2024, 759000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'HR-V', 'e:HEV EL', 2024, 1079000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'HR-V', 'RS', 2024, 1149000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'CR-V', 'e:HEV EL', 2024, 1699000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'Accord', 'e:HEV EL', 2024, 1799000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'Jazz', 'RS', 2024, 679000.00);

-- Toyota Models (12 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Camry', 'Hybrid Premium', 2024, 1599000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Camry', '2.5 HV Premium', 2024, 1699000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Yaris Cross', 'Premium', 2024, 849000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Yaris Cross', 'Mid', 2024, 779000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Fortuner', 'Legender', 2024, 1859000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Fortuner', '2.8 V', 2024, 1699000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Hilux Revo', 'Rocco', 2024, 1199000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Corolla Cross', 'Hybrid Premium', 2024, 1199000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Corolla Altis', 'Hybrid Premium', 2024, 1049000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Veloz', 'Premium', 2024, 799000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Alphard', 'Hybrid', 2024, 5499000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Vios', 'Premium', 2024, 629000.00);

-- Mazda Models (6 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Mazda'), 'CX-5', '2.5 Turbo SP', 2024, 1799000.00),
    ((SELECT id FROM car_brands WHERE name='Mazda'), 'CX-5', '2.0 S', 2024, 1299000.00),
    ((SELECT id FROM car_brands WHERE name='Mazda'), 'CX-3', '2.0 SP', 2024, 1049000.00),
    ((SELECT id FROM car_brands WHERE name='Mazda'), 'CX-30', '2.0 SP', 2024, 1249000.00),
    ((SELECT id FROM car_brands WHERE name='Mazda'), '3', '2.0 SP Sedan', 2024, 1099000.00),
    ((SELECT id FROM car_brands WHERE name='Mazda'), 'BT-50', 'Pro Thunder', 2024, 1199000.00);

-- Isuzu Models (4 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Isuzu'), 'D-Max', 'Hi-Lander Z-Prestige', 2024, 1054000.00),
    ((SELECT id FROM car_brands WHERE name='Isuzu'), 'D-Max', 'X-Series', 2024, 899000.00),
    ((SELECT id FROM car_brands WHERE name='Isuzu'), 'MU-X', 'Ultimate', 2024, 1539000.00),
    ((SELECT id FROM car_brands WHERE name='Isuzu'), 'MU-X', 'Prestige', 2024, 1399000.00);

-- MG Models (5 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='MG'), 'ZS EV', 'Long Range', 2024, 1190000.00),
    ((SELECT id FROM car_brands WHERE name='MG'), 'MG4 EV', 'Long Range', 2024, 1099000.00),
    ((SELECT id FROM car_brands WHERE name='MG'), 'HS', '2.0 X', 2024, 1099000.00),
    ((SELECT id FROM car_brands WHERE name='MG'), 'EP', 'Executive', 2024, 1399000.00),
    ((SELECT id FROM car_brands WHERE name='MG'), '5', 'D', 2024, 599000.00);

-- BYD Models (5 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='BYD'), 'Seal', 'Premium', 2024, 1449000.00),
    ((SELECT id FROM car_brands WHERE name='BYD'), 'Seal', 'Excellence', 2024, 1599000.00),
    ((SELECT id FROM car_brands WHERE name='BYD'), 'Dolphin', 'Extended Range', 2024, 859900.00),
    ((SELECT id FROM car_brands WHERE name='BYD'), 'Atto 3', 'Extended Range', 2024, 1099000.00),
    ((SELECT id FROM car_brands WHERE name='BYD'), 'Atto 3', 'Standard Range', 2024, 999000.00);

-- GWM Models (3 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='GWM'), 'Tank', '300 Hi-Torq', 2024, 1799000.00),
    ((SELECT id FROM car_brands WHERE name='GWM'), 'Tank', '300 Urban', 2024, 1599000.00),
    ((SELECT id FROM car_brands WHERE name='GWM'), 'Ora', 'Good Cat Ultra', 2024, 899000.00);

-- Tesla Models (4 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Tesla'), 'Model 3', 'Long Range', 2024, 1899000.00),
    ((SELECT id FROM car_brands WHERE name='Tesla'), 'Model 3', 'Performance', 2024, 2199000.00),
    ((SELECT id FROM car_brands WHERE name='Tesla'), 'Model Y', 'Long Range', 2024, 2099000.00),
    ((SELECT id FROM car_brands WHERE name='Tesla'), 'Model Y', 'Performance', 2024, 2299000.00);

-- BMW Models (4 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='BMW'), '3 Series', '330e M Sport', 2024, 2999000.00),
    ((SELECT id FROM car_brands WHERE name='BMW'), '5 Series', '530e M Sport', 2024, 3799000.00),
    ((SELECT id FROM car_brands WHERE name='BMW'), 'X3', 'xDrive30e M Sport', 2024, 3499000.00),
    ((SELECT id FROM car_brands WHERE name='BMW'), 'iX', 'xDrive50', 2024, 4999000.00);

-- Mercedes-Benz Models (4 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Mercedes-Benz'), 'C-Class', 'C 350e AMG Dynamic', 2024, 3350000.00),
    ((SELECT id FROM car_brands WHERE name='Mercedes-Benz'), 'E-Class', 'E 300e AMG Dynamic', 2024, 3999000.00),
    ((SELECT id FROM car_brands WHERE name='Mercedes-Benz'), 'GLC', 'GLC 300e 4MATIC', 2024, 3799000.00),
    ((SELECT id FROM car_brands WHERE name='Mercedes-Benz'), 'EQS', 'EQS 450+', 2024, 6499000.00);

-- Nissan Models (3 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Nissan'), 'Kicks', 'e-Power V', 2024, 899000.00),
    ((SELECT id FROM car_brands WHERE name='Nissan'), 'Note', 'e-Power VL', 2024, 749000.00),
    ((SELECT id FROM car_brands WHERE name='Nissan'), 'Terra', 'VL 4WD', 2024, 1549000.00);

-- Mitsubishi Models (3 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Mitsubishi'), 'Pajero Sport', 'GT Premium', 2024, 1799000.00),
    ((SELECT id FROM car_brands WHERE name='Mitsubishi'), 'Triton', 'Athlete', 2024, 1099000.00),
    ((SELECT id FROM car_brands WHERE name='Mitsubishi'), 'Xpander', 'GT', 2024, 799000.00);

-- ============================================================
-- 10. Insurance Plans
-- ============================================================
INSERT INTO insurance_plans (plan_type, plan_name, insurer_name) VALUES
    ('Type 1', 'Zeus Comprehensive Plus', 'Zeus Insurance'),
    ('Type 1', 'Zeus EV Shield', 'Zeus Insurance'),
    ('Type 2+', 'Zeus Value Protect', 'Zeus Insurance'),
    ('Type 3+', 'Zeus Budget Safe', 'Zeus Insurance');

-- ============================================================
-- 11. Plan Coverages
-- ============================================================
INSERT INTO plan_coverages (plan_id, coverage_type, coverage_limit) VALUES
    -- Type 1 Comprehensive Plus
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Own Vehicle Damage (Accident)', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Flood and Fire Damage', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Theft and Robbery', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Third Party Property Damage', 2500000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Third Party Bodily Injury', 1000000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Medical Expenses (Driver/Passenger)', 100000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Bail Bond', 300000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Windscreen Damage', NULL),
    
    -- Type 1 EV Shield
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Own Vehicle Damage (Accident)', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Flood and Fire Damage', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Theft and Robbery', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Third Party Property Damage', 2500000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Third Party Bodily Injury', 1000000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Battery Replacement', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Bail Bond', 300000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'EV Charging Equipment', 50000.00),
    
    -- Type 2+ Value Protect
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), 'Own Vehicle Damage (Collision with identified vehicle only)', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), 'Flood and Fire Damage', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), 'Theft and Robbery', NULL),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), 'Third Party Property Damage', 1000000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), 'Third Party Bodily Injury', 500000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), 'Medical Expenses (Driver/Passenger)', 50000.00),
    
    -- Type 3+ Budget Safe
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), 'Own Vehicle Damage (Collision with identified vehicle, max 100,000 THB)', 100000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), 'Third Party Property Damage', 500000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), 'Third Party Bodily Injury', 300000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), 'Medical Expenses (Driver/Passenger)', 30000.00);

-- ============================================================
-- Additional Car Models (2024-2025)
-- ============================================================

-- Ford Models (4 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Ford'), 'Ranger', 'Wildtrak 2.0 Bi-Turbo 4WD', 2024, 1279000.00),
    ((SELECT id FROM car_brands WHERE name='Ford'), 'Ranger', 'Raptor 3.0 V6', 2024, 1959000.00),
    ((SELECT id FROM car_brands WHERE name='Ford'), 'Everest', 'Titanium+ 4WD', 2024, 1999000.00),
    ((SELECT id FROM car_brands WHERE name='Ford'), 'Everest', 'Sport 4WD', 2024, 1799000.00);

-- Hyundai Models (5 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Hyundai'), 'IONIQ 5', 'Long Range AWD', 2024, 2299000.00),
    ((SELECT id FROM car_brands WHERE name='Hyundai'), 'IONIQ 6', 'Long Range AWD', 2024, 2399000.00),
    ((SELECT id FROM car_brands WHERE name='Hyundai'), 'Tucson', 'Hybrid Premium', 2024, 1699000.00),
    ((SELECT id FROM car_brands WHERE name='Hyundai'), 'Creta', 'Sport', 2024, 899000.00),
    ((SELECT id FROM car_brands WHERE name='Hyundai'), 'Staria', 'Premium', 2024, 1899000.00);

-- Subaru Models (3 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Subaru'), 'Forester', 'Advance', 2024, 1799000.00),
    ((SELECT id FROM car_brands WHERE name='Subaru'), 'XV', 'GT Edition', 2024, 1499000.00),
    ((SELECT id FROM car_brands WHERE name='Subaru'), 'Outback', '2.5i-T EyeSight', 2024, 2099000.00);

-- Suzuki Models (3 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Suzuki'), 'Swift', 'GLX', 2024, 639000.00),
    ((SELECT id FROM car_brands WHERE name='Suzuki'), 'Ertiga', 'GX', 2024, 759000.00),
    ((SELECT id FROM car_brands WHERE name='Suzuki'), 'Vitara', '1.4 Turbo GLX', 2024, 1099000.00);

-- Audi Models (3 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Audi'), 'A4', '40 TFSI S line', 2024, 2799000.00),
    ((SELECT id FROM car_brands WHERE name='Audi'), 'Q5', '45 TFSI quattro S line', 2024, 3499000.00),
    ((SELECT id FROM car_brands WHERE name='Audi'), 'e-tron', 'Q8 55 quattro', 2024, 5499000.00);

-- Porsche Models (3 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Porsche'), 'Cayenne', 'S E-Hybrid', 2024, 6999000.00),
    ((SELECT id FROM car_brands WHERE name='Porsche'), 'Macan', 'T', 2024, 4499000.00),
    ((SELECT id FROM car_brands WHERE name='Porsche'), 'Taycan', '4S', 2024, 7299000.00);

-- Volvo Models (3 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Volvo'), 'XC40', 'Recharge Twin Pure Electric', 2024, 2799000.00),
    ((SELECT id FROM car_brands WHERE name='Volvo'), 'XC60', 'Recharge Plug-in T8', 2024, 3399000.00),
    ((SELECT id FROM car_brands WHERE name='Volvo'), 'C40', 'Recharge Twin', 2024, 2999000.00);

-- Chevrolet Models (2 variants)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Chevrolet'), 'Colorado', 'LTZ Z71 4WD', 2024, 1199000.00),
    ((SELECT id FROM car_brands WHERE name='Chevrolet'), 'Trailblazer', 'LTZ AWD', 2024, 1299000.00);

-- Nissan extra models
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Nissan'), 'Navara', 'Pro-4X 4WD', 2024, 1099000.00),
    ((SELECT id FROM car_brands WHERE name='Nissan'), 'Almera', 'VL Turbo CVT', 2024, 699000.00);

-- Mitsubishi extra models
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Mitsubishi'), 'Eclipse Cross', 'PHEV', 2024, 1999000.00),
    ((SELECT id FROM car_brands WHERE name='Mitsubishi'), 'Outlander', 'PHEV', 2024, 2199000.00);

-- 2025 model year variants (key bestsellers)
INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Honda'), 'Civic', 'e:HEV RS', 2025, 1749000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'CR-V', 'e:HEV EL', 2025, 1749000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Camry', 'Hybrid Premium', 2025, 1649000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Corolla Cross', 'Hybrid Premium', 2025, 1249000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Fortuner', 'Legender', 2025, 1929000.00),
    ((SELECT id FROM car_brands WHERE name='BYD'), 'Seal', 'Premium', 2025, 1499000.00),
    ((SELECT id FROM car_brands WHERE name='BYD'), 'Atto 3', 'Extended Range', 2025, 1149000.00),
    ((SELECT id FROM car_brands WHERE name='Tesla'), 'Model 3', 'Long Range', 2025, 1949000.00),
    ((SELECT id FROM car_brands WHERE name='Tesla'), 'Model Y', 'Long Range', 2025, 2149000.00),
    ((SELECT id FROM car_brands WHERE name='MG'), 'MG4 EV', 'Long Range', 2025, 1149000.00),
    ((SELECT id FROM car_brands WHERE name='BMW'), '3 Series', '330e M Sport', 2025, 3149000.00),
    ((SELECT id FROM car_brands WHERE name='Mazda'), 'CX-5', '2.5 Turbo SP', 2025, 1849000.00);

-- Note: Premium matrix will be generated programmatically based on vehicle price tiers
-- For brevity, showing sample premiums for key models. In production, use a pricing algorithm.

-- ============================================================
-- 12. Sample Premium Matrix (Key Models Only - Expand as needed)
-- ============================================================

-- Helper function to calculate premiums based on car price
-- Type 1: ~1.5-2% of car value
-- Type 2+: ~0.8-1.2% of car value  
-- Type 3+: ~0.5-0.8% of car value

-- Honda Civic variants
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    -- Type R
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Type R' AND name='Civic' LIMIT 1), 45000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Type R' AND name='Civic' LIMIT 1), 22000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Type R' AND name='Civic' LIMIT 1), 15000.00, 5000.00),
    -- e:HEV RS
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='e:HEV RS' LIMIT 1), 25000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='e:HEV RS' LIMIT 1), 13000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='e:HEV RS' LIMIT 1), 9500.00, 3000.00),
    -- Civic EL
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='EL' AND name='Civic' LIMIT 1), 18000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='EL' AND name='Civic' LIMIT 1), 10000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='EL' AND name='Civic' LIMIT 1), 7500.00, 3000.00);

-- Honda City variants
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='SV' AND name='City' LIMIT 1), 15000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='SV' AND name='City' LIMIT 1), 8500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='SV' AND name='City' LIMIT 1), 6500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='RS' AND name='City' LIMIT 1), 16500.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='RS' AND name='City' LIMIT 1), 9000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='RS' AND name='City' LIMIT 1), 7000.00, 2000.00);

-- Toyota Camry variants
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Hybrid Premium' AND name='Camry' LIMIT 1), 26000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Hybrid Premium' AND name='Camry' LIMIT 1), 14000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Hybrid Premium' AND name='Camry' LIMIT 1), 10500.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='2.5 HV Premium' AND name='Camry' LIMIT 1), 27500.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='2.5 HV Premium' AND name='Camry' LIMIT 1), 14500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='2.5 HV Premium' AND name='Camry' LIMIT 1), 11000.00, 3000.00);

-- EV Models (Tesla, BYD, MG)
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    -- Tesla Model 3
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Long Range' AND name='Model 3' LIMIT 1), 42000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Performance' AND name='Model 3' LIMIT 1), 48000.00, 5000.00),
    -- Tesla Model Y
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Long Range' AND name='Model Y' LIMIT 1), 46000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Performance' AND name='Model Y' LIMIT 1), 55000.00, 5000.00),
    -- BYD Seal
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Premium' AND name='Seal' LIMIT 1), 32000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Excellence' AND name='Seal' LIMIT 1), 35000.00, 0.00),
    -- BYD Dolphin
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Extended Range' AND name='Dolphin' LIMIT 1), 22000.00, 0.00),
    -- MG ZS EV
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Long Range' AND name='ZS EV' LIMIT 1), 28000.00, 0.00),
    -- MG4 EV
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Long Range' AND name='MG4 EV' LIMIT 1), 26000.00, 0.00);

-- Luxury Models (BMW, Mercedes-Benz)
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    -- BMW 3 Series
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='330e M Sport' AND name='3 Series' LIMIT 1), 48000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='330e M Sport' AND name='3 Series' LIMIT 1), 24000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='330e M Sport' AND name='3 Series' LIMIT 1), 18000.00, 5000.00),
    -- BMW 5 Series
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='530e M Sport' AND name='5 Series' LIMIT 1), 62000.00, 5000.00),
    -- Mercedes C-Class
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='C 350e AMG Dynamic' AND name='C-Class' LIMIT 1), 52000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='C 350e AMG Dynamic' AND name='C-Class' LIMIT 1), 26000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='C 350e AMG Dynamic' AND name='C-Class' LIMIT 1), 20000.00, 5000.00),
    -- Mercedes E-Class
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='E 300e AMG Dynamic' AND name='E-Class' LIMIT 1), 65000.00, 5000.00);

-- Ford Models
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Wildtrak 2.0 Bi-Turbo 4WD' LIMIT 1), 22000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Wildtrak 2.0 Bi-Turbo 4WD' LIMIT 1), 11000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Wildtrak 2.0 Bi-Turbo 4WD' LIMIT 1), 8500.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Raptor 3.0 V6' LIMIT 1), 35000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Raptor 3.0 V6' LIMIT 1), 18000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Titanium+ 4WD' LIMIT 1), 34000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Titanium+ 4WD' LIMIT 1), 17500.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Titanium+ 4WD' LIMIT 1), 13000.00, 3000.00);

-- Hyundai Models (EV/Hybrid via EV Shield; ICE via standard plans)
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Long Range AWD' AND name='IONIQ 5' LIMIT 1), 50000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Long Range AWD' AND name='IONIQ 5' LIMIT 1), 48000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Long Range AWD' AND name='IONIQ 6' LIMIT 1), 52000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Long Range AWD' AND name='IONIQ 6' LIMIT 1), 50000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Hybrid Premium' AND name='Tucson' LIMIT 1), 28000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Hybrid Premium' AND name='Tucson' LIMIT 1), 14500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Sport' AND name='Creta' LIMIT 1), 16000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Sport' AND name='Creta' LIMIT 1), 8500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Sport' AND name='Creta' LIMIT 1), 6500.00, 2000.00);

-- Subaru Models
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Advance' AND name='Forester' LIMIT 1), 30000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Advance' AND name='Forester' LIMIT 1), 15500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Advance' AND name='Forester' LIMIT 1), 11500.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='GT Edition' AND name='XV' LIMIT 1), 25000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='GT Edition' AND name='XV' LIMIT 1), 13000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='2.5i-T EyeSight' LIMIT 1), 35000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='2.5i-T EyeSight' LIMIT 1), 18000.00, 2000.00);

-- Suzuki Models
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='GLX' AND name='Swift' LIMIT 1), 13000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='GLX' AND name='Swift' LIMIT 1), 7000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='GLX' AND name='Swift' LIMIT 1), 5500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='GX' AND name='Ertiga' LIMIT 1), 14500.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='GX' AND name='Ertiga' LIMIT 1), 7500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='GX' AND name='Ertiga' LIMIT 1), 5800.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='1.4 Turbo GLX' LIMIT 1), 18500.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='1.4 Turbo GLX' LIMIT 1), 9500.00, 2000.00);

-- Audi Models
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='40 TFSI S line' LIMIT 1), 45000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='40 TFSI S line' LIMIT 1), 22000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='40 TFSI S line' LIMIT 1), 17000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='45 TFSI quattro S line' LIMIT 1), 58000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='45 TFSI quattro S line' LIMIT 1), 29000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Q8 55 quattro' LIMIT 1), 95000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Q8 55 quattro' LIMIT 1), 92000.00, 5000.00);

-- Porsche Models
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='S E-Hybrid' LIMIT 1), 115000.00, 10000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='T' AND name='Macan' LIMIT 1), 75000.00, 8000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='4S' LIMIT 1), 125000.00, 10000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='4S' LIMIT 1), 120000.00, 10000.00);

-- Volvo EV/PHEV Models
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Recharge Twin Pure Electric' LIMIT 1), 55000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Recharge Twin Pure Electric' LIMIT 1), 52000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Recharge Plug-in T8' LIMIT 1), 60000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Recharge Plug-in T8' LIMIT 1), 57000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Recharge Twin' AND name='C40' LIMIT 1), 58000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Recharge Twin' AND name='C40' LIMIT 1), 55000.00, 3000.00);

-- Chevrolet Models
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='LTZ Z71 4WD' LIMIT 1), 21000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='LTZ Z71 4WD' LIMIT 1), 10500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='LTZ Z71 4WD' LIMIT 1), 8000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='LTZ AWD' LIMIT 1), 22500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='LTZ AWD' LIMIT 1), 11500.00, 2000.00);

-- Extra Nissan and Mitsubishi models
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Pro-4X 4WD' LIMIT 1), 19500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Pro-4X 4WD' LIMIT 1), 9500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Pro-4X 4WD' LIMIT 1), 7500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='VL Turbo CVT' LIMIT 1), 13500.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='VL Turbo CVT' LIMIT 1), 7000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='VL Turbo CVT' LIMIT 1), 5500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='PHEV' AND name='Eclipse Cross' LIMIT 1), 36000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='PHEV' AND name='Eclipse Cross' LIMIT 1), 18000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='PHEV' AND name='Outlander' LIMIT 1), 39000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='PHEV' AND name='Outlander' LIMIT 1), 20000.00, 3000.00);

-- 2025 Model Year Premiums
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE name='Civic' AND sub_model='e:HEV RS' AND year=2025 LIMIT 1), 26000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE name='Civic' AND sub_model='e:HEV RS' AND year=2025 LIMIT 1), 13500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE name='Civic' AND sub_model='e:HEV RS' AND year=2025 LIMIT 1), 10000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE name='CR-V' AND sub_model='e:HEV EL' AND year=2025 LIMIT 1), 28000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE name='CR-V' AND sub_model='e:HEV EL' AND year=2025 LIMIT 1), 14500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE name='Camry' AND sub_model='Hybrid Premium' AND year=2025 LIMIT 1), 27000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE name='Camry' AND sub_model='Hybrid Premium' AND year=2025 LIMIT 1), 14000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE name='Camry' AND sub_model='Hybrid Premium' AND year=2025 LIMIT 1), 10500.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE name='Fortuner' AND sub_model='Legender' AND year=2025 LIMIT 1), 31000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE name='Fortuner' AND sub_model='Legender' AND year=2025 LIMIT 1), 16000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE name='Fortuner' AND sub_model='Legender' AND year=2025 LIMIT 1), 12000.00, 3000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE name='Seal' AND sub_model='Premium' AND year=2025 LIMIT 1), 33500.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE name='Atto 3' AND sub_model='Extended Range' AND year=2025 LIMIT 1), 24000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE name='Model 3' AND sub_model='Long Range' AND year=2025 LIMIT 1), 43000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE name='Model Y' AND sub_model='Long Range' AND year=2025 LIMIT 1), 47000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE name='MG4 EV' AND sub_model='Long Range' AND year=2025 LIMIT 1), 27000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE name='3 Series' AND sub_model='330e M Sport' AND year=2025 LIMIT 1), 51000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE name='3 Series' AND sub_model='330e M Sport' AND year=2025 LIMIT 1), 25500.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE name='CX-5' AND sub_model='2.5 Turbo SP' AND year=2025 LIMIT 1), 31000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE name='CX-5' AND sub_model='2.5 Turbo SP' AND year=2025 LIMIT 1), 16000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE name='CX-5' AND sub_model='2.5 Turbo SP' AND year=2025 LIMIT 1), 12000.00, 3000.00);

-- Popular SUVs and Pickups
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    -- Toyota Fortuner
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Legender' AND name='Fortuner' LIMIT 1), 29000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Legender' AND name='Fortuner' LIMIT 1), 15000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Legender' AND name='Fortuner' LIMIT 1), 11000.00, 3000.00),
    -- Isuzu D-Max
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Hi-Lander Z-Prestige' AND name='D-Max' LIMIT 1), 19000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Hi-Lander Z-Prestige' AND name='D-Max' LIMIT 1), 9500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Hi-Lander Z-Prestige' AND name='D-Max' LIMIT 1), 7500.00, 2000.00),
    -- Isuzu MU-X
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Ultimate' AND name='MU-X' LIMIT 1), 27000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Ultimate' AND name='MU-X' LIMIT 1), 13500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='Ultimate' AND name='MU-X' LIMIT 1), 10000.00, 3000.00),
    -- Mazda CX-5
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='2.5 Turbo SP' AND name='CX-5' LIMIT 1), 30000.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='2.5 Turbo SP' AND name='CX-5' LIMIT 1), 15500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='2.5 Turbo SP' AND name='CX-5' LIMIT 1), 11500.00, 3000.00);

-- ============================================================
-- 13. Comprehensive Policy Documents for RAG
-- ============================================================
INSERT INTO policy_documents (plan_type, section, content, metadata) VALUES
    -- Coverage Details
    ('Type 1', 'Coverage', 'Flood and Fire Coverage: Protects the insured vehicle against damage caused by natural floods, flash floods, and accidental fires up to the total insured value. This includes damage from water entering the engine, electrical systems, and interior. Fire coverage extends to fires caused by accidents, electrical faults, or external sources.', '{"topic": "flood", "topic_2": "fire", "page": 5}'),
    ('Type 1', 'Coverage', 'Third-Party Liability: Covers bodily injury and property damage to third parties caused by the insured vehicle. Maximum coverage for property damage is 2,500,000 THB and bodily injury is 1,000,000 THB per person. This includes legal defense costs and court-ordered compensation.', '{"topic": "third_party", "page": 7}'),
    ('Type 1', 'Coverage', 'Battery and EV Components (EV Shield): For electric vehicles, the high-voltage battery and electric drive components are covered against accidental damage. In case of total loss of battery due to accident, replacement cost is covered up to the vehicle''s sum insured without depreciation for vehicles under 3 years old. Includes coverage for charging cables and wall-mounted chargers up to 50,000 THB.', '{"topic": "ev_battery", "page": 6}'),
    ('Type 1', 'Coverage', 'Theft and Robbery: Covers the loss of the insured vehicle due to theft, robbery, or embezzlement. The insurer will compensate up to the sum insured stated in the policy schedule. Requires police report filed within 24 hours and cooperation with investigation.', '{"topic": "theft", "page": 4}'),
    ('Type 1', 'Coverage', 'Windscreen Damage: Accidental shattering or breakage of the windscreen or windows is fully covered without applying any deductible, provided no other damage occurred to the vehicle. Includes side mirrors and sunroof glass. Repair or replacement at authorized service centers.', '{"topic": "windscreen", "page": 5}'),
    ('Type 1', 'Coverage', 'Personal Accident Coverage: Provides compensation for death or permanent disability of the driver and passengers resulting from a covered accident. Coverage limit is 100,000 THB per person. Includes medical expenses up to policy limits.', '{"topic": "personal_accident", "page": 8}'),
    ('Type 1', 'Coverage', 'Towing and Roadside Assistance: 24/7 emergency towing service to the nearest authorized repair center within 100 km. Includes battery jump-start, tire change, fuel delivery (customer pays for fuel), and lockout assistance. Unlimited calls per year.', '{"topic": "roadside_assistance", "page": 9}'),
    
    ('Type 2+', 'Coverage', 'Collision with Land Vehicles: Type 2+ covers damage to the insured vehicle ONLY when it collides with another land vehicle, and the identity of the other party can be provided (license plate or details). Requires police report for claims over 50,000 THB. Does not cover single-vehicle accidents.', '{"topic": "collision", "page": 3}'),
    ('Type 2+', 'Coverage', 'Fire and Theft Protection: Type 2+ includes full coverage for fire damage and theft, identical to Type 1. Vehicle must be equipped with factory-installed or approved aftermarket immobilizer system for theft coverage to be valid.', '{"topic": "fire_theft_type2", "page": 4}'),
    
    ('Type 3+', 'Coverage', 'Collision with Land Vehicles (Budget): Type 3+ covers damage to the insured vehicle up to a maximum limit of 100,000 THB per accident, ONLY when colliding with another identified land vehicle. Deductible applies. Police report mandatory for all claims.', '{"topic": "collision", "page": 3}'),
    ('Type 3+', 'Coverage', 'Third-Party Liability (Basic): Type 3+ provides third-party liability coverage with limits of 500,000 THB for property damage and 300,000 THB per person for bodily injury. Lower than Type 1 and Type 2+ but meets legal minimum requirements.', '{"topic": "third_party_basic", "page": 7}'),
    
    -- Exclusions
    ('All', 'Exclusion', 'Drunk Driving Exclusion: The insurance policy becomes entirely void and will not cover any damages or liabilities if the driver of the insured vehicle at the time of the accident has a Blood Alcohol Concentration (BAC) exceeding 50mg%. This applies to all plan types. Insurer may pursue recovery of any paid claims.', '{"topic": "alcohol", "page": 12}'),
    ('All', 'Exclusion', 'Illegal Purposes and Racing Exclusion: No coverage is provided if the vehicle is used for illegal activities (e.g., transporting contraband) or involved in any form of street racing, speed testing, or motorsport events. Track day events require separate coverage endorsement.', '{"topic": "illegal_use", "topic_2": "racing", "page": 13}'),
    ('All', 'Exclusion', 'Unlicensed Driver: The policy will not cover any damages if the driver at the time of the accident does not hold a valid driving license for the specific class of vehicle, or if their license has been suspended or revoked. International licenses must be accompanied by valid passport and entry stamp.', '{"topic": "unlicensed_driver", "page": 14}'),
    ('All', 'Exclusion', 'Commercial Use Exclusion: Standard personal car insurance policies (unless explicitly stated as commercial) exclude coverage if the vehicle is used for hire, reward, public transport, or delivery services (e.g., Grab, Lalamove, Uber). Rideshare endorsement available for additional premium.', '{"topic": "commercial_use", "page": 13}'),
    ('All', 'Exclusion', 'Acts of War and Terrorism: Damages arising directly or indirectly from war, invasion, acts of foreign enemies, hostilities, civil war, rebellion, revolution, insurrection, military or usurped power, or terrorism are completely excluded. Nuclear incidents also excluded.', '{"topic": "war_terrorism", "page": 15}'),
    ('All', 'Exclusion', 'Driving Outside Territory: Coverage is restricted to accidents occurring within the territorial limits of Thailand. Accidents in neighboring countries (e.g., Malaysia, Laos, Cambodia) are not covered unless a cross-border extension was purchased. ASEAN coverage available as add-on.', '{"topic": "territory", "page": 16}'),
    ('All', 'Exclusion', 'Wear and Tear: Normal wear and tear, mechanical or electrical breakdown, and gradual deterioration are not covered. This includes brake pads, tires (unless damaged in covered accident), battery degradation, and routine maintenance items.', '{"topic": "wear_tear", "page": 14}'),
    
    ('Type 2+', 'Exclusion', 'Single-Vehicle Accidents: Type 2+ and Type 3+ policies do NOT cover damages from single-vehicle accidents such as hitting a tree, fence, or animal, or overturning without another vehicle involved. Upgrade to Type 1 for comprehensive own-damage coverage.', '{"topic": "single_vehicle_accident", "page": 8}'),
    ('Type 1', 'Exclusion', 'Battery Degradation (EV): Natural wear and tear, gradual loss of battery capacity, or failure of the EV battery not caused by an external accident are strictly excluded from coverage. Manufacturer warranty covers battery degradation issues.', '{"topic": "ev_battery_wear", "page": 14}'),
    
    -- Claims Process
    ('All', 'Condition', 'Accident Reporting Condition: The policyholder must report any accident or claim to the insurance company via the mobile application or hotline (1-800-ZEUS-INS) within 24 hours of the incident. Failure to do so may result in delayed processing or claim denial. Take photos of damage and accident scene.', '{"topic": "claim_reporting", "page": 18}'),
    ('All', 'Condition', 'Claims Documentation: Required documents include: (1) Completed claim form, (2) Copy of driving license, (3) Copy of vehicle registration, (4) Police report (for accidents involving third parties or theft), (5) Repair estimates or invoices, (6) Photos of damage. Submit within 7 days of incident.', '{"topic": "claim_documents", "page": 19}'),
    ('All', 'Condition', 'Repair Authorization: For claims over 50,000 THB, the insurer must authorize repairs before work begins. Use authorized repair centers for guaranteed parts and workmanship. Non-authorized repairs may result in reduced claim payment or denial.', '{"topic": "repair_authorization", "page": 20}'),
    ('All', 'Condition', 'Claim Settlement Timeline: Simple claims (windscreen, minor repairs) settled within 3-5 business days. Major accident claims requiring investigation settled within 15-30 days. Total loss claims settled within 30-45 days after all documentation received.', '{"topic": "claim_timeline", "page": 21}'),
    
    -- Policy Conditions
    ('All', 'Condition', 'Vehicle Modification: Any performance or structural modifications made to the vehicle after policy inception (e.g., changing engines, adding roll cages, modifying suspension, body kits) must be declared to the insurer within 14 days. Undeclared modifications may invalidate coverage. Cosmetic modifications (decals, tints within legal limits) do not require notification.', '{"topic": "modifications", "page": 19}'),
    ('All', 'Condition', 'Duty of Care: The insured must take all reasonable steps to safeguard the vehicle from loss or damage and maintain it in an efficient and roadworthy condition. This includes regular servicing, keeping the vehicle locked, and not leaving keys in the ignition of an unattended vehicle. Violation may result in claim denial.', '{"topic": "duty_of_care", "page": 18}'),
    ('All', 'Condition', 'Premium Payment: Annual premium must be paid in full before policy inception. Installment plans available with 5% surcharge. Grace period of 15 days after due date. Policy automatically lapses if premium not received within grace period. No coverage during lapsed period.', '{"topic": "premium_payment", "page": 22}'),
    ('All', 'Condition', 'Policy Renewal: Renewal notice sent 30 days before expiry. No-claims discount up to 50% for claim-free years. Premium adjustment based on claims history and vehicle age. Renewal not guaranteed for vehicles over 15 years old or with excessive claims.', '{"topic": "renewal", "page": 23}'),
    ('All', 'Condition', 'Cancellation Policy: Policyholder may cancel anytime with 30 days notice. Refund calculated on short-rate basis (not pro-rata). Insurer may cancel for non-payment, fraud, or material misrepresentation with 15 days notice. No refund if policy cancelled by insurer for fraud.', '{"topic": "cancellation", "page": 24}'),
    
    -- Add-ons and Optional Coverage
    ('All', 'Coverage', 'Flood Coverage Add-on: Enhanced flood protection for areas prone to flooding. Covers engine damage from water ingestion, electrical system damage, and interior damage. Includes emergency towing from flooded areas. Additional premium 500-2,000 THB depending on vehicle value and location.', '{"topic": "flood_addon", "page": 25}'),
    ('All', 'Coverage', 'Deductible Waiver Add-on: Eliminates the deductible for at-fault claims. Available for Type 1 policies only. Additional premium 10-15% of base premium. Not available for high-performance vehicles or drivers under 25.', '{"topic": "deductible_waiver", "page": 26}'),
    ('All', 'Coverage', 'Replacement Vehicle Add-on: Provides a replacement vehicle (similar class) while your car is being repaired for covered claims. Maximum 30 days per claim. Additional premium 1,500-3,000 THB annually. Subject to availability.', '{"topic": "replacement_vehicle", "page": 27}'),
    ('All', 'Coverage', 'Personal Belongings Coverage: Covers theft of personal belongings from the vehicle up to 20,000 THB per incident. Requires evidence of forced entry. Electronics, jewelry, and cash have sub-limits. Additional premium 500 THB annually.', '{"topic": "personal_belongings", "page": 28}'),
    
    -- Definitions
    ('All', 'Definition', 'Deductible Definition: A deductible (or excess) is the fixed amount the policyholder is responsible for paying out-of-pocket for each at-fault claim, or when the third party cannot be identified, before the insurance coverage begins to pay for the remaining damages. Deductible does not apply to third-party liability claims or windscreen-only claims.', '{"topic": "deductible", "page": 3}'),
    ('All', 'Definition', 'Total Loss: A vehicle is considered a Total Loss if the estimated cost of repairs exceeds 70% of the vehicle''s sum insured at the time of the accident, or if the vehicle is stolen and not recovered within 30 days. In such cases, the insurer will pay the full sum insured (minus deductible if applicable) and take ownership of the salvage.', '{"topic": "total_loss", "page": 4}'),
    ('All', 'Definition', 'Depreciation for Parts: When replacing parts on vehicles older than 3 years, a depreciation rate may be applied to the cost of new parts, meaning the policyholder may need to contribute to the cost of betterment, unless an add-on covers full replacement value. Depreciation schedule: 3-5 years (10%), 5-7 years (20%), 7-10 years (30%), over 10 years (40%).', '{"topic": "depreciation", "page": 5}'),
    ('All', 'Definition', 'Sum Insured: The maximum amount the insurer will pay in the event of a total loss. For new vehicles, this is typically the manufacturer''s suggested retail price. For used vehicles, it is the agreed market value at policy inception. Sum insured decreases annually based on depreciation schedule.', '{"topic": "sum_insured", "page": 6}'),
    ('All', 'Definition', 'No-Claims Discount (NCD): A discount on the renewal premium for each claim-free year. NCD scale: 1 year (10%), 2 years (20%), 3 years (30%), 4 years (40%), 5+ years (50%). NCD resets to 0% after any claim. NCD is transferable between insurers with proof of claims history.', '{"topic": "ncd", "page": 7}'),
    
    -- Payment and Billing
    ('All', 'Condition', 'Payment Methods: Premium can be paid via bank transfer, credit card (Visa, Mastercard, AMEX), debit card, or mobile banking (PromptPay). Credit card payments incur 2% processing fee. Installment plans available for premiums over 15,000 THB (3, 6, or 12 monthly payments).', '{"topic": "payment_methods", "page": 29}'),
    ('All', 'Condition', 'Refund Policy: If policy is cancelled within 15 days of inception (cooling-off period) and no claims have been made, full refund minus administrative fee of 500 THB. After cooling-off period, refund calculated on short-rate basis (approximately 90% of pro-rata refund).', '{"topic": "refund_policy", "page": 30}'),
    
    -- Special Conditions
    ('Type 1', 'Condition', 'Agreed Value vs Market Value: Type 1 policies can be issued on agreed value basis (value agreed at inception, no depreciation) or market value basis (value adjusted annually). Agreed value policies have 10-15% higher premium but provide better protection against depreciation.', '{"topic": "agreed_value", "page": 31}'),
    ('All', 'Condition', 'Young Driver Surcharge: Drivers under 25 years old incur additional premium of 20-50% depending on age and driving experience. Surcharge waived if driver has completed approved defensive driving course and has clean driving record for 2+ years.', '{"topic": "young_driver", "page": 32}'),
    ('All', 'Condition', 'High-Performance Vehicle Conditions: Vehicles with engine capacity over 3.0L or power output over 300hp require special underwriting. Additional premium 30-100%. May require installation of GPS tracker and parking in secured location overnight. Some insurers may decline coverage.', '{"topic": "high_performance", "page": 33}');

-- ============================================================
-- Additional RAG Documents: EV/PHEV, Pricing, Brand-Specific, Scenarios
-- ============================================================
INSERT INTO policy_documents (plan_type, section, content, metadata) VALUES

    -- EV and PHEV specific coverage
    ('Type 1', 'Coverage', 'PHEV and Hybrid Battery Coverage: Plug-in hybrid (PHEV) and hybrid vehicles have their high-voltage battery pack covered under Zeus Comprehensive Plus and Zeus EV Shield plans. Accidental damage to the hybrid system, inverter, and electric motor is included. Thermal runaway caused by external impact is covered. Gradual degradation and manufacturer defects are excluded and fall under manufacturer warranty.', '{"topic": "phev_hybrid_battery", "page": 6}'),
    ('Type 1', 'Coverage', 'EV Charging Infrastructure: Under Zeus EV Shield plan, damage to the vehicle''s onboard charger caused by power surge or faulty charging equipment is covered up to 80,000 THB. Wall-mounted home chargers (EVSE) are covered up to 50,000 THB when damage is caused by fire or flooding. Public charging station damage liability is covered under third-party liability.', '{"topic": "ev_charging", "page": 6}'),
    ('Type 1', 'Coverage', 'Electric Vehicle Towing: All EV and PHEV vehicles covered under Zeus plans receive priority towing with flatbed truck service (not wheel-lift) to protect the battery and drivetrain. EV-specific technician dispatched to scene for safety assessment before towing. Service available 24/7 across all provinces in Thailand.', '{"topic": "ev_towing", "page": 9}'),

    -- Pricing and premium factors
    ('All', 'Condition', 'Premium Calculation Factors: Car insurance premiums in Thailand are calculated based on multiple factors: (1) Vehicle sum insured value, (2) Plan type (Type 1 is most expensive, Type 3+ is cheapest), (3) Driver age and experience, (4) Garage location and province, (5) Vehicle usage (personal/commercial), (6) Claims history and No-Claims Discount, (7) Safety features (ADAS, dash cam discount available). EV vehicles carry slightly higher premiums due to repair costs.', '{"topic": "premium_calculation", "page": 2}'),
    ('All', 'Condition', 'Premium Pricing Tiers by Vehicle Value: Zeus Insurance uses the following base rate structure: Vehicles under 500,000 THB: Type 1 rate 1.8-2.2%, Type 2+ rate 1.0-1.2%, Type 3+ rate 0.6-0.8%. Vehicles 500,000-1,500,000 THB: Type 1 rate 1.5-1.8%, Type 2+ rate 0.8-1.0%, Type 3+ rate 0.5-0.7%. Vehicles over 1,500,000 THB: Type 1 rate 1.3-1.6%, Type 2+ rate 0.7-0.9%, Type 3+ rate 0.4-0.6%. Luxury and exotic cars over 4,000,000 THB: special rates apply, minimum 1.5%.', '{"topic": "pricing_tiers", "page": 2}'),
    ('All', 'Condition', 'Dash Camera Discount: Vehicles equipped with a front-facing dashboard camera with continuous recording capability are eligible for a 3-5% discount on premium. Camera footage must be submitted for at-fault claims. Zeus Insurance partners with approved dash cam brands for discounted installation packages. Rear dash cam provides additional 1% discount.', '{"topic": "dashcam_discount", "page": 33}'),
    ('All', 'Condition', 'ADAS Safety Feature Discount: Vehicles equipped with Advanced Driver Assistance Systems (ADAS) including Autonomous Emergency Braking (AEB), Lane Departure Warning, and Adaptive Cruise Control are eligible for 5-8% premium discount. Must be factory-installed. Vehicles with full ADAS suite (AEB + Lane Keep Assist + Blind Spot Monitor) receive maximum 8% discount.', '{"topic": "adas_discount", "page": 33}'),

    -- Claim scenarios
    ('All', 'Condition', 'Hit and Run Accident Scenario: If your vehicle is damaged by an unidentified hit-and-run driver: Under Type 1 — fully covered as own damage claim, deductible applies. Under Type 2+ and Type 3+ — NOT covered because the third party cannot be identified. This is one of the key advantages of upgrading to Type 1. Police report must be filed within 24 hours to support the claim.', '{"topic": "hit_and_run", "page": 8}'),
    ('All', 'Condition', 'Flooding Scenario — Driving into Flooded Road: If a driver knowingly drives into a visibly flooded road and the engine is damaged (hydro-lock), this may be considered negligence and the claim could be denied. However, if the vehicle was stationary and flood water rose around it, or the driver was unaware of depth, the claim is covered under flood coverage. Assessor will evaluate circumstances. Type 2+ and 3+ do not cover flood damage.', '{"topic": "flood_scenario", "page": 12}'),
    ('All', 'Condition', 'Parking Lot Damage: Damage caused by unknown vehicles in parking lots is covered under Type 1 as own damage. CCTV footage from the parking facility is recommended to support the claim. If the responsible party is identified, the claim proceeds as a third-party claim (covered under all plan types). Scratches and dents from parking lot incidents have a minimum damage threshold of 3,000 THB to file a claim.', '{"topic": "parking_damage", "page": 11}'),
    ('All', 'Condition', 'Animal Collision: Collision with animals (stray dogs, cats, livestock, deer) is covered as own damage under Type 1 only. Type 2+ and Type 3+ do not cover animal collisions as they require another identifiable vehicle. Police or wildlife department report recommended for claims over 20,000 THB. Insured sum applies minus deductible.', '{"topic": "animal_collision", "page": 11}'),

    -- Brand-specific notes
    ('Type 1', 'Coverage', 'Tesla Model Coverage Notes: Tesla vehicles require specialized repair at authorized Tesla Service Centers or certified body shops with Tesla-approved parts. Zeus EV Shield guarantees use of genuine Tesla replacement parts. Over-the-air software updates do not affect coverage. Autopilot-related accidents are covered under standard collision terms — autonomous driving mode does not void coverage if the driver was legally supervising.', '{"topic": "tesla_coverage", "page": 6}'),
    ('Type 1', 'Coverage', 'BYD Vehicle Coverage: BYD vehicles (Seal, Atto 3, Dolphin) are covered under Zeus EV Shield with access to BYD-authorized repair centers across Thailand. Blade Battery technology damage from external impact is covered. BYD''s proprietary charging systems and DiLink infotainment damage from accident is covered. BYD Han and Tang models covered with special luxury EV endorsement.', '{"topic": "byd_coverage", "page": 6}'),
    ('Type 1', 'Coverage', 'Hybrid Vehicle Repair: Toyota hybrid vehicles (Camry Hybrid, Corolla Cross Hybrid, Yaris Cross Hybrid) and Honda hybrid vehicles (Civic e:HEV, HR-V e:HEV) require specialized hybrid technicians for high-voltage component repair. Zeus Insurance partners with Toyota and Honda authorized service centers. Hybrid-specific repairs are fully covered under Zeus Comprehensive Plus at no extra charge.', '{"topic": "hybrid_repair", "page": 6}'),

    -- Exclusions additional
    ('All', 'Exclusion', 'Rideshare and Delivery Exclusion Details: Using a personal vehicle registered under a personal insurance policy for Grab, Bolt, InDrive, Lalamove, Lineman, or any for-hire transportation service immediately voids coverage during the period of commercial use. Zeus Insurance offers a Rideshare Endorsement add-on for drivers who occasionally use vehicles for rideshare, covering up to 20 ride hours per week for additional 15% premium.', '{"topic": "rideshare_exclusion", "page": 13}'),
    ('All', 'Exclusion', 'Intentional Damage Exclusion: Any damage intentionally caused by the policyholder, driver, or authorized user is strictly excluded. Insurance fraud is a criminal offense under Thai law. Suspicious claims may be investigated by the Anti-Fraud Unit. Proven fraud results in policy cancellation, claim recovery, and potential criminal prosecution.', '{"topic": "fraud_exclusion", "page": 15}'),
    ('All', 'Exclusion', 'Mechanical Breakdown vs Accident: Pure mechanical or electrical breakdown not caused by an external accident is not covered. For example: engine failure due to lack of oil, transmission failure, alternator failure, or EV battery management system failure from software issues. These are manufacturer warranty or extended warranty matters. However, if a mechanical failure causes an accident resulting in vehicle damage, the resulting damage IS covered.', '{"topic": "mechanical_breakdown", "page": 14}'),

    -- Thai language context documents
    ('All', 'Coverage', 'ประกันชั้น 1 (Type 1 Insurance): ประกันภัยรถยนต์ชั้น 1 คือความคุ้มครองที่ครอบคลุมมากที่สุด ครอบคลุมความเสียหายของรถยนต์ของท่านเองจากอุบัติเหตุทุกกรณี ไม่ว่าจะเป็นการชน น้ำท่วม ไฟไหม้ การโจรกรรม รวมถึงความรับผิดต่อบุคคลภายนอก เหมาะสำหรับรถยนต์ใหม่หรือรถยนต์ราคาสูง เบี้ยประกันสูงกว่าชั้น 2+ และ 3+ แต่ให้ความคุ้มครองสูงสุด', '{"topic": "type1_thai", "language": "th", "page": 1}'),
    ('All', 'Coverage', 'ประกันชั้น 2+ (Type 2+ Insurance): ประกันภัยรถยนต์ชั้น 2+ คุ้มครองความเสียหายของรถยนต์ตัวเองเฉพาะกรณีที่ชนกับรถยนต์คันอื่นที่ระบุตัวตนได้เท่านั้น และยังคุ้มครองไฟไหม้และการโจรกรรม เหมาะสำหรับรถยนต์อายุ 3-7 ปี ที่ต้องการความคุ้มครองระดับกลางในราคาที่เหมาะสม ไม่คุ้มครองรถชนแบบไม่มีคู่กรณี', '{"topic": "type2plus_thai", "language": "th", "page": 1}'),
    ('All', 'Coverage', 'ประกันชั้น 3+ (Type 3+ Insurance): ประกันภัยรถยนต์ชั้น 3+ คุ้มครองความเสียหายของรถยนต์ตัวเองจากการชนกับรถยนต์คันอื่นที่ระบุตัวตนได้ สูงสุด 100,000 บาทต่อครั้ง และคุ้มครองความรับผิดต่อบุคคลภายนอก เบี้ยประกันต่ำที่สุดในบรรดาประกันภัยรถยนต์ เหมาะสำหรับรถยนต์อายุมากหรือผู้ที่ต้องการประหยัดค่าใช้จ่าย', '{"topic": "type3plus_thai", "language": "th", "page": 1}'),
    ('All', 'Coverage', 'ส่วนลดไม่มีประวัติเคลมหรือ NCD (No-Claims Discount): หากท่านไม่มีการเรียกร้องค่าสินไหมทดแทนในปีที่ผ่านมา ท่านจะได้รับส่วนลดเบี้ยประกันเมื่อต่ออายุกรมธรรม์ โดยส่วนลดจะสะสมตามจำนวนปีที่ไม่มีการเคลม: 1 ปี = 10%, 2 ปี = 20%, 3 ปี = 30%, 4 ปี = 40%, 5 ปีขึ้นไป = 50% สูงสุด หากมีการเคลม NCD จะถูกรีเซ็ตกลับเป็น 0%', '{"topic": "ncd_thai", "language": "th", "page": 7}'),
    ('All', 'Condition', 'ขั้นตอนการเคลมประกัน (Claims Process Thai): เมื่อเกิดอุบัติเหตุ กรุณาปฏิบัติตามขั้นตอนดังนี้: 1) ถ่ายรูปความเสียหายและสถานที่เกิดเหตุ 2) แจ้งตำรวจและขอสำเนาบันทึกประจำวัน 3) แจ้งบริษัทประกันภายใน 24 ชั่วโมง ผ่านแอปพลิเคชันหรือสายด่วน 4) นำรถเข้าอู่ที่ได้รับการรับรองจากบริษัทประกัน 5) ส่งเอกสารครบถ้วนภายใน 7 วัน ระยะเวลาพิจารณา: เคลมเล็กน้อย 3-5 วันทำการ, เคลมหนัก 15-30 วัน', '{"topic": "claims_process_thai", "language": "th", "page": 18}'),

    -- Order and quotation process
    ('All', 'Condition', 'Quotation Validity and Acceptance: Insurance quotations generated by Zeus AI are valid for 30 days from the date of issue. The quotation number (format: QUO-YYYYMMDD-XXXX) must be referenced when proceeding to purchase. Premium rates are locked for the quotation validity period. After 30 days, a new quotation must be generated as rates may have changed.', '{"topic": "quotation_validity", "page": 2}'),
    ('All', 'Condition', 'Policy Inception and Coverage Start: Coverage begins on the policy start date specified in the order, typically 1-7 days after payment confirmation. Same-day coverage available for urgent requests with additional processing fee. The policy document (PDF) is issued within 24 hours of payment confirmation and sent to the registered email. Physical copy dispatched within 7 business days.', '{"topic": "policy_inception", "page": 22}'),
    ('All', 'Condition', 'Payment Methods for Policy Purchase: Zeus Insurance accepts the following payment methods: (1) PromptPay QR Code — instant confirmation, no processing fee, (2) Bank Transfer — confirmation within 1-2 business hours, (3) Credit/Debit Card (Visa, Mastercard) — instant confirmation, 1.5% processing fee, (4) Installment Plan — available for premiums over 15,000 THB, 3/6/12 months, 0% interest with participating banks.', '{"topic": "payment_methods_order", "page": 29}');

-- ============================================================
-- End of init_supabase_v2.sql
-- ============================================================
