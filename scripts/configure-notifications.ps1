param(
    [string]$Email,
    [string]$SmtpServer,
    [int]$Port = 587,
    [string]$WebhookUrl,
    [string]$ConfigPath = "$PSScriptRoot/../config/notifications.json"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (!(Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }

$config = Get-Content $ConfigPath | ConvertFrom-Json

Write-Host "📧 Configuring notifications..." -ForegroundColor Cyan

if ($Email) {
    $config.email.enabled = $true
    $config.email.to = $Email
    if ($SmtpServer) { $config.email.smtpServer = $SmtpServer }
    if ($Port) { $config.email.port = $Port }
    Write-Host "  Email: $Email via $SmtpServer:$Port" -ForegroundColor Green
    Write-Host "  Store credentials with:" -ForegroundColor Yellow
    Write-Host "    cmdkey /generic:Bottleneck-SMTP /user:$Email /pass:yourpassword" -ForegroundColor Gray
}

if ($WebhookUrl) {
    $config.webhook.enabled = $true
    $config.webhook.url = $WebhookUrl
    Write-Host "  Webhook: $WebhookUrl" -ForegroundColor Green
}

$config.enabled = $config.email.enabled -or $config.webhook.enabled

$config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
Write-Host "`n✅ Configuration saved to: $ConfigPath" -ForegroundColor Green
Write-Host "   Notifications enabled: $($config.enabled)" -ForegroundColor Cyan
