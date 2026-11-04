/**
 * ============================================================================
 * 🚀 Google Apps Script: Auto Sync Google Sheets -> Supabase (v2.2.0)
 * โครงการ: Smart CAD Borrow & New Parcel System
 * Deployment URL: https://script.google.com/macros/s/AKfycbz4eoX91Wfe0Op7hi3fhSYWCcbA0I_rNeS_bY7Op73pEaCI6s6t6AwJubFL_alluZwZzg/exec
 * 
 * ✨ จุดเด่นเวอร์ชัน v2.2.0:
 * 1. 🖼️ Auto Drive Image Resolver: แปลง Relative Path จาก AppSheet (เช่น borrow_transactions_Images/xxx.jpg)
 *    เป็น Google CDN Direct Link (https://lh3.googleusercontent.com/d/{fileId}) อัตโนมัติขณะซิงก์
 * 2. 🔓 Public Read Permission: ปรับสิทธิ์ไฟล์ใน Drive เป็น "ทุกคนที่มีลิงก์ดูได้" อัตโนมัติ เพื่อให้หน้าเว็บโหลดรูปและลายเซ็นได้ 100%
 * 3. 🛠️ One-Click Image Repair: เพิ่มเมนู "🖼️ ซ่อมแซมและอัปเดตลิงก์รูปภาพทั้งหมดไป Supabase" แก้รูปภาพที่มีอยู่แล้วในคลิกเดียว
 * 4. ⏰ Dual Keep-Alive Engine: ป้องกันฐานข้อมูล Supabase หยุดทำงานเมื่อไม่มีการเคลื่อนไหวเกิน 7 วัน
 * ============================================================================
 */

const CONFIG = {
  SUPABASE_URL: "https://undafgcijvuhvdmyjatk.supabase.co",
  SUPABASE_KEY: "YOUR_SUPABASE_SECRET_KEY", // นำ SUPABASE_SECRET_KEY จาก .env มาวางตรงนี้ (หรือใช้ Anon Key สำหรับซิงก์ทั่วไป)
  SUPABASE_ANON_KEY: "sb_publishable_WGFEQiopY91Fxi5o_-McKw_iwTRS5yn",
  SYNC_TOKEN: "CAD_SECURE_SYNC_TOKEN_2026", // 🛡️ Secret Token สำหรับป้องกัน Unauthorized Webhook Trigger
  SHEET_ASSETS: "assets",
  SHEET_TRANSACTIONS: "borrow_transactions"
};

// In-Memory Cache สำหรับเก็บ File ID และ URL เพื่อลดเวลาค้นหาไฟล์ในไดรฟ์
const DRIVE_URL_CACHE = {};

/**
 * 🖼️ ฟังก์ชันแปลงชื่อไฟล์หรือ Relative Path ของ Google Drive / AppSheet ให้เป็น Google CDN URL
 * เช่น "borrow_transactions_Images/9e1c57fd.borrower_photo.063854.jpg" 
 * -> "https://lh3.googleusercontent.com/d/1a2b3c4d5e6f..."
 */
