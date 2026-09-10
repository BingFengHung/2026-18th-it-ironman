# Day 20：AI 實戰 7：智慧剪貼簿管家（複製代碼或報錯自動翻譯與解析）

> 在日常開發與維運過程中，遇到長篇英文日誌、看不懂的 Stack Trace 或生澀的開源文件時，標準的動作是：
>
> 1. 按 `Ctrl + C` 複製文字。
> 2. 打開瀏覽器切換到 Google 翻譯或 ChatGPT 網頁。
> 3. 按 `Ctrl + V` 貼上，等待回覆。
> 4. 再切回 IDE 或終端機。
>
> 這個過程雖然不難，但**這個過程天會嚴重打斷開發心流**！
> 今天我們結合 Day 14 的 **`🤖 agy 推理核心大腦`** Subflow 積木，打造一個 **「零切換、無感輔助」的智慧剪貼簿管家**：複製文字後按下快捷指令，AI 自動辨識內容、生成白話摘要與修復指令，**直接寫回剪貼簿並彈出 Toast 提醒**，讓你按 `Ctrl + V` 貼出來的就是解法！

---

本文同步發布於 GitHub： [2026-18th-it-ironman](https://github.com/BingFengHung/2026-18th-it-ironman/blob/main/Day20_智慧剪貼簿管家_複製代碼或報錯自動翻譯與解析.md)

## 傳統手動翻譯 vs 智慧剪貼簿管家

| 比較項目           | ❌ 傳統手動切瀏覽器                              | ✅ AI 智慧剪貼簿管家                                  |
| :----------------- | :----------------------------------------------- | :---------------------------------------------------- |
| **操作步驟** | 複製 ➔ 切換視窗 ➔ 貼上 ➔ 等待 ➔ 複製 ➔ 切回 | **複製 ➔ 快捷觸發 ➔ 直接貼出解答！**          |
| **打斷心流** | 嚴重（視窗頻繁跳轉）                             | **0 切換（專注在當前編輯器）**                  |
| **內容識別** | 通用翻譯軟體無法針對代碼給予修復指令             | **指名道姓（報錯/代碼/文章）並給出具體命令**    |
| **結果輸出** | 留在網頁上                                       | **自動覆蓋寫入系統剪貼簿 + Windows Toast 預覽** |

---

## 系統工作流架構

![01](./image/day20/01.png)

* **【剪貼簿捕獲與前置截取】**：PowerShell `Get-Clipboard` 取得系統剪貼簿原文，截取前 800 字元完成「脫水」，搭配 JSON Schema 契約鎖定輸出欄位，杜絕 AI 回覆格式漂移。
* **【AI 積木推理核心】**：沿用 Day 14 封裝的 `🤖 agy 推理核心大腦` Subflow，無論輸入文本含多少換行、引號或特殊字元，積木內部自體完成跳脫與雙軌解包，外部零負擔。
* **【無縫回寫閉環】**：AI 推理結果透過 PowerShell `Set-Clipboard` 直接覆蓋系統剪貼簿，同步彈出 WinRT Toast 預覽摘要，按下 `Ctrl + V` 即得白話解答，全程 0 次視窗切換。

---

## 實戰動手做：打造剪貼簿智慧中樞

整條流水線簡潔純粹，僅需 4 步即可完成：

```
[快捷觸發 (Inject / HTTP)] 
       ↓
【步驟 1：抓取 Windows 剪貼簿 (Exec)】 ➔ PowerShell Get-Clipboard
       ↓
【步驟 2：截取脫水與組裝契約 (Function)】 ➔ 截取前 800 字元 + Schema 強制約束
       ↓
【步驟 3：調用專屬 AI 積木 (Subflow)】 ➔ 🤖 agy 推理核心大腦（自體完成跳脫與解包）
       ↓
【步驟 4：格式化並寫回剪貼簿 (Function ➔ Exec)】 ➔ Set-Clipboard + 原生 Toast
```

---

### 快捷觸發設定：`Ctrl + Alt + C` 全域熱鍵

要真正做到「0 切換視窗」，唯一的答案是 **AutoHotkey 全域熱鍵**。安裝 [AutoHotkey v2](https://www.autohotkey.com/) 後建立一個 `.ahk` 腳本：

```autohotkey
; cb-ai.ahk — 選取文字後直接按 Ctrl+Alt+C
; 自動完成：複製選取內容 → 觸發 AI 分析，一鍵搞定！
^!c:: {
    Send "^c"      ; 模擬 Ctrl+C，把選取文字複製到剪貼簿
    Sleep 300      ; 等 300ms 確保剪貼簿已更新
    Run 'powershell -NoProfile -WindowStyle Hidden -Command "Invoke-RestMethod -Uri http://127.0.0.1:1880/api/ai/clipboard -Method POST"',, "Hide"
}
```

將此檔案放在「**啟動資料夾**」（在執行對話框輸入 `shell:startup`）中，開機自動載入。之後使用流程只剩 **兩個動作**：

1. 用滑鼠或鍵盤**選取任意文字**（不需要先按 Ctrl+C！）
2. 按下 `Ctrl + Alt + C`（**自動複製 + 送出 AI 請求**，完全不切換視窗）
3. 幾秒後 Toast 從右下角彈出 → 按 `Ctrl + V` 貼出白話解答 ✅

> **🔑 為什麼這樣才對：步驟數對比**
>
> | 方法                         | 動作步驟                                                 | 視窗切換                  |
> | ---------------------------- | -------------------------------------------------------- | ------------------------- |
> | 傳統切 ChatGPT / Google 翻譯 | 選取 → Ctrl+C → 切視窗 → 貼上 → 等待 → 複製 → 切回 | **2 次**            |
> | 原版雙鍵（先 Ctrl+C 再熱鍵） | 選取 → Ctrl+C → Ctrl+Alt+C                             | **0 次，但 3 步**   |
> | **本版 AHK 單鍵** ✅   | 選取 →`Ctrl+Alt+C` → `Ctrl+V`                      | **0 次，只需 2 步** |

> **💡 測試 / 除錯用途**：Flow 中的 `inject` 節點（Node-RED 畫布上那顆按鈕）僅供開發時在畫布上手動觸發驗證，`http in` 節點才是正式供 AutoHotkey 呼叫的入口。兩者並列是「開發除錯」與「日常使用」的雙軌設計。

---

### 步驟 1：抓取 Windows 系統剪貼簿內容（Exec 節點）

拉出一個 **`exec`** 節點，執行 PowerShell 內建指令抓取剪貼簿字串：

* **Command**：`powershell -NoProfile -Command "Get-Clipboard"`
* **附加 msg.payload**：**不要打勾（false）**。

> **💡 原理解析**：
> 透過 PowerShell 原生 `Get-Clipboard` cmdlet，可精確取得剪貼簿中的純文字、代碼或多行日誌，相容性極高且無需安裝額外的本機全域依賴。

---

### 步驟 2：內容長度截取與 Prompt 組裝（Function 節點）

在 Function 節點中，截取前 800 字元避免 Token 浪費，並定義嚴格的 JSON Schema 契約：

```javascript
// 🔑 核心一：空內容防呆（避免觸發無意義的 AI 呼叫）
const text = (msg.payload || '').toString().trim();
if (!text || text.length < 5) { node.warn('剪貼簿為空，跳過'); return null; }

// 🔑 核心二：截取前 800 字元「脫水」— 精準鎖定報錯核心，大幅縮短推理延遲
const cleanText = text.substring(0, 800);

// 🔑 核心三：JSON Schema 強制約束輸出格式，杜絕 AI 自由發揮造成解包失敗
msg.schema = {
  type: 'object',
  required: ['content_type', 'summary_zh', 'action_suggestion'],
  properties: {
    content_type: { type: 'string' },   // 'ERROR_LOG' | 'CODE_SNIPPET' | 'ENGLISH_TEXT' | 'GENERAL'
    summary_zh:   { type: 'string' },   // 白話中文摘要
    action_suggestion: { type: 'string' } // 建議排查動作
  }
};
msg.prompt = `你是智慧剪貼簿管家，請分析下列文字並回傳 JSON：\n"""\n${cleanText}\n"""`;
return msg;
```

> **🔑 重點說明：截取前置脫水**
> 剪貼簿有時會複製到上萬行的巨大檔案，限制 800 字元能精準鎖定報錯的核心堆疊，大幅縮短 AI 推理延遲。

---

### 步驟 3：調用專屬 AI 樂高積木（`🤖 agy 推理核心大腦` Subflow）

從左側「**AI 模組**」拖入 Day 14 封裝完成的 **`🤖 agy 推理核心大腦`**，接在步驟 2 後方即可。Subflow 內部已自體完成引號跳脫、CLI 呼叫與結構化雙軌解包（詳見 [Day 14](https://github.com/BingFengHung/2026-18th-it-ironman/blob/main/Day14_打造專屬Subflow樂高積木_封裝agy推理核心節點.md)），輸出端直接傳出含有 `content_type`、`summary_zh`、`action_suggestion` 的純淨物件。

> **💡 積木複用優勢**：任何分頁只要傳入 `msg.prompt`（可選 `msg.schema`），就能享有安全跳脫與雙軌解包，Day 20 不需要也不應重複這段邏輯。

---

### 步驟 4：格式化並寫回系統剪貼簿（Function ➔ Exec 節點）

在 Function 節點中組裝乾淨的中文文字，透過 PowerShell `Set-Clipboard` 寫回本機剪貼簿並彈出 Toast：

```javascript
// 🔑 核心一：組裝格式化輸出（寫回剪貼簿的內容）
const formattedOutput = `【AI 剪貼簿解析】\n📌 摘要: ${data.summary_zh}\n💡 建議: ${data.action_suggestion}`;

// 🔑 核心二：單引號跳脫（防止 PowerShell 命令被截斷）
const escapedText = formattedOutput.replace(/'/g, "''");

// 🔑 核心三：Toast 換行必須用 PowerShell `n，不能用 JS \n
const toastMsg = data.summary_zh;
msg.payload = `powershell -NoProfile -Command "Set-Clipboard -Value '${escapedText}'; ` +
  `[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null; ` +
  `$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02); ` +
  `$textNodes = $template.GetElementsByTagName('text'); ` +
  `$textNodes.Item(0).AppendChild($template.CreateTextNode('📋 AI 剪貼簿: ${data.content_type}')) > $null; ` +
  `$textNodes.Item(1).AppendChild($template.CreateTextNode('${toastMsg}')) > $null; ` +
  `[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('AI 剪貼簿管家').Show([Windows.UI.Notifications.ToastNotification]::new($template));"`;
return msg;
```

> **🔑 重點說明：無縫心流體驗**
> 一旦 PowerShell 執行完畢，系統右下角響起提示音並彈出 Toast 卡片，使用者按下 `Ctrl + V` 就能立即貼出結構清晰的中文白話解答與修復建議。

---

## 成果驗收：實測效果

當你複製了一段報錯：
`npm ERR! code ENOENT syscall open path package.json`

執行後，Windows 右下角彈出 Toast，且你的剪貼簿內容自動被替換為：

```text
【AI 剪貼簿解析】
📌 摘要: 找不到 package.json 檔案，導致 npm 命令無法定位專案設定。
💡 建議: 請確認當前終端機路徑是否位於包含 package.json 的專案根目錄下。
```

直接按下 `Ctrl + V` 就能把解析結果貼給同事或貼入筆記！

---

## 完整 Flow 程式

在 Node-RED 點擊「右上角選單」➔「匯入」即可一鍵部署：

本案例 flow

![02](./image/day20/02.png)

### 本範例 flow 位置：👉 [下載](https://github.com/BingFengHung/2026-18th-it-ironman/blob/main/flows/flow_day20_smart_clipboard.json)

---

## 今日總結與明日預告

今天我們打造了徹底解放開發心流的**智慧剪貼簿管家**。透過 Node-RED 串接 Windows 剪貼簿與 Day 14 的 AI Subflow 積木，實現了「複製 ➔ 快捷觸發 ➔ 直接貼出解答」的極致絲滑體驗。

* **明天（Day 21）**：我們將探索多任務並行時的必備防護——**並行防護與資源控制：Semaphore 號誌燈保護與 MD5 特徵快取機制**！
