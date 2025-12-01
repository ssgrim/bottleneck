# Bottleneck.Alerts.ps1
# Threshold-based alerting with notifications and logging

function Test-BottleneckThresholds {
    <#
    .SYNOPSIS
    Tests current metrics against configured thresholds and triggers alerts.
    
    .DESCRIPTION
    Monitors network and system metrics against user-defined thresholds.
    Generates toast notifications and log entries when thresholds are exceeded.
    
    .PARAMETER ConfigPath
    Path to threshold configuration file (JSON). If not specified, uses defaults.
    
    .PARAMETER ShowToast
    Display Windows toast notifications for alerts (default: true on Windows 10+).
    
    .PARAMETER LogOnly
    Only log alerts, don't display notifications.
    
    .EXAMPLE
    Test-BottleneckThresholds
    
    .EXAMPLE
    Test-BottleneckThresholds -LogOnly
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath,
        
        [bool]$ShowToast = $true,
        
        [switch]$LogOnly
    )
    
    # Load thresholds
    $thresholds = Get-AlertThresholds -ConfigPath $ConfigPath
    
    # Gather current metrics
    $metrics = Get-CurrentMetrics
    
    $alerts = @()
    
    # Check network thresholds
    if ($metrics.Network) {
        if ($metrics.Network.SuccessRatePercent -lt $thresholds.Network.MinSuccessRate) {
            $alerts += [pscustomobject]@{
                Severity = 'Critical'
                Category = 'Network'
                Message = "Network success rate ($($metrics.Network.SuccessRatePercent)%) below threshold ($($thresholds.Network.MinSuccessRate)%)"
                Value = $metrics.Network.SuccessRatePercent
                Threshold = $thresholds.Network.MinSuccessRate
            }
        }
        
        if ($metrics.Network.P95LatencyMs -gt $thresholds.Network.MaxP95Latency) {
            $alerts += [pscustomobject]@{
                Severity = 'Warning'
                Category = 'Network'
                Message = "P95 latency ($($metrics.Network.P95LatencyMs)ms) exceeds threshold ($($thresholds.Network.MaxP95Latency)ms)"
                Value = $metrics.Network.P95LatencyMs
                Threshold = $thresholds.Network.MaxP95Latency
            }
        }
    }
    
    # Check path quality thresholds
    if ($metrics.PathQuality -and $metrics.PathQuality.WorstHopLossPercent -gt $thresholds.PathQuality.MaxHopLoss) {
        $alerts += [pscustomobject]@{
            Severity = 'Warning'
            Category = 'PathQuality'
            Message = "Hop $($metrics.PathQuality.WorstHopIP) has $($metrics.PathQuality.WorstHopLossPercent)% loss (threshold: $($thresholds.PathQuality.MaxHopLoss)%)"
            Value = $metrics.PathQuality.WorstHopLossPercent
            Threshold = $thresholds.PathQuality.MaxHopLoss
        }
    }
    
    # Check system thresholds
    if ($metrics.System) {
        if ($metrics.System.CPUUsagePercent -gt $thresholds.System.MaxCPU) {
            $alerts += [pscustomobject]@{
                Severity = 'Warning'
                Category = 'System'
                Message = "CPU usage ($([math]::Round($metrics.System.CPUUsagePercent,1))%) exceeds threshold ($($thresholds.System.MaxCPU)%)"
                Value = $metrics.System.CPUUsagePercent
                Threshold = $thresholds.System.MaxCPU
            }
        }
        
        if ($metrics.System.MemoryUsagePercent -gt $thresholds.System.MaxMemory) {
            $alerts += [pscustomobject]@{
                Severity = 'Warning'
                Category = 'System'
                Message = "Memory usage ($($metrics.System.MemoryUsagePercent)%) exceeds threshold ($($thresholds.System.MaxMemory)%)"
                Value = $metrics.System.MemoryUsagePercent
                Threshold = $thresholds.System.MaxMemory
            }
        }
    }
    
    # Check disk thresholds
    if ($metrics.Disk -and $metrics.Disk.UsagePercent -gt $thresholds.Disk.MaxUsage) {
        $alerts += [pscustomobject]@{
            Severity = if ($metrics.Disk.UsagePercent -gt 95) { 'Critical' } else { 'Warning' }
            Category = 'Disk'
            Message = "Disk usage ($($metrics.Disk.UsagePercent)%) exceeds threshold ($($thresholds.Disk.MaxUsage)%)"
            Value = $metrics.Disk.UsagePercent
            Threshold = $thresholds.Disk.MaxUsage
        }
    }
    
    # Process alerts
    if ($alerts.Count -gt 0) {
        Write-Host "`n⚠️  $($alerts.Count) threshold alert(s) detected:" -ForegroundColor Yellow
        
        foreach ($alert in $alerts) {
            $color = switch ($alert.Severity) {
                'Critical' { 'Red' }
                'Warning' { 'Yellow' }
                default { 'Gray' }
            }
            
            Write-Host "  [$($alert.Severity)] $($alert.Message)" -ForegroundColor $color
            
            # Log to file
            Save-AlertLog -Alert $alert
            
            # Show toast notification
            if ($ShowToast -and -not $LogOnly) {
                Show-ToastNotification -Alert $alert
            }
        }
        
        Write-Host ""
    } else {
        Write-Host "`n✓ All metrics within acceptable thresholds" -ForegroundColor Green
    }
    
    return $alerts
}

function Get-AlertThresholds {
    param([string]$ConfigPath)
    
    # Default thresholds
    $defaults = @{
        Network = @{
            MinSuccessRate = 99.5
            MaxP95Latency = 150
        }
        PathQuality = @{
            MaxHopLoss = 3.0
        }
        System = @{
            MaxCPU = 85
            MaxMemory = 90
        }
        Disk = @{
            MaxUsage = 85
        }
    }
    
    # Load from config if specified
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        try {
            $custom = Get-Content $ConfigPath | ConvertFrom-Json
            # Merge with defaults
            foreach ($key in $custom.PSObject.Properties.Name) {
                if ($defaults.ContainsKey($key)) {
                    foreach ($subKey in $custom.$key.PSObject.Properties.Name) {
                        $defaults[$key][$subKey] = $custom.$key.$subKey
                    }
                }
            }
        } catch {
            Write-Warning "Could not load custom thresholds from $ConfigPath, using defaults"
        }
    }
    
    return $defaults
}

function Save-AlertLog {
    param($Alert)
    
    try {
        $logFile = Join-Path $PSScriptRoot '..' '..' 'Reports' 'alerts.log'
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $entry = "$timestamp [$($Alert.Severity)] $($Alert.Category): $($Alert.Message)"
        Add-Content -Path $logFile -Value $entry
    } catch {
        Write-Verbose "Could not write to alert log: $_"
    }
}

function Show-ToastNotification {
    param($Alert)
    
    try {
        # Check Windows version
        $os = [System.Environment]::OSVersion.Version
        if ($os.Major -lt 10) { return }
        
        # Use BurntToast module if available, otherwise fall back to basic notification
        if (Get-Module -ListAvailable -Name BurntToast) {
            Import-Module BurntToast -ErrorAction SilentlyContinue
            $params = @{
                Text = "Bottleneck Alert", $Alert.Message
                AppLogo = $null
                Sound = if ($Alert.Severity -eq 'Critical') { 'Alarm' } else { 'Default' }
            }
            New-BurntToastNotification @params
        } else {
            # Fallback: Use Windows Forms notification
            Add-Type -AssemblyName System.Windows.Forms
            $notify = New-Object System.Windows.Forms.NotifyIcon
            $notify.Icon = [System.Drawing.SystemIcons]::Warning
            $notify.BalloonTipIcon = if ($Alert.Severity -eq 'Critical') { 'Error' } else { 'Warning' }
            $notify.BalloonTipTitle = "Bottleneck Alert - $($Alert.Category)"
            $notify.BalloonTipText = $Alert.Message
            $notify.Visible = $true
            $notify.ShowBalloonTip(5000)
            Start-Sleep -Seconds 1
            $notify.Dispose()
        }
    } catch {
        Write-Verbose "Could not display toast notification: $_"
    }
}

function New-AlertThresholdConfig {
    <#
    .SYNOPSIS
    Creates a custom alert threshold configuration file.
    
    .PARAMETER OutputPath
    Path to save configuration file.
    
    .EXAMPLE
    New-AlertThresholdConfig -OutputPath '.\my-thresholds.json'
    #>
    param([Parameter(Mandatory)][string]$OutputPath)
    
    $config = @{
        Network = @{
            MinSuccessRate = 99.5
            MaxP95Latency = 150
        }
        PathQuality = @{
            MaxHopLoss = 3.0
        }
        System = @{
            MaxCPU = 85
            MaxMemory = 90
        }
        Disk = @{
            MaxUsage = 85
        }
    }
    
    $config | ConvertTo-Json -Depth 5 | Set-Content $OutputPath
    Write-Host "✓ Threshold configuration template created: $OutputPath" -ForegroundColor Green
    Write-Host "  Edit this file to customize alert thresholds." -ForegroundColor Gray
}

# Phase 6: Fused alert computation
function Get-FusedAlertLevel {
    [CmdletBinding()] param(
        [Parameter()][object[]]$LatencySpikes = @(),
        [Parameter()][object[]]$LossBursts = @(),
        [Parameter()][object[]]$JitterVolatility = @()
    )
    $latencyCount = ($LatencySpikes | Measure-Object).Count
    $lossCount = ($LossBursts | Measure-Object).Count
    $jitterCount = ($JitterVolatility | Measure-Object).Count
    # Simple weighted score; refine in follow-ups
    $score = (2*$latencyCount) + (3*$lossCount) + (1*$jitterCount)
    switch ($score) {
        { $_ -ge 12 } { return 'Critical' }
        { $_ -ge 7 }  { return 'High' }
        { $_ -ge 3 }  { return 'Moderate' }
        { $_ -ge 1 }  { return 'Low' }
        default       { return 'None' }
    }
}
Export-ModuleMember -Function Get-FusedAlertLevel
