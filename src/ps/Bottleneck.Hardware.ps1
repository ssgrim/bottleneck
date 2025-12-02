# Bottleneck.Hardware.ps1
# Consolidated hardware health checks: Memory, Battery, CPU Throttling, Disk, and Thermal

# ========== Memory Health ==========
function Test-BottleneckMemoryHealth {
    try {
        # Check for memory errors in event log
        $memErrors = Get-SafeWinEvent -FilterHashtable @{LogName = 'System'; Id = 1101, 1001; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 100
        $errorCount = if ($memErrors) { $memErrors.Count } else { 0 }

        # Check for ECC errors if available
        $eccErrors = 0
        try {
            $memConfig = Get-WmiObject -Class Win32_PhysicalMemory
            foreach ($mem in $memConfig) {
                if ($mem.DataWidth -ne $mem.TotalWidth) {
                    # ECC memory detected, check for errors
                    # Note: Most consumer systems don't expose detailed ECC stats
                }
            }
        }
        catch {}

        $impact = if ($errorCount -gt 5) { 8 } elseif ($errorCount -gt 0) { 5 } else { 2 }
        $confidence = 7
        $effort = 3
        $priority = 2
        $evidence = "Memory errors (7 days): $errorCount"
        $fixId = if ($errorCount -gt 5) { 'MemoryDiagnostic' } else { '' }
        $msg = if ($errorCount -gt 5) { 'Multiple memory errors detected. Run memory diagnostic.' } elseif ($errorCount -gt 0) { 'Some memory errors found.' } else { 'No memory errors detected.' }

        return New-BottleneckResult -Id 'MemoryHealth' -Tier 'Standard' -Category 'Memory Health' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    }
    catch {
        return $null
    }
}

# ========== Battery Health ==========
function Test-BottleneckBattery {
    try {
        $battery = Get-WmiObject -Class Win32_Battery -ErrorAction SilentlyContinue
        if (-not $battery) {
            # No battery detected (desktop)
            return $null
        }

        $designCapacity = $battery.DesignCapacity
        $fullChargeCapacity = $battery.FullChargeCapacity
        $wear = 0
        if ($designCapacity -gt 0) {
            $wear = [math]::Round((($designCapacity - $fullChargeCapacity) / $designCapacity) * 100, 1)
        }

        $cycles = 0
        try {
            $batteryReport = powercfg /batteryreport /output "$env:TEMP\battery-report.html" /xml 2>&1
            if (Test-Path "$env:TEMP\battery-report.xml") {
                [xml]$report = Get-Content "$env:TEMP\battery-report.xml"
                $cycles = $report.BatteryReport.Batteries.Battery.CycleCount
            }
        }
        catch {}

        $impact = if ($wear -gt 30) { 7 } elseif ($wear -gt 20) { 5 } else { 2 }
        $confidence = 8
        $effort = 4
        $priority = 3
        $evidence = "Battery wear: $wear%, Cycles: $cycles, Capacity: $fullChargeCapacity / $designCapacity"
        $fixId = ''
        $msg = if ($wear -gt 30) { 'Battery significantly degraded. Consider replacement.' } elseif ($wear -gt 20) { 'Battery showing wear.' } else { 'Battery health OK.' }

        return New-BottleneckResult -Id 'Battery' -Tier 'Standard' -Category 'Battery' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    }
    catch {
        return $null
    }
}

# ========== CPU Throttling ==========
function Test-BottleneckCPUThrottle {
    try {
        $cpu = Get-CachedCimInstance -ClassName Win32_Processor
        $maxClockSpeed = $cpu.MaxClockSpeed
        $currentClockSpeed = $cpu.CurrentClockSpeed

        # Calculate throttle percentage
        $throttlePercent = 0
        if ($maxClockSpeed -gt 0) {
            $throttlePercent = [math]::Round((($maxClockSpeed - $currentClockSpeed) / $maxClockSpeed) * 100, 1)
        }

        # Check power plan
        $powerPlan = (powercfg /GetActiveScheme) 2>&1
        $isPowerSaver = $powerPlan -match 'Power saver'

        # Check thermal throttling
        $thermalThrottle = $false
        try {
            $perfCounter = Get-Counter '\Processor Information(_Total)\% Processor Performance' -ErrorAction SilentlyContinue
            if ($perfCounter.CounterSamples[0].CookedValue -lt 80) {
                $thermalThrottle = $true
            }
        }
        catch {}

        # Detect if this is a laptop (battery present)
        $isLaptop = $false
        try {
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            $isLaptop = ($null -ne $battery)
        } catch {}
        
        # Adjust impact based on system type and actual throttling
        $impact = if ($throttlePercent -gt 30 -or $thermalThrottle) { 
            7 
        } elseif ($throttlePercent -gt 20 -and $isLaptop) { 
            4  # More tolerant for laptops
        } elseif ($throttlePercent -gt 15) { 
            5 
        } else { 
            2 
        }
        $confidence = 7
        $effort = 2
        $priority = 3
        $evidence = "Clock: $currentClockSpeed / $maxClockSpeed MHz (${throttlePercent}% throttle), Thermal: $thermalThrottle"
        $fixId = if ($isPowerSaver) { 'PowerPlanHighPerformance' } else { '' }
        $msg = if ($throttlePercent -gt 30 -or $thermalThrottle) { 
            'Significant CPU throttling detected. Check thermals or power settings.' 
        } elseif ($throttlePercent -gt 20) { 
            if ($isLaptop) { 
                'Moderate CPU throttling (normal for laptops on battery).' 
            } else { 
                'Moderate CPU throttling. Consider checking thermals.' 
            }
        } elseif ($throttlePercent -gt 15) { 
            'Minor CPU throttling detected.' 
        } else { 
            'CPU running at expected speed.' 
        }

        return New-BottleneckResult -Id 'CPUThrottle' -Tier 'Standard' -Category 'CPU Throttling' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    }
    catch {
        return $null
    }
}

# ========== Disk Fragmentation ==========
function Test-BottleneckDiskFragmentation {
    try {
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -eq 'C' }
        $isDiskSSD = $false

        # Check if it's an SSD
        $physicalDisks = Get-PhysicalDisk
        foreach ($disk in $physicalDisks) {
            if ($disk.MediaType -eq 'SSD') {
                $isDiskSSD = $true
                break
            }
        }

        if ($isDiskSSD) {
            # SSDs don't need defrag
            return New-BottleneckResult -Id 'DiskFrag' -Tier 'Standard' -Category 'Disk Fragmentation' -Impact 2 -Confidence 9 -Effort 1 -Priority 5 -Evidence "SSD detected" -FixId '' -Message 'SSD detected - defragmentation not needed.'
        }

        # For HDDs, check fragmentation
        $defrag = Optimize-Volume -DriveLetter C -Analyze -Verbose 4>&1
        $fragPercent = 0
        if ($defrag -match '(\d+)%') {
            $fragPercent = [int]$matches[1]
        }

        $impact = if ($fragPercent -gt 20) { 6 } elseif ($fragPercent -gt 10) { 4 } else { 2 }
        $confidence = 8
        $effort = 3
        $priority = 4
        $evidence = "Fragmentation: $fragPercent%"
        $fixId = if ($fragPercent -gt 10) { 'Defragment' } else { '' }
        $msg = if ($fragPercent -gt 20) { 'High disk fragmentation detected.' } elseif ($fragPercent -gt 10) { 'Moderate fragmentation.' } else { 'Disk fragmentation low.' }

        return New-BottleneckResult -Id 'DiskFrag' -Tier 'Standard' -Category 'Disk Fragmentation' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    }
    catch {
        return $null
    }
}

