-- ============================================================
-- Zeus Insurance App - Advanced Relational & RAG Schema
-- ============================================================

-- 1. Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Drop old tables/views to avoid conflicts during re-initialization
DROP VIEW IF EXISTS vw_quotation_details CASCADE;
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
    plan_type VARCHAR(50) NOT NULL, -- e.g., 'Type 1', 'Type 2+', 'Type 3'
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
-- 3. Advanced RAG Table
-- ============================================================
CREATE TABLE policy_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_type VARCHAR(50),
    section VARCHAR(50), -- 'Coverage', 'Exclusion', 'Condition', 'Definition'
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
-- 4. Session Table
-- ============================================================
CREATE TABLE chat_sessions (
    id BIGSERIAL PRIMARY KEY,
    session_id UUID NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('user', 'ai')),
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 5. Read-Only View: vw_quotation_details
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
    pp.deductible
FROM plan_premiums pp
JOIN car_models cm ON pp.car_model_id = cm.id
JOIN car_brands cb ON cm.brand_id = cb.id
JOIN insurance_plans ip ON pp.plan_id = ip.id;

-- ============================================================
-- 6. Row Level Security (RLS)
-- ============================================================
ALTER TABLE car_brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE car_models ENABLE ROW LEVEL SECURITY;
ALTER TABLE insurance_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_coverages ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_premiums ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read-only on car_brands" ON car_brands FOR SELECT USING (true);
CREATE POLICY "Allow read-only on car_models" ON car_models FOR SELECT USING (true);
CREATE POLICY "Allow read-only on insurance_plans" ON insurance_plans FOR SELECT USING (true);
CREATE POLICY "Allow read-only on plan_coverages" ON plan_coverages FOR SELECT USING (true);
CREATE POLICY "Allow read-only on plan_premiums" ON plan_premiums FOR SELECT USING (true);
CREATE POLICY "Allow read-only on policy_documents" ON policy_documents FOR SELECT USING (true);
CREATE POLICY "Allow public update access on policy_documents" ON policy_documents FOR UPDATE USING (true);

CREATE POLICY "Allow insert on chat_sessions" ON chat_sessions FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow select on chat_sessions" ON chat_sessions FOR SELECT USING (true);

-- ============================================================
-- RPC for RAG with section filter
-- ============================================================
CREATE OR REPLACE FUNCTION match_documents (
    query_embedding VECTOR(2000),
    match_threshold FLOAT DEFAULT 0.5,
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
-- 7. Mock Data
-- ============================================================
INSERT INTO car_brands (name) VALUES 
    ('Honda'), ('Toyota'), ('GWM'), ('Isuzu'), 
    ('BMW'), ('Mercedes-Benz'), ('Tesla'), ('BYD'), ('Nissan'), ('MG');

INSERT INTO car_models (brand_id, name, sub_model, year, estimated_price) VALUES
    ((SELECT id FROM car_brands WHERE name='Honda'), 'Civic', 'Type R', 2024, 2350000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'Civic', 'e:HEV RS', 2024, 1699000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'City', 'SV', 2024, 699000.00),
    ((SELECT id FROM car_brands WHERE name='Honda'), 'HR-V', 'e:HEV EL', 2024, 1079000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Camry', 'Hybrid Premium', 2024, 1599000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Yaris Cross', 'Premium', 2024, 849000.00),
    ((SELECT id FROM car_brands WHERE name='Toyota'), 'Fortuner', 'Legender', 2024, 1859000.00),
    ((SELECT id FROM car_brands WHERE name='GWM'), 'Tank', '300 Hi-Torq', 2024, 1799000.00),
    ((SELECT id FROM car_brands WHERE name='GWM'), 'Ora', 'Good Cat Ultra', 2024, 899000.00),
    ((SELECT id FROM car_brands WHERE name='Isuzu'), 'D-Max', 'Hi-Lander Z-Prestige', 2024, 1054000.00),
    ((SELECT id FROM car_brands WHERE name='Isuzu'), 'MU-X', 'Ultimate', 2024, 1539000.00),
    ((SELECT id FROM car_brands WHERE name='Tesla'), 'Model 3', 'Long Range', 2024, 1899000.00),
    ((SELECT id FROM car_brands WHERE name='Tesla'), 'Model Y', 'Performance', 2024, 2299000.00),
    ((SELECT id FROM car_brands WHERE name='BYD'), 'Seal', 'Premium', 2024, 1449000.00),
    ((SELECT id FROM car_brands WHERE name='BYD'), 'Dolphin', 'Extended Range', 2024, 859900.00),
    ((SELECT id FROM car_brands WHERE name='BMW'), '3 Series', '330e M Sport', 2024, 2999000.00),
    ((SELECT id FROM car_brands WHERE name='Mercedes-Benz'), 'C-Class', 'C 350e AMG Dynamic', 2024, 3350000.00);

INSERT INTO insurance_plans (plan_type, plan_name, insurer_name) VALUES
    ('Type 1', 'Zeus Comprehensive Plus', 'Zeus Insurance'),
    ('Type 1', 'Zeus EV Shield', 'Zeus Insurance'),
    ('Type 2+', 'Zeus Value Protect', 'Zeus Insurance'),
    ('Type 3+', 'Zeus Budget Safe', 'Zeus Insurance');

-- Insert coverages for Type 1 Comprehensive
INSERT INTO plan_coverages (plan_id, coverage_type, coverage_limit) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Third Party Property Damage', 2500000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Third Party Bodily Injury', 1000000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Medical Expenses (Driver/Passenger)', 100000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), 'Bail Bond', 300000.00);

-- Insert coverages for Type 1 EV
INSERT INTO plan_coverages (plan_id, coverage_type, coverage_limit) VALUES
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Third Party Property Damage', 2500000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Third Party Bodily Injury', 1000000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Battery Replacement', NULL), -- Up to actual value
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), 'Bail Bond', 300000.00);

