# Bottleneck.psm1
# Main module entry point

# Load performance and logging utilities first
. $PSScriptRoot/Bottleneck.Performance.ps1
. $PSScriptRoot/Bottleneck.Logging.ps1

# Initialize logging
Initialize-BottleneckLogging
. $PSScriptRoot/Bottleneck.Elevation.ps1
# Admin warning suppression flag
$script:SuppressAdminWarning = $false

# Honor environment variable to suppress admin warning on import
try {
    $envSuppress = $env:BN_SUPPRESS_ADMIN_WARNING
    if ($envSuppress -and ($envSuppress -match '^(1|true|yes)$')) { $script:SuppressAdminWarning = $true }
} catch {}

function Set-BottleneckAdminWarning {
    [CmdletBinding()]
    param([Parameter()][bool]$Suppress = $true)
    $script:SuppressAdminWarning = $Suppress
}

# Load other modules
. $PSScriptRoot/Bottleneck.Constants.ps1
. $PSScriptRoot/Bottleneck.Utils.ps1
. $PSScriptRoot/Bottleneck.Checks.ps1
. $PSScriptRoot/Bottleneck.Fixes.ps1
. $PSScriptRoot/Bottleneck.Report.ps1
. $PSScriptRoot/Bottleneck.ReportUtils.ps1
. $PSScriptRoot/Bottleneck.Thermal.ps1
. $PSScriptRoot/Bottleneck.PDF.ps1
. $PSScriptRoot/Bottleneck.Battery.ps1
. $PSScriptRoot/Bottleneck.Disk.ps1
. $PSScriptRoot/Bottleneck.Memory.ps1
. $PSScriptRoot/Bottleneck.CPUThrottle.ps1
. $PSScriptRoot/Bottleneck.Services.ps1
. $PSScriptRoot/Bottleneck.WindowsFeatures.ps1
. $PSScriptRoot/Bottleneck.Network.ps1
. $PSScriptRoot/Bottleneck.Security.ps1
. $PSScriptRoot/Bottleneck.UserExperience.ps1
. $PSScriptRoot/Bottleneck.DeepScan.ps1
. $PSScriptRoot/Bottleneck.SystemPerformance.ps1
. $PSScriptRoot/Bottleneck.Parallel.ps1
. $PSScriptRoot/Bottleneck.NetworkScan.ps1
. $PSScriptRoot/Bottleneck.NetworkDeep.ps1
. $PSScriptRoot/Bottleneck.NetworkProbes.ps1
. $PSScriptRoot/Bottleneck.ComputerScan.ps1
. $PSScriptRoot/Bottleneck.Version.ps1
. $PSScriptRoot/Bottleneck.NetworkMonitor.ps1
. $PSScriptRoot/Bottleneck.Speedtest.ps1
. $PSScriptRoot/Bottleneck.Metrics.ps1
. $PSScriptRoot/Bottleneck.Alerts.ps1
. $PSScriptRoot/Bottleneck.Scheduler.ps1
. $PSScriptRoot/Bottleneck.Elevation.ps1

# Check admin rights
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $script:IsAdmin) {
    if (-not $script:SuppressAdminWarning) {
        Write-Warning "⚠️  Some checks require administrator privileges. Run as admin for complete results."
        Write-BottleneckLog "Running without admin privileges - some checks will be limited" -Level "WARN"
    } else {
        Write-BottleneckLog "Admin warning suppressed by user preference" -Level "INFO"
    }
} else {
    Write-BottleneckLog "Running with administrator privileges" -Level "INFO"
}

function Invoke-BottleneckScan {
    [CmdletBinding()]
    param(
        [ValidateSet('Quick','Standard','Deep')]
        [string]$Tier = 'Quick',

        [Parameter()]
        [switch]$Sequential
    )

    Write-BottleneckLog "Starting $Tier scan" -Level "INFO"
    $scanStart = Get-Date

    $checks = Get-BottleneckChecks -Tier $Tier
    Write-BottleneckLog "Executing $($checks.Count) checks" -Level "INFO"

    $results = @()

    if ($Sequential -or $PSVersionTable.PSVersion.Major -lt 7) {
        Write-BottleneckLog "Using sequential execution" -Level "INFO"
        foreach ($check in $checks) {
            try {
                $checkStart = Get-Date
                $result = & $check
                $checkDuration = ((Get-Date) - $checkStart).TotalMilliseconds
                Write-BottleneckLog "Check $check completed in $([math]::Round($checkDuration))ms" -Level "DEBUG"
                if ($result) { $results += $result }
            } catch {
                Write-BottleneckLog "Check $check failed: $_" -Level "ERROR" -CheckId $check
            }
        }
    } else {
        Write-BottleneckLog "Using parallel execution" -Level "INFO"
        $parallelResults = Invoke-BottleneckParallelChecks -CheckNames $checks -ThrottleLimit 8 -TimeoutSeconds 180
        $results += $parallelResults
    }

    $scanDuration = ((Get-Date) - $scanStart).TotalSeconds
    Write-BottleneckLog "Scan completed in $([math]::Round($scanDuration,1)) seconds with $($results.Count) results" -Level "INFO"

    return $results
}

Export-ModuleMember -Function Invoke-BottleneckScan, Invoke-BottleneckReport, Invoke-BottleneckFixCleanup, Invoke-BottleneckFixRetrim, Set-BottleneckPowerPlanHighPerformance, Invoke-BottleneckFixTriggerUpdate, Invoke-BottleneckFixDefragment, Invoke-BottleneckFixMemoryDiagnostic, Invoke-BottleneckFixRestartServices, Invoke-BottleneckNetworkScan, Invoke-BottleneckNetworkRootCause, Invoke-BottleneckNetworkCsvDiagnostics, Request-ElevatedScan, Set-BottleneckAdminWarning, Invoke-BottleneckComputerScan, Invoke-BottleneckNetworkMonitor, Invoke-BottleneckSpeedtest, Get-SpeedtestHistory, Get-BottleneckNetworkTrafficSnapshot, Export-BottleneckMetrics, Test-BottleneckThresholds, New-AlertThresholdConfig, Get-BottleneckVersion, Register-BottleneckScheduledScan, Get-BottleneckScheduledScans, Remove-BottleneckScheduledScan
