param(
    [switch] $Computer,
    [switch] $Network,
    [int] $Minutes,
    [string] $Profile,
    [switch] $AI,
  [switch] $CollectLogs,
  [int] $TraceIntervalMinutes
)

# Elevation helper
function Ensure-Elevated {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Restarting with admin privileges..."
        $scriptPath = $MyInvocation.MyCommand.Path
        $argsList = @()
        if ($Computer) { $argsList += '-Computer' }
        if ($Network) { $argsList += '-Network' }
        if ($Minutes) { $argsList += @('-Minutes', $Minutes) }
        if ($Profile) { $argsList += @('-Profile', $Profile) }
        if ($AI) { $argsList += '-AI' }
        if ($CollectLogs) { $argsList += '-CollectLogs' }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = (Get-Command pwsh).Source
        $psi.Arguments = "-NoLogo -NoProfile -File `"$scriptPath`" $($argsList -join ' ')"
        $psi.Verb = 'runas'
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit 0
    }
}

Ensure-Elevated

# Resolve repo root and import module fresh
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Push-Location $repoRoot
try {
    Import-Module "$repoRoot/src/ps/Bottleneck.psm1" -Force -ErrorAction Stop
} catch {
    Write-Warning "Failed to import Bottleneck module: $($_.Exception.Message)"
}

# Load profile if provided
$effectiveMinutes = $Minutes
$enableAI = [bool]$AI
$effectiveTraceInterval = $TraceIntervalMinutes
if ($Profile) {
    $profilesPath = Join-Path $repoRoot 'config/scan-profiles.json'
    if (Test-Path $profilesPath) {
        try {
            $profiles = Get-Content $profilesPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $p = $profiles[$Profile]
            if ($null -ne $p) {
                if (-not $Minutes -and $p.Minutes) { $effectiveMinutes = [int]$p.Minutes }
                if (-not $AI -and $p.AI -ne $null) { $enableAI = [bool]$p.AI }
              if (-not $TraceIntervalMinutes -and $p.TraceIntervalMinutes) { $effectiveTraceInterval = [int]$p.TraceIntervalMinutes }
                Write-Host "Profile '$Profile' loaded: Minutes=$effectiveMinutes, AI=$enableAI"
            } else {
                Write-Warning "Profile '$Profile' not found in $profilesPath"
            }
        } catch {
            Write-Warning "Failed to read profiles: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Profiles file not found: $profilesPath"
    }
}

# Default minutes
if (-not $effectiveMinutes) { $effectiveMinutes = 15 }
if (-not $effectiveTraceInterval) { $effectiveTraceInterval = 5 }

# Run Computer scan
if ($Computer) {
    Write-Host "Starting Computer scan..."
    $results = Invoke-BottleneckScan -Tier Standard
    Write-Host "Generating report..."
    $Global:Bottleneck_EnableAI = $enableAI
    Invoke-BottleneckReport -Results $results -Tier Standard
}

# Run Network scan + RCA/Diagnostics
if ($Network) {
    Write-Host "Starting network monitor for $effectiveMinutes minute(s)..."
  & "$repoRoot/scripts/run-network-monitor.ps1" -Minutes $effectiveMinutes -TraceIntervalMinutes $effectiveTraceInterval
    Write-Host "Running RCA and diagnostics..."
    $rca = $null
    $diag = $null
    try { $rca = Invoke-BottleneckNetworkRootCause } catch { Write-Warning "RCA failed: $($_.Exception.Message)" }
    try { $diag = Invoke-BottleneckNetworkCsvDiagnostics } catch { Write-Warning "Diagnostics failed: $($_.Exception.Message)" }
    if ($rca) { Write-Host ("RCA likely cause: " + $rca.LikelyCause) }
    if ($diag) { Write-Host ("CSV fused alert: " + $diag.FusedAlertLevel) }
}

# Open latest report if exists
$latestReport = Get-ChildItem "$repoRoot/Reports" -Filter 'Full-scan-*.html' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestReport) {
    Write-Host ("Report: " + $latestReport.FullName)
    try { Start-Process $latestReport.FullName } catch {}
}

# Collect logs optionally
if ($CollectLogs) {
    Write-Host "Collecting logs and artifacts..."
    & "$repoRoot/scripts/collect-logs.ps1" -IncludeAll -OpenFolder
}

Pop-Locationparam(
  [switch]$Computer,
  [switch]$Network,
  [int]$Minutes = 15,
  [switch]$Deep,
  [switch]$AI,
  [switch]$CollectLogs,
  [ValidateSet('quick','standard','deep')][string]$Profile
)

$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo

# Elevate if needed
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Elevation required. Relaunching as Administrator..."
  Start-Process pwsh -Verb RunAs -ArgumentList '-NoLogo','-NoProfile','-Command',"Push-Location '$repo'; & scripts\run.ps1 -Computer:$($Computer.IsPresent) -Network:$($Network.IsPresent) -Minutes $Minutes -Deep:$($Deep.IsPresent) -AI:$($AI.IsPresent) -CollectLogs:$($CollectLogs.IsPresent); Pop-Location"
  Pop-Location
  return
}

# Fresh module import
Get-Module Bottleneck -ListAvailable | ForEach-Object { Remove-Module $_.Name -Force -ErrorAction SilentlyContinue }
Import-Module "$repo\src\ps\Bottleneck.psm1" -Force

# Apply profile presets if provided
if ($Profile) {
  try {
    $profilesPath = Join-Path $repo 'config' 'scan-profiles.json'
    if (Test-Path $profilesPath) {
      $profiles = Get-Content $profilesPath -Raw | ConvertFrom-Json
      $p = $profiles.$Profile
      if ($p) {
        if ($p.minutes) { $Minutes = [int]$p.minutes }
        if ($p.ai -ne $null) { $AI = [bool]$p.ai }
      }
    }
  } catch {}
}

# Enable AI triage if requested (after profile application)
if ($AI) { $Global:Bottleneck_EnableAI = $true } else { $Global:Bottleneck_EnableAI = $false }

if ($Computer) {
  Write-Host 'Running Computer scan...'
  $tier = if ($Deep) { 'Deep' } else { 'Standard' }
  $res = Invoke-BottleneckScan -Tier $tier
  Invoke-BottleneckReport -Results $res -Tier $tier
}

if ($Network) {
  Write-Host "Running Network monitor for $Minutes minute(s)..."
  & "$repo\scripts\run-network-monitor.ps1" -Minutes $Minutes
  Write-Host 'Running RCA and CSV diagnostics...'
  $rca = Invoke-BottleneckNetworkRootCause
  $diag = Invoke-BottleneckNetworkCsvDiagnostics
  Write-Host ("Likely cause: " + $rca.LikelyCause)
  Write-Host ("Fused alert: " + $diag.FusedAlertLevel)
}

if ($CollectLogs) {
  & "$repo\scripts\collect-logs.ps1" -IncludeAll -OpenFolder
}

Pop-Location
