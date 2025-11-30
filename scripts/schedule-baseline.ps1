param(
    [ValidateSet('Daily','Weekly','Monthly')][string]$Frequency = 'Weekly',
    [ValidateSet('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')][string]$DayOfWeek = 'Sunday',
    [string]$Time = '02:00',
    [int]$RetainLast = 4,
    [switch]$UseAdaptiveTargets,
    [string]$Duration = '30min'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$taskName = "Bottleneck-BaselineMonitor"
$scriptRoot = Split-Path -Parent $PSScriptRoot
$monitorScript = Join-Path $scriptRoot 'bottleneck\src\ps\Bottleneck.psm1'
$reportsDir = Join-Path $scriptRoot 'Reports'

if (!(Test-Path $monitorScript)) { throw "Monitor module not found: $monitorScript" }

# Build command for scheduled task
$adaptiveFlag = if ($UseAdaptiveTargets) { '-UseAdaptiveTargets' } else { '' }
$cmd = "pwsh.exe"
$args = "-NoProfile -ExecutionPolicy Bypass -Command `"Import-Module '$monitorScript' -DisableNameChecking; Invoke-BottleneckNetworkMonitor -Duration '$Duration' -Interval 10 $adaptiveFlag -TracerouteInterval 15`""

Write-Host "Creating scheduled task: $taskName" -ForegroundColor Cyan
Write-Host "  Frequency: $Frequency" -ForegroundColor Gray
Write-Host "  Time: $Time" -ForegroundColor Gray
if ($Frequency -eq 'Weekly') { Write-Host "  Day: $DayOfWeek" -ForegroundColor Gray }

# Create trigger
$trigger = $null
switch ($Frequency) {
    'Daily' { $trigger = New-ScheduledTaskTrigger -Daily -At $Time }
    'Weekly' { $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time }
    'Monthly' { $trigger = New-ScheduledTaskTrigger -Daily -At $Time } # Monthly requires custom setup
}

# Create action
$action = New-ScheduledTaskAction -Execute $cmd -Argument $args -WorkingDirectory $scriptRoot

# Create principal (run whether user is logged on or not)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest

# Register task
try {
    Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Principal $principal -Description "Bottleneck weekly baseline network monitor" -Force | Out-Null
    Write-Host "`n✅ Task '$taskName' registered successfully!" -ForegroundColor Green
    Write-Host "   View with: Get-ScheduledTask -TaskName '$taskName'" -ForegroundColor Yellow
    Write-Host "   Run now: Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Yellow
    Write-Host "   Remove: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false" -ForegroundColor Yellow
} catch {
    Write-Host "`n❌ Failed to register task: $_" -ForegroundColor Red
    throw
}

# Cleanup old reports (retention policy)
Write-Host "`nApplying retention policy (keep last $RetainLast runs)..." -ForegroundColor Cyan
$csvs = Get-ChildItem $reportsDir -Filter 'network-monitor-*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($csvs.Count -gt $RetainLast) {
    $toDelete = $csvs | Select-Object -Skip $RetainLast
    foreach ($f in $toDelete) {
        Write-Host "  Deleting old report: $($f.Name)" -ForegroundColor Gray
        Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  Retained $RetainLast most recent runs." -ForegroundColor Green
} else {
    Write-Host "  No cleanup needed ($($csvs.Count) runs < $RetainLast retention)." -ForegroundColor Gray
}
