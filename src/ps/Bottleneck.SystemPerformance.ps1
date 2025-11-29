# Bottleneck.SystemPerformance.ps1
# Real-time system performance monitoring: CPU/Memory utilization, fan speed, system temp, stuck processes

function Test-BottleneckCPUUtilization {
    <#
    .SYNOPSIS
    Monitors CPU utilization over time to detect sustained high usage patterns
    #>
    try {
        # Sample CPU over 5 seconds to get accurate reading
        $samples = @()
        for ($i = 0; $i -lt 5; $i++) {
            $cpu = Get-CimInstance Win32_Processor
            $samples += $cpu.LoadPercentage
            if ($i -lt 4) { Start-Sleep -Seconds 1 }
        }
        
        $avgLoad = [math]::Round(($samples | Measure-Object -Average).Average, 1)
        $maxLoad = ($samples | Measure-Object -Maximum).Maximum
        $minLoad = ($samples | Measure-Object -Minimum).Minimum
        
        # Get process causing high CPU
        $topProcs = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | 
            ForEach-Object { "$($_.ProcessName) ($([math]::Round($_.CPU, 1))s)" }
        
        $impact = if ($avgLoad -gt 90) { 9 } elseif ($avgLoad -gt 80) { 7 } elseif ($avgLoad -gt 70) { 5 } else { 2 }
        $confidence = 9
        $effort = 2
        $priority = if ($avgLoad -gt 80) { 1 } else { 3 }
        $evidence = "5s avg: ${avgLoad}%, range: ${minLoad}%-${maxLoad}%, Top: $($topProcs[0..2] -join ', ')"
        $fixId = if ($avgLoad -gt 80) { 'HighCPUProcess' } else { '' }
        $msg = if ($avgLoad -gt 90) { 
            "Critical CPU usage (${avgLoad}%). Top process: $($topProcs[0])"
        } elseif ($avgLoad -gt 80) {
            "High CPU usage (${avgLoad}%). Investigation needed."
        } elseif ($avgLoad -gt 70) {
            "Elevated CPU usage (${avgLoad}%)."
        } else {
            "CPU utilization normal (${avgLoad}%)."
        }
        
        return New-BottleneckResult -Id 'CPUUtilization' -Tier 'Standard' -Category 'CPU Performance' `
            -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority `
            -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        Write-BottleneckLog "CPU utilization check failed: $_" -Level "ERROR" -CheckId "CPUUtilization"
        return $null
    }
}

function Test-BottleneckMemoryUtilization {
    <#
    .SYNOPSIS
    Monitors memory utilization and identifies memory-hungry processes
    #>
    try {
        $os = Get-CachedCimInstance -ClassName Win32_OperatingSystem
        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedGB = $totalGB - $freeGB
        $usedPercent = [math]::Round(($usedGB / $totalGB) * 100, 1)
        
        # Get committed memory (includes page file)
        $committed = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
        $commitLimit = if ($committed) { [math]::Round($committed.CommitLimit / 1MB, 2) } else { 0 }
        $commitUsed = if ($committed) { [math]::Round($committed.CommittedBytes / 1MB, 2) } else { 0 }
        
        # Get memory-hungry processes
        $topProcs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
            ForEach-Object { "$($_.ProcessName) ($([math]::Round($_.WorkingSet64 / 1GB, 2))GB)" }
        
        # Check for memory leaks (high page faults)
        $pageFaults = if ($committed) { $committed.PageFaultsPersec } else { 0 }
        
        $impact = if ($usedPercent -gt 95) { 9 } elseif ($usedPercent -gt 90) { 8 } elseif ($usedPercent -gt 80) { 6 } else { 2 }
        $confidence = 9
        $effort = 2
        $priority = if ($usedPercent -gt 90) { 1 } else { 3 }
        $evidence = "Used: ${usedGB}/${totalGB}GB (${usedPercent}%), Committed: ${commitUsed}/${commitLimit}GB, Top: $($topProcs[0..2] -join ', ')"
        $fixId = if ($usedPercent -gt 90) { 'HighMemoryUsage' } else { '' }
        $msg = if ($usedPercent -gt 95) {
            "Critical memory pressure (${usedPercent}%). Top: $($topProcs[0])"
        } elseif ($usedPercent -gt 90) {
            "High memory usage (${usedPercent}%). Close unnecessary apps."
        } elseif ($usedPercent -gt 80) {
            "Elevated memory usage (${usedPercent}%)."
        } else {
            "Memory utilization normal (${usedPercent}%)."
        }
        
        return New-BottleneckResult -Id 'MemoryUtilization' -Tier 'Standard' -Category 'Memory Performance' `
            -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority `
            -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        Write-BottleneckLog "Memory utilization check failed: $_" -Level "ERROR" -CheckId "MemoryUtilization"
        return $null
    }
}

