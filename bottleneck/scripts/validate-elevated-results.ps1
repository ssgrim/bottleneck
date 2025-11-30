# Validate-ElevatedResults.ps1
# Compare privileged vs non-privileged scan capabilities

param(
    [switch]$ShowDiff
)

$reportsDir = Join-Path $PSScriptRoot '..' '..' 'Reports'

Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         ELEVATED DIAGNOSTICS VALIDATION                  ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check current privilege level
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "Current Session:" -ForegroundColor Green
Write-Host "  Privilege Level: $(if($isAdmin){'Administrator ✓'}else{'Standard User'})" -ForegroundColor $(if($isAdmin){'Green'}else{'Yellow'})
Write-Host "  User: $env:USERNAME" -ForegroundColor White
Write-Host "  Process ID: $PID`n" -ForegroundColor Gray

# Capability matrix
$capabilities = @(
    [PSCustomObject]@{ Check='Event Log Security'; Standard='Limited'; Admin='Full'; Critical='High' }
    [PSCustomObject]@{ Check='Firewall Rules'; Standard='Basic'; Admin='Complete'; Critical='Medium' }
    [PSCustomObject]@{ Check='SMART Diagnostics'; Standard='Summary'; Admin='Detailed'; Critical='High' }
    [PSCustomObject]@{ Check='Service Health'; Standard='Status'; Admin='Full Analysis'; Critical='Medium' }
    [PSCustomObject]@{ Check='Windows Update'; Standard='N/A'; Admin='Available'; Critical='High' }
    [PSCustomObject]@{ Check='System Integrity'; Standard='N/A'; Admin='SFC/DISM'; Critical='Critical' }
    [PSCustomObject]@{ Check='Network Deep Scan'; Standard='Basic'; Admin='Packet Capture'; Critical='Medium' }
    [PSCustomObject]@{ Check='Performance Counters'; Standard='Limited'; Admin='Extended'; Critical='Low' }
)

Write-Host "Capability Comparison:" -ForegroundColor Green
$capabilities | Format-Table -AutoSize

# Check recent reports
Write-Host "`nRecent Reports:" -ForegroundColor Green
if (Test-Path $reportsDir) {
    $reports = Get-ChildItem $reportsDir -Filter "*.pdf" | Sort-Object LastWriteTime -Descending | Select-Object -First 5
    if ($reports) {
        $reports | ForEach-Object {
            $age = [math]::Round(((Get-Date) - $_.LastWriteTime).TotalMinutes, 1)
            Write-Host "  • $($_.Name) ($([math]::Round($_.Length/1KB, 1)) KB) - ${age}m ago" -ForegroundColor White
        }
    } else {
        Write-Host "  No PDF reports found" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Reports directory not found" -ForegroundColor Red
}

# Check network monitor logs
Write-Host "`nNetwork Monitor Logs:" -ForegroundColor Green
if (Test-Path $reportsDir) {
    $csvs = Get-ChildItem $reportsDir -Filter "network-monitor-*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 3
    if ($csvs) {
        $csvs | ForEach-Object {
            $lines = (Get-Content $_.FullName | Measure-Object -Line).Lines - 1
            $age = [math]::Round(((Get-Date) - $_.LastWriteTime).TotalMinutes, 1)
            Write-Host "  • $($_.Name) ($lines samples) - ${age}m ago" -ForegroundColor White
        }
    } else {
        Write-Host "  No network monitor logs found" -ForegroundColor Yellow
    }
}

# Check metrics
Write-Host "`nAdaptive Metrics:" -ForegroundColor Green
$metricsFile = Join-Path $reportsDir 'metrics-latest.json'
if (Test-Path $metricsFile) {
    $metrics = Get-Content $metricsFile | ConvertFrom-Json
    Write-Host "  System:" -ForegroundColor Cyan
    Write-Host "    CPU: $($metrics.System.CPUPercent)%" -ForegroundColor White
    Write-Host "    Memory: $($metrics.System.MemoryUsedPercent)%" -ForegroundColor White
    Write-Host "    Disk Free: $($metrics.System.DiskFreeGB) GB" -ForegroundColor White
    if ($metrics.Network) {
        Write-Host "  Network:" -ForegroundColor Cyan
        Write-Host "    Success Rate: $($metrics.Network.SuccessRate)%" -ForegroundColor White
        Write-Host "    Avg Latency: $($metrics.Network.AvgLatency) ms" -ForegroundColor White
    }
} else {
    Write-Host "  No metrics file found" -ForegroundColor Yellow
}

# Check adaptive history
Write-Host "`nAdaptive History:" -ForegroundColor Green
$historyFile = Join-Path $reportsDir 'scan-history.json'
if (Test-Path $historyFile) {
    $history = Get-Content $historyFile | ConvertFrom-Json
    $count = ($history | Measure-Object).Count
    Write-Host "  Total Records: $count" -ForegroundColor White
    if ($count -gt 0) {
        $latest = $history | Select-Object -Last 1
        Write-Host "  Latest: $($latest.Timestamp)" -ForegroundColor Gray
        Write-Host "  Success Rate: $($latest.Summary.Network.SuccessRate)%" -ForegroundColor White
    }
} else {
    Write-Host "  No history file yet" -ForegroundColor Yellow
}

# Target performance
Write-Host "`nTarget Performance:" -ForegroundColor Green
$targetFile = Join-Path $reportsDir 'target-performance.json'
if (Test-Path $targetFile) {
    $targets = Get-Content $targetFile | ConvertFrom-Json
    Write-Host "  Tracked Targets: $(($targets | Measure-Object).Count)" -ForegroundColor White
    $top3 = $targets | Sort-Object Score -Descending | Select-Object -First 3
    Write-Host "  Top 3 by Score:" -ForegroundColor Cyan
    $top3 | ForEach-Object {
        Write-Host "    $($_.Target): $($_.Score) (Lat: $($_.AvgLatencyMs)ms, Success: $($_.SuccessRate)%)" -ForegroundColor White
    }
} else {
    Write-Host "  No target performance data yet" -ForegroundColor Yellow
}

Write-Host "`n✓ Validation complete`n" -ForegroundColor Green

if ($isAdmin) {
    Write-Host "💡 Elevated session provides full diagnostic capabilities" -ForegroundColor Cyan
} else {
    Write-Host "⚠️  Standard session - some checks limited" -ForegroundColor Yellow
    Write-Host "   Run: .\scripts\run-elevated.ps1 -ScanType Quick" -ForegroundColor Gray
}