function resolveDriveFileUrl(filePathOrUrl) {
  if (!filePathOrUrl || typeof filePathOrUrl !== 'string') return filePathOrUrl;
  const raw = filePathOrUrl.trim();
  if (!raw) return null;

  // 1. หากเป็น Base64 data URL อยู่แล้ว ให้ส่งกลับทันที
  if (raw.startsWith('data:image/')) return raw;

  // 2. หากเป็น Google Drive CDN link อยู่แล้ว
  if (raw.startsWith('https://lh3.googleusercontent.com/d/')) return raw;

  // 3. หากเป็นลิงก์ Google Drive แชร์แบบเดิม เช่น /file/d/ID/view หรือ ?id=ID
  const driveMatch = raw.match(/\/file\/d\/([a-zA-Z0-9_-]+)/) || raw.match(/[?&]id=([a-zA-Z0-9_-]+)/);
  if (driveMatch && driveMatch[1]) {
    const fileId = driveMatch[1];
    try {
      const file = DriveApp.getFileById(fileId);
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch (e) {
      Logger.log(`Warning: unable to set sharing for Drive file ${fileId}: ${e.message}`);
    }
    return `https://lh3.googleusercontent.com/d/${fileId}`;
  }

  // หากเป็น URL ภายนอกทั่วไป (http:// หรือ https://) ที่ไม่ใช่ Drive
  if (raw.startsWith('http://') || (raw.startsWith('https://') && !raw.includes('drive.google.com'))) {
    return raw;
  }

  // 4. กรณีเป็น Relative Path ของ AppSheet เช่น borrow_transactions_Images/9e1c57fd.jpg หรือชื่อไฟล์เดี่ยว
  const fileName = raw.includes('/') ? raw.split('/').pop() : raw;
  if (DRIVE_URL_CACHE[fileName]) {
    return DRIVE_URL_CACHE[fileName];
  }

  try {
    // ค้นหาไฟล์ใน Google Drive
    let files = DriveApp.getFilesByName(fileName);
    
    // หากไม่พบ ให้ลองค้นหาในโฟลเดอร์ของ Spreadsheet ปัจจุบัน
    if (!files.hasNext()) {
      try {
        const ssFile = DriveApp.getFileById(SpreadsheetApp.getActiveSpreadsheet().getId());
        const parents = ssFile.getParents();
        while (parents.hasNext() && !files.hasNext()) {
          const parentFolder = parents.next();
          const searchSub = parentFolder.searchFiles(`title = '${fileName.replace(/'/g, "\\'")}' and trashed = false`);
          if (searchSub.hasNext()) {
            files = searchSub;
            break;
          }
        }
      } catch (errSearch) {
        Logger.log(`Error searching parent folders for ${fileName}: ${errSearch.message}`);
      }
    }

    if (files.hasNext()) {
      const file = files.next();
      // ตั้งสิทธิ์ให้อ่านได้สาธารณะผ่านลิงก์ เพื่อให้ browser สามารถโหลดรูปแสดงในเว็บได้
      try {
        file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
      } catch (errSharing) {
        Logger.log(`Sharing permission notice for ${fileName}: ${errSharing.message}`);
      }
      
      const fileId = file.getId();
      const cdnUrl = `https://lh3.googleusercontent.com/d/${fileId}`;
      DRIVE_URL_CACHE[fileName] = cdnUrl;
      Logger.log(`🖼️ แปลงรูปภาพสำเร็จ: ${fileName} -> ${cdnUrl}`);
      return cdnUrl;
    } else {
      Logger.log(`⚠️ ไม่พบไฟล์ภาพใน Google Drive: ${fileName}`);
    }
  } catch (err) {
    Logger.log(`❌ เกิดข้อผิดพลาดในการค้นหาไฟล์ (${fileName}): ${err.message}`);
  }

  // หากค้นหาไม่พบ ให้ส่งค่าเดิมกลับไป
  return raw;
}

/**
 * รองรับ Web App GET Request (เช่น เรียกผ่าน URL เพื่อสั่งซิงก์, ตรวจสอบภาพ, หรือ Ping ทดสอบ)
 */
function doGet(e) {
  const action = (e && e.parameter && e.parameter.action) ? e.parameter.action : 'sync';
  
  // 1. ตรวจสอบสถานะการทำงาน
  if (action === 'ping') {
    return ContentService.createTextOutput(JSON.stringify({
      status: 'ok',
      version: 'v2.2.0',
      message: 'GAS Web App is active (v2.2.0 Auto Drive Image Resolver & Keep-Alive)',
      timestamp: new Date().toISOString()
    })).setMimeType(ContentService.MimeType.JSON);
  }

  // 2. ทดสอบ Keep-Alive ผ่าน HTTP GET
  if (action === 'keepalive') {
    const res = keepSupabaseAlive();
    return ContentService.createTextOutput(JSON.stringify(res)).setMimeType(ContentService.MimeType.JSON);
  }

  // 3. ฟังก์ชัน Resolve รูปภาพแบบ On-Demand ผ่าน HTTP
  if (action === 'resolveImage') {
    const fileName = (e && e.parameter && e.parameter.file) ? String(e.parameter.file) : '';
    const resolvedUrl = resolveDriveFileUrl(fileName);
    return ContentService.createTextOutput(JSON.stringify({
      status: 'ok',
      original: fileName,
      url: resolvedUrl
    })).setMimeType(ContentService.MimeType.JSON);
  }

  // 🛡️ ตรวจสอบ Secret Token เพื่อป้องกันคำขอก่อกวน
  const token = e && e.parameter && e.parameter.token;
  if (CONFIG.SYNC_TOKEN && token !== CONFIG.SYNC_TOKEN) {
    return ContentService.createTextOutput(JSON.stringify({
      status: 'error',
      message: '401 Unauthorized: Token ไม่ถูกต้องหรือไม่ได้รับอนุญาต'
    })).setMimeType(ContentService.MimeType.JSON);
  }

  // Action default: สั่งซิงก์ข้อมูลไป Supabase
  const resAssets = syncAssetsToSupabase();
  const resTx = syncTransactionsToSupabase();

  return ContentService.createTextOutput(JSON.stringify({
    status: 'success',
    version: 'v2.2.0',
    timestamp: new Date().toISOString(),
    results: {
      assets: resAssets,
      transactions: resTx
    }
  })).setMimeType(ContentService.MimeType.JSON);
}

/**
 * รองรับ Web App POST Request (เช่น Webhook จาก AppSheet หรือ Web Dashboard)
 */
function doPost(e) {
  let body = {};
  try {
    if (e && e.postData && e.postData.contents) {
      body = JSON.parse(e.postData.contents);
    }
  } catch (err) {}

  // 🛡️ ตรวจสอบ Secret Token
  const token = (e && e.parameter && e.parameter.token) || (body && body.token);
  if (CONFIG.SYNC_TOKEN && token !== CONFIG.SYNC_TOKEN) {
    return ContentService.createTextOutput(JSON.stringify({
      status: 'error',
      message: '401 Unauthorized: Token ไม่ถูกต้องหรือไม่ได้รับอนุญาต'
    })).setMimeType(ContentService.MimeType.JSON);
  }

  const resAssets = syncAssetsToSupabase();
  const resTx = syncTransactionsToSupabase();

  return ContentService.createTextOutput(JSON.stringify({
    status: 'success',
    version: 'v2.2.0',
    received: body,
    timestamp: new Date().toISOString(),
    results: {
      assets: resAssets,
      transactions: resTx
    }
  })).setMimeType(ContentService.MimeType.JSON);
}

/**
 * สร้าง Custom Menu บน Google Sheets ให้กดปุ่ม Sync ได้ง่ายๆ
 */
function onOpen() {
  const ui = SpreadsheetApp.getUi();
  ui.createMenu('🚀 Supabase Sync')
    .addItem('🔄 ซิงก์ข้อมูลทั้งหมดไป Supabase', 'syncAllToSupabase')
    .addItem('📦 ซิงก์เฉพาะตาราง Assets', 'syncAssetsToSupabase')
    .addItem('📋 ซิงก์เฉพาะตาราง Transactions', 'syncTransactionsToSupabase')
    .addSeparator()
    .addItem('🖼️ ซ่อมแซมและอัปเดตลิงก์รูปภาพทั้งหมดไป Supabase', 'repairAndSyncImagesToSupabase')
    .addSeparator()
    .addItem('⏰ ติดตั้งระบบป้องกัน Supabase หลับ (Keep-Alive ทุก 2 วัน)', 'installKeepAliveTrigger')
    .addItem('⚡ ทดสอบ Ping Supabase ทันที', 'testKeepAliveNow')
    .addItem('⏹️ ปิดระบบป้องกัน Supabase หลับ', 'removeKeepAliveTrigger')
    .addToUi();
}

/**
 * ฟังก์ชันหลัก: ซิงก์ข้อมูลทั้งหมด
 */
function syncAllToSupabase() {
  const resAssets = syncAssetsToSupabase();
  const resTx = syncTransactionsToSupabase();
  
  SpreadsheetApp.getActiveSpreadsheet().toast(
    `Assets: ${resAssets.status} | Transactions: ${resTx.status}`,
    '✅ ซิงก์ข้อมูลสำเร็จ! (v2.2.0)',
    5
  );
}

/**
 * ซิงก์ตาราง Assets ไป Supabase (Upsert โดยใช้ asset_id)
 */
function syncAssetsToSupabase() {
  return syncTableToSupabase(CONFIG.SHEET_ASSETS, 'assets', 'asset_id');
}

/**
 * ซิงก์ตาราง Transactions ไป Supabase (Upsert โดยใช้ tx_id)
 */
function syncTransactionsToSupabase() {
  return syncTableToSupabase(CONFIG.SHEET_TRANSACTIONS, 'borrow_transactions', 'tx_id');
}

/**
 * 🖼️ เมนูพิเศษ: สแกนซ่อมแซมและแปลงลิงก์รูปภาพทั้งหมดพร้อมส่งไปอัปเดตที่ Supabase ทันที
 */
function repairAndSyncImagesToSupabase() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  ss.toast('กำลังสแกนหาไฟล์ภาพใน Google Drive และแปลงเป็นลิงก์สาธารณะ...', '🖼️ กำลังดำเนินการ', 10);
  
  const resAssets = syncAssetsToSupabase();
  const resTx = syncTransactionsToSupabase();
  
  const ui = SpreadsheetApp.getUi();
  ui.alert(
    '✅ ซ่อมแซมและอัปเดตลิงก์รูปภาพเรียบร้อยแล้ว! (v2.2.0)',
    `ระบบได้แปลง Relative Path จาก AppSheet เป็น Google Drive CDN URL และอัปเดตไปยัง Supabase สำเร็จ:\n\n` +
    `• ข้อมูลครุภัณฑ์ (Assets): ${resAssets.status}\n` +
    `• รายการยืม-คืน (Transactions): ${resTx.status}\n\n` +
    `ขณะนี้คุณสามารถเปิดดูรูปผู้ยืม สภาพอุปกรณ์ และลายเซ็นในหน้าเว็บระบบได้อย่างสมบูรณ์`,
    ui.ButtonSet.OK
  );
}

