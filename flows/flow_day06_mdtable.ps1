# 在 PowerShell 中一鍵將剪貼簿文字轉為 Markdown 表格
function mdtable {
    $clip = Get-Clipboard
    if ([string]::IsNullOrWhiteSpace($clip)) {
        Write-Host "⚠️ 剪貼簿目前沒有文字！" -ForegroundColor Yellow
        return
    }
    $body = @{ text = $clip } | ConvertTo-Json
    $res = Invoke-RestMethod -Uri "http://127.0.0.1:1880/api/ai/table" -Method Post -Body $body -ContentType "application/json; charset=utf-8"
    Write-Host "✅ 已成功將剪貼簿文字轉為 Markdown 表格並寫回剪貼簿！" -ForegroundColor Green
}
