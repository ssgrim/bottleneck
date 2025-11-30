#requires -Version 7.0
Set-StrictMode -Version Latest

function Send-BottleneckEmailAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$To,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$SmtpServer,
        [int]$Port = 587,
        [Parameter(Mandatory)][PSCredential]$Credential,
        [switch]$UseSSL = $true
    )
    
    try {
        Send-MailMessage -To $To -From $Credential.UserName -Subject $Subject -Body $Body -BodyAsHtml -SmtpServer $SmtpServer -Port $Port -Credential $Credential -UseSsl:$UseSSL -ErrorAction Stop
        Write-Verbose "Email sent to $To"
        return $true
    } catch {
        Write-Warning "Failed to send email: $_"
        return $false
    }
}

function Send-BottleneckWebhookAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WebhookUrl,
        [Parameter(Mandatory)][hashtable]$Payload
    )
    
    try {
        $json = $Payload | ConvertTo-Json -Depth 5 -Compress
        $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $json -ContentType 'application/json' -ErrorAction Stop
        Write-Verbose "Webhook posted to $WebhookUrl"
        return $true
    } catch {
        Write-Warning "Failed to post webhook: $_"
        return $false
    }
}

function Get-BottleneckAlertTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('None','Low','Medium','High','Critical')][string]$Level,
        [Parameter(Mandatory)][hashtable]$Context
    )
    
    $emoji = switch ($Level) {
        'Critical' { '🔴' }
        'High' { '🟠' }
        'Medium' { '🟡' }
        'Low' { '🔵' }
        default { '⚪' }
    }
    
    $subject = "$emoji Bottleneck Alert: $Level - $($Context['Summary'])"
    
    $body = @"
<html>
<head><style>
body{font-family:Arial,sans-serif;margin:0;padding:20px;background:#f5f5f5}
.card{background:#fff;border-radius:8px;padding:20px;margin-bottom:20px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}
.badge{display:inline-block;padding:4px 12px;border-radius:12px;color:#fff;font-weight:bold}
.crit{background:#c62828} .high{background:#f57c00} .med{background:#fbc02d} .low{background:#1976d2}
.small{font-size:12px;color:#666}
</style></head>
<body>
<div class="card">
  <h2>$emoji Network Alert: <span class="badge crit">$Level</span></h2>
  <p><strong>Summary:</strong> $($Context['Summary'])</p>
  <p><strong>Generated:</strong> $($Context['Timestamp'])</p>
</div>
<div class="card">
  <h3>Targets Affected</h3>
  <ul>
    $(($Context['Targets'] | ForEach-Object { "<li>$_</li>" }) -join "`n")
  </ul>
</div>
<div class="card">
  <h3>Metrics</h3>
  <p><strong>Total Fails:</strong> $($Context['TotalFails'])</p>
  <p><strong>Max Avg Latency:</strong> $($Context['MaxAvgLatency']) ms</p>
  <p><strong>Anomalies:</strong> $($Context['AnomalyCount'])</p>
</div>
<div class="card small">
  <p>This is an automated alert from Bottleneck. View full report: <a href="file:///$($Context['ReportPath'])">$($Context['ReportPath'])</a></p>
</div>
</body>
</html>
"@
    
    return @{ Subject = $subject; Body = $body }
}

function Invoke-BottleneckNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('None','Low','Medium','High','Critical')][string]$AlertLevel,
        [Parameter(Mandatory)][hashtable]$Context,
        [string]$ConfigPath = "$PSScriptRoot/../../config/notifications.json"
    )
    
    if ($AlertLevel -eq 'None' -or $AlertLevel -eq 'Low') {
        Write-Verbose "Alert level $AlertLevel below notification threshold"
        return
    }
    
    if (!(Test-Path $ConfigPath)) {
        Write-Warning "Notification config not found: $ConfigPath. Skipping notifications."
        return
    }
    
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    
    if (!$config.enabled) {
        Write-Verbose "Notifications disabled in config"
        return
    }
    
    $template = Get-BottleneckAlertTemplate -Level $AlertLevel -Context $Context
    
    # Email
    if ($config.email.enabled -and $config.email.to) {
        if ($config.email.credentialName) {
            try {
                $cred = Get-StoredCredential -Target $config.email.credentialName -ErrorAction Stop
                $sent = Send-BottleneckEmailAlert -To $config.email.to -Subject $template.Subject -Body $template.Body -SmtpServer $config.email.smtpServer -Port $config.email.port -Credential $cred
                if ($sent) { Write-Host "✅ Email notification sent" -ForegroundColor Green }
            } catch {
                Write-Warning "Email credential not found: $($config.email.credentialName)"
            }
        } else {
            Write-Warning "Email enabled but no credential configured"
        }
    }
    
    # Webhook
    if ($config.webhook.enabled -and $config.webhook.url) {
        $payload = @{
            level = $AlertLevel
            summary = $Context['Summary']
            timestamp = $Context['Timestamp']
            targets = $Context['Targets']
            metrics = @{
                totalFails = $Context['TotalFails']
                maxAvgLatency = $Context['MaxAvgLatency']
                anomalyCount = $Context['AnomalyCount']
            }
            reportPath = $Context['ReportPath']
        }
        $sent = Send-BottleneckWebhookAlert -WebhookUrl $config.webhook.url -Payload $payload
        if ($sent) { Write-Host "✅ Webhook notification posted" -ForegroundColor Green }
    }
}

Export-ModuleMember -Function Send-BottleneckEmailAlert, Send-BottleneckWebhookAlert, Get-BottleneckAlertTemplate, Invoke-BottleneckNotification