/**
 * Generic Upsert ไปยัง Supabase REST API พร้อมระบบ Auto Drive Image Resolver
 */
function syncTableToSupabase(sheetName, tableName, onConflictKey) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName(sheetName);
  
  if (!sheet) {
    Logger.log(`⚠️ ไม่พบแผ่นงานชื่อ: ${sheetName}`);
    return { status: `ไม่พบแผ่นงาน ${sheetName}` };
  }

  const data = sheet.getDataRange().getValues();
  if (data.length < 2) {
    return { status: 'ไม่มีข้อมูลในชีต' };
  }

  const headers = data[0];
  const payload = [];
  const IMAGE_FIELD_REGEX = /(?:photo|signature|image)$/i;

  for (let i = 1; i < data.length; i++) {
    const row = data[i];
    if (!row[0] || String(row[0]).trim() === '') continue;

    const record = {};
    for (let j = 0; j < headers.length; j++) {
      const key = String(headers[j]).trim();
      let val = row[j];

      if (val instanceof Date) {
        val = Utilities.formatDate(val, Session.getScriptTimeZone(), "yyyy-MM-dd'T'HH:mm:ss'Z'");
      } else if (val === '' || val === null || val === undefined) {
        val = null;
      } else if (typeof val === 'string' && IMAGE_FIELD_REGEX.test(key)) {
        // 🖼️ แปลง AppSheet relative path หรือ Google Drive URL เป็น Google CDN URL อัตโนมัติ
        val = resolveDriveFileUrl(val);
      }
      
      record[key] = val;
    }
    payload.push(record);
  }

  if (payload.length === 0) {
    return { status: 'ไม่มีแถวข้อมูลที่สมบูรณ์' };
  }

  const apiKey = (CONFIG.SUPABASE_KEY && !CONFIG.SUPABASE_KEY.startsWith("YOUR_")) 
    ? CONFIG.SUPABASE_KEY 
    : CONFIG.SUPABASE_ANON_KEY;

  const url = `${CONFIG.SUPABASE_URL}/rest/v1/${tableName}?on_conflict=${onConflictKey}`;
  const options = {
    method: 'post',
    contentType: 'application/json',
    headers: {
      'apikey': apiKey,
      'Authorization': `Bearer ${apiKey}`,
      'Prefer': 'resolution=merge-duplicates'
    },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  };

  try {
    const response = UrlFetchApp.fetch(url, options);
    const code = response.getResponseCode();
    if (code >= 200 && code < 300) {
      Logger.log(`✅ ซิงก์ ${tableName} สำเร็จ: ${payload.length} รายการ`);
      return { status: `ซิงก์สำเร็จ (${payload.length} แถว)` };
    } else {
      Logger.log(`❌ ซิงก์ ${tableName} ล้มเหลว (${code}): ${response.getContentText()}`);
      return { status: `เกิดข้อผิดพลาด (${code})` };
    }
  } catch (err) {
    Logger.log(`❌ Exception in syncTableToSupabase: ${err.message}`);
    return { status: `Exception: ${err.message}` };
  }
}

