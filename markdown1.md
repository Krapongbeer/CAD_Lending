# โครงการพัฒนาระบบยืม-คืนอุปกรณ์และครุภัณฑ์ใหม่ (Smart Asset Lending System)

## 1. ภาพรวมระบบ (System Overview)
ระบบบริหารจัดการการยืม-คืนอุปกรณ์และครุภัณฑ์ใหม่ที่ยังไม่ได้รับเลขครุภัณฑ์ โดยอ้างอิงจาก Serial Number และรูปภาพเป็นหลัก 
- **Frontend (Mobile/Tablet):** AppSheet (เก็บข้อมูลอุปกรณ์, ถ่ายรูปผู้ยืม/อุปกรณ์, เซ็นชื่ออิเล็กทรอนิกส์)
- **Primary Data Store:** Google Sheets & Google Drive (เก็บไฟล์ภาพและลายเซ็น)
- **Backend & Real-time DB:** Supabase (PostgreSQL & Supabase Storage)
- **Web Dashboard:** แสดงผลสถิติ, ติดตามสถานะการยืม-คืน และอัปเดตเลขครุภัณฑ์ย้อนหลัง

---

## 2. ขั้นตอนการทำงาน (Workflow)
1. **การลงทะเบียนอุปกรณ์ใหม่ (Asset Registration)**
   - สแกน `Serial Number` จากตัวเครื่อง
   - ถ่ายรูปอุปกรณ์
   - กำหนดสถานะทะเบียนเป็น `รอเลขครุภัณฑ์` และสถานะการยืมเป็น `ว่าง`
2. **การยืมอุปกรณ์ (Borrowing Process)**
   - เลือกอุปกรณ์ที่มีสถานะ `ว่าง` (ค้นหาจาก Serial Number หรือชื่อ)
   - กรอกข้อมูลผู้ยืม, แผนก และวันที่กำหนดคืน
   - ถ่ายรูปผู้ยืมคู่กับอุปกรณ์ และถ่ายรูปสภาพอุปกรณ์
   - ผู้ยืมเซ็นชื่อลงบนหน้าจอแอปพลิเคชัน
   - ระบบอัปเดตสถานะอุปกรณ์เป็น `ถูกยืม` อัตโนมัติ
3. **การคืนอุปกรณ์ (Returning Process)**
   - ค้นหารายการจากเมนู `กำลังยืม`
   - ตรวจสอบสภาพและถ่ายรูปอุปกรณ์ตอนคืน
   - เซ็นชื่อยืนยันการคืน
   - ระบบอัปเดตสถานะอุปกรณ์กลับเป็น `ว่าง`

---

## 3. โครงสร้างตาราง (Database Schema)

### 3.1 ตาราง `assets`
- `asset_id` (PK, Text) : รหัสอ้างอิงระบบ `UNIQUEID()`
- `serial_number` (Text, Unique) : ซีเรียลนัมเบอร์
- `asset_code` (Text, Nullable) : เลขครุภัณฑ์ (อัปเดตภายหลังได้)
- `asset_name` (Text) : ชื่อและรุ่นอุปกรณ์
- `category` (Text) : หมวดหมู่อุปกรณ์
- `asset_image` (Image/URL) : รูปภาพประจำตัวอุปกรณ์
- `reg_status` (Enum) : `รอเลขครุภัณฑ์` | `มีเลขครุภัณฑ์แล้ว`
- `borrow_status` (Enum) : `ว่าง` | `ถูกยืม` | `ซ่อมบำรุง`

### 3.2 ตาราง `borrow_transactions`
- `tx_id` (PK, Text) : รหัสธุรกรรม `UNIQUEID()`
- `asset_id` (FK, Text) : อ้างอิง `assets.asset_id`
- `borrower_name` (Text) : ชื่อผู้ยืม
- `department` (Text) : หน่วยงาน/แผนก
- `phone` (Text) : เบอร์ติดต่อ
- `borrow_date` (DateTime) : วันเวลาที่ยืม
- `due_date` (Date) : กำหนดส่งคืน
- `borrower_photo` (Image/URL) : รูปถ่ายผู้ยืม
- `equip_borrow_photo` (Image/URL) : รูปสภาพอุปกรณ์ตอนยืม
- `borrow_signature` (Signature/URL) : ลายเซ็นตอนยืม
- `return_date` (DateTime, Nullable) : วันเวลาที่คืนจริง
- `equip_return_photo` (Image/URL, Nullable) : รูปสภาพอุปกรณ์ตอนคืน
- `return_signature` (Signature/URL, Nullable) : ลายเซ็นตอนคืน
- `tx_status` (Enum) : `กำลังยืม` | `คืนแล้ว` | `เกินกำหนด`
- `remark` (Text) : หมายเหตุ

---

## 4. รายการสิ่งที่ต้องทำ (To-Do List)
- [x] เตรียมไฟล์ Template Google Sheets ตามโครงสร้างตาราง `assets` และ `borrow_transactions` (`template_sheet_assets.csv`, `template_sheet_borrow_transactions.csv`)
- [x] เขียน SQL Schema สำหรับ Supabase พร้อม Auto-sync Triggers และ Views (`supabase_schema.sql` - รันสำเร็จแล้ว)
- [x] เขียน Google Apps Script สำหรับ Sync ข้อมูลไปยัง Supabase REST API พร้อม Web App Endpoint (`sync_appscript.js`)
- [x] จัดทำพิมพ์เขียวและคู่มือการตั้งค่า AppSheet ละเอียดทุกฟิลด์ (`APPSHEET_BLUEPRINT.md`)
- [x] พัฒนาหน้า Web Dashboard เชื่อมต่อกับ Supabase API แบบ Real-time พร้อมปุ่ม Export ไปยัง CAD-Inventory (`index.html`)