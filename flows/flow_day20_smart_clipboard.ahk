; cb-ai.ahk — 選取文字後直接按 Ctrl+Alt+C
; 自動完成：複製選取內容 → 觸發 AI 分析，一鍵搞定！
^!c:: {
    Send "^c"      ; 模擬 Ctrl+C，把選取文字複製到剪貼簿
    Sleep 300      ; 等 300ms 確保剪貼簿已更新
    Run 'powershell -NoProfile -WindowStyle Hidden -Command "Invoke-RestMethod -Uri http://127.0.0.1:1880/api/ai/clipboard -Method POST"',, "Hide"
}