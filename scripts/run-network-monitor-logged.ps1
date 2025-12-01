# run-network-monitor-logged.ps1
# Wrapper to run network monitor with detailed .out logging and fractional duration support

[CmdletBinding()] param(
    [string]$TargetHost = 'www.yahoo.com',
    [double]$DurationHours = 0.25,
    [int]$PingIntervalSeconds = 5,
    [string]$ReportsDir = (Join-Path $PSScriptRoot '..' 'Reports')
)

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$outLog = Join-Path $ReportsDir "network-monitor-$timestamp.out"

function Write-NetMonLog { param([string]$Text)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts | $Text" | Out-File -FilePath $outLog -Append -Encoding UTF8
}

try {
    Write-NetMonLog "Starting monitor wrapper"
    Write-NetMonLog "Params: target=$TargetHost durationHours=$DurationHours intervalSec=$PingIntervalSeconds"

    $baseScript = Join-Path $PSScriptRoot 'run-network-monitor.ps1'
    if (-not (Test-Path $baseScript)) { throw "Monitor script not found: $baseScript" }
    Write-NetMonLog "Calling base script: $baseScript"

    # The base script expects [int] DurationHours; if fractional, round up to nearest minute
    $durationForBase = [int][math]::Ceiling($DurationHours)
    if ($durationForBase -lt 1 -and $DurationHours -gt 0) { $durationForBase = 1 }
    Write-NetMonLog "Translated duration for base script: $durationForBase hours"

    & $baseScript -TargetHost $TargetHost -DurationHours $durationForBase -PingIntervalSeconds $PingIntervalSeconds

    # Find latest CSV/HTML generated
    $latestCsv  = Get-ChildItem (Join-Path $ReportsDir 'network-monitor-*.csv')  | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $latestHtml = Get-ChildItem (Join-Path $ReportsDir 'network-monitor-*.html') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestCsv)  { Write-NetMonLog "CSV: $($latestCsv.FullName)" }
    if ($latestHtml) { Write-NetMonLog "HTML: $($latestHtml.FullName)" }

    Write-Host ("Monitor CSV: " + ($latestCsv?.FullName))
    Write-Host ("Monitor HTML: " + ($latestHtml?.FullName))

    # Compute RCA/Diagnostics using module if available
    $modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'src/ps/Bottleneck.psm1'
    if (Test-Path $modulePath) {
        try {
            Write-NetMonLog "Importing module for RCA: $modulePath"
            Import-Module $modulePath -Force
            $rca  = Invoke-BottleneckNetworkRootCause
            $diag = Invoke-BottleneckNetworkCsvDiagnostics
            Write-NetMonLog ("RCA Fused Alert: " + $rca.FusedAlertLevel)
            Write-NetMonLog ("CSV Fused Alert: " + $diag.FusedAlertLevel)
            Write-Host ("RCA Fused Alert: " + $rca.FusedAlertLevel)
            Write-Host ("CSV Fused Alert: " + $diag.FusedAlertLevel)
        } catch {
            Write-NetMonLog "RCA/Diagnostics failed: $_"
        }
    } else {
        Write-NetMonLog "Module not found for RCA: $modulePath"
    }

} catch {
    Write-NetMonLog "ERROR: $_"
    throw
} finally {
    Write-NetMonLog "Monitor wrapper complete. Log: $outLog"
    Write-Host "Monitor log: $outLog"
}
