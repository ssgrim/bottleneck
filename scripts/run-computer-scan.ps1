param(
    [ValidateSet('Deep')]
    [string]$Tier = 'Deep'
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] $msg"
}

# Ensure admin elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Info 'Elevation required. Relaunching as Administrator...'
    $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Push-Location ''{0}''; & ''{1}'' -Tier {2}; Pop-Location"' -f (Split-Path -Parent $PSScriptRoot), (Join-Path $PSScriptRoot 'run-computer-scan.ps1'), $Tier
    Start-Process PowerShell -Verb RunAs -ArgumentList $args | Out-Null
    exit 0
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'src' 'ps' 'Bottleneck.psm1'
if (-not (Test-Path $modulePath)) { throw "Module not found: $modulePath" }

Write-Info 'Importing Bottleneck module...'
Remove-Module Bottleneck -ErrorAction SilentlyContinue
Import-Module $modulePath -Force

Write-Info "Running Computer scan (Tier=$Tier)..."
$results = Invoke-BottleneckScan -Tier $Tier

Write-Info 'Generating system report...'
Invoke-BottleneckReport -Results $results -Tier $Tier

$report = Get-ChildItem -Path (Join-Path $repoRoot 'Reports') -Filter 'Full-scan-*.html' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($report) {
    Write-Info ("Report: " + $report.FullName)
    try { Start-Process -FilePath $report.FullName } catch { }
} else {
    Write-Info 'No Full-scan report found in Reports/.'
}
