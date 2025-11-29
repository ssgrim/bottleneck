<#
.SYNOPSIS
Runs a deep/full performance scan and generates reports.
#>

Import-Module "$PSScriptRoot/../src/ps/Bottleneck.psm1" -Force

$results = Invoke-BottleneckScan -Tier Deep

Invoke-BottleneckReport -Results $results -Tier Deep

$oneDriveDocs = "$env:USERPROFILE\OneDrive\Documents"
if (Test-Path $oneDriveDocs) {
    $oneDriveReport = Get-ChildItem $oneDriveDocs -Filter "Full-scan-*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($oneDriveReport) {
        Write-Host "Full scan complete. Opening report..."
        Start-Process $oneDriveReport.FullName
    }
} else {
    Write-Host "Full scan complete. Report saved to Documents\ScanReports folder."
}