# ========== Thermal Monitoring ==========
function Get-BottleneckCPUTemp {
    $cpuTemp = $null
    try {
        $wmi = Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" -ErrorAction SilentlyContinue
        if ($wmi) {
            $cpuTemp = [math]::Round(($wmi.CurrentTemperature - 2732) / 10, 1)
        }
    }
    catch {}
    return $cpuTemp
}

function Get-BottleneckGPUTemp {
    $gpuTemp = $null
    try {
        $ohm = Get-WmiObject -Namespace root\OpenHardwareMonitor -Class Sensor -ErrorAction SilentlyContinue
        if ($ohm) {
            $gpuTemp = ($ohm | Where-Object { $_.Name -like '*GPU Core*' -and $_.SensorType -eq 'Temperature' }).Value
        }
    }
    catch {}
    return $gpuTemp
}

function Get-BottleneckDiskTemp {
    $diskTemp = $null
    try {
        $ohm = Get-WmiObject -Namespace root\OpenHardwareMonitor -Class Sensor -ErrorAction SilentlyContinue
        if ($ohm) {
            $diskTemp = ($ohm | Where-Object { $_.Name -like '*HDD*' -and $_.SensorType -eq 'Temperature' }).Value
        }
    }
    catch {}
    return $diskTemp
}

function Test-BottleneckThermal {
    $cpu = Get-BottleneckCPUTemp
    $gpu = Get-BottleneckGPUTemp
    $disk = Get-BottleneckDiskTemp
    
    # Build readable display values
    $cpuDisplay = if ($cpu) { "${cpu}°C" } else { "no sensor" }
    $gpuDisplay = if ($gpu) { "${gpu}°C" } else { "no sensor" }
    $diskDisplay = if ($disk) { "${disk}°C" } else { "no sensor" }
    
    $impact = 2
    $confidence = if ($cpu -or $gpu -or $disk) { 8 } else { 3 }
    $effort = 2
    $priority = 1
    $evidence = "CPU: $cpuDisplay, GPU: $gpuDisplay, Disk: $diskDisplay"
    $fixId = ''
    $msg = if (-not $cpu -and -not $gpu -and -not $disk) {
        "No thermal sensors detected. Install OpenHardwareMonitor for temperature monitoring."
    } else {
        "Thermal status: CPU=$cpuDisplay, GPU=$gpuDisplay, Disk=$diskDisplay"
    }
    if ($cpu -gt 85 -or $gpu -gt 85 -or $disk -gt 55) {
        $impact = 9
        $msg = "High temperature detected! CPU=$cpu°C, GPU=$gpu°C, Disk=$disk°C"
    }
    return New-BottleneckResult -Id 'Thermal' -Tier 'Standard' -Category 'Thermal' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}
