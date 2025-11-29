
# Bottleneck.Fixes.ps1
function Invoke-BottleneckFixCleanup {
    [CmdletBinding()]
    param([switch]$Confirm)
    if ($Confirm) {
        Write-Host "Creating restore point..."
        Checkpoint-Computer -Description "Bottleneck Cleanup" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
    }
    Write-Host "Cleaning temp files..."
    Remove-Item -Path $env:TEMP\* -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Temp files cleaned."
}

function Invoke-BottleneckFixRetrim {
    [CmdletBinding()]
    param([switch]$Confirm)
    if ($Confirm) {
        Write-Host "Creating restore point..."
        Checkpoint-Computer -Description "Bottleneck SSD Retrim" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
    }
    Write-Host "Running SSD retrim..."
    Optimize-Volume -DriveLetter C -ReTrim -Verbose
    Write-Host "SSD retrim complete."
}

function Set-BottleneckPowerPlanHighPerformance {
    [CmdletBinding()]
    param()
    Write-Host "Setting power plan to High performance..."
    $guid = (powercfg /L | Select-String "High performance" | ForEach-Object { $_.Line.Split()[3] })
    if ($guid) { powercfg /S $guid }
    Write-Host "Power plan set."
}

function Invoke-BottleneckFixTriggerUpdate {
    [CmdletBinding()]
    param([switch]$Confirm)
    if ($Confirm) {
        Write-Host "Creating restore point..."
        Checkpoint-Computer -Description "Bottleneck Windows Update" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
    }
    Write-Host "Triggering Windows Update..."
    Install-WindowsUpdate -AcceptAll -AutoReboot
    Write-Host "Windows Update triggered."
}

function Invoke-BottleneckFixDefragment {
    [CmdletBinding()]
    param([switch]$Confirm)
    if ($Confirm) {
        Write-Host "Creating restore point..."
        Checkpoint-Computer -Description "Bottleneck Defragment" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
    }
    Write-Host "Defragmenting disk..."
    Optimize-Volume -DriveLetter C -Defrag -Verbose
    Write-Host "Defragmentation complete."
}

function Invoke-BottleneckFixMemoryDiagnostic {
    [CmdletBinding()]
    param([switch]$Confirm)
    Write-Host "Scheduling memory diagnostic on next reboot..."
    mdsched.exe
    Write-Host "Memory diagnostic scheduled. Restart your computer to run."
}

function Invoke-BottleneckFixRestartServices {
    [CmdletBinding()]
    param([switch]$Confirm)
    if ($Confirm) {
        Write-Host "Creating restore point..."
        Checkpoint-Computer -Description "Bottleneck Service Restart" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
    }
    Write-Host "Restarting failed services..."
    $failedServices = Get-Service | Where-Object { $_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic' }
    foreach ($service in $failedServices) {
        try {
            Write-Host "  Starting $($service.Name)..."
            Start-Service -Name $service.Name -ErrorAction Stop
            Write-Host "  $($service.Name) started successfully."
        } catch {
            Write-Warning "  Failed to start $($service.Name): $_"
        }
    }
    Write-Host "Service restart complete."
}
