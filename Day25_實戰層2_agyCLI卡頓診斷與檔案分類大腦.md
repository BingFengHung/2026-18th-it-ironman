# Day 25：E2E 實戰層 2：任務路由與決策契約

> `agy CLI`、JSON Schema 與共用 Subflow 已在前面完成。今天的問題不是如何再呼叫一次 AI，而是如何讓同一個推理元件接收不同任務，並且不把分類結果誤當成系統診斷結果。

本文同步發布於 GitHub：[2026-18th-it-ironman](https://github.com/BingFengHung/2026-18th-it-ironman/blob/main/Day25_實戰層2_agyCLI卡頓診斷與檔案分類大腦.md)

## 決策層的責任

![系統架構流程圖](image/day25/01.png)

今天只做三件事：驗證任務、選擇決策契約、把結果交給 Day26。它不掃描檔案、不搬移檔案，也不執行 AI 回傳的指令。

| `task_type`     | 輸入位置                     | 決策輸出                                           |
| ----------------- | ---------------------------- | -------------------------------------------------- |
| `CLASSIFY_FILE` | `input.files`              | `category`、`reason`                           |
| `PERF_RCA`      | `input.metrics` 與事件資料 | `severity`、`root_cause`、`suggested_action` |
| 其他              | 任務 Envelope                | `UNSUPPORTED_TASK`，不呼叫 AI                    |

## 路由器的三道檢查

路由器先確認 `task_id`、`task_type` 與 `input` 存在，再用白名單判斷任務類型，最後才載入對應 Prompt 與 Schema。未知類型不能套用通用 Prompt，因為那會把輸入錯誤偽裝成正常 AI 結果。

```javascript
const task = msg.payload;
const route = routes[task.task_type];

if (!task.task_id || !task.input || !route) {
    msg.payload = {
        status: 'UNSUPPORTED_TASK',
        task_id: task.task_id || null,
        reason: '缺少必要欄位或不支援的 task_type'
    };
    return [null, msg];
}

msg.prompt = route.prompt(task);
msg.schema = route.schema;
msg.task = task;
return [msg, null];
```

這段核心邏輯的價值是把「選擇任務」和「執行 AI」分開。Schema 只描述輸出形狀，Prompt 才描述判斷背景；兩者都完成後才進入 Day14 的共用推理 Subflow。

## 結果如何交接給 Day26

AI 結果不能直接覆蓋原始任務。建議保留 `task_id`、`task_type` 與 `input`，再新增 `decision`：

```json
{
  "task_id": "task_...",
  "task_type": "CLASSIFY_FILE",
  "decision": {
    "category": "Installers",
    "reason": "檔名與副檔名顯示為安裝程式"
  }
}
```

Day26 仍須重新檢查類別白名單、實際路徑與檔案是否存在。AI 的輸出是建議，不是授權。

## 驗收矩陣

| 案例                         | 預期結果                            |
| ---------------------------- | ----------------------------------- |
| 合法`CLASSIFY_FILE`        | 產生分類 Schema 結果                |
| 合法`PERF_RCA`             | 產生診斷 Schema 結果                |
| 缺少`task_id` 或 `input` | 路由層拒絕                          |
| 未知`task_type`            | 不呼叫 AI，輸出`UNSUPPORTED_TASK` |
| CLI 失敗                     | 保留原始 Envelope，交給 Day28       |
| 非 JSON 結果                 | 不進入執行層                        |

## 完整 Flow

在 Node-RED 點擊「右上角選單」➔「匯入」即可一鍵部署：

本案例 flow

![1789595775684](./image/day25/02.png)

### 本範例 Flow 位置：👉 [下載](https://github.com/BingFengHung/2026-18th-it-ironman/blob/main/flows/flow_day25_e2e_ai_brain.json)

## 今日總結與明日預告

今天建立的是「任務到決策」的邊界。

明天會把決策當成不可信輸入，必須經過安全檢查後才執行搬移、通知與審計。
