# 在 PowerShell 中一鍵產出今日工作日報 (支援自訂工作備註與 0 commit 保底)
function daily-report {
    param([string]$Notes = "")
    if ($Notes) {
        Write-Host "`n⏳ 正在彙整今日進度與工作備註: '$Notes'..." -ForegroundColor Yellow
    } else {
        Write-Host "`n⏳ 正在彙整今日所有 Git 提交並由 AI 提煉日報，請稍候..." -ForegroundColor Yellow
    }
    try {
        $body = @{ notes = $Notes } | ConvertTo-Json
        $res = Invoke-RestMethod -Uri "http://127.0.0.1:1880/api/ai/report" -Method Post -Body $body -ContentType "application/json; charset=utf-8"
        Write-Host "🎉 每日工作日報已成功生成！" -ForegroundColor Green
        Write-Host "📁 存檔路徑: $($res.savedPath)" -ForegroundColor Cyan
        Write-Host "`n--- 日報預覽 ---" -ForegroundColor DarkGray
        Write-Host $res.content
        Write-Host "----------------`n" -ForegroundColor DarkGray
    } catch {
        Write-Host "❌ 無法連線至 Node-RED 日報端點，請確認 Node-RED 是否已啟動！" -ForegroundColor Red
    }
}