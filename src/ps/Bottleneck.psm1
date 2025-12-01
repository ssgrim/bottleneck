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

# Load other modules (hardened paths)
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
Load-ModuleFile 'Bottleneck.Alerts.ps1'

# Check admin rights
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $script:IsAdmin) {
    Write-Warning "⚠️  Some checks require administrator privileges. Run as admin for complete results."
    Write-BottleneckLog "Running without admin privileges - some checks will be limited" -Level "WARN"
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
        # Sequential execution (PowerShell 5.1 or -Sequential flag)
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
        # Parallel execution (PowerShell 7+)
        # Note: Parallel runspaces can't access module functions, so we use sequential for now
        # TODO: Refactor to export check results to shared data structure for true parallelism
        Write-BottleneckLog "Using sequential execution (parallel requires module scope refactoring)" -Level "INFO"
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
    }
    
    $scanDuration = ((Get-Date) - $scanStart).TotalSeconds
    Write-BottleneckLog "Scan completed in $([math]::Round($scanDuration,1)) seconds with $($results.Count) results" -Level "INFO"
    
    return $results
}

Export-ModuleMember -Function Invoke-BottleneckScan, Invoke-BottleneckReport, Invoke-BottleneckFixCleanup, Invoke-BottleneckFixRetrim, Set-BottleneckPowerPlanHighPerformance, Invoke-BottleneckFixTriggerUpdate, Invoke-BottleneckFixDefragment, Invoke-BottleneckFixMemoryDiagnostic, Invoke-BottleneckFixRestartServices, Get-FusedAlertLevel
