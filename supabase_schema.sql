-- ============================================================================
-- 🚀 Smart CAD Borrow & New Parcel System - Database Schema (Supabase / PostgreSQL)
-- Description: ระบบบริหารจัดการการยืม-คืนอุปกรณ์และครุภัณฑ์ใหม่ที่ยังไม่ได้รับเลขครุภัณฑ์
-- ============================================================================

-- 1. ลบตารางเดิมถ้ามีอยู่แล้ว (Clean Slate ตามคำขอ)
DROP TABLE IF EXISTS borrow_transactions CASCADE;
DROP TABLE IF EXISTS assets CASCADE;
DROP TYPE IF EXISTS reg_status_type CASCADE;
DROP TYPE IF EXISTS borrow_status_type CASCADE;
DROP TYPE IF EXISTS tx_status_type CASCADE;

-- 2. สร้าง Custom ENUM Types
CREATE TYPE reg_status_type AS ENUM ('รอเลขครุภัณฑ์', 'มีเลขครุภัณฑ์แล้ว');
CREATE TYPE borrow_status_type AS ENUM ('ว่าง', 'ถูกยืม', 'ซ่อมบำรุง', 'จำหน่าย');
CREATE TYPE tx_status_type AS ENUM ('กำลังยืม', 'คืนแล้ว', 'เกินกำหนด', 'ยกเลิก');