-- Premium Matrix
INSERT INTO plan_premiums (plan_id, car_model_id, base_premium, deductible) VALUES
    -- Type R (Sports Car)
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Type R'), 45000.00, 3000.00),
    -- Hybrids/ICE
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='e:HEV RS'), 25000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Hybrid Premium'), 26000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='SV'), 15000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Premium' AND name='Yaris Cross'), 17500.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='300 Hi-Torq'), 28000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='Hi-Lander Z-Prestige'), 19000.00, 0.00),
    -- Luxury
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='330e M Sport'), 48000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Comprehensive Plus'), (SELECT id FROM car_models WHERE sub_model='C 350e AMG Dynamic'), 52000.00, 5000.00),
    -- EVs
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Long Range'), 42000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Performance'), 55000.00, 5000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Premium' AND name='Seal'), 32000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Extended Range'), 22000.00, 0.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus EV Shield'), (SELECT id FROM car_models WHERE sub_model='Good Cat Ultra'), 23500.00, 0.00),
    -- Value/Budget Plans (Type 2+ / 3+)
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='SV'), 8500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Budget Safe'), (SELECT id FROM car_models WHERE sub_model='SV'), 6500.00, 2000.00),
    ((SELECT id FROM insurance_plans WHERE plan_name='Zeus Value Protect'), (SELECT id FROM car_models WHERE sub_model='Hi-Lander Z-Prestige'), 9500.00, 2000.00);