/**
 * ============================================================================
 * ⏰ ระบบป้องกัน Supabase Free Tier หลับ (Keep-Alive Engine 24/7)
 * Supabase Free Tier จะหยุดการทำงาน (Paused) หากไม่มีการส่งคำขอเกิน 7 วัน
 * ฟังก์ชันนี้จะส่ง Ping เพื่อกระตุ้น Database Connection ให้อยู่ในสถานะ Active เสมอ
 * ============================================================================
 */

function keepSupabaseAlive() {
  const apiKey = (CONFIG.SUPABASE_KEY && !CONFIG.SUPABASE_KEY.startsWith("YOUR_")) 
    ? CONFIG.SUPABASE_KEY 
    : CONFIG.SUPABASE_ANON_KEY;

  // ส่ง Query เบาๆ 1 แถวเพื่อกระตุ้น Database Connection
  const url = `${CONFIG.SUPABASE_URL}/rest/v1/assets?select=asset_id&limit=1`;
  const options = {
    method: 'get',
    headers: {
      'apikey': apiKey,
      'Authorization': `Bearer ${apiKey}`,
      'User-Agent': 'SmartCAD-KeepAlive/2.2.0'
    },
    muteHttpExceptions: true
  };

  try {
    const startTime = new Date().getTime();
    const response = UrlFetchApp.fetch(url, options);
    const code = response.getResponseCode();
    const latency = new Date().getTime() - startTime;

    if (code >= 200 && code < 300) {
      Logger.log(`🟢 Supabase Keep-Alive สำเร็จ (${code}) - เวลาตอบสนอง ${latency}ms`);
      return { status: `เชื่อมต่อสำเร็จ (${code}) Latency: ${latency}ms`, success: true };
    } else {
      Logger.log(`🟡 Supabase Keep-Alive ตอบสนองด้วยรหัส (${code}): ${response.getContentText()}`);
      return { status: `ตอบสนองด้วยรหัส (${code})`, success: false };
    }
  } catch (err) {
    Logger.log(`🔴 Supabase Keep-Alive Exception: ${err.message}`);
    return { status: `เกิดข้อผิดพลาด: ${err.message}`, success: false };
  }
}