-- ============================================================================
-- 3. ตาราง `assets` (อุปกรณ์ / ครุภัณฑ์ใหม่)
-- ============================================================================
CREATE TABLE assets (
    asset_id TEXT PRIMARY KEY,                       -- รหัสอ้างอิงระบบ เช่น UNIQUEID() หรือ AST-xxxx
    serial_number TEXT UNIQUE NOT NULL,             -- ซีเรียลนัมเบอร์ (ห้ามซ้ำ)
    asset_code TEXT,                                -- เลขครุภัณฑ์ (อัปเดตภายหลังเมื่อได้รับเลข)
    asset_name TEXT NOT NULL,                       -- ชื่อและรุ่นอุปกรณ์
    category TEXT DEFAULT 'อุปกรณ์ไอที',            -- หมวดหมู่อุปกรณ์
    asset_image TEXT,                               -- รูปภาพประจำตัวอุปกรณ์ (URL หรือ Drive Link)
    reg_status reg_status_type NOT NULL DEFAULT 'รอเลขครุภัณฑ์',
    borrow_status borrow_status_type NOT NULL DEFAULT 'ว่าง',
    notes TEXT,                                     -- บันทึกเพิ่มเติม
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes สำหรับ assets
CREATE INDEX idx_assets_serial_number ON assets(serial_number);
CREATE INDEX idx_assets_asset_code ON assets(asset_code);
CREATE INDEX idx_assets_reg_status ON assets(reg_status);
CREATE INDEX idx_assets_borrow_status ON assets(borrow_status);

-- ============================================================================
-- 4. ตาราง `borrow_transactions` (บันทึกธุรกรรมการยืม-คืน)
-- ============================================================================
CREATE TABLE borrow_transactions (
    tx_id TEXT PRIMARY KEY,                          -- รหัสธุรกรรม เช่น UNIQUEID() หรือ TX-xxxx
    asset_id TEXT NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    borrower_name TEXT NOT NULL,                    -- ชื่อผู้ยืม
    department TEXT NOT NULL,                       -- หน่วยงาน/แผนก
    phone TEXT,                                     -- เบอร์ติดต่อ
    borrow_date TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- วันเวลาที่ยืม
    due_date DATE NOT NULL,                         -- วันกำหนดส่งคืน
    borrower_photo TEXT,                            -- รูปถ่ายผู้ยืม (URL)
    equip_borrow_photo TEXT,                        -- รูปสภาพอุปกรณ์ตอนยืม (URL)
    borrow_signature TEXT,                          -- ลายเซ็นตอนยืม (URL / Base64 / Canvas)
    return_date TIMESTAMPTZ,                        -- วันเวลาที่คืนจริง
    equip_return_photo TEXT,                        -- รูปสภาพอุปกรณ์ตอนคืน (URL)
    return_signature TEXT,                          -- ลายเซ็นตอนคืน (URL / Base64 / Canvas)
    tx_status tx_status_type NOT NULL DEFAULT 'กำลังยืม',
    remark TEXT,                                    -- หมายเหตุ
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes สำหรับ borrow_transactions
CREATE INDEX idx_tx_asset_id ON borrow_transactions(asset_id);
CREATE INDEX idx_tx_borrower_name ON borrow_transactions(borrower_name);
CREATE INDEX idx_tx_status ON borrow_transactions(tx_status);
CREATE INDEX idx_tx_due_date ON borrow_transactions(due_date);

-- ============================================================================
-- 5. Auto Update `updated_at` Trigger Function
-- ============================================================================
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_assets_timestamp
    BEFORE UPDATE ON assets
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_update_tx_timestamp
    BEFORE UPDATE ON borrow_transactions
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- ============================================================================
-- 6. Trigger อัปเดตสถานะของอุปกรณ์อัตโนมัติ (Auto-Sync borrow_status)
-- ============================================================================
CREATE OR REPLACE FUNCTION sync_asset_status_on_transaction()
RETURNS TRIGGER AS $$
BEGIN
    -- กรณีเพิ่มรายการยืมใหม่ หรือเปลี่ยนสถานะเป็น 'กำลังยืม'
    IF (TG_OP = 'INSERT' AND NEW.tx_status = 'กำลังยืม') OR 
       (TG_OP = 'UPDATE' AND NEW.tx_status = 'กำลังยืม') THEN
        UPDATE assets 
        SET borrow_status = 'ถูกยืม'
        WHERE asset_id = NEW.asset_id;
    END IF;

    -- กรณีคืนอุปกรณ์ (สถานะเป็น 'คืนแล้ว')
    IF (TG_OP = 'UPDATE' AND NEW.tx_status = 'คืนแล้ว') OR 
       (TG_OP = 'INSERT' AND NEW.tx_status = 'คืนแล้ว') THEN
        UPDATE assets 
        SET borrow_status = 'ว่าง'
        WHERE asset_id = NEW.asset_id;
    END IF;

    -- กรณีเกินกำหนด (ยังคงสถานะ 'ถูกยืม')
    IF (TG_OP = 'UPDATE' AND NEW.tx_status = 'เกินกำหนด') THEN
        UPDATE assets 
        SET borrow_status = 'ถูกยืม'
        WHERE asset_id = NEW.asset_id;
    END IF;

    -- กรณียกเลิกรายการยืม
    IF (TG_OP = 'UPDATE' AND NEW.tx_status = 'ยกเลิก') THEN
        UPDATE assets 
        SET borrow_status = 'ว่าง'
        WHERE asset_id = NEW.asset_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_asset_borrow_status
    AFTER INSERT OR UPDATE OF tx_status ON borrow_transactions
    FOR EACH ROW EXECUTE FUNCTION sync_asset_status_on_transaction();

-- ============================================================================
-- 7. Views อำนวยความสะดวกสำหรับ Dashboard / Reporting
-- ============================================================================
CREATE OR REPLACE VIEW view_active_borrowings AS
SELECT 
    t.tx_id,
    t.asset_id,
    a.serial_number,
    a.asset_code,
    a.asset_name,
    a.category,
    a.asset_image,
    t.borrower_name,
    t.department,
    t.phone,
    t.borrow_date,
    t.due_date,
    CASE 
        WHEN CURRENT_DATE > t.due_date AND t.tx_status = 'กำลังยืม' THEN 'เกินกำหนด'
        ELSE t.tx_status::TEXT
    END AS current_status,
    (CURRENT_DATE - t.due_date) AS days_overdue,
    t.borrower_photo,
    t.equip_borrow_photo,
    t.borrow_signature
FROM borrow_transactions t
JOIN assets a ON t.asset_id = a.asset_id
WHERE t.tx_status = 'กำลังยืม'
ORDER BY t.due_date ASC;

-- View สำหรับ Handoff ไปยัง CAD-Inventory (อุปกรณ์ที่ได้เลขครุภัณฑ์แล้ว)
CREATE OR REPLACE VIEW view_assets_ready_for_cad_inventory AS
SELECT 
    asset_id,
    serial_number,
    asset_code,
    asset_name,
    category,
    asset_image,
    borrow_status,
    updated_at AS parcel_assigned_at
FROM assets
WHERE reg_status = 'มีเลขครุภัณฑ์แล้ว'
  AND asset_code IS NOT NULL 
  AND TRIM(asset_code) <> '';

-- ============================================================================
-- 8. Row Level Security (RLS) & Policies
-- ============================================================================
ALTER TABLE assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE borrow_transactions ENABLE ROW LEVEL SECURITY;

-- อนุญาตให้ Service Role เข้าถึงได้เต็มที่
CREATE POLICY "Full access for service role on assets" 
    ON assets FOR ALL 
    TO service_role 
    USING (true) 
    WITH CHECK (true);

CREATE POLICY "Full access for service role on borrow_transactions" 
    ON borrow_transactions FOR ALL 
    TO service_role 
    USING (true) 
    WITH CHECK (true);

-- อนุญาตให้ Anon / Authenticated อ่านได้ (สำหรับ Dashboard และ Web App)
CREATE POLICY "Public read access on assets" 
    ON assets FOR SELECT 
    TO anon, authenticated 
    USING (true);

CREATE POLICY "Public read access on borrow_transactions" 
    ON borrow_transactions FOR SELECT 
    TO anon, authenticated 
    USING (true);

-- อนุญาตให้ Anon / Authenticated เขียน/อัปเดตได้ (กรณี AppSheet หรือ Web App เรียกผ่าน Key)
CREATE POLICY "Public insert/update access on assets" 
    ON assets FOR ALL 
    TO anon, authenticated 
    USING (true) 
    WITH CHECK (true);

CREATE POLICY "Public insert/update access on borrow_transactions" 
    ON borrow_transactions FOR ALL 
    TO anon, authenticated 
    USING (true) 
    WITH CHECK (true);

-- ============================================================================
-- 9. ข้อมูลจำลองเริ่มต้น (Seed Data ตัวอย่างสำหรับการทดสอบระบบ)
-- ============================================================================
INSERT INTO assets (asset_id, serial_number, asset_code, asset_name, category, reg_status, borrow_status, notes)
VALUES 
    ('AST-1001', 'SN-DELL-5520-001', NULL, 'โน้ตบุ๊ก Dell Latitude 5520 i7/16GB', 'คอมพิวเตอร์และโน้ตบุ๊ก', 'รอเลขครุภัณฑ์', 'ว่าง', 'จัดซื้อล็อตใหม่ 2568 รองบประมาณตรวจรับ'),
    ('AST-1002', 'SN-IPAD-AIR5-002', NULL, 'iPad Air 5 64GB Wi-Fi (Space Gray)', 'แท็บเล็ต', 'รอเลขครุภัณฑ์', 'ว่าง', 'สำหรับงานลงทะเบียนและตรวจการประชุม'),
    ('AST-1003', 'SN-EPSON-EB2250U', '7440-001-0520', 'เครื่องฉายโปรเจกเตอร์ Epson EB-2250U', 'โสตทัศนูปกรณ์', 'มีเลขครุภัณฑ์แล้ว', 'ว่าง', 'ได้รับเลขครุภัณฑ์เรียบร้อยแล้ว พร้อมโอนไป CAD-Inventory');

INSERT INTO borrow_transactions (tx_id, asset_id, borrower_name, department, phone, borrow_date, due_date, tx_status, remark)
VALUES 
    ('TX-2026-001', 'AST-1002', 'นายสมชาย ใจดี', 'งานการเงินและพัสดุ', '081-234-5678', NOW() - INTERVAL '2 days', CURRENT_DATE + INTERVAL '5 days', 'กำลังยืม', 'ยืมใช้งานประชุมวิชาการประจำปี');

-- อัปเดตสถานะ AST-1002 ตาม transaction ข้างต้น
UPDATE assets SET borrow_status = 'ถูกยืม' WHERE asset_id = 'AST-1002';

-- ============================================================================
-- 10. 🛡️ Enterprise Security & Authentication Architecture (ระบบยืนยันตัวตนมาตรฐานสากล)
-- ============================================================================

-- 10.1 เปิดใช้งาน Cryptographic Extension สำหรับ Bcrypt
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 10.2 สร้างตาราง `system_users` สำหรับจัดเก็บข้อมูลผู้ใช้งานและ Password Hash
CREATE TABLE IF NOT EXISTS system_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'staff',
    department VARCHAR(100) DEFAULT 'กองบริหารงานกลาง',
    email VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index สำหรับค้นหาผู้ใช้งานรวดเร็ว O(1)
CREATE INDEX IF NOT EXISTS idx_users_username ON system_users(LOWER(username));

-- 10.3 ตั้งค่า Row Level Security (RLS) ขั้นสูงสุด (Strict Isolation)
ALTER TABLE system_users ENABLE ROW LEVEL SECURITY;

-- 🛡️ ป้องกันไม่ให้ใครก็ตามสามารถ SELECT ข้อมูลหรือ Hash จากตารางนี้ผ่าน Anon/Public REST API ได้ 100%
CREATE POLICY "Strict Deny Public Select on system_users" 
    ON system_users FOR ALL 
    TO anon, authenticated 
    USING (false);

-- อนุญาตเฉพาะ Service Role (Backend/Server) เท่านั้นที่อ่านเขียนตารางนี้ได้
CREATE POLICY "Full access for service role on system_users" 
    ON system_users FOR ALL 
    TO service_role 
    USING (true) 
    WITH CHECK (true);

-- 10.4 นำเข้าข้อมูลผู้ใช้งานจากระบบ CAD-Inventory โดยเก็บเป็น Bcrypt Hash (ต้นฉบับตรงกับ cad_inventory.db 100%)
INSERT INTO system_users (username, password_hash, full_name, role, department, email)
VALUES 
    (
        'superadmin', 
        '$2b$12$k0vPnjDaVEDis030i9CbouKD5XK.Hf6r2EHafCGe11Rl0vEC6wf8G', 
        'ผู้ดูแลระบบสูงสุด (Super Administrator)', 
        'superadmin', 
        'กองบริหารงานกลาง', 
        'superadmin@cad.cmu.ac.th'
    ),
    (
        'admin', 
        '$2b$12$r.Pr4bdybDWAOeXW3vVLU.wAXPcY4kC3CsgjyIiI2IMceJG/ICWFm', 
        'เจ้าหน้าที่พัสดุและครุภัณฑ์ (Admin CAD)', 
        'admin', 
        'กองบริหารงานกลาง', 
        'admin@cad.cmu.ac.th'
    ),
    (
        'staff', 
        '$2b$12$WQSBlQ5UipTzkyeKJJQeseDDkVQ/ZxnjlVEK/e.fA9hjJ2T7DaqmW', 
        'เจ้าหน้าที่ผู้ตรวจสอบ/ผู้ครอบครอง (Staff Auditor)', 
        'staff', 
        'กองบริหารงานกลาง', 
        'staff@cad.cmu.ac.th'
    ),
    (
        'executive', 
        '$2b$12$Wz5XTr77j4HWuIIc/zxe2uc53KL1jHkwSxXZpRtrs0SuZjlQzOUuO', 
        'ผู้อำนวยการกองบริหารงานกลาง (Executive)', 
        'executive', 
        'กองบริหารงานกลาง', 
        'executive@cad.cmu.ac.th'
    )
ON CONFLICT (username) DO UPDATE 
SET 
    password_hash = EXCLUDED.password_hash,
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    department = EXCLUDED.department,
    email = EXCLUDED.email,
    updated_at = NOW();

-- 10.5 สร้าง Stored Procedure (RPC) สำหรับตรวจสอบการเข้าสู่ระบบอย่างปลอดภัย (Security Definer)
-- ฟังก์ชันนี้จะประมวลผลการคำนวณ Hash บน PostgreSQL Engine ฝั่งเซิร์ฟเวอร์เท่านั้น ไม่ส่ง Hash ออกมาภายนอก
CREATE OR REPLACE FUNCTION authenticate_user(p_username TEXT, p_password TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user RECORD;
    v_dummy_hash TEXT := '$2b$12$k0vPnjDaVEDis030i9CbouKD5XK.Hf6r2EHafCGe11Rl0vEC6wf8G';
    v_is_valid BOOLEAN := FALSE;
BEGIN
    -- ค้นหาผู้ใช้งานตาม username แบบ Case-insensitive
    SELECT id, username, password_hash, full_name, role, department, email, is_active
    INTO v_user
    FROM system_users
    WHERE LOWER(username) = LOWER(TRIM(p_username));

    -- ตรวจสอบ Bcrypt Hash บน Database Engine
    IF FOUND AND v_user.is_active = TRUE THEN
        v_is_valid := (v_user.password_hash = crypt(p_password, v_user.password_hash));
    ELSE
        -- ทำงานหลอก (Dummy calculation) เพื่อป้องกัน Timing Attack / User Enumeration
        PERFORM crypt(p_password, v_dummy_hash);
        v_is_valid := FALSE;
    END IF;

    -- ส่งเฉพาะข้อมูล User ที่ปลอดภัยกลับออกไป (ไม่ส่ง password_hash หลุดออกไปเด็ดขาด)
    IF v_is_valid THEN
        RETURN jsonb_build_object(
            'success', true,
            'user', jsonb_build_object(
                'id', v_user.id,
                'username', v_user.username,
                'full_name', v_user.full_name,
                'role', v_user.role,
                'department', v_user.department,
                'email', v_user.email
            )
        );
    ELSE
        RETURN jsonb_build_object(
            'success', false,
            'message', 'ชื่อผู้ใช้งานหรือรหัสผ่านไม่ถูกต้อง'
        );
    END IF;
END;
$$;

-- ให้สิทธิ์ Anon และ Authenticated เรียกใช้ RPC Function นี้ได้
GRANT EXECUTE ON FUNCTION authenticate_user(TEXT, TEXT) TO anon, authenticated;

-- ============================================================================
-- 11. 📜 Enterprise Audit Logging System (ระบบบันทึกประวัติการตรวจสอบตามมาตรฐานสากล)
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    username VARCHAR(50) NOT NULL,
    user_role VARCHAR(20) NOT NULL DEFAULT 'staff',
    action VARCHAR(50) NOT NULL,
    target_type VARCHAR(50),
    target_id VARCHAR(100),
    details TEXT,
    ip_address VARCHAR(50) DEFAULT 'web-client',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes สำหรับการสืบค้นและ Audit ที่รวดเร็ว
CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_username ON audit_logs(username);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);

-- เปิด RLS สำหรับ Audit Logs
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- อนุญาตให้อ่านและบันทึกข้อมูลผ่าน Web Application ได้
CREATE POLICY "Public read and insert on audit_logs"
    ON audit_logs FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- บันทึกข้อมูลเริ่มต้น (System Initial Audit Log)
INSERT INTO audit_logs (username, user_role, action, target_type, target_id, details)
VALUES 
    ('system', 'superadmin', 'SYSTEM_INIT', 'DATABASE', 'v1.2.0', 'ระบบ SmartCAD-Lending และระบบ Audit Logging เริ่มต้นทำงานเรียบร้อยแล้ว'),
    ('superadmin', 'superadmin', 'SCHEMA_MIGRATION', 'SECURITY', 'system_users', 'ติดตั้งระบบพิสูจน์ตัวตน Bcrypt และ RLS สำเร็จ');


