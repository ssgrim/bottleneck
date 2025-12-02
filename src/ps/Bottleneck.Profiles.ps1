<#
.SYNOPSIS
    Get available scan profiles and their configurations.

.DESCRIPTION
    Lists all available scan profiles with descriptions, included checks, and emphasis areas.
    Profiles are persona-based configurations optimized for specific use cases.

.PARAMETER Name
    Optional. Name of a specific profile to retrieve. If omitted, lists all profiles.

.PARAMETER ListNames
    Returns only profile names without details.

.EXAMPLE
    Get-BottleneckProfile
    Lists all available profiles with full details.

.EXAMPLE
    Get-BottleneckProfile -Name "RemoteWorker"
    Shows details for the RemoteWorker profile only.

.EXAMPLE
    Get-BottleneckProfile -ListNames
    Returns just the profile names.
#>
function Get-BottleneckProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [switch]$ListNames
    )

    try {
        $profilePath = Join-Path $PSScriptRoot "..\..\config\scan-profiles.json"

        if (-not (Test-Path $profilePath)) {
            Write-Error "Profile configuration not found: $profilePath"
            return
        }

        $profiles = Get-Content $profilePath -Raw | ConvertFrom-Json

        if ($ListNames) {
            return $profiles.PSObject.Properties.Name
        }

        if ($Name) {
            $profile = $profiles.$Name
            if (-not $profile) {
                Write-Error "Profile '$Name' not found. Available profiles: $($profiles.PSObject.Properties.Name -join ', ')"
                return
            }

            $output = [PSCustomObject]@{
                Name = $Name
                Description = $profile.description
                Tier = $profile.tier
                NetworkMinutes = $profile.minutes
                TraceInterval = $profile.traceIntervalMinutes
                TargetHost = $profile.targetHost
                Emphasis = $profile.emphasis -join ', '
                IncludedChecks = if ($profile.includedChecks) { $profile.includedChecks.Count } else { "All for tier" }
                ExcludedChecks = if ($profile.excludedChecks) { $profile.excludedChecks.Count } else { 0 }
            }

            Write-Host "`n=== $Name Profile ===" -ForegroundColor Cyan
            Write-Host "Description: $($output.Description)" -ForegroundColor White
            Write-Host "Tier: $($output.Tier)" -ForegroundColor Yellow
            Write-Host "Network Monitoring: $($output.NetworkMinutes) minutes" -ForegroundColor White
            Write-Host "Trace Interval: $($output.TraceInterval) minutes" -ForegroundColor White
            Write-Host "Target Host: $($output.TargetHost)" -ForegroundColor White

            if ($profile.emphasis) {
                Write-Host "Emphasis Areas: $($output.Emphasis)" -ForegroundColor Green
            }

            if ($profile.includedChecks) {
                Write-Host "`nIncluded Checks ($($profile.includedChecks.Count)):" -ForegroundColor Green
                $profile.includedChecks | ForEach-Object { Write-Host "  • $_" -ForegroundColor Gray }
            }

            if ($profile.excludedChecks) {
                Write-Host "`nExcluded Checks ($($profile.excludedChecks.Count)):" -ForegroundColor Red
                $profile.excludedChecks | ForEach-Object { Write-Host "  • $_" -ForegroundColor Gray }
            }

            Write-Host ""
            return $output
        }

        # List all profiles
        Write-Host "`n=== Available Scan Profiles ===" -ForegroundColor Cyan
        Write-Host ""

        foreach ($profileName in $profiles.PSObject.Properties.Name) {
            $profile = $profiles.$profileName
            $tierBadge = switch ($profile.tier) {
                "Quick" { "[QUICK]" }
                "Standard" { "[STANDARD]" }
                "Deep" { "[DEEP]" }
                default { "" }
            }

            Write-Host "$tierBadge $profileName" -ForegroundColor Yellow
            Write-Host "  $($profile.description)" -ForegroundColor Gray

            if ($profile.emphasis) {
                Write-Host "  Focus: $($profile.emphasis -join ', ')" -ForegroundColor Green
            }

            Write-Host ""
        }

        Write-Host "Use: Get-BottleneckProfile -Name <ProfileName> for details" -ForegroundColor Cyan
        Write-Host "Use: .\run.ps1 -Computer -Profile <ProfileName> to run a profile" -ForegroundColor Cyan
        Write-Host ""

    } catch {
        Write-Error "Error reading profiles: $_"
    }
}
