# 📱 AppSheet Configuration Blueprint (คู่มือการตั้งค่า AppSheet ฉบับสมบูรณ์)

โครงสร้างการตั้งค่าแอปพลิเคชัน **Smart CAD Lending & New Parcel** บน AppSheet สำหรับใช้งานบนสมาร์ตโฟน/แท็บเล็ต

---

## 1. การเชื่อมต่อข้อมูล (Data Sources)

1. เข้าเว็บ **[AppSheet.com](https://www.appsheet.com)**
2. คลิก **Create > App > Start with existing data**
3. เลือกไฟล์ Google Sheets: `CAD-borrow&newpacel` (จาก Google Drive)
4. เพิ่มตารางทั้ง 2 เข้าสู่ AppSheet:
   - ตาราง `assets`
   - ตาราง `borrow_transactions`

---

## 2. การตั้งค่าคอลัมน์ (Data > Columns)

### 2.1 ตาราง `assets`

| คอลัมน์ | Type | Key? | Label? | Formula / Initial Value | คำอธิบาย / การตั้งค่าพิเศษ |
|---|---|:---:|:---:|---|---|
| `asset_id` | **Text** | ✅ | ❌ | `UNIQUEID()` | Auto Key |
| `serial_number` | **Text** | ❌ | ❌ | | **ติ๊กถูกช่อง Scannable = TRUE** (เปิดกล้องสแกนได้) |
| `asset_name` | **Text** | ❌ | ✅ | | ชื่อและรุ่นอุปกรณ์ (ให้ติ๊กช่อง Label) |
| `category` | **Enum** | ❌ | ❌ | | ค่า: `คอมพิวเตอร์และโน้ตบุ๊ก`, `แท็บเล็ต`, `โสตทัศนูปกรณ์`, `อุปกรณ์เน็ตเวิร์ก`, `อื่นๆ` |
| `asset_image` | **Image** | ❌ | ❌ | | รูปภาพประจำตัวเครื่อง |
| `reg_status` | **Enum** | ❌ | ❌ | `"รอเลขครุภัณฑ์"` | ค่า: `รอเลขครุภัณฑ์`, `มีเลขครุภัณฑ์แล้ว` |
| `borrow_status` | **Enum** | ❌ | ❌ | `"ว่าง"` | ค่า: `ว่าง`, `ถูกยืม`, `ซ่อมบำรุง` |
| `asset_code` | **Text** | ❌ | ❌ | | เลขครุภัณฑ์ (กรอกภายหลังเมื่อได้รับเลข) |
| `notes` | **LongText**| ❌ | ❌ | | หมายเหตุ |
| `created_at` | **DateTime**| ❌ | ❌ | `NOW()` | วันเวลาที่ลงทะเบียน |
| `updated_at` | **DateTime**| ❌ | ❌ | `NOW()` | วันเวลาที่แก้ไขล่าสุด |

---

### 2.2 ตาราง `borrow_transactions`

| คอลัมน์ | Type | Key? | Label? | Formula / Initial Value | คำอธิบาย / การตั้งค่าพิเศษ |
|---|---|:---:|:---:|---|---|
| `tx_id` | **Text** | ✅ | ❌ | `UNIQUEID()` | Auto Key |
| `asset_id` | **Ref** | ❌ | ❌ | | **ชี้ไปตาราง `assets`** (Referenced Table Name = `assets`) |
| `borrower_name` | **Text** | ❌ | ✅ | | ชื่อผู้ยืม |
| `department` | **Text** | ❌ | ❌ | | แผนก/ฝ่าย |
| `phone` | **Phone** | ❌ | ❌ | | เบอร์โทรศัพท์ |
| `borrow_date` | **DateTime**| ❌ | ❌ | `NOW()` | วันเวลาที่ยืม |
| `due_date` | **Date** | ❌ | ❌ | `TODAY() + 7` | กำหนดส่งคืน (Default 7 วัน) |
| `borrower_photo`| **Image** | ❌ | ❌ | | ถ่ายรูปผู้ยืมคู่กับอุปกรณ์ |
| `equip_borrow_photo`| **Image**| ❌ | ❌ | | รูปสภาพอุปกรณ์ตอนส่งมอบ |
| `borrow_signature`| **Signature**| ❌ | ❌ | | **ลายเซ็นอิเล็กทรอนิกส์ตอนยืม** |
| `return_date` | **DateTime**| ❌ | ❌ | | วันเวลาคืนจริง |
| `equip_return_photo`| **Image**| ❌ | ❌ | | รูปสภาพอุปกรณ์ตอนคืน |
| `return_signature`| **Signature**| ❌ | ❌ | | **ลายเซ็นอิเล็กทรอนิกส์ตอนคืน** |
| `tx_status` | **Enum** | ❌ | ❌ | `"กำลังยืม"` | ค่า: `กำลังยืม`, `คืนแล้ว`, `เกินกำหนด` |
| `remark` | **LongText**| ❌ | ❌ | | หมายเหตุเพิ่มเติม |

---

## 3. การสร้าง Slices (มุมมองกรองข้อมูล)

ไปที่เมนู **Data > Slices** สร้าง 3 Slices ดังนี้:

### Slice 1: `Assets_Available` (อุปกรณ์ที่พร้อมให้ยืม)
- **Table:** `assets`
- **Row filter condition:**
  ```excel
  [borrow_status] = "ว่าง"
  ```

### Slice 2: `Active_Loans` (รายการที่กำลังยืมอยู่)
- **Table:** `borrow_transactions`
- **Row filter condition:**
  ```excel
  [tx_status] = "กำลังยืม"
  ```

### Slice 3: `Assets_Waiting_Parcel` (อุปกรณ์ที่รอใส่เลขครุภัณฑ์)
- **Table:** `assets`
- **Row filter condition:**
  ```excel
  [reg_status] = "รอเลขครุภัณฑ์"
  ```

---

## 4. การสร้าง Actions (ปุ่มคำสั่งลัด)

### Action 1: "ปุ่มกดยืมอุปกรณ์" (Borrow Action)
- **Table:** `assets`
- **Do this:** `App: go to another view within this app`
- **Target:**
  ```excel
  LINKTOFORM("borrow_transactions_Form", "asset_id", [asset_id])
  ```
- **Only if this condition is true:**
  ```excel
  [borrow_status] = "ว่าง"
  ```
- **Display Icon:** `tag` หรือ `arrow-up-right`
- **Display name:** `"ยืมอุปกรณ์ชิ้นนี้"`

### Action 2: "ปุ่มยืนยันการคืน" (Return Action)
- **Table:** `borrow_transactions`
- **Do this:** `App: go to another view within this app`
- **Target:**
  ```excel
  LINKTOROW([tx_id], "Return_Form")
  ```
- **Only if this condition is true:**
  ```excel
  [tx_status] = "กำลังยืม"
  ```
- **Display Icon:** `check-circle`
- **Display name:** `"ทำรายการคืน"`

---

## 5. การสร้าง Views (หน้าจอการใช้งาน)

ไปที่เมนู **App > Views**:

1. **View 1: `อุปกรณ์พร้อมยืม` (Available Assets)**
   - View type: `Card` หรือ `Deck`
   - For this data: เลือก Slice `Assets_Available`
   - Position: `center`

2. **View 2: `กำลังยืม` (Active Loans)**
   - View type: `Table`
   - For this data: เลือก Slice `Active_Loans`
   - Position: `left`

3. **View 3: `สแกนค้นหาอุปกรณ์` (Scan Asset)**
   - เปิด Search Bar แล้วสแกนบาร์โค้ดผ่านไอคอนกล้องใน AppSheet ได้ทันที

4. **View 4: `รอใส่เลขครุภัณฑ์` (Waiting Parcel Code)**
   - View type: `Table`
   - For this data: เลือก Slice `Assets_Waiting_Parcel`
   - Position: `menu` (อยู่ในแถบขยายด้านข้าง)
