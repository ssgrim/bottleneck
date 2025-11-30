param(
    [Parameter(Mandatory)][string]$Profile,
    [string]$ConfigPath = "$PSScriptRoot/../config/bottleneck.profiles.json",
    [switch]$UseAdaptiveTargets
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (!(Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }

$config = Get-Content $ConfigPath | ConvertFrom-Json
$profileData = $config.profiles.PSObject.Properties[$Profile]?.Value

if (!$profileData) {
    Write-Host "❌ Profile '$Profile' not found in $ConfigPath" -ForegroundColor Red
    Write-Host "Available profiles:" -ForegroundColor Yellow
    $config.profiles.PSObject.Properties.Name | ForEach-Object { Write-Host "  - $_" -ForegroundColor Cyan }
    throw "Invalid profile"
}

Write-Host "✅ Loaded profile: $Profile" -ForegroundColor Green
Write-Host "   Description: $($profileData.description)" -ForegroundColor Gray
Write-Host "   Targets: $($profileData.targets -join ', ')" -ForegroundColor Gray
Write-Host "   Duration: $($profileData.duration)" -ForegroundColor Gray
Write-Host "   Interval: $($profileData.interval)s" -ForegroundColor Gray

# Import module
$moduleRoot = Join-Path $PSScriptRoot '../bottleneck/src/ps'
Import-Module (Join-Path $moduleRoot 'Bottleneck.psm1') -DisableNameChecking -Force

# Build parameters
$monitorParams = @{
    Duration = $profileData.duration
    Interval = $profileData.interval
    TracerouteInterval = $profileData.tracerouteInterval
}

if ($UseAdaptiveTargets) {
    $monitorParams['UseAdaptiveTargets'] = $true
} else {
    $monitorParams['PrimaryTarget'] = $profileData.targets[0]
    if ($profileData.targets.Count -gt 1) {
        $monitorParams['AdditionalTargets'] = $profileData.targets[1..($profileData.targets.Count-1)]
    }
}

Write-Host "`n🚀 Starting monitor with profile settings..." -ForegroundColor Cyan
Invoke-BottleneckNetworkMonitor @monitorParams
