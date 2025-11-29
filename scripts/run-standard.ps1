<#
.SYNOPSIS
Runs a standard performance scan and generates reports.
#>

Import-Module "$PSScriptRoot/../src/ps/Bottleneck.psm1" -Force

$results = Invoke-BottleneckScan -Tier Standard

Invoke-BottleneckReport -Results $results -Tier Standard

$oneDriveDocs = "$env:USERPROFILE\OneDrive\Documents"
if (Test-Path $oneDriveDocs) {
    $oneDriveReport = Get-ChildItem $oneDriveDocs -Filter "Standard-scan-*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($oneDriveReport) {
        Write-Host "Standard scan complete. Opening report..."
        Start-Process $oneDriveReport.FullName
    }
} else {
    Write-Host "Standard scan complete. Report saved to Documents\ScanReports folder."
}
