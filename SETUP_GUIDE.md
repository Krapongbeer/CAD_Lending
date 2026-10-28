# 🚀 คู่มือการติดตั้งและเริ่มต้นใช้งาน Smart Asset Lending System

ระบบบริหารจัดการการยืม-คืนอุปกรณ์และครุภัณฑ์ใหม่ที่ยังไม่ได้รับเลขครุภัณฑ์ (เชื่อมต่อ AppSheet + Google Sheets + Supabase)

---

## 📌 ขั้นตอนที่ 1: ติดตั้ง Database Schema ใน Supabase

1. เปิดเบราว์เซอร์ไปที่ **[Supabase Dashboard](https://supabase.com/dashboard/project/undafgcijvuhvdmyjatk)**
2. คลิกเมนู **SQL Editor** (ไอคอน `>_` ที่แถบด้านซ้าย)
3. กด **New Query**
4. เปิดไฟล์ [`supabase_schema.sql`](./supabase_schema.sql) ในโฟลเดอร์นี้ คัดลอกโค้ดทั้งหมดมาวาง
5. กดปุ่ม **Run** (หรือกด `Ctrl+Enter` / `Cmd+Enter`)
6. ระบบจะ:
   - ล้างข้อมูล/ตารางเดิมตามที่คุณสั่ง
   - สร้างตาราง `assets` และ `borrow_transactions` พร้อม Index & Constraint ครบถ้วน
   - สร้าง Trigger สำหรับ Auto-Sync สถานะยืม-คืนอัตโนมัติ
   - สร้าง View สรุปข้อมูลสำหรับหน้า Dashboard และ View สำหรับส่งต่อ (Handoff) ไปยัง CAD-Inventory

---

## 📌 ขั้นตอนที่ 2: สร้าง Google Sheets สำหรับ AppSheet

1. สร้าง Google Spreadsheet ใหม่ที่ Google Drive ของคุณ ตั้งชื่อว่า:  
   `Smart CAD Borrow & New Parcel`
2. สร้าง 2 แผ่นงาน (Tabs):
   - **แผ่นงานที่ 1**: ตั้งชื่อแท็บว่า `assets`
   - **แผ่นงานที่ 2**: ตั้งชื่อแท็บว่า `borrow_transactions`
3. คัดลอกข้อมูลหัวตารางจากไฟล์ CSV ในโปรเจกต์ไปวางที่แถวที่ 1:
   - ตาราง `assets` ดูจาก [`template_sheet_assets.csv`](./template_sheet_assets.csv)
   - ตาราง `borrow_transactions` ดูจาก [`template_sheet_borrow_transactions.csv`](./template_sheet_borrow_transactions.csv)

---

## 📌 ขั้นตอนที่ 3: ติดตั้ง Auto-Sync ด้วย Google Apps Script

1. ในหน้า Google Sheets ให้ไปที่เมนูด้านบน: **Extensions (ส่วนขยาย) > Apps Script**
2. ลบโค้ดเดิมออกทั้งหมด
3. คัดลอกโค้ดจากไฟล์ [`sync_appscript.js`](./sync_appscript.js) ไปวาง
4. กด **Save (บันทึก 💾)**
5. รีเฟรชหน้า Google Sheets จะพบเมนูใหม่ชื่อ **`🚀 Supabase Sync`** ที่แถบเมนูด้านบน
6. สามารถกด **🔄 ซิงก์ข้อมูลทั้งหมดไป Supabase** ได้ทันทีด้วยคลิกเดียว

---

## 📌 ขั้นตอนที่ 4: เชื่อมต่อ AppSheet

1. เข้าไปที่ **[AppSheet.com](https://www.appsheet.com)** > กด **Create > App > Start with existing data**
2. เลือก Google Sheets ที่เพิ่งสร้างไว้ในขั้นตอนที่ 2
3. ตั้งค่า Data Types ใน AppSheet ให้ถูกต้อง:
   - **ตาราง assets**:
     - `asset_id`: Key, Initial value = `UNIQUEID()`
     - `serial_number`: Text, Scannable = `TRUE`
     - `asset_image`: Image
     - `reg_status`: Enum (`รอเลขครุภัณฑ์`, `มีเลขครุภัณฑ์แล้ว`)
     - `borrow_status`: Enum (`ว่าง`, `ถูกยืม`, `ซ่อมบำรุง`)
   - **ตาราง borrow_transactions**:
     - `tx_id`: Key, Initial value = `UNIQUEID()`
     - `asset_id`: Ref -> ชี้ไปตาราง `assets`
     - `due_date`: Date
     - `borrower_photo`: Image
     - `equip_borrow_photo`: Image
     - `borrow_signature`: Signature
     - `equip_return_photo`: Image
     - `return_signature`: Signature
     - `tx_status`: Enum (`กำลังยืม`, `คืนแล้ว`, `เกินกำหนด`)

---

## 📌 ขั้นตอนที่ 5: การส่งต่อข้อมูลเข้า CAD-Inventory (เมื่อได้เลขครุภัณฑ์)

เมื่ออุปกรณ์ชิ้นใดได้รับเลขครุภัณฑ์แล้ว:
1. ใน AppSheet หรือ Google Sheets ให้กรอก `asset_code` และเปลี่ยน `reg_status` เป็น `มีเลขครุภัณฑ์แล้ว`
2. ข้อมูลจะปรากฏใน View บน Supabase ชื่อ `view_assets_ready_for_cad_inventory` ทันที
3. สามารถกด Export เป็น Excel จาก Supabase หรือ Google Sheets แล้วนำไป Import เข้า CAD-Inventory ผ่านเมนู Import ได้อย่างปลอดภัย 100% โดยไม่ทับข้อมูลเก่า
