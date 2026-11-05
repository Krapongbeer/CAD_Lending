-- ============================================================================
-- 🛡️ Smart CAD Borrow & New Parcel System - Comprehensive Security Hardening Patch v2.3.0
-- กองบริหารงานกลาง สำนักงานมหาวิทยาลัย มหาวิทยาลัยเชียงใหม่
-- 
-- คำแนะนำ: คัดลอกโค้ดทั้งหมดนี้ไปวางใน Supabase Dashboard > SQL Editor แล้วกด "Run" 1 ครั้ง
-- สคริปต์นี้ปลอดภัย 100% ไม่ลบข้อมูลครุภัณฑ์หรือรายการยืมเดิมที่มีอยู่แล้วในระบบ
-- ============================================================================

-- 1. เปิดใช้งาน Extension ที่จำเป็นสำหรับเข้ารหัสรหัสผ่าน Bcrypt
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- 2. ยกระดับ Row Level Security (RLS) บน assets และ borrow_transactions
-- ============================================================================

-- 2.1 เปิดใช้งาน RLS (หากยังไม่เปิด)
ALTER TABLE IF EXISTS assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS borrow_transactions ENABLE ROW LEVEL SECURITY;

-- 2.2 🛡️ ล้าง Policy เดิมที่อาจเปิดสิทธิ์กว้างเกินไป (FOR ALL) ที่ทำให้คนภายนอกสั่ง DELETE ได้
DROP POLICY IF EXISTS "Public insert/update access on assets" ON assets;
DROP POLICY IF EXISTS "Public insert/update access on borrow_transactions" ON borrow_transactions;
DROP POLICY IF EXISTS "Allow public all access on assets" ON assets;
DROP POLICY IF EXISTS "Allow public all access on borrow_transactions" ON borrow_transactions;
DROP POLICY IF EXISTS "Full access for service role on assets" ON assets;
DROP POLICY IF EXISTS "Full access for service role on borrow_transactions" ON borrow_transactions;
DROP POLICY IF EXISTS "Public read access on assets" ON assets;
DROP POLICY IF EXISTS "Public read access on borrow_transactions" ON borrow_transactions;
DROP POLICY IF EXISTS "Public insert access on assets" ON assets;
DROP POLICY IF EXISTS "Public insert access on borrow_transactions" ON borrow_transactions;
DROP POLICY IF EXISTS "Public update access on assets" ON assets;
DROP POLICY IF EXISTS "Public update access on borrow_transactions" ON borrow_transactions;
DROP POLICY IF EXISTS "Strictly deny delete on assets for public" ON assets;
DROP POLICY IF EXISTS "Strictly deny delete on borrow_transactions for public" ON borrow_transactions;

-- 2.3 อนุญาตให้ Service Role (ระบบหลังบ้าน) เข้าถึงได้เต็มที่
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

-- 2.4 สิทธิ์การอ่าน (SELECT): ให้ Anon และ Authenticated อ่านได้เพื่อแสดงผลบน Dashboard
CREATE POLICY "Public read access on assets" 
    ON assets FOR SELECT 
    TO anon, authenticated 
    USING (true);

CREATE POLICY "Public read access on borrow_transactions" 
    ON borrow_transactions FOR SELECT 
    TO anon, authenticated 
    USING (true);

-- 2.5 สิทธิ์การเพิ่มข้อมูล (INSERT): อนุญาตให้บันทึกพัสดุและรายการยืมใหม่ได้
CREATE POLICY "Public insert access on assets" 
    ON assets FOR INSERT 
    TO anon, authenticated 
    WITH CHECK (true);

CREATE POLICY "Public insert access on borrow_transactions" 
    ON borrow_transactions FOR INSERT 
    TO anon, authenticated 
    WITH CHECK (true);

-- 2.6 สิทธิ์การแก้ไขข้อมูล (UPDATE): อนุญาตให้อัปเดตสถานะและเลขครุภัณฑ์ได้
CREATE POLICY "Public update access on assets" 
    ON assets FOR UPDATE 
    TO anon, authenticated 
    USING (true) 
    WITH CHECK (true);

CREATE POLICY "Public update access on borrow_transactions" 
    ON borrow_transactions FOR UPDATE 
    TO anon, authenticated 
    USING (true) 
    WITH CHECK (true);

-- 2.7 ⛔ STRICT RESTRICTIVE POLICY (บล็อกการ DELETE ถาวร 100%):
-- ป้องกันไม่ให้ใครก็ตามสามารถสั่ง DELETE ผ่าน Public/Anon REST API ได้เด็ดขาด
CREATE POLICY "Strictly deny delete on assets for public" 
    ON assets AS RESTRICTIVE FOR DELETE 
    TO anon, authenticated 
    USING (false);

CREATE POLICY "Strictly deny delete on borrow_transactions for public" 
    ON borrow_transactions AS RESTRICTIVE FOR DELETE 
    TO anon, authenticated 
    USING (false);

-- ============================================================================
-- 3. ตาราง login_attempts (ป้องกัน Brute-Force Rate Limiting)
-- ============================================================================
CREATE TABLE IF NOT EXISTS login_attempts (
    id BIGSERIAL PRIMARY KEY,
    ip_address VARCHAR(45),
    username VARCHAR(50) NOT NULL,
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    success BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_lookup 
    ON login_attempts (username, attempted_at DESC);

ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Full access for service role on login_attempts" ON login_attempts;
DROP POLICY IF EXISTS "Public insert access on login_attempts" ON login_attempts;

CREATE POLICY "Full access for service role on login_attempts" 
    ON login_attempts FOR ALL 
    TO service_role 
    USING (true) 
    WITH CHECK (true);

CREATE POLICY "Public insert access on login_attempts" 
    ON login_attempts FOR INSERT 
    TO anon, authenticated 
    WITH CHECK (true);

-- ============================================================================
-- 4. ตาราง audit_logs (Immutable Append-Only Audit Trail)
-- ============================================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    username VARCHAR(50) NOT NULL,
    user_role VARCHAR(20) NOT NULL,
    action VARCHAR(50) NOT NULL,
    target_type VARCHAR(50) NOT NULL,
    target_id VARCHAR(100),
    details TEXT,
    ip_address VARCHAR(45) DEFAULT '127.0.0.1'
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_username ON audit_logs(username);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);

ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read access on audit_logs" ON audit_logs;
DROP POLICY IF EXISTS "Public insert access on audit_logs" ON audit_logs;
DROP POLICY IF EXISTS "Full access for service role on audit_logs" ON audit_logs;
DROP POLICY IF EXISTS "Strictly deny delete on audit_logs for public" ON audit_logs;
DROP POLICY IF EXISTS "Strictly deny update on audit_logs for public" ON audit_logs;

CREATE POLICY "Public read access on audit_logs"
    ON audit_logs FOR SELECT
    TO anon, authenticated
    USING (true);

CREATE POLICY "Public insert access on audit_logs"
    ON audit_logs FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

CREATE POLICY "Full access for service role on audit_logs" 
    ON audit_logs FOR ALL 
    TO service_role 
    USING (true) 
    WITH CHECK (true);

-- บล็อก UPDATE และ DELETE บน audit_logs สำหรับ Anon/Public 100% ป้องกันการทำลายประวัติ
CREATE POLICY "Strictly deny delete on audit_logs for public" 
    ON audit_logs AS RESTRICTIVE FOR DELETE 
    TO anon, authenticated 
    USING (false);

CREATE POLICY "Strictly deny update on audit_logs for public" 
    ON audit_logs AS RESTRICTIVE FOR UPDATE 
    TO anon, authenticated 
    USING (false);

-- ============================================================================
-- 5. ตาราง system_users และ Safe View
-- ============================================================================
CREATE TABLE IF NOT EXISTS system_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('superadmin', 'admin', 'staff', 'executive')),
    department VARCHAR(100) DEFAULT 'กองบริหารงานกลาง',
    email VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE system_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Strict Deny Public Select on system_users" ON system_users;
DROP POLICY IF EXISTS "Full access for service role on system_users" ON system_users;

CREATE POLICY "Strict Deny Public Select on system_users" 
    ON system_users FOR ALL 
    TO anon, authenticated 
    USING (false);

CREATE POLICY "Full access for service role on system_users" 
    ON system_users FOR ALL 
    TO service_role 
    USING (true) 
    WITH CHECK (true);

-- เพิ่มผู้ใช้งานเริ่มต้นหากยังไม่มี
INSERT INTO system_users (username, password_hash, full_name, role, department, email)
VALUES 
    ('superadmin', crypt('superadmin1234', gen_salt('bf', 10)), 'ผู้ดูแลระบบสูงสุด (Super Administrator)', 'superadmin', 'กองบริหารงานกลาง', 'superadmin@cad.cmu.ac.th'),
    ('admin', crypt('admin1234', gen_salt('bf', 10)), 'เจ้าหน้าที่พัสดุ (CAD Parcel Officer)', 'admin', 'งานพัสดุและครุภัณฑ์', 'admin@cad.cmu.ac.th'),
    ('staff', crypt('staff1234', gen_salt('bf', 10)), 'เจ้าหน้าที่ผู้ส่งมอบ (Inventory Staff)', 'staff', 'หน่วยสนับสนุนเทคนิค', 'staff@cad.cmu.ac.th'),
    ('executive', crypt('exec1234', gen_salt('bf', 10)), 'ผู้อำนวยการกอง (Executive Director)', 'executive', 'กองบริหารงานกลาง', 'executive@cad.cmu.ac.th')
