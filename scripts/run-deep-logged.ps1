# run-deep-logged.ps1
# Wrapper to run Deep computer scan with detailed .out logging

[CmdletBinding()] param(
    [string]$ReportsDir = (Join-Path $PSScriptRoot '..' 'Reports')
)

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$outLog = Join-Path $ReportsDir "deep-scan-$timestamp.out"

function Write-DeepLog { param([string]$Text)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts | $Text" | Out-File -FilePath $outLog -Append -Encoding UTF8
}

try {
    Write-DeepLog "Starting Deep scan wrapper"
    $modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'src/ps/Bottleneck.psm1'
    if (-not (Test-Path $modulePath)) { throw "Module not found: $modulePath" }
    Write-DeepLog "Importing module: $modulePath"
    Import-Module $modulePath -Force

    Write-DeepLog "Invoking Deep scan"
    $deepResults = Invoke-BottleneckScan -Tier Deep
    Write-DeepLog "Deep scan returned results: count=$($deepResults.Count)"

    Write-DeepLog "Generating Deep report"
    Invoke-BottleneckReport -Results $deepResults -Tier Deep

    $latest = Get-ChildItem (Join-Path $ReportsDir 'Full-scan-*.html') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        Write-DeepLog "Report generated: $($latest.FullName)"
        Start-Process $latest.FullName | Out-Null
        Write-Host "Report: $($latest.FullName)"
    } else {
        Write-DeepLog "No Deep report found in $ReportsDir"
        Write-Host "No Deep report found."
    }
} catch {
    Write-DeepLog "ERROR: $_"
    throw
} finally {
    Write-DeepLog "Deep scan wrapper complete. Log: $outLog"
    Write-Host "Deep scan log: $outLog"
}
