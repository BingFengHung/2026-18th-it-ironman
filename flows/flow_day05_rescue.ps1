# 在 PowerShell 中一鍵呼叫本機 AI 救援 (自動讀取上一條報錯)
function rescue {
    # 智慧抓取，優先自動抓取上一條報錯 ($Error[0])，若無則抓剪貼簿
    $err = ""
    if ($Error.Count -gt 0 -and $Error[0]) {
        $err = $Error[0] | Out-String
    }
    if ([string]::IsNullOrWhiteSpace($err)) {
        $err = Get-Clipboard
    }

    if ([string]::IsNullOrWhiteSpace($err)) {
        Write-Host "⚠️ 目前沒有捕獲到終端報錯或剪貼簿文字！" -ForegroundColor Yellow
        return
    }

    $body = @{ error = $err.Trim() } | ConvertTo-Json
    try {
        $res = Invoke-RestMethod -Uri "http://127.0.0.1:1880/api/ai/rescue" -Method Post -Body $body -ContentType "application/json; charset=utf-8"
        
        # 雙重相容：若回傳為外層 Envelope 物件，自動解包取 structured_output
        if ($res.structured_output) {
            $res = $res.structured_output
        }

        Write-Host "`n🔍 故障原因: " -ForegroundColor Yellow -NoNewline
        Write-Host $res.plain_reason
        Write-Host "💡 建議修復指令:" -ForegroundColor Green
        $res.fix_commands | ForEach-Object { Write-Host "  > $_" -ForegroundColor Cyan }
        Write-Host ""
    } catch {
        Write-Host "❌ 無法連線至 Node-RED 救援端點: $($_.Exception.Message)" -ForegroundColor Red
    }
}
