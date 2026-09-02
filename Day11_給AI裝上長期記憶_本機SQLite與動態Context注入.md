# Day 11｜AI 核心：給 AI 裝上長期記憶（本機 SQLite + 動態 Context 注入）

> 如果每次請 AI 做卡頓診斷或系統決策時，都只給它「當下這一瞬間」的資料，AI 往往只能給出「請嘗試重開機」或「關閉 Chrome」這種空泛無用的建議。
> 但如果我們將「過去這 7 天的崩潰紀錄、上次的修復方式、使用者個人的開發習慣」動態塞入 Prompt，AI 的診斷就會瞬間變得精準無比！
> 今天我們在 Windows 本機打造專屬記憶庫，實作 **AI 主動長期記憶（Agentic Text-to-SQL + 動態 Context 注入）** 架構！

---

本文同步發布於 GitHub： [2026-18th-it-ironman](https://github.com/BingFengHung/2026-18th-it-ironman/blob/main/Day11_給AI裝上長期記憶_本機SQLite與動態Context注入.md)

## 痛點對比：金魚腦 AI vs 具備主動記憶的專屬管家

| 比較項目           | ❌ 無狀態 AI（金魚腦）     | ⚠️ 固定條件查詢（受限版）                     | ✅ AI 主動檢索記憶（Agentic Text-to-SQL）                                                 |
| :----------------- | :------------------------- | :---------------------------------------------- | :---------------------------------------------------------------------------------------- |
| **輸入數據** | 只有當下「記憶體佔用 85%」 | 當下資料 +**寫死只查同一進程名稱**        | 當下資料 +**AI 自主動態聯想關聯進程與閾值**                                         |
| **關聯能力** | 完全無法關聯               | 遇到`docker.exe` 連鎖引發 `vmmemWSL` 就瞎掉 | **自動檢索 WSL、Docker 容器與過往超過 3GB 的重大事故**                              |
| **診斷結論** | 「建議關閉應用程式。」     | 「過去 3 天 vmmemWSL 發生 3 次超標。」          | **「比對過去 Docker 編譯與 WSL 紀錄，確認為容器快取連鎖洩漏，精準給出修復指令。」** |

---

## 本機 SQLite 主動記憶架構圖

![01](./image/day11/01.png)

---

* 我們將資料庫的 Schema 提供給 AI Agent，讓 Agent 先根據當前異常情境**自主決定檢索策略並寫出最精準的 SQL**。
* 再由本機 SQLite 執行查詢，把撈出來的精準結構化歷史數據動態注入給下一個階段的 AI Agent 進行深度診斷。
* **既保留了關聯式資料庫 100% 精確的時序與數值過濾，又賦予了 AI 跨進程自主聯想的強大智慧！**

---

## 前置準備：在 Windows 上安裝與驗證 SQLite CLI

在 Windows 上使用 SQLite 不需要啟動任何背景資料庫服務（如 MySQL 或 PostgreSQL），它是純粹的單一執行檔（`sqlite3.exe`），極度輕量、零依賴。

### 安裝 sqlite

Windows 10 / 11 系統已預載 Windows 套件管理員（winget），打開 PowerShell 直接執行：

```powershell
winget install SQLite.SQLite
```

> **💡 其他安裝管道（備選）**：
>
> * **Scoop 套件管理員**：`scoop install sqlite`
> * **Chocolatey 套件管理員**：`choco install sqlite`
> * **官網手動下載免安裝包**：至 [SQLite 官網下載頁面](https://www.sqlite.org/download.html) 下載 `sqlite-tools-win-x64-*.zip`，解壓縮後將資料夾加入系統環境變數 `Path`。

### 驗證安裝成果

安裝完成後，請**重新開啟一個新的 PowerShell 終端機**，輸入：

```powershell
sqlite3 --version
```

若能成功印出版本號，代表本機環境配置完成！

---

## 實戰動手做：打造本機自主記憶庫（雙階 Agentic 流程）

整條 Node-RED 自動化流程分為兩大核心階段：

1. **階段一（Query Planning）**：AI 觀察異常，自主分析關聯生態系，動態生成最適 SQLite 檢索語句。
2. **階段二（RCA Diagnosis）**：本機 SQLite 執行查詢後，將歷史記憶動態注入 Prompt，由 AI 做出深層根因診斷。

---

### 步驟 1：本機歷史資料庫架構設計

我們在本地建立一張輕量化的事故歷史表，定義欄位如下：

```sql
CREATE TABLE IF NOT EXISTS system_incidents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT (datetime('now', 'localtime')),
    process_name TEXT NOT NULL,
    memory_mb REAL NOT NULL,
    last_action TEXT
);
```

---

### 步驟 2：組裝 SQL 生成 Prompt 與 Schema 約束（Function 節點）

拉出第一個 **`function`** 節點，命名為 `1. 組裝 SQL 生成 Prompt (Function)`。

> **💡 Setup 設定提醒**：請在 Function 節點「設定（Setup）」➔「模組（Modules）」頁籤中引入 `os`、`fs`、`path`。

```javascript
// Function 節點：組裝 SQL 生成 Prompt (Setup 注入 os, fs, path)
const current = msg.payload;
msg.currentEvent = current;

const homedir = os.homedir();
const logDir = path.join(homedir, 'SystemLogs');
fs.mkdirSync(logDir, { recursive: true });

const schema = {
  type: 'object',
  properties: {
    thought: { type: 'string', description: '關聯進程、閾值與檢索策略思考' },
    sql: { type: 'string', description: 'SQLite SELECT 查詢語句' }
  },
  required: ['thought', 'sql']
};

// 💡 最佳實踐：將 Schema 存成本地檔案傳入，徹底避免 Windows/PowerShell 引號跳脫爆炸
const schemaFile = path.join(logDir, 'schema_sql.json');
fs.writeFileSync(schemaFile, JSON.stringify(schema, null, 2), 'utf-8');

const prompt = `你是一位資深的 Windows 系統架構師與自動化維運專家。
當前監控系統捕獲到一筆即時異常事件：
- 進程名稱: ${current.process_name} (PID: ${current.pid})
- 記憶體佔用: ${current.memory_mb} MB

本機 SQLite 資料庫已記錄過去事故，資料表結構為：
CREATE TABLE system_incidents (
    id INTEGER PRIMARY KEY,
    timestamp DATETIME,
    process_name TEXT,
    memory_mb REAL,
    last_action TEXT
);

為了對此異常進行最深度的 RCA 根因診斷，請不要受限於單一進程名稱！
請自主分析可能與其連鎖關聯的進程生態（例如 Docker、WSL、編譯器等）、合理的嚴重度閾值，並寫出一條最有參考價值的 SQLite SELECT 查詢語句（最多檢索 5 筆，按 timestamp 降序）。`;

// 💡 關鍵調優：加入 --effort low 加速思考至 6~10 秒內完成，避免 Node-RED Exec 節點等待過久
msg.payload = `agy -p ${JSON.stringify(prompt)} --output-format json --effort low --dangerously-skip-permissions --json-schema "${schemaFile.replace(/\\/g, '/')}"`;
return msg;
```

---

### 步驟 3：調用本機 `agy CLI` 讓 AI 自主生成檢索 SQL（Exec 節點）

拉出一個 **`exec`** 節點，執行合成好的 Prompt：

* **節點名稱**：`2. AI 自主生成檢索 SQL (Exec)`
* **Command**：留空（完全由上游 `msg.payload` 傳入完整命令行）。
* **附加 msg.payload**：**打勾（true）**。
* **超時 (Timeout)**：**設定為 60 秒**（為本機 AI 推理預留充裕時間，防止被 Node-RED 提前中斷）。

---

### 步驟 4：解析 SQL、執行安全防禦並組裝 SQLite 查詢指令（Function 節點）

拉出一個 **`function`** 節點，命名為 `3. 解析 SQL 並組裝 SQLite 查詢 (Function)`。
解析 AI 生成的 SQL，加入安全白名單防禦（**嚴格限制只允許 `SELECT` 語句，防止惡意注入**），並確保本機資料夾與資料庫就緒：

> **💡 Setup 設定提醒**：請在 Function 節點「設定（Setup）」➔「模組（Modules）」頁籤中引入 `os`、`fs`、`path`。

```javascript
// Function 節點：解析 SQL 並組裝 SQLite 查詢 (Setup 注入 os, fs, path)
let parsed;
try {
    parsed = typeof msg.payload === 'string' ? JSON.parse(msg.payload) : msg.payload;
} catch (e) {
    node.error('AI SQL 生成失敗: ' + msg.payload);
    return null;
}

let result = parsed.structured_output;
if (!result && parsed.response) {
    try {
        result = typeof parsed.response === 'string' ? JSON.parse(parsed.response) : parsed.response;
    } catch (e) {
        const match = parsed.response.match(/\{[\s\S]*\}/);
        if (match) result = JSON.parse(match[0]);
    }
}

msg.retrievalThought = (result && result.thought) ? result.thought : '自主分析關聯生態系';
let generatedSql = (result && result.sql) ? result.sql.trim() : '';

// 🛡️ 安全防禦：確保僅允許執行 SELECT 查詢
if (!/^select\b/i.test(generatedSql)) {
    generatedSql = `SELECT timestamp, process_name, memory_mb, last_action FROM system_incidents WHERE process_name = '${msg.currentEvent.process_name}' ORDER BY timestamp DESC LIMIT 5;`;
}

const homedir = os.homedir();
const logDir = path.join(homedir, 'SystemLogs');
fs.mkdirSync(logDir, { recursive: true });
const dbPath = path.join(logDir, 'pc_guardian.db').replace(/\\/g, '/');

const proc = (msg.currentEvent.process_name || 'unknown').replace(/'/g, "''");
const mem = Number(msg.currentEvent.memory_mb) || 0;

// 組合 SQL：初始化資料表 + 預置示範數據 + 寫入當前異常 + 執行 AI 的動態查詢
const fullSql = `
CREATE TABLE IF NOT EXISTS system_incidents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT (datetime('now', 'localtime')),
    process_name TEXT NOT NULL,
    memory_mb REAL NOT NULL,
    last_action TEXT
);
INSERT INTO system_incidents (timestamp, process_name, memory_mb, last_action)
SELECT '2026-08-28 14:20:00', '${proc}', 2800, '手動重啟 Docker'
WHERE NOT EXISTS (SELECT 1 FROM system_incidents);

INSERT INTO system_incidents (timestamp, process_name, memory_mb, last_action)
SELECT '2026-08-30 09:15:00', '${proc}', 3100, '執行 wsl --shutdown'
WHERE (SELECT count(*) FROM system_incidents) = 1;

INSERT INTO system_incidents (process_name, memory_mb, last_action)
VALUES ('${proc}', ${mem}, '觸發即時 RCA 診斷');

${generatedSql}
`.trim().replace(/\r?\n/g, ' ');

msg.generatedSql = generatedSql;
msg.payload = `sqlite3 -json "${dbPath}" "${fullSql}"`;
return msg;
```

---

### 步驟 5：執行本機 `sqlite3.exe` CLI 檢索記憶（Exec 節點）

拉出一個 **`exec`** 節點，執行剛才組裝完成的指令：

* **節點名稱**：`4. 執行 SQLite CLI 查詢 (Exec)`
* **Command**：留空。
* **附加 msg.payload**：**打勾（true）**。
* **超時 (Timeout)**：可設定為 10 秒。

SQLite 會以毫秒級速度執行 AI 自主設計的查詢，並將結構化結果輸出為純 JSON 陣列！

---

### 步驟 6：組裝含歷史記憶之深度 RCA Prompt（Function 節點）

拉出一個 **`function`** 節點，命名為 `5. 拼接歷史記憶與 RCA Prompt (Function)`。
將當前異常、AI 的檢索思路、SQLite 查出的跨進程歷史以及使用者 Profile 進行動態 Context 注入：

> **💡 Setup 設定提醒**：請在 Function 節點「設定（Setup）」➔「模組（Modules）」頁籤中引入 `os`、`fs`、`path`。

```javascript
// Function 節點：拼接歷史記憶與 RCA Prompt (Setup 注入 os, fs, path)
const current = msg.currentEvent || {};
let history = [];

try {
    history = typeof msg.payload === 'string' ? JSON.parse(msg.payload) : (msg.payload || []);
} catch (e) {
    history = [];
}

const historyList = history.map(h => `- [${h.timestamp}] 進程 ${h.process_name} 佔用 ${h.memory_mb} MB (前次處置: ${h.last_action || '無'})`).join('\n');
const userProfile = '使用者主要進行 WSL2 Linux 容器開發、Docker 與 VS Code 專案編譯。';

const prompt = `你是一個個人專屬的 Windows 系統維運顧問。請根據「當前異常」、「AI 自主檢索策略」與「SQLite 歷史事件庫」進行深度 RCA 根因診斷：

【當前異常事件】:
- 進程: ${current.process_name} (PID: ${current.pid})
- 記憶體佔用: ${current.memory_mb} MB

【AI 自主檢索策略與思考】:
- 執行之動態 SQL: ${msg.generatedSql}
- 策略思考: ${msg.retrievalThought}

【自本機 SQLite 調取出的歷史關聯事件】:
${historyList || '無相關歷史異常紀錄'}

【使用者個人開發環境背景 (Profile)】:
${userProfile}

請結合關聯進程生態（WSL 與 Docker 交互影響）與歷史趨勢，給出深度分析與量身定做的處置方案。`;

const schema = {
  type: 'object',
  properties: {
    retrieval_analysis: { type: 'string', description: '對檢索出的跨進程歷史數據之關聯分析' },
    root_cause: { type: 'string', description: '深層技術根因 (RCA)' },
    action_plan: { type: 'string', description: '量身定制的修復動作與預防建議' }
  },
  required: ['retrieval_analysis', 'root_cause', 'action_plan']
};

const homedir = os.homedir();
const logDir = path.join(homedir, 'SystemLogs');
fs.mkdirSync(logDir, { recursive: true });
const schemaFile = path.join(logDir, 'schema_rca.json');
fs.writeFileSync(schemaFile, JSON.stringify(schema, null, 2), 'utf-8');

// 💡 關鍵調優：加入 --effort low 加速思考，大幅提升響應速度
msg.payload = `agy -p ${JSON.stringify(prompt)} --output-format json --effort low --dangerously-skip-permissions --json-schema "${schemaFile.replace(/\\/g, '/')}"`;
return msg;
```

---

### 步驟 7：調用本機 `agy CLI` 進行最終 RCA 根因診斷（Exec 節點）

拉出一個 **`exec`** 節點，執行最終診斷：

* **節點名稱**：`6. AI 深度根因診斷 (Exec)`
* **Command**：留空。
* **附加 msg.payload**：**打勾（true）**。
* **超時 (Timeout)**：**設定為 60 秒**。

---

### 步驟 8：雙軌安全解包與成果驗收（Function ➔ Debug 節點）

> **💡 Setup 設定提醒**：請在 Function 節點「設定（Setup）」➔「模組（Modules）」頁籤中引入 `os`、`fs`、`path`。

```javascript
// Function 節點：雙軌安全解包 (Setup 注入 os, fs, path)
let parsed;
try {
    parsed = typeof msg.payload === 'string' ? JSON.parse(msg.payload) : msg.payload;
} catch (e) {
    node.error('JSON 解析失敗: ' + msg.payload);
    return null;
}

let result = parsed.structured_output;
if (!result && parsed.response) {
    try {
        result = typeof parsed.response === 'string' ? JSON.parse(parsed.response) : parsed.response;
    } catch (e) {
        const match = parsed.response.match(/\{[\s\S]*\}/);
        if (match) result = JSON.parse(match[0]);
    }
}

msg.payload = {
    executed_sql: msg.generatedSql,
    retrieval_thought: msg.retrievalThought,
    diagnosis: result || parsed
};

// 💡 同步將最新診斷成果存檔至本機目錄，方便外部系統整合與稽核
try {
    const homedir = os.homedir();
    fs.writeFileSync(path.join(homedir, 'SystemLogs', 'latest_diagnosis.json'), JSON.stringify(msg.payload, null, 2), 'utf-8');
} catch (err) {}

return msg;
```

---

## 成果驗收：AI 自主檢索記憶與專屬深度診斷成果

當系統異常觸發時，AI 不再被動接受死板的固定查詢，而是展現出驚人的自主推理能力：

### 1. AI 自主生成的 SQL 檢索與思考

```json
{
  "thought": "vmmemWSL 是 WSL2 虛擬機的核心進程，通常與 Docker Desktop 連鎖運作。為了全面排查，我不僅要查詢 vmmem，還要將 docker、wsl 相關進程一併納入，且設定記憶體 >= 3000MB 篩選嚴重事故。",
  "executed_sql": "SELECT id, timestamp, process_name, memory_mb, last_action FROM system_incidents WHERE (process_name LIKE '%vmmem%' OR process_name LIKE '%docker%' OR process_name LIKE '%wsl%') AND memory_mb >= 3000 ORDER BY timestamp DESC LIMIT 5;"
}
```

### 2. 結合自主檢索情報後的最終 RCA 診斷

```json
{
  "retrieval_analysis": "歷史庫顯示過去 3 天內 vmmemWSL 與 Docker 容器進程均有多次突破 3GB 的記錄，且前次執行重啟後依舊復發，說明屬於高頻慣性洩漏。",
  "root_cause": "Docker 容器頻繁編譯產生的 Linux 核心 Page Cache 未被定期回收，疊加 WSL2 動態記憶體上限未受約束，導致 Windows 實體記憶體被吃滿。",
  "action_plan": "1. 立即在 Windows 使用者根目錄建立 .wslconfig 限制 memory=4GB。\n2. 在 Docker Compose 加入 cache 限制，一勞永逸解決 Page Cache 滾雪球問題。"
}
```

---

## 完整 Flow 程式

### 本範例 flow 位置：👉 [下載](https://github.com/BingFengHung/2026-18th-it-ironman/blob/main/flows/flow_day11_sqlite_memory.json)

本案例 flow

![02](./image/day11/02.png)

---

## 今日總結與明日預告

今天我們打破了傳統寫死 SQL 與固定查詢的框架，讓本機 AI 晉身為能夠**「自主思考檢索策略 ➔ 自動生成 SQL 檢索本機 SQLite ➔ 注入 Context 完成深度推理」**的真正 Agentic 長期記憶架構！

* **明天（Day 12）**：當我們賦予 AI 更多自主行動力時，安全最重要——**AI 雙層安全防禦：硬性白名單 + 隔離區防誤刪**！