ON CONFLICT (username) DO NOTHING;

-- Safe View สำหรับแสดงผลรายชื่อผู้ใช้งาน (ไม่เปิดเผย password_hash เด็ดขาด)
CREATE OR REPLACE VIEW view_system_users AS
SELECT 
    id,
    username,
    full_name,
    role,
    department,
    email,
    is_active,
    created_at,
    updated_at
FROM system_users;

GRANT SELECT ON view_system_users TO anon, authenticated;

-- ============================================================================
-- 6. Stored Procedures (Security Definer พร้อม Search Path ปลอดภัย)
-- ============================================================================

-- 6.1 ตรวจสอบการเข้าสู่ระบบอย่างปลอดภัย พร้อม Brute-force Rate Limiting
DROP FUNCTION IF EXISTS authenticate_user(TEXT, TEXT);
CREATE OR REPLACE FUNCTION authenticate_user(
    p_username TEXT, 
    p_password TEXT,
    p_ip_address TEXT DEFAULT '127.0.0.1'
)
RETURNS JSONB 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user RECORD;
    v_recent_failures INT;
    v_clean_user TEXT;
BEGIN
    v_clean_user := LOWER(TRIM(p_username));

    -- ตรวจสอบการพยายามล็อกอินผิดพลาดเกิน 5 ครั้งใน 15 นาที
    SELECT COUNT(*) INTO v_recent_failures
    FROM login_attempts
    WHERE username = v_clean_user
      AND success = FALSE
      AND attempted_at > NOW() - INTERVAL '15 minutes';

    IF v_recent_failures >= 5 THEN
        INSERT INTO audit_logs (username, user_role, action, target_type, target_id, details, ip_address)
        VALUES (v_clean_user, 'unknown', 'SECURITY_ALERT', 'AUTH', 'RATE_LIMIT_EXCEEDED', 
                format('ถูกระงับการเข้าสู่ระบบ 15 นาทีเนื่องจากกรอกรหัสผ่านผิดเกินกำหนด (Failed count: %s)', v_recent_failures), p_ip_address);

        RETURN jsonb_build_object(
            'success', false,
            'message', 'คุณกรอกรหัสผ่านผิดเกิน 5 ครั้ง บัญชีถูกระงับการเข้าสู่ระบบชั่วคราวเป็นเวลา 15 นาที เพื่อความปลอดภัย'
        );
    END IF;

    -- ค้นหาผู้ใช้
    SELECT id, username, password_hash, full_name, role, department, email, is_active
    INTO v_user
    FROM system_users
    WHERE LOWER(username) = v_clean_user;

    IF NOT FOUND THEN
        INSERT INTO login_attempts (username, ip_address, success)
        VALUES (v_clean_user, p_ip_address, FALSE);
        RETURN jsonb_build_object('success', false, 'message', 'ชื่อผู้ใช้งานหรือรหัสผ่านไม่ถูกต้อง');
    END IF;

    IF v_user.is_active = FALSE THEN
        RETURN jsonb_build_object('success', false, 'message', 'บัญชีผู้ใช้นี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแลระบบสูงสุด');
    END IF;

    -- ตรวจสอบรหัสผ่าน Bcrypt
    IF v_user.password_hash = crypt(p_password, v_user.password_hash) THEN
        INSERT INTO login_attempts (username, ip_address, success)
        VALUES (v_clean_user, p_ip_address, TRUE);

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
        INSERT INTO login_attempts (username, ip_address, success)
        VALUES (v_clean_user, p_ip_address, FALSE);
        RETURN jsonb_build_object('success', false, 'message', 'ชื่อผู้ใช้งานหรือรหัสผ่านไม่ถูกต้อง');
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION authenticate_user(TEXT, TEXT, TEXT) TO anon, authenticated;

-- 6.2 เพิ่มผู้ใช้งานใหม่ (เฉพาะ Superadmin พร้อม Re-authentication รหัสผ่าน)
CREATE OR REPLACE FUNCTION admin_create_user(
    p_admin_username TEXT,
    p_admin_password TEXT,
    p_new_username TEXT,
    p_password TEXT,
    p_full_name TEXT,
    p_role TEXT,
    p_department TEXT DEFAULT 'กองบริหารงานกลาง',
    p_email TEXT DEFAULT NULL
)
RETURNS JSONB 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_admin RECORD;
    v_clean_user TEXT;
    v_clean_role TEXT;
