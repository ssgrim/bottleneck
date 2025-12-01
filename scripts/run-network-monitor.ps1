# run-network-monitor.ps1
# Long-running network connectivity monitor for diagnosing intermittent drops

[CmdletBinding()]
param(
    [Parameter()][string]$TargetHost = 'www.yahoo.com',
    [Parameter()][double]$DurationHours = 4,
    [Parameter()][int]$PingIntervalSeconds = 5
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Bottleneck Network Monitor" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Prompt for duration if not specified
if ($PSBoundParameters.Count -eq 0) {
    Write-Host "This tool will monitor your network connection to detect intermittent drops." -ForegroundColor Yellow
    Write-Host "Perfect for diagnosing streaming issues (Netflix, Spotify, etc.)" -ForegroundColor Yellow
    Write-Host ""
    
    $durationInput = Read-Host "Enter monitoring duration in hours (default: 4)"
    if ($durationInput) { $DurationHours = [double]$durationInput }
    
    $targetInput = Read-Host "Enter target host to monitor (default: www.yahoo.com)"
    if ($targetInput) { $TargetHost = $targetInput }
    
    $intervalInput = Read-Host "Enter ping interval in seconds (default: 5)"
    if ($intervalInput) { $PingIntervalSeconds = [int]$intervalInput }
}

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Target: $TargetHost" -ForegroundColor White
Write-Host "  Duration: $DurationHours hours" -ForegroundColor White
Write-Host "  Interval: $PingIntervalSeconds seconds" -ForegroundColor White
Write-Host "  Estimated pings: $([math]::Floor(([double]$DurationHours * 3600) / $PingIntervalSeconds))" -ForegroundColor White
Write-Host ""

# Calculate end time
$startTime = Get-Date
$endTime = $startTime.AddHours($DurationHours)
Write-Host "Start time: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "End time: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host ""

# Save current power plan
Write-Host "Saving current power plan..." -ForegroundColor Yellow
$currentPowerPlan = (powercfg /GetActiveScheme) -replace '.*GUID:\s+([a-f0-9\-]+).*', '$1'
Write-Host "Current plan: $currentPowerPlan" -ForegroundColor Gray

# Disable sleep and hibernation temporarily
Write-Host "Disabling sleep/hibernation for monitoring duration..." -ForegroundColor Yellow
$originalACTimeout = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String 'Current AC Power Setting Index:').ToString() -replace '.*:\s+0x([0-9a-f]+)', '$1'
$originalDCTimeout = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String 'Current DC Power Setting Index:').ToString() -replace '.*:\s+0x([0-9a-f]+)', '$1'
$originalMonitorTimeout = (powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE | Select-String 'Current AC Power Setting Index:').ToString() -replace '.*:\s+0x([0-9a-f]+)', '$1'

powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change standby-timeout-dc 0 | Out-Null
powercfg /change hibernate-timeout-ac 0 | Out-Null
powercfg /change hibernate-timeout-dc 0 | Out-Null
powercfg /change monitor-timeout-ac 0 | Out-Null

Write-Host "Power settings configured for long-running scan." -ForegroundColor Green
Write-Host ""

# Create log file
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logDir = "$PSScriptRoot/../Reports"
$logFile = Join-Path $logDir "network-monitor-$timestamp.csv"
$reportFile = Join-Path $logDir "network-monitor-$timestamp.html"
 $outFile = Join-Path $logDir "network-monitor-$timestamp.out"
 function Write-MonitorOut { param([string]$Text) $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts | $Text" | Out-File -FilePath $outFile -Append -Encoding UTF8 }

# Initialize CSV with headers
"Timestamp,TargetHost,Status,ResponseTime,DNS,Router,ISP,Notes" | Out-File $logFile -Encoding UTF8
 Write-MonitorOut "Initialized monitor: target=$TargetHost durationHours=$DurationHours intervalSec=$PingIntervalSeconds csv=$logFile html=$reportFile"

# Get router IP (default gateway)
$routerIP = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object -First 1).NextHop
Write-Host "Detected router: $routerIP" -ForegroundColor Cyan
 Write-MonitorOut "Detected router: $routerIP"

