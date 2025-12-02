# Bottleneck.psm1
# Main module entry point

function Load-ModuleFile($name) {
    try {
        . (Join-Path $PSScriptRoot $name)
    } catch {
        Write-Warning "Failed to load module file '$name': $_"
    }
}

# Load performance and logging utilities first
Load-ModuleFile 'Bottleneck.Performance.ps1'
Load-ModuleFile 'Bottleneck.Logging.ps1'

# Initialize logging
Initialize-BottleneckLogging
Load-ModuleFile 'Bottleneck.Elevation.ps1'
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
Load-ModuleFile 'Bottleneck.Constants.ps1'
Load-ModuleFile 'Bottleneck.Utils.ps1'
Load-ModuleFile 'Bottleneck.Checks.ps1'
Load-ModuleFile 'Bottleneck.Fixes.ps1'
Load-ModuleFile 'Bottleneck.Report.ps1'
Load-ModuleFile 'Bottleneck.ReportUtils.ps1'
Load-ModuleFile 'Bottleneck.Thermal.ps1'
Load-ModuleFile 'Bottleneck.PDF.ps1'
Load-ModuleFile 'Bottleneck.Battery.ps1'
Load-ModuleFile 'Bottleneck.Disk.ps1'
Load-ModuleFile 'Bottleneck.Memory.ps1'
Load-ModuleFile 'Bottleneck.CPUThrottle.ps1'
Load-ModuleFile 'Bottleneck.Services.ps1'
Load-ModuleFile 'Bottleneck.WindowsFeatures.ps1'
Load-ModuleFile 'Bottleneck.Network.ps1'
Load-ModuleFile 'Bottleneck.Security.ps1'
Load-ModuleFile 'Bottleneck.UserExperience.ps1'
Load-ModuleFile 'Bottleneck.DeepScan.ps1'
Load-ModuleFile 'Bottleneck.SystemPerformance.ps1'
Load-ModuleFile 'Bottleneck.Parallel.ps1'
Load-ModuleFile 'Bottleneck.NetworkScan.ps1'
Load-ModuleFile 'Bottleneck.NetworkDeep.ps1'
Load-ModuleFile 'Bottleneck.NetworkProbes.ps1'
Load-ModuleFile 'Bottleneck.ComputerScan.ps1'
Load-ModuleFile 'Bottleneck.Version.ps1'
Load-ModuleFile 'Bottleneck.NetworkMonitor.ps1'
Load-ModuleFile 'Bottleneck.Speedtest.ps1'
Load-ModuleFile 'Bottleneck.Metrics.ps1'
Load-ModuleFile 'Bottleneck.Alerts.ps1'
Load-ModuleFile 'Bottleneck.Scheduler.ps1'
Load-ModuleFile 'Bottleneck.Elevation.ps1'

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