-- Advanced RAG Policy Documents
INSERT INTO policy_documents (plan_type, section, content, metadata) VALUES
    -- Coverages
    ('Type 1', 'Coverage', 'Flood and Fire Coverage: Protects the insured vehicle against damage caused by natural floods, flash floods, and accidental fires up to the total insured value.', '{"topic": "flood", "topic_2": "fire", "page": 5}'),
    ('Type 1', 'Coverage', 'Third-Party Liability: Covers bodily injury and property damage to third parties caused by the insured vehicle. Maximum coverage for property damage is 2,500,000 THB and bodily injury is 1,000,000 THB per person.', '{"topic": "third_party", "page": 7}'),
    ('Type 1', 'Coverage', 'Battery and EV Components (EV Shield): For electric vehicles, the high-voltage battery and electric drive components are covered against accidental damage. In case of total loss of battery due to accident, replacement cost is covered up to the vehicle''s sum insured without depreciation for vehicles under 3 years old.', '{"topic": "ev_battery", "page": 6}'),
    ('Type 1', 'Coverage', 'Theft and Robbery: Covers the loss of the insured vehicle due to theft, robbery, or embezzlement. The insurer will compensate up to the sum insured stated in the policy schedule.', '{"topic": "theft", "page": 4}'),
    ('Type 1', 'Coverage', 'Windscreen Damage: Accidental shattering or breakage of the windscreen or windows is fully covered without applying any deductible, provided no other damage occurred to the vehicle.', '{"topic": "windscreen", "page": 5}'),
    ('Type 2+', 'Coverage', 'Collision with Land Vehicles: Type 2+ covers damage to the insured vehicle ONLY when it collides with another land vehicle, and the identity of the other party can be provided (license plate or details).', '{"topic": "collision", "page": 3}'),
    ('Type 3+', 'Coverage', 'Collision with Land Vehicles (Budget): Type 3+ covers damage to the insured vehicle up to a maximum limit of 100,000 THB per accident, ONLY when colliding with another identified land vehicle.', '{"topic": "collision", "page": 3}'),
    
    -- Exclusions
    ('All', 'Exclusion', 'Drunk Driving Exclusion: The insurance policy becomes entirely void and will not cover any damages or liabilities if the driver of the insured vehicle at the time of the accident has a Blood Alcohol Concentration (BAC) exceeding 50mg%.', '{"topic": "alcohol", "page": 12}'),
    ('All', 'Exclusion', 'Illegal Purposes and Racing Exclusion: No coverage is provided if the vehicle is used for illegal activities (e.g., transporting contraband) or involved in any form of street racing, speed testing, or motorsport events.', '{"topic": "illegal_use", "topic_2": "racing", "page": 13}'),
    ('All', 'Exclusion', 'Unlicensed Driver: The policy will not cover any damages if the driver at the time of the accident does not hold a valid driving license for the specific class of vehicle, or if their license has been suspended or revoked.', '{"topic": "unlicensed_driver", "page": 14}'),
    ('All', 'Exclusion', 'Commercial Use Exclusion: Standard personal car insurance policies (unless explicitly stated as commercial) exclude coverage if the vehicle is used for hire, reward, public transport, or delivery services (e.g., Grab, Lalamove, Uber).', '{"topic": "commercial_use", "page": 13}'),
    ('All', 'Exclusion', 'Acts of War and Terrorism: Damages arising directly or indirectly from war, invasion, acts of foreign enemies, hostilities, civil war, rebellion, revolution, insurrection, military or usurped power, or terrorism are completely excluded.', '{"topic": "war_terrorism", "page": 15}'),
    ('Type 2+', 'Exclusion', 'Single-Vehicle Accidents: Type 2+ and Type 3+ policies do NOT cover damages from single-vehicle accidents such as hitting a tree, fence, or animal, or overturning without another vehicle involved.', '{"topic": "single_vehicle_accident", "page": 8}'),
    ('Type 1', 'Exclusion', 'Battery Degradation (EV): Natural wear and tear, gradual loss of battery capacity, or failure of the EV battery not caused by an external accident are strictly excluded from coverage.', '{"topic": "ev_battery_wear", "page": 14}'),
    ('All', 'Exclusion', 'Driving Outside Territory: Coverage is restricted to accidents occurring within the territorial limits of Thailand. Accidents in neighboring countries (e.g., Malaysia, Laos, Cambodia) are not covered unless a cross-border extension was purchased.', '{"topic": "territory", "page": 16}'),
    
    -- Conditions
    ('All', 'Condition', 'Accident Reporting Condition: The policyholder must report any accident or claim to the insurance company via the mobile application or hotline within 24 hours of the incident. Failure to do so may result in delayed processing or claim denial.', '{"topic": "claim_reporting", "page": 18}'),
    ('All', 'Condition', 'Vehicle Modification: Any performance or structural modifications made to the vehicle after policy inception (e.g., changing engines, adding roll cages, modifying suspension) must be declared to the insurer. Undeclared modifications may invalidate coverage.', '{"topic": "modifications", "page": 19}'),
    ('All', 'Condition', 'Duty of Care: The insured must take all reasonable steps to safeguard the vehicle from loss or damage and maintain it in an efficient and roadworthy condition. Leaving the keys in the ignition of an unattended vehicle violates this duty.', '{"topic": "duty_of_care", "page": 18}'),
    
    -- Definitions
    ('All', 'Definition', 'Deductible Definition: A deductible (or excess) is the fixed amount the policyholder is responsible for paying out-of-pocket for each at-fault claim, or when the third party cannot be identified, before the insurance coverage begins to pay for the remaining damages.', '{"topic": "deductible", "page": 3}'),
    ('All', 'Definition', 'Total Loss: A vehicle is considered a Total Loss if the estimated cost of repairs exceeds 70% of the vehicle''s sum insured at the time of the accident. In such cases, the insurer will pay the full sum insured and take ownership of the salvage.', '{"topic": "total_loss", "page": 4}'),
    ('All', 'Definition', 'Depreciation for Parts: When replacing parts on vehicles older than 3 years, a depreciation rate may be applied to the cost of new parts, meaning the policyholder may need to contribute to the cost of betterment, unless an add-on covers full replacement value.', '{"topic": "depreciation", "page": 5}');