# Monitoring variables
$totalPings = 0
$successfulPings = 0
$failedPings = 0
$drops = @()
$currentDrop = $null
$responseTimes = @()
$dnsIssues = 0
$routerIssues = 0
$ispIssues = 0

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  MONITORING STARTED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Press Ctrl+C to stop monitoring early (power plan will be restored)" -ForegroundColor Yellow
Write-Host ""

# Register cleanup on Ctrl+C
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Host "`n`nRestoring power plan..." -ForegroundColor Yellow
    powercfg /setactive $currentPowerPlan
}

try {
    while ((Get-Date) -lt $endTime) {
    Write-MonitorOut "Monitoring loop start: start=$($startTime.ToString('yyyy-MM-dd HH:mm:ss')) end=$($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        $pingTime = Get-Date
            Write-MonitorOut "Ping#$totalPings status=$status rt=$responseTime dns=$dnsSuccess router=$routerSuccess notes='$notes'"
        $totalPings++
        
        # Test DNS resolution
        $dnsSuccess = $false
        try {
            $resolved = Resolve-DnsName -Name $TargetHost -ErrorAction Stop
            $dnsSuccess = $true
        } catch {
            $dnsIssues++
        }
        
        # Test router connectivity
        $routerSuccess = $false
        $routerPing = Test-Connection -ComputerName $routerIP -Count 1 -ErrorAction SilentlyContinue
        if ($routerPing) {
            $routerSuccess = $true
        } else {
            $routerIssues++
        }
        
        # Test target host
        $targetPing = Test-Connection -ComputerName $TargetHost -Count 1 -ErrorAction SilentlyContinue
        
        if ($targetPing) {
            $responseTime = $targetPing.ResponseTime
            $responseTimes += $responseTime
            $successfulPings++
            $status = "Success"
            $notes = ""
            
            # Check if recovering from drop
            if ($currentDrop) {
                $dropDuration = (Get-Date) - $currentDrop.StartTime
                $currentDrop.EndTime = Get-Date
                $currentDrop.Duration = $dropDuration.TotalSeconds
                $drops += $currentDrop
                $currentDrop = $null
                $notes = "RECOVERED after $([math]::Round($dropDuration.TotalSeconds,1))s"
                Write-Host "[$($pingTime.ToString('HH:mm:ss'))] " -NoNewline -ForegroundColor Gray
                Write-Host "✓ RECOVERED " -NoNewline -ForegroundColor Green
                Write-Host "after $([math]::Round($dropDuration.TotalSeconds,1))s" -ForegroundColor Yellow
            }
            
            # Check for high latency (spike)
            if ($responseTime -gt 500) {
                Write-Host "[$($pingTime.ToString('HH:mm:ss'))] " -NoNewline -ForegroundColor Gray
                Write-Host "⚠ SPIKE " -NoNewline -ForegroundColor Yellow
                Write-Host "$($responseTime)ms" -ForegroundColor Red
                $notes = "High latency spike"
            } elseif ($totalPings % 10 -eq 0) {
                # Show periodic updates
                Write-Host "[$($pingTime.ToString('HH:mm:ss'))] " -NoNewline -ForegroundColor Gray
                Write-Host "✓ " -NoNewline -ForegroundColor Green
                Write-Host "$($responseTime)ms" -ForegroundColor White
            }
        } else {
            $failedPings++
            $status = "FAILED"
            $responseTime = 0
            
            # Determine failure type
            $failureType = if (-not $routerSuccess) { 
                "Router down" 
                $ispIssues++
            } elseif (-not $dnsSuccess) { 
                "DNS failure" 
            } else { 
                "ISP/Internet issue"
                $ispIssues++
            }
            
            $notes = $failureType
            
            # Track drops
            if (-not $currentDrop) {
                $currentDrop = @{
                    StartTime = $pingTime
                    EndTime = $null
                    Duration = 0
                    Type = $failureType
                }
                Write-Host "[$($pingTime.ToString('HH:mm:ss'))] " -NoNewline -ForegroundColor Gray
                Write-Host "✗ DROP DETECTED " -NoNewline -ForegroundColor Red
                Write-Host "- $failureType" -ForegroundColor Yellow
            } else {
                # Drop continues
                $dropDuration = (Get-Date) - $currentDrop.StartTime
                if ($dropDuration.TotalSeconds % 30 -lt $PingIntervalSeconds) {
                    Write-Host "[$($pingTime.ToString('HH:mm:ss'))] " -NoNewline -ForegroundColor Gray
                    Write-Host "✗ Still down " -NoNewline -ForegroundColor Red
                    Write-Host "for $([math]::Round($dropDuration.TotalSeconds,1))s" -ForegroundColor Yellow
                }
            }
        }
        
        # Log to CSV
        "$($pingTime.ToString('yyyy-MM-dd HH:mm:ss')),$TargetHost,$status,$responseTime,$dnsSuccess,$routerSuccess,$(-not ($failedPings -eq $totalPings)),$notes" | Out-File $logFile -Append -Encoding UTF8
        
        # Sleep until next interval
        Start-Sleep -Seconds $PingIntervalSeconds
    }
} finally {
        Write-MonitorOut "Monitoring loop complete: pings=$totalPings success=$successfulPings fail=$failedPings"
    # Restore power plan
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  MONITORING COMPLETE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Restoring power plan..." -ForegroundColor Yellow
    
    powercfg /change standby-timeout-ac ([Convert]::ToInt32($originalACTimeout, 16) / 60) | Out-Null
    powercfg /change standby-timeout-dc ([Convert]::ToInt32($originalDCTimeout, 16) / 60) | Out-Null
    powercfg /change monitor-timeout-ac ([Convert]::ToInt32($originalMonitorTimeout, 16) / 60) | Out-Null
    powercfg /setactive $currentPowerPlan | Out-Null
    
    Write-Host "Power plan restored." -ForegroundColor Green
    Write-Host ""
    
    # Calculate statistics
    $packetLoss = if ($totalPings -gt 0) { [math]::Round(($failedPings / $totalPings) * 100, 2) } else { 0 }
    $avgResponseTime = if ($responseTimes.Count -gt 0) { [math]::Round(($responseTimes | Measure-Object -Average).Average, 1) } else { 0 }
    $minResponseTime = if ($responseTimes.Count -gt 0) { ($responseTimes | Measure-Object -Minimum).Minimum } else { 0 }
    $maxResponseTime = if ($responseTimes.Count -gt 0) { ($responseTimes | Measure-Object -Maximum).Maximum } else { 0 }
    $totalDrops = $drops.Count
    if ($currentDrop) { $totalDrops++ }
    $avgDropDuration = if ($drops.Count -gt 0) { [math]::Round(($drops | Measure-Object -Property Duration -Average).Average, 1) } else { 0 }
    $maxDropDuration = if ($drops.Count -gt 0) { [math]::Round(($drops | Measure-Object -Property Duration -Maximum).Maximum, 1) } else { 0 }
    $successPercent = if ($totalPings -gt 0) { [math]::Round(($successfulPings/$totalPings)*100,1) } else { 0 }
    $routerPercent = if ($failedPings -gt 0) { [math]::Round(($routerIssues/$failedPings)*100,1) } else { 0 }
    $dnsPercent = if ($failedPings -gt 0) { [math]::Round(($dnsIssues/$failedPings)*100,1) } else { 0 }
    $ispPercent = if ($failedPings -gt 0) { [math]::Round(($ispIssues/$failedPings)*100,1) } else { 0 }
    
    # Display summary
    Write-Host "SUMMARY" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "Total Pings: $totalPings" -ForegroundColor White
    Write-Host "Successful: $successfulPings ($successPercent%)" -ForegroundColor Green
    Write-Host "Failed: $failedPings ($packetLoss%)" -ForegroundColor Red
    Write-Host "Network Drops: $totalDrops" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Response Time:" -ForegroundColor Cyan
    Write-Host "  Average: $avgResponseTime ms" -ForegroundColor White
    Write-Host "  Min: $minResponseTime ms" -ForegroundColor White
    Write-Host "  Max: $maxResponseTime ms" -ForegroundColor White
    Write-Host ""
    Write-Host "Drop Statistics:" -ForegroundColor Cyan
    Write-Host "  Average Duration: $avgDropDuration seconds" -ForegroundColor White
    Write-Host "  Max Duration: $maxDropDuration seconds" -ForegroundColor White
    Write-Host "  DNS Issues: $dnsIssues" -ForegroundColor White
    Write-Host "  Router Issues: $routerIssues" -ForegroundColor White
    Write-Host "  ISP/Internet Issues: $ispIssues" -ForegroundColor White
    Write-Host ""
    
    # Generate HTML report
    Write-Host "Generating report..." -ForegroundColor Yellow
    Write-MonitorOut "Generating report: $reportFile"
    
    # Create timeline of drops
    $dropTimeline = ""
    foreach ($drop in $drops) {
        $dropTimeline += "<tr><td>$($drop.StartTime.ToString('HH:mm:ss'))</td><td>$($drop.EndTime.ToString('HH:mm:ss'))</td><td>$([math]::Round($drop.Duration,1))s</td><td>$($drop.Type)</td></tr>"
    }
    
    # Determine diagnosis
    $diagnosis = if ($routerIssues -gt $ispIssues * 2) {
        "LOCAL NETWORK ISSUE: Most drops appear to be router/local network related. Check WiFi signal strength, router health, network cable connections."
    } elseif ($dnsIssues -gt $totalDrops / 2) {
        "DNS ISSUE: Many failures are DNS-related. Consider changing DNS servers to Google (8.8.8.8) or Cloudflare (1.1.1.1)."
    } elseif ($maxDropDuration -gt 60) {
        "ISP ISSUE: Extended outages suggest ISP problems. Contact your internet service provider with this report."
    } elseif ($totalDrops -gt 10) {
        "FREQUENT MICRO-DROPS: Brief but frequent disconnections detected. This causes streaming interruptions. Check for ISP congestion, WiFi interference, or failing network hardware."
    } else {
        "STABLE CONNECTION: Connection is generally stable with minimal disruptions."
    }
    
    $diagnosisColor = if ($totalDrops -gt 10 -or $maxDropDuration -gt 60) { "#dc3545" } elseif ($totalDrops -gt 5) { "#ffc107" } else { "#28a745" }
    
    $html = @"
<html>
<head>
<title>Network Monitor Report - $timestamp</title>
<style>
body { font-family: 'Segoe UI', Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 20px; }
.container { max-width: 1000px; margin: 0 auto; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 10px 40px rgba(0,0,0,0.2); }
.header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }
.header h1 { margin: 0; font-size: 28px; font-weight: 300; }
.content { padding: 30px; }
.diagnosis { background: $diagnosisColor; color: white; padding: 20px; border-radius: 8px; margin-bottom: 30px; }
.diagnosis h2 { margin: 0 0 10px 0; font-size: 20px; }
.metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }
.metric { background: #f8f9fa; padding: 15px; border-radius: 8px; border-left: 4px solid #667eea; }
.metric-label { font-size: 11px; color: #6c757d; text-transform: uppercase; margin-bottom: 5px; }
.metric-value { font-size: 24px; font-weight: bold; color: #495057; }
table { width: 100%; border-collapse: collapse; margin: 20px 0; }
th { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 12px; text-align: left; font-size: 12px; text-transform: uppercase; }
td { border-bottom: 1px solid #e9ecef; padding: 12px; }
tr:hover { background: #f8f9fa; }
h2 { color: #495057; margin: 30px 0 15px 0; padding-bottom: 10px; border-bottom: 2px solid #667eea; }
</style>
</head>
<body>
<div class="container">
<div class="header">
<h1>Network Connectivity Monitor Report</h1>
<p>$($startTime.ToString('yyyy-MM-dd HH:mm:ss')) - $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))</p>
</div>
<div class="content">
<div class="diagnosis">
<h2>Diagnosis</h2>
<p>$diagnosis</p>
</div>
<div class="metrics">
<div class="metric">
<div class="metric-label">Total Pings</div>
<div class="metric-value">$totalPings</div>
</div>
<div class="metric">
<div class="metric-label">Packet Loss</div>
<div class="metric-value">$packetLoss%</div>
</div>
<div class="metric">
<div class="metric-label">Network Drops</div>
<div class="metric-value">$totalDrops</div>
</div>
<div class="metric">
<div class="metric-label">Avg Response</div>
<div class="metric-value">$avgResponseTime ms</div>
</div>
<div class="metric">
<div class="metric-label">Max Latency</div>
<div class="metric-value">$maxResponseTime ms</div>
</div>
<div class="metric">
<div class="metric-label">Longest Drop</div>
<div class="metric-value">$maxDropDuration s</div>
</div>
</div>
<h2>Connection Drops Timeline</h2>
$(if ($drops.Count -gt 0) { @"
<table>
<tr><th>Start Time</th><th>End Time</th><th>Duration</th><th>Type</th></tr>
$dropTimeline
</table>
"@ } else { "<p>No connection drops detected during monitoring period.</p>" })
<h2>Issue Breakdown</h2>
<table>
<tr><th>Issue Type</th><th>Occurrences</th><th>Percentage</th></tr>
<tr><td>Router/Local Network</td><td>$routerIssues</td><td>$routerPercent%</td></tr>
<tr><td>DNS Issues</td><td>$dnsIssues</td><td>$dnsPercent%</td></tr>
<tr><td>ISP/Internet Issues</td><td>$ispIssues</td><td>$ispPercent%</td></tr>
</table>
<h2>Recommendations</h2>
<ul style="line-height: 1.8;">
$(if ($routerIssues -gt $totalDrops / 2) { "<li><strong>Check WiFi signal strength</strong> - Move closer to router or consider WiFi extender</li><li><strong>Restart router</strong> - Power cycle modem and router</li><li><strong>Update router firmware</strong> - Check manufacturer website</li>" })
$(if ($dnsIssues -gt 5) { "<li><strong>Change DNS servers</strong> - Use Google DNS (8.8.8.8) or Cloudflare (1.1.1.1)</li>" })
$(if ($ispIssues -gt $totalDrops / 2) { "<li><strong>Contact ISP</strong> - Provide this report showing connection instability</li><li><strong>Check for service outages</strong> - Visit ISP's status page</li>" })
$(if ($maxResponseTime -gt 200) { "<li><strong>High latency detected</strong> - Check for bandwidth-hogging applications</li>" })
<li><strong>Raw log file:</strong> $logFile</li>
</ul>
</div>
</div>
</body>
</html>
"@
    
    $html | Out-File $reportFile -Encoding UTF8
    
    Write-Host "Report saved to: $reportFile" -ForegroundColor Green
    Write-Host "Log file saved to: $logFile" -ForegroundColor Green
    Write-MonitorOut "Saved report=$reportFile csv=$logFile"
    Write-Host ""
    Write-Host "Opening report..." -ForegroundColor Cyan
    Start-Process $reportFile
    Write-MonitorOut "Opened report viewer"
}
