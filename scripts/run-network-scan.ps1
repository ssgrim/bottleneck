param(
    [double]$DurationHours = 0.25,
    [int]$DurationMinutes
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
    $durArgs = if ($PSBoundParameters.ContainsKey('DurationMinutes')) { "-DurationMinutes $DurationMinutes" } else { "-DurationHours $DurationHours" }
    $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Push-Location ''{0}''; & ''{1}'' {2}; Pop-Location"' -f (Split-Path -Parent $PSScriptRoot), (Join-Path $PSScriptRoot 'run-network-scan.ps1'), $durArgs
    Start-Process PowerShell -Verb RunAs -ArgumentList $args | Out-Null
    exit 0
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$reportsDir = Join-Path $repoRoot 'Reports'

if ($PSBoundParameters.ContainsKey('DurationMinutes')) {
    $DurationHours = [math]::Round(($DurationMinutes / 60.0), 4)
}

if ($DurationHours -le 0) { throw "Duration must be > 0. Use -DurationHours or -DurationMinutes." }

# 1) Run the monitor
$monitorScript = Join-Path $PSScriptRoot 'run-network-monitor.ps1'
if (-not (Test-Path $monitorScript)) { throw "Monitor script not found: $monitorScript" }

Write-Info ("Starting Network scan for " + ($DurationHours.ToString('0.###')) + ' hours...')
& $monitorScript -DurationHours $DurationHours

# 2) Import module for RCA/diagnostics
$modulePath = Join-Path $repoRoot 'src' 'ps' 'Bottleneck.psm1'
if (Test-Path $modulePath) {
    try {
        Write-Info 'Importing Bottleneck module...'
        Remove-Module Bottleneck -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force

        Write-Info 'Running RCA and diagnostics...'
        $rca = Invoke-BottleneckNetworkRootCause
        $diag = Invoke-BottleneckNetworkCsvDiagnostics
    } catch {
        Write-Info ('RCA/Diagnostics skipped due to error: ' + $_.Exception.Message)
    }
}

# 3) Open latest network monitor HTML if present
$netReport = Get-ChildItem -Path $reportsDir -Filter 'network-monitor-*.html' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($netReport) {
    Write-Info ("Network report: " + $netReport.FullName)
    try { Start-Process -FilePath $netReport.FullName } catch { }
}