BEGIN
    v_clean_user := LOWER(TRIM(p_new_username));
    v_clean_role := LOWER(TRIM(p_role));

    IF v_clean_role NOT IN ('superadmin', 'admin', 'staff', 'executive') THEN
        RETURN jsonb_build_object('success', false, 'message', 'บทบาทไม่ถูกต้อง (ต้องเป็น superadmin, admin, staff, หรือ executive)');
    END IF;

    SELECT id, username, password_hash, role, is_active
    INTO v_admin
    FROM system_users
    WHERE LOWER(username) = LOWER(TRIM(p_admin_username));

    IF NOT FOUND OR v_admin.is_active = FALSE OR v_admin.role != 'superadmin' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Permission denied: เฉพาะ Superadmin เท่านั้น');
    END IF;

    IF p_admin_password IS NULL OR TRIM(p_admin_password) = '' OR v_admin.password_hash != crypt(p_admin_password, v_admin.password_hash) THEN
        INSERT INTO audit_logs (username, user_role, action, target_type, target_id, details)
        VALUES (COALESCE(p_admin_username, 'unknown'), 'attacker', 'SECURITY_ALERT', 'USER_MGMT', 'UNAUTHORIZED_ATTEMPT', 
                format('พยายามสร้างผู้ใช้ %s โดยไม่ใส่รหัสผ่าน Superadmin ที่ถูกต้อง (Authorization Failed)', v_clean_user));
        RETURN jsonb_build_object('success', false, 'message', 'Permission denied: รหัสผ่านยืนยันสิทธิ์ Superadmin ไม่ถูกต้อง');
    END IF;

    IF EXISTS (SELECT 1 FROM system_users WHERE LOWER(username) = v_clean_user) THEN
        RETURN jsonb_build_object('success', false, 'message', format('ชื่อผู้ใช้งาน "%s" มีอยู่ในระบบแล้ว', v_clean_user));
    END IF;

    INSERT INTO system_users (username, password_hash, full_name, role, department, email, is_active)
    VALUES (v_clean_user, crypt(p_password, gen_salt('bf', 10)), TRIM(p_full_name), v_clean_role, 
            COALESCE(NULLIF(TRIM(p_department), ''), 'กองบริหารงานกลาง'), NULLIF(TRIM(p_email), ''), true);

    INSERT INTO audit_logs (username, user_role, action, target_type, target_id, details)
    VALUES (v_admin.username, 'superadmin', 'USER_MANAGEMENT', 'USER', v_clean_user, 
            format('สร้างผู้ใช้งานใหม่: %s (บทบาท: %s, ชื่อ: %s)', v_clean_user, v_clean_role, TRIM(p_full_name)));

    RETURN jsonb_build_object('success', true, 'message', 'สร้างผู้ใช้งานสำเร็จ');
END;
$$;

