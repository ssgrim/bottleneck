# Bottleneck.Thermal.ps1
# Uses WMI and OpenHardwareMonitor to get CPU, GPU, and disk temperatures

function Get-BottleneckCPUTemp {
    $cpuTemp = $null
    try {
        $wmi = Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" -ErrorAction SilentlyContinue
        if ($wmi) {
            $cpuTemp = [math]::Round(($wmi.CurrentTemperature - 2732) / 10, 1)
        }
    } catch {}
    return $cpuTemp
}

function Get-BottleneckGPUTemp {
    $gpuTemp = $null
    try {
        $ohm = Get-WmiObject -Namespace root\OpenHardwareMonitor -Class Sensor -ErrorAction SilentlyContinue
        if ($ohm) {
            $gpuTemp = ($ohm | Where-Object { $_.Name -like '*GPU Core*' -and $_.SensorType -eq 'Temperature' }).Value
        }
    } catch {}
    return $gpuTemp
}

function Get-BottleneckDiskTemp {
    $diskTemp = $null
    try {
        $ohm = Get-WmiObject -Namespace root\OpenHardwareMonitor -Class Sensor -ErrorAction SilentlyContinue
        if ($ohm) {
            $diskTemp = ($ohm | Where-Object { $_.Name -like '*HDD*' -and $_.SensorType -eq 'Temperature' }).Value
        }
    } catch {}
    return $diskTemp
}

function Test-BottleneckThermal {
    $cpu = Get-BottleneckCPUTemp
    $gpu = Get-BottleneckGPUTemp
    $disk = Get-BottleneckDiskTemp
    $impact = 2
    $confidence = 8
    $effort = 2
    $priority = 1
    $evidence = "CPU: $cpu°C, GPU: $gpu°C, Disk: $disk°C"
    $fixId = ''
    $msg = "Thermal status: CPU=$cpu°C, GPU=$gpu°C, Disk=$disk°C"
    if ($cpu -gt 85 -or $gpu -gt 85 -or $disk -gt 55) {
        $impact = 9
        $msg = "High temperature detected! CPU=$cpu°C, GPU=$gpu°C, Disk=$disk°C"
    }
    return New-BottleneckResult -Id 'Thermal' -Tier 'Standard' -Category 'Thermal' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}
