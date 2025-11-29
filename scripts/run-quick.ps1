<#
.SYNOPSIS
Runs a quick performance scan and generates reports.
#>

Import-Module "$PSScriptRoot/../src/ps/Bottleneck.psm1" -Force

$results = Invoke-BottleneckScan -Tier Quick

Invoke-BottleneckReport -Results $results -Tier Quick

$userDocs = [Environment]::GetFolderPath('MyDocuments')
$userScanDir = Join-Path $userDocs 'ScanReports'
$scanType = $results[0].Tier
switch ($scanType) {
	'Quick' { $prefix = 'Basic-scan' }
	'Standard' { $prefix = 'Standard-scan' }
	'Deep' { $prefix = 'Full-scan' }
	default { $prefix = 'Scan' }
}
$oneDriveDocs = "$env:USERPROFILE\OneDrive\Documents"
if (Test-Path $oneDriveDocs) {
    $oneDriveReport = Get-ChildItem $oneDriveDocs -Filter "$prefix-*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($oneDriveReport) {
        Write-Host "Scan complete. Opening report..."
        Start-Process $oneDriveReport.FullName
    }
} else {
    Write-Host "Scan complete. Report saved to Documents\ScanReports folder."
}