function Test-BottleneckFanSpeed {
    <#
    .SYNOPSIS
    Monitors fan speeds to detect cooling issues
    #>
    try {
        $fanData = @()
        $fanIssues = @()
        
        # Try WMI sensors (works on some systems)
        $fans = Get-CimInstance -Namespace root/cimv2 -ClassName Win32_Fan -ErrorAction SilentlyContinue
        if ($fans) {
            foreach ($fan in $fans) {
                $status = $fan.Status
                $active = $fan.ActiveCooling
                $fanData += "Fan: $($fan.Name), Status: $status, Active: $active"
                if ($status -ne 'OK') {
                    $fanIssues += $fan.Name
                }
            }
        }
        
        # Try OpenHardwareMonitor namespace (if installed)
        try {
            $ohmFans = Get-CimInstance -Namespace root/OpenHardwareMonitor -ClassName Sensor -ErrorAction SilentlyContinue |
                Where-Object { $_.SensorType -eq 'Fan' }
            if ($ohmFans) {
                foreach ($fan in $ohmFans) {
                    $rpm = $fan.Value
                    $fanData += "$($fan.Name): ${rpm} RPM"
                    # Typical fans should be >500 RPM under load
                    if ($rpm -lt 500 -and $rpm -gt 0) {
                        $fanIssues += "$($fan.Name) (${rpm} RPM)"
                    }
                }
            }
        } catch {}
        
        # Check via performance counters
        try {
            $thermalZone = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
            if ($thermalZone) {
                foreach ($zone in $thermalZone) {
                    $temp = [math]::Round(($zone.CurrentTemperature - 2732) / 10, 1)
                    $fanData += "Thermal Zone $($zone.InstanceName): ${temp}°C"
                    if ($temp -gt 85) {
                        $fanIssues += "Zone $($zone.InstanceName) overheating (${temp}°C)"
                    }
                }
            }
        } catch {}
        
        $impact = if ($fanIssues.Count -gt 0) { 8 } elseif ($fanData.Count -eq 0) { 3 } else { 2 }
        $confidence = if ($fanData.Count -gt 0) { 7 } else { 4 }
        $effort = 2
        $priority = if ($fanIssues.Count -gt 0) { 2 } else { 4 }
        $evidence = if ($fanData.Count -gt 0) { $fanData -join '; ' } else { 'No fan sensors detected (common on laptops without monitoring software)' }
        $fixId = if ($fanIssues.Count -gt 0) { 'FanIssue' } else { '' }
        $msg = if ($fanIssues.Count -gt 0) {
            "Fan issues detected: $($fanIssues -join ', '). Check cooling system."
        } elseif ($fanData.Count -eq 0) {
            "No fan sensors available. Install HWiNFO or OpenHardwareMonitor for monitoring."
        } else {
            "Fan speeds normal. $($fanData.Count) sensor(s) detected."
        }
        
        return New-BottleneckResult -Id 'FanSpeed' -Tier 'Standard' -Category 'Cooling System' `
            -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority `
            -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckSystemTemperature {
    <#
    .SYNOPSIS
    Comprehensive system temperature monitoring beyond just CPU
    #>
    try {
        $temps = @{}
        $hotspots = @()
        
        # CPU temperature
        try {
            $cpu = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
            if ($cpu) {
                $cpuTemp = [math]::Round(($cpu[0].CurrentTemperature - 2732) / 10, 1)
                $temps['CPU'] = $cpuTemp
                if ($cpuTemp -gt 85) { $hotspots += "CPU: ${cpuTemp}°C" }
            }
        } catch {}
        
        # Motherboard/System temperature via OpenHardwareMonitor
        try {
            $ohm = Get-CimInstance -Namespace root/OpenHardwareMonitor -ClassName Sensor -ErrorAction SilentlyContinue
            if ($ohm) {
                $systemTemps = $ohm | Where-Object { $_.SensorType -eq 'Temperature' }
                foreach ($sensor in $systemTemps) {
                    $name = $sensor.Name
                    $value = [math]::Round($sensor.Value, 1)
                    
                    if ($name -like '*GPU*') {
                        $temps['GPU'] = $value
                        if ($value -gt 85) { $hotspots += "GPU: ${value}°C" }
                    } elseif ($name -like '*Motherboard*' -or $name -like '*System*') {
                        $temps['Motherboard'] = $value
                        if ($value -gt 70) { $hotspots += "Motherboard: ${value}°C" }
                    } elseif ($name -like '*HDD*' -or $name -like '*SSD*') {
                        $temps['Storage'] = $value
                        if ($value -gt 55) { $hotspots += "Storage: ${value}°C" }
                    }
                }
            }
        } catch {}
        
        # SMART disk temperature
        try {
            $smart = Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_ATAPISmartData -ErrorAction SilentlyContinue
            if ($smart) {
                # Temperature is in SMART attribute 194 (0xC2)
                foreach ($disk in $smart) {
                    # This is complex SMART parsing - simplified check
                    if (-not $temps.ContainsKey('Storage')) {
                        $temps['Storage'] = 'N/A'
                    }
                }
            }
        } catch {}
        
        $impact = if ($hotspots.Count -gt 2) { 9 } elseif ($hotspots.Count -gt 0) { 7 } elseif ($temps.Count -eq 0) { 3 } else { 2 }
        $confidence = if ($temps.Count -gt 2) { 8 } elseif ($temps.Count -gt 0) { 6 } else { 3 }
        $effort = 2
        $priority = if ($hotspots.Count -gt 0) { 1 } else { 4 }
        
        $tempSummary = ($temps.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)°C" }) -join ', '
        $evidence = if ($tempSummary) { $tempSummary } else { 'No temperature sensors detected' }
        $fixId = if ($hotspots.Count -gt 0) { 'HighTemperature' } else { '' }
        $msg = if ($hotspots.Count -gt 2) {
            "Multiple overheating components: $($hotspots -join ', '). Immediate cooling attention needed!"
        } elseif ($hotspots.Count -gt 0) {
            "Temperature warning: $($hotspots -join ', '). Check cooling."
        } elseif ($temps.Count -eq 0) {
            "No temperature sensors available. Install HWiNFO or OpenHardwareMonitor for monitoring."
        } else {
            "System temperatures normal. $($temps.Count) sensor(s) monitored."
        }
        
        return New-BottleneckResult -Id 'SystemTemperature' -Tier 'Standard' -Category 'Thermal Management' `
            -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority `
            -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckStuckProcesses {
    <#
    .SYNOPSIS
    Detects stuck, zombie, or hung processes that are consuming resources
    #>
    try {
        $stuckProcs = @()
        $zombieProcs = @()
        $hungProcs = @()
        
        # Get all processes with CPU time and handle counts
        $allProcs = Get-Process | Where-Object { $_.Id -ne 0 -and $_.Id -ne 4 }
        
        foreach ($proc in $allProcs) {
            try {
                # Check for high handle count (possible leak)
                if ($proc.HandleCount -gt 10000) {
                    $stuckProcs += "$($proc.ProcessName) (PID: $($proc.Id), $($proc.HandleCount) handles)"
                }
                
                # Check for zombie processes (no CPU time but still running for >1 hour)
                $runtime = (Get-Date) - $proc.StartTime
                if ($runtime.TotalHours -gt 1 -and $proc.CPU -lt 1) {
                    # Check if responding
                    if (-not $proc.Responding) {
                        $zombieProcs += "$($proc.ProcessName) (PID: $($proc.Id), not responding for $([math]::Round($runtime.TotalHours, 1))h)"
                    }
                }
                
                # Check for hung processes (not responding)
                if (-not $proc.Responding -and $proc.MainWindowHandle -ne 0) {
                    $hungProcs += "$($proc.ProcessName) (PID: $($proc.Id))"
                }
                
            } catch {
                # Process may have exited during enumeration
            }
        }
        
        # Check for processes with excessive threads
        $threadHogs = $allProcs | Where-Object { $_.Threads.Count -gt 200 } |
            ForEach-Object { "$($_.ProcessName) ($($_.Threads.Count) threads)" }
        
        $totalIssues = $stuckProcs.Count + $zombieProcs.Count + $hungProcs.Count
        
        $impact = if ($totalIssues -gt 10) { 8 } elseif ($totalIssues -gt 5) { 6 } elseif ($totalIssues -gt 0) { 4 } else { 2 }
        $confidence = 8
        $effort = 1
        $priority = if ($totalIssues -gt 5) { 2 } else { 4 }
        
        $evidenceParts = @()
        if ($stuckProcs.Count -gt 0) { $evidenceParts += "Stuck: $($stuckProcs.Count)" }
        if ($zombieProcs.Count -gt 0) { $evidenceParts += "Zombie: $($zombieProcs.Count)" }
        if ($hungProcs.Count -gt 0) { $evidenceParts += "Hung: $($hungProcs.Count)" }
        if ($threadHogs.Count -gt 0) { $evidenceParts += "Thread hogs: $($threadHogs.Count)" }
        
        $evidence = if ($evidenceParts.Count -gt 0) { 
            "$($evidenceParts -join ', '). Examples: $($stuckProcs[0..2] -join '; ')"
        } else {
            "All processes healthy. $($allProcs.Count) processes scanned."
        }
        
        $fixId = if ($totalIssues -gt 0) { 'StuckProcess' } else { '' }
        $msg = if ($totalIssues -gt 10) {
            "Severe process issues detected. $totalIssues stuck/hung/zombie processes. System restart recommended."
        } elseif ($totalIssues -gt 5) {
            "Multiple problem processes: $totalIssues issues. Consider ending unresponsive tasks."
        } elseif ($totalIssues -gt 0) {
            "$totalIssues problem process(es) detected. Review Task Manager."
        } else {
            "No stuck or hung processes detected."
        }
        
        return New-BottleneckResult -Id 'StuckProcesses' -Tier 'Standard' -Category 'Process Health' `
            -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority `
            -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckJavaHeap {
    <#
    .SYNOPSIS
    Monitors Java processes for heap utilization and memory issues
    #>
    try {
        $javaProcs = Get-Process | Where-Object { $_.ProcessName -like '*java*' -or $_.ProcessName -like '*javaw*' }
        
        if ($javaProcs.Count -eq 0) {
            return New-BottleneckResult -Id 'JavaHeap' -Tier 'Deep' -Category 'Java Performance' `
                -Impact 1 -Confidence 10 -Effort 1 -Priority 5 `
                -Evidence "No Java processes running" -FixId '' `
                -Message "No Java processes detected."
        }
        
        $javaIssues = @()
        $heapData = @()
        
        foreach ($proc in $javaProcs) {
            try {
                $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 0)
                $cpuTime = [math]::Round($proc.CPU, 1)
                $threads = $proc.Threads.Count
                
                $heapData += "$($proc.ProcessName) (PID: $($proc.Id)): ${memMB}MB, ${cpuTime}s CPU, $threads threads"
                
                # High memory (>2GB) could indicate heap issues
                if ($memMB -gt 2048) {
                    $javaIssues += "$($proc.ProcessName) using ${memMB}MB (possible heap leak)"
                }
                
                # Excessive threads (>500) can indicate issues
                if ($threads -gt 500) {
                    $javaIssues += "$($proc.ProcessName) has $threads threads (possible thread leak)"
                }
                
                # Try to get JVM heap stats via command line args
                try {
                    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
                    if ($cmdLine -match '-Xmx(\d+)([mMgG])') {
                        $maxHeap = $matches[1]
                        $unit = $matches[2].ToUpper()
                        $maxHeapMB = if ($unit -eq 'G') { $maxHeap * 1024 } else { $maxHeap }
                        
                        $heapUsagePercent = [math]::Round(($memMB / $maxHeapMB) * 100, 1)
                        $heapData[-1] += ", Max heap: ${maxHeapMB}MB, Usage: ${heapUsagePercent}%"
                        
                        if ($heapUsagePercent -gt 90) {
                            $javaIssues += "$($proc.ProcessName) heap ${heapUsagePercent}% full (near limit)"
                        }
                    }
                } catch {}
                
            } catch {
                # Process may have exited
            }
        }
        
        $impact = if ($javaIssues.Count -gt 2) { 7 } elseif ($javaIssues.Count -gt 0) { 5 } else { 2 }
        $confidence = 7
        $effort = 3
        $priority = if ($javaIssues.Count -gt 0) { 3 } else { 5 }
        $evidence = "$($javaProcs.Count) Java process(es): $($heapData -join ' | ')"
        $fixId = if ($javaIssues.Count -gt 0) { 'JavaHeapIssue' } else { '' }
        $msg = if ($javaIssues.Count -gt 2) {
            "Multiple Java issues: $($javaIssues -join '; '). Review heap settings."
        } elseif ($javaIssues.Count -gt 0) {
            "Java performance issues: $($javaIssues -join '; ')"
        } else {
            "$($javaProcs.Count) Java process(es) running normally."
        }
        
        return New-BottleneckResult -Id 'JavaHeap' -Tier 'Deep' -Category 'Java Performance' `
            -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority `
            -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}