/**
 * ปุ่มทดสอบ Ping ทันทีจากเมนู Google Sheets
 */
function testKeepAliveNow() {
  const result = keepSupabaseAlive();
  const ui = SpreadsheetApp.getUi();
  ui.alert(
    '⚡ ผลการทดสอบ Supabase Ping (v2.2.0)',
    `สถานะ: ${result.status}\n\nเมื่อระบบทำงานปกติ Supabase จะได้รับสัญญาณและรีเซ็ตเวลานับถอยหลัง 7 วันให้อัตโนมัติ`,
    ui.ButtonSet.OK
  );
}

/**
 * ติดตั้ง Google Apps Script Time-Driven Trigger ให้อัตโนมัติ (คลิกเดียวผ่านเมนู)
 * ทำงานทุกๆ 2 วัน ในช่วงเวลา 06:00 - 07:00 น.
 */
function installKeepAliveTrigger() {
  // 1. ลบ Trigger เดิมที่มีชื่อซ้ำออกก่อนเพื่อไม่ให้เกิดการทำงานซ้ำซ้อน
  const triggers = ScriptApp.getProjectTriggers();
  for (let i = 0; i < triggers.length; i++) {
    if (triggers[i].getHandlerFunction() === 'keepSupabaseAlive') {
      ScriptApp.deleteTrigger(triggers[i]);
    }
  }

  // 2. สร้าง Trigger ใหม่ให้ทำงานทุกๆ 2 วัน (ป้องกันการหลับเกิน 7 วัน 100%)
  ScriptApp.newTrigger('keepSupabaseAlive')
    .timeBased()
    .everyDays(2)
    .atHour(6)
    .create();

  // 3. ทดสอบ Ping ทันที 1 ครั้งเพื่อยืนยันผล
  const pingResult = keepSupabaseAlive();

  const ui = SpreadsheetApp.getUi();
  ui.alert(
    '⏰ ติดตั้งระบบป้องกัน Supabase หลับ (Keep-Alive v2.2.0) สำเร็จ!',
    `ระบบตั้งเวลาอัตโนมัติให้ส่งสัญญาณ Ping ทุกๆ 2 วัน (เวลา 06:00 น.) เรียบร้อยแล้ว\n\n` +
    `หมดกังวลเรื่อง Supabase Free Tier หยุดทำงาน (Paused) เมื่อไม่มีคนใช้งานเกิน 7 วัน\n\n` +
    `ผลการทดสอบการเชื่อมต่อทันที: ${pingResult.status}`,
    ui.ButtonSet.OK
  );
}

/**
 * ยกเลิก Trigger ป้องกันหลับ (หากต้องการปิด)
 */
function removeKeepAliveTrigger() {
  const triggers = ScriptApp.getProjectTriggers();
  let count = 0;
  for (let i = 0; i < triggers.length; i++) {
    if (triggers[i].getHandlerFunction() === 'keepSupabaseAlive') {
      ScriptApp.deleteTrigger(triggers[i]);
      count++;
    }
  }

  const ui = SpreadsheetApp.getUi();
  ui.alert(
    '⏹️ ปิดระบบ Keep-Alive เรียบร้อย',
    `ยกเลิก Trigger ไปทั้งหมด ${count} ตัว`,
    ui.ButtonSet.OK
  );
}