GRANT EXECUTE ON FUNCTION admin_create_user(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- 6.3 ลบผู้ใช้งาน (เฉพาะ Superadmin พร้อม Re-authentication รหัสผ่าน)
CREATE OR REPLACE FUNCTION admin_delete_user(
    p_admin_username TEXT,
    p_admin_password TEXT,
    p_target_username TEXT
)
RETURNS JSONB 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_admin RECORD;
    v_clean_target TEXT;
BEGIN
    v_clean_target := LOWER(TRIM(p_target_username));

    IF v_clean_target = 'superadmin' THEN
        RETURN jsonb_build_object('success', false, 'message', 'ไม่อนุญาตให้ลบบัญชี Superadmin หลัก');
    END IF;

    SELECT id, username, password_hash, role, is_active
    INTO v_admin
    FROM system_users
    WHERE LOWER(username) = LOWER(TRIM(p_admin_username));

    IF NOT FOUND OR v_admin.is_active = FALSE OR v_admin.role != 'superadmin' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Permission denied: เฉพาะ Superadmin เท่านั้น');
    END IF;

    IF p_admin_password IS NULL OR TRIM(p_admin_password) = '' OR v_admin.password_hash != crypt(p_admin_password, v_admin.password_hash) THEN
        INSERT INTO audit_logs (username, user_role, action, target_type, target_id, details)
        VALUES (COALESCE(p_admin_username, 'unknown'), 'attacker', 'SECURITY_ALERT', 'USER_MGMT', 'UNAUTHORIZED_ATTEMPT', 
                format('พยายามลบผู้ใช้ %s โดยไม่ใส่รหัสผ่าน Superadmin ที่ถูกต้อง (Authorization Failed)', v_clean_target));
        RETURN jsonb_build_object('success', false, 'message', 'Permission denied: รหัสผ่านยืนยันสิทธิ์ Superadmin ไม่ถูกต้อง');
    END IF;

    DELETE FROM system_users WHERE LOWER(username) = v_clean_target;

    INSERT INTO audit_logs (username, user_role, action, target_type, target_id, details)
    VALUES (v_admin.username, 'superadmin', 'USER_MANAGEMENT', 'USER', v_clean_target, 
            format('ลบผู้ใช้งาน: %s ออกจากระบบและฐานข้อมูล Supabase', v_clean_target));

    RETURN jsonb_build_object('success', true, 'message', 'ลบผู้ใช้งานสำเร็จ');
END;
$$;

GRANT EXECUTE ON FUNCTION admin_delete_user(TEXT, TEXT, TEXT) TO anon, authenticated;

-- 6.4 เปิด/ปิดสถานะผู้ใช้งาน (Active / Suspended พร้อม Re-authentication)
CREATE OR REPLACE FUNCTION admin_toggle_user_status(
    p_admin_username TEXT,
    p_admin_password TEXT,
    p_target_username TEXT,
    p_is_active BOOLEAN
)
RETURNS JSONB 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_admin RECORD;
    v_clean_target TEXT;
    v_action_text TEXT;
BEGIN
    v_clean_target := LOWER(TRIM(p_target_username));

    IF v_clean_target = 'superadmin' AND p_is_active = FALSE THEN
        RETURN jsonb_build_object('success', false, 'message', 'ไม่อนุญาตให้ระงับบัญชี Superadmin หลัก');
    END IF;

    SELECT id, username, password_hash, role, is_active
    INTO v_admin
    FROM system_users
    WHERE LOWER(username) = LOWER(TRIM(p_admin_username));

    IF NOT FOUND OR v_admin.is_active = FALSE OR v_admin.role != 'superadmin' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Permission denied: เฉพาะ Superadmin เท่านั้น');
    END IF;

    IF p_admin_password IS NULL OR TRIM(p_admin_password) = '' OR v_admin.password_hash != crypt(p_admin_password, v_admin.password_hash) THEN
        INSERT INTO audit_logs (username, user_role, action, target_type, target_id, details)
        VALUES (COALESCE(p_admin_username, 'unknown'), 'attacker', 'SECURITY_ALERT', 'USER_MGMT', 'UNAUTHORIZED_ATTEMPT', 
                format('พยายามเปลี่ยนสถานะผู้ใช้ %s โดยไม่ใส่รหัสผ่าน Superadmin ที่ถูกต้อง (Authorization Failed)', v_clean_target));
        RETURN jsonb_build_object('success', false, 'message', 'Permission denied: รหัสผ่านยืนยันสิทธิ์ Superadmin ไม่ถูกต้อง');
    END IF;

    UPDATE system_users 
    SET is_active = p_is_active, updated_at = NOW() 
    WHERE LOWER(username) = v_clean_target;

    v_action_text := CASE WHEN p_is_active THEN 'เปิดใช้งาน' ELSE 'ระงับชั่วคราว' END;

    INSERT INTO audit_logs (username, user_role, action, target_type, target_id, details)
    VALUES (v_admin.username, 'superadmin', 'USER_MANAGEMENT', 'USER', v_clean_target, 
            format('เปลี่ยนสถานะบัญชี: %s เป็น %s', v_clean_target, v_action_text));

    RETURN jsonb_build_object('success', true, 'message', format('เปลี่ยนสถานะผู้ใช้งานเป็น %s สำเร็จ', v_action_text));
END;
$$;

GRANT EXECUTE ON FUNCTION admin_toggle_user_status(TEXT, TEXT, TEXT, BOOLEAN) TO anon, authenticated;

-- ============================================================================
-- 7. บันทึกประวัติเริ่มต้นความปลอดภัย (v2.3.0 Hardened)
-- ============================================================================
INSERT INTO audit_logs (username, user_role, action, target_type, target_id, details)
VALUES 
    ('system', 'superadmin', 'SECURITY_PATCH_V2.3.0', 'DATABASE', 'v2.3.0', 
     'ติดตั้งระบบความปลอดภัยระดับองค์กร v2.3.0: เปิดใช้งาน Restrictive RLS บล็อกการ DELETE บน assets และ transactions สำหรับบุคคลภายนอก 100%, สร้างตาราง login_attempts ป้องกัน Brute-force, เปิดใช้งาน Append-only audit_logs, และล็อก search_path ทุก Stored Procedure');
