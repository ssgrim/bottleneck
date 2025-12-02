
# Bottleneck.Fixes.ps1
function Invoke-BottleneckFixCleanup {
    [CmdletBinding()]
    param([switch]$Confirm, [switch]$Deep)
    
    if ($Confirm) {
        Write-Host "Creating restore point..."
        Checkpoint-Computer -Description "Bottleneck Cleanup" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
    }
    
    $freedSpace = 0
    
    # Clean temp files
    Write-Host "Cleaning temp files..." -ForegroundColor Cyan
    try {
        $tempSize = (Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        $freedSpace += $tempSize
        Write-Host "  Cleaned temp files: $([math]::Round($tempSize, 2)) GB" -ForegroundColor Green
    } catch {
        Write-Warning "  Failed to clean temp files: $_"
    }
    
    # Clean Windows temp
    Write-Host "Cleaning Windows temp..." -ForegroundColor Cyan
    try {
        $winTempSize = (Get-ChildItem C:\Windows\Temp -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB
        Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        $freedSpace += $winTempSize
        Write-Host "  Cleaned Windows temp: $([math]::Round($winTempSize, 2)) GB" -ForegroundColor Green
    } catch {
        Write-Warning "  Failed to clean Windows temp: $_"
    }
    
    if ($Deep) {
        # Clean Windows Update cache
        Write-Host "Cleaning Windows Update cache..." -ForegroundColor Cyan
        try {
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            $updateSize = (Get-ChildItem C:\Windows\SoftwareDistribution\Download -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB
            Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service wuauserv -ErrorAction SilentlyContinue
            $freedSpace += $updateSize
            Write-Host "  Cleaned update cache: $([math]::Round($updateSize, 2)) GB" -ForegroundColor Green
        } catch {
            Write-Warning "  Failed to clean update cache: $_"
        }
        
        # Run Disk Cleanup
        Write-Host "Running Disk Cleanup utility..." -ForegroundColor Cyan
        try {
            cleanmgr /sagerun:1 | Out-Null
            Write-Host "  Disk Cleanup completed" -ForegroundColor Green
        } catch {
            Write-Warning "  Disk Cleanup failed: $_"
        }
    }
    
    Write-Host "`nTotal space freed: $([math]::Round($freedSpace, 2)) GB" -ForegroundColor Green
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
    param([switch]$Auto)
    
    # Detect system type
    $isLaptop = $false
    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        $isLaptop = ($null -ne $battery)
    } catch {}
    
    if ($Auto -and $isLaptop) {
        Write-Host "Laptop detected. Setting to Balanced for battery life..." -ForegroundColor Cyan
        $guid = (powercfg /L | Select-String "Balanced" | ForEach-Object { $_.Line.Split()[3] })
        if ($guid) { 
            powercfg /S $guid 
            Write-Host "Power plan set to Balanced (recommended for laptops)" -ForegroundColor Green
        }
    } else {
        Write-Host "Setting power plan to High Performance..." -ForegroundColor Cyan
        $guid = (powercfg /L | Select-String "High performance" | ForEach-Object { $_.Line.Split()[3] })
        if ($guid) { 
            powercfg /S $guid 
            Write-Host "Power plan set to High Performance" -ForegroundColor Green
            if ($isLaptop) {
                Write-Warning "Note: High Performance on laptop will reduce battery life"
            }
        } else {
            Write-Warning "High Performance plan not found. Creating custom plan..."
            # Create high performance plan if it doesn't exist
            $output = powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
            if ($output -match '\{([a-f0-9\-]+)\}') {
                $newGuid = $matches[1]
                powercfg /S $newGuid
                Write-Host "Custom High Performance plan created and activated" -ForegroundColor Green
            }
        }
    }
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
