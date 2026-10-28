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
      message: 'GAS Web App is active',
      timestamp: new Date().toISOString()
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
