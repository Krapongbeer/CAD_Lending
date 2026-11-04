/**
 * ============================================================================
 * 🚀 Google Apps Script: Auto Sync Google Sheets -> Supabase
 * โครงการ: Smart CAD Borrow & New Parcel System
 * Deployment URL: https://script.google.com/macros/s/AKfycbz4eoX91Wfe0Op7hi3fhSYWCcbA0I_rNeS_bY7Op73pEaCI6s6t6AwJubFL_alluZwZzg/exec
 * ============================================================================
 */

const CONFIG = {
  SUPABASE_URL: "https://undafgcijvuhvdmyjatk.supabase.co",
  SUPABASE_KEY: "YOUR_SUPABASE_SECRET_KEY", // นำ SUPABASE_SECRET_KEY จาก .env มาวางตรงนี้
  SUPABASE_ANON_KEY: "sb_publishable_WGFEQiopY91Fxi5o_-McKw_iwTRS5yn",
  SYNC_TOKEN: "CAD_SECURE_SYNC_TOKEN_2026", // 🛡️ Secret Token สำหรับป้องกัน Unauthorized Webhook Trigger
  SHEET_ASSETS: "assets",
  SHEET_TRANSACTIONS: "borrow_transactions"
};

/**
 * รองรับ Web App GET Request (เช่น เรียกผ่าน URL เพื่อสั่งซิงก์ หรือ Ping ทดสอบ)
 */
function doGet(e) {
  const action = (e && e.parameter && e.parameter.action) ? e.parameter.action : 'sync';
  
  if (action === 'ping') {
    return ContentService.createTextOutput(JSON.stringify({
      status: 'ok',
      message: 'GAS Web App is active (v2.0.0 Secured)',
      timestamp: new Date().toISOString()
    })).setMimeType(ContentService.MimeType.JSON);
  }

  // ⏰ รองรับการทดสอบ Keep-Alive ผ่าน HTTP GET
  if (action === 'keepalive') {
    const res = keepSupabaseAlive();
    return ContentService.createTextOutput(JSON.stringify(res)).setMimeType(ContentService.MimeType.JSON);
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
    '✅ ซิงก์ข้อมูลสำเร็จ!',
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
 * Generic Upsert ไปยัง Supabase REST API
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
      }
      
      record[key] = val;
    }
    payload.push(record);
  }

  if (payload.length === 0) {
    return { status: 'ไม่มีแถวข้อมูลที่สมบูรณ์' };
  }

  const url = `${CONFIG.SUPABASE_URL}/rest/v1/${tableName}?on_conflict=${onConflictKey}`;
  const options = {
    method: 'post',
    contentType: 'application/json',
    headers: {
      'apikey': CONFIG.SUPABASE_KEY,
      'Authorization': `Bearer ${CONFIG.SUPABASE_KEY}`,
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
      'User-Agent': 'SmartCAD-KeepAlive/2.0'
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
    '⚡ ผลการทดสอบ Supabase Ping',
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
    '⏰ ติดตั้งระบบป้องกัน Supabase หลับ (Keep-Alive) สำเร็จ!',
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
