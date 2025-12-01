# Bottleneck.DeepScan.ps1
# Advanced deep-tier diagnostic checks

function Test-BottleneckETW {
    try {
        # ETW analysis requires elevated permissions and is resource-intensive
        # Check if running as admin
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            return New-BottleneckResult -Id 'ETW' -Tier 'Deep' -Category 'ETW Tracing' -Impact 2 -Confidence 5 -Effort 5 -Priority 9 -Evidence 'Requires administrator privileges' -FixId '' -Message 'ETW analysis requires admin rights.'
        }
        
        # Collect performance counter data for CPU context switches and interrupts
        $cpuContextSwitches = (Get-Counter '\System\Context Switches/sec' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        $cpuInterrupts = (Get-Counter '\Processor(_Total)\Interrupts/sec' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        
        # High context switches indicate thread contention
        $contextSwitchesPerCore = $cpuContextSwitches / $env:NUMBER_OF_PROCESSORS
        
        # Check for kernel time
        $kernelTime = (Get-Counter '\Processor(_Total)\% Privileged Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        
        $issues = @()
        if ($contextSwitchesPerCore -gt 5000) {
            $issues += "High context switches ($([math]::Round($contextSwitchesPerCore)) per core/sec)"
        }
        if ($cpuInterrupts -gt 5000) {
            $issues += "High interrupt rate ($([math]::Round($cpuInterrupts))/sec)"
        }
        if ($kernelTime -gt 30) {
            $issues += "High kernel time ($([math]::Round($kernelTime))%)"
        }
        
        $impact = if ($issues.Count -gt 2) { 7 } elseif ($issues.Count -gt 0) { 5 } else { 2 }
        $confidence = 8
        $effort = 5
        $priority = 7
        $evidence = if ($issues.Count -gt 0) { 
            $issues -join '; ' 
        } else { 
            "Context switches: $([math]::Round($contextSwitchesPerCore))/core/sec, Interrupts: $([math]::Round($cpuInterrupts))/sec, Kernel: $([math]::Round($kernelTime))%"
        }
        $fixId = ''
        $msg = if ($issues.Count -gt 2) { 
            'Multiple system performance issues detected.' 
        } elseif ($issues.Count -gt 0) { 
            'Some system performance issues found.' 
        } else { 
            'System performance metrics are normal.' 
        }
        
        return New-BottleneckResult -Id 'ETW' -Tier 'Deep' -Category 'ETW Tracing' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckFullSMART {
    try {
        # Get detailed SMART attributes
        $smart = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_ATAPISmartData -ErrorAction SilentlyContinue
        
        if (-not $smart) {
            return New-BottleneckResult -Id 'FullSMART' -Tier 'Deep' -Category 'Full SMART' -Impact 2 -Confidence 5 -Effort 4 -Priority 8 -Evidence 'SMART data not available' -FixId '' -Message 'Unable to read detailed SMART data.'
        }
        
        # Get failure prediction
        $failPredict = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        
        # Get physical disk info
        $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        $criticalIssues = @()
        $warnings = @()
        
        foreach ($disk in $disks) {
            # Check health status
            if ($disk.HealthStatus -ne 'Healthy') {
                $criticalIssues += "$($disk.FriendlyName): $($disk.HealthStatus)"
            }
            
            # Check operational status
            if ($disk.OperationalStatus -ne 'OK') {
                $warnings += "$($disk.FriendlyName): $($disk.OperationalStatus)"
            }
            
            # Check for wear (SSD specific)
            if ($disk.MediaType -eq 'SSD') {
                # Approximate wear indicator from usage
                $usage = $disk.Usage
                if ($usage -eq 'Retired') {
                    $criticalIssues += "$($disk.FriendlyName): Drive retired"
                }
            }
        }
        
        # Check for predicted failures
        $predictedFailures = $failPredict | Where-Object { $_.PredictFailure -eq $true }
        if ($predictedFailures) {
            foreach ($fail in $predictedFailures) {
                $criticalIssues += "Drive failure predicted"
            }
        }
        
        $impact = if ($criticalIssues.Count -gt 0) { 10 } elseif ($warnings.Count -gt 1) { 6 } else { 2 }
        $confidence = 9
        $effort = 4
        $priority = 1
        $evidence = "Disks: $($disks.Count), Critical: $($criticalIssues.Count), Warnings: $($warnings.Count)"
        if ($criticalIssues.Count -gt 0) {
            $evidence += " - CRITICAL: $($criticalIssues -join '; ')"
        }
        $fixId = ''
        $msg = if ($criticalIssues.Count -gt 0) { 
            'CRITICAL: Disk failure imminent - backup immediately!' 
        } elseif ($warnings.Count -gt 1) { 
            'Disk health warnings detected.' 
        } else { 
            'All disks are healthy.' 
        }
        
        return New-BottleneckResult -Id 'FullSMART' -Tier 'Deep' -Category 'Full SMART' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckSFC {
    try {
        # Check if running as admin
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            return New-BottleneckResult -Id 'SFC' -Tier 'Deep' -Category 'System Integrity' -Impact 2 -Confidence 5 -Effort 5 -Priority 9 -Evidence 'Requires administrator privileges' -FixId '' -Message 'System integrity check requires admin rights.'
        }
        
        # Check CBS log for recent SFC/DISM results
        $cbsLog = "$env:SystemRoot\Logs\CBS\CBS.log"
        $sfcResults = @()
        
        if (Test-Path $cbsLog) {
            # Get recent SFC scan results from log
            $recentLines = Get-Content $cbsLog -Tail 1000 -ErrorAction SilentlyContinue | Select-String 'corrupt|violation|repair'
            $sfcResults = $recentLines | Select-Object -First 10
        }
        
        # Check DISM health
        $dismHealth = $null
        try {
            # This is a quick check - full scan would take minutes
            $dismResult = DISM /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
            if ($dismResult -match 'repairable|corrupt') {
                $dismHealth = 'Issues detected'
            } elseif ($dismResult -match 'healthy|no component store corruption') {
                $dismHealth = 'Healthy'
            }
        } catch {
            $dismHealth = 'Unable to check'
        }
        
        $impact = if ($sfcResults.Count -gt 5 -or $dismHealth -eq 'Issues detected') { 8 } elseif ($sfcResults.Count -gt 0) { 5 } else { 2 }
        $confidence = 7
        $effort = 5
        $priority = 3
        $evidence = "CBS log entries: $($sfcResults.Count), DISM health: $dismHealth"
        $fixId = ''
        $msg = if ($impact -ge 8) { 
            'System file corruption detected - run full SFC/DISM repair.' 
        } elseif ($impact -ge 5) { 
            'Possible system file issues found.' 
        } else { 
            'System integrity appears normal.' 
        }
        
        return New-BottleneckResult -Id 'SFC' -Tier 'Deep' -Category 'System Integrity' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckEventLog {
    try {
        # Deep analysis across multiple event logs
        $logs = @('System', 'Application', 'Security')
        $criticalErrors = @()
        $patterns = @()
        
        foreach ($logName in $logs) {
            # Get critical errors from last 30 days
            $errors = Invoke-WithTimeout -TimeoutSeconds 15 -ScriptBlock {
                $start = (Get-Date).AddDays(-30)
                $filter = @{ Level=1,2; StartTime=$start }
                if ($using:logName) { $filter['LogName'] = $using:logName } else { $filter['LogName'] = 'System' }
                Get-WinEvent -FilterHashtable $filter -MaxEvents 500 -ErrorAction SilentlyContinue
            }
            
            if ($errors) {
                $criticalErrors += $errors
                
                # Find repeated error patterns
                $grouped = $errors | Group-Object Id | Where-Object { $_.Count -gt 10 } | Sort-Object Count -Descending | Select-Object -First 5
                foreach ($group in $grouped) {
                    $patterns += "Event $($group.Name): $($group.Count) occurrences"
                }
            }
        }
        
        # Check for disk errors
        $diskErrors = $criticalErrors | Where-Object { $_.Message -match 'disk|drive|volume|storage' }
        
        # Check for memory errors
        $memoryErrors = $criticalErrors | Where-Object { $_.Message -match 'memory|page fault|pool' }
        
        # Check for driver crashes
        $driverCrashes = $criticalErrors | Where-Object { $_.Message -match 'driver|bugcheck|bluescreen|stop error' }
        
        $impact = if ($driverCrashes.Count -gt 5) { 9 } elseif ($diskErrors.Count -gt 10 -or $memoryErrors.Count -gt 10) { 7 } elseif ($criticalErrors.Count -gt 100) { 6 } else { 2 }
        $confidence = 8
        $effort = 4
        $priority = 4
        $evidence = "Critical errors (30d): $($criticalErrors.Count), Disk: $($diskErrors.Count), Memory: $($memoryErrors.Count), Driver crashes: $($driverCrashes.Count)"
        if ($patterns.Count -gt 0) {
            $evidence += " - Patterns: $($patterns -join '; ')"
        }
        $fixId = ''
        $msg = if ($driverCrashes.Count -gt 5) { 
            'Multiple driver crashes detected - system stability at risk.' 
        } elseif ($impact -ge 7) { 
            'Significant error patterns found requiring investigation.' 
        } elseif ($impact -ge 6) { 
            'High volume of errors detected.' 
        } else { 
            'Event log analysis shows normal activity.' 
        }
        
        return New-BottleneckResult -Id 'EventLog' -Tier 'Deep' -Category 'Event Log Analysis' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckBackgroundProcs {
    try {
        # Get all running processes with resource usage
        $processes = Get-Process | Where-Object { $_.CPU -gt 0 -or $_.WorkingSet -gt 10MB }
        
        # Identify high CPU processes
        $highCPU = $processes | Sort-Object CPU -Descending | Select-Object -First 10
        $cpuHogs = $highCPU | Where-Object { $_.CPU -gt 100 } | Select-Object -First 5
        
        # Identify high memory processes
        $highMemory = $processes | Sort-Object WorkingSet -Descending | Select-Object -First 10
        $memoryHogs = $highMemory | Where-Object { $_.WorkingSet -gt 500MB } | Select-Object -First 5
        
        # Check for suspicious processes (unusual names, high resource usage from unknown apps)
        $suspicious = @()
        foreach ($proc in $processes) {
            # Flag processes with random-looking names or from temp folders
            if ($proc.Path -match '\\Temp\\|\\AppData\\Local\\Temp\\' -and $proc.CPU -gt 10) {
                $suspicious += "$($proc.ProcessName) (CPU: $([math]::Round($proc.CPU,1)))"
            }
        }
        
        # Count total background processes
        $totalProcs = $processes.Count
        
        $impact = if ($suspicious.Count -gt 2) { 8 } elseif ($cpuHogs.Count -gt 3) { 6 } elseif ($totalProcs -gt 200) { 5 } else { 2 }
        $confidence = 7
        $effort = 3
        $priority = 5
        
        $topCPU = $cpuHogs | ForEach-Object { "$($_.ProcessName) ($([math]::Round($_.CPU,1))s)" }
        $topMem = $memoryHogs | ForEach-Object { "$($_.ProcessName) ($([math]::Round($_.WorkingSet/1MB))MB)" }
        
        $evidence = "Total processes: $totalProcs, CPU hogs: $($cpuHogs.Count), Memory hogs: $($memoryHogs.Count), Suspicious: $($suspicious.Count)"
        if ($topCPU.Count -gt 0) {
            $evidence += " - Top CPU: $($topCPU -join ', ')"
        }
        $fixId = ''
        $msg = if ($suspicious.Count -gt 2) { 
            'Suspicious processes detected - possible malware.' 
        } elseif ($cpuHogs.Count -gt 3) { 
            'Multiple resource-intensive processes running.' 
        } elseif ($totalProcs -gt 200) { 
            'High number of background processes.' 
        } else { 
            'Background process usage is normal.' 
        }
        
        return New-BottleneckResult -Id 'BackgroundProcs' -Tier 'Deep' -Category 'Background Processes' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckHardwareReco {
    try {
        # Analyze system specs and generate upgrade recommendations
        $recommendations = @()
        $urgency = 'Low'
        
        # Check RAM
        $totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        if ($totalRAM -lt 8) {
            $recommendations += "URGENT: Upgrade RAM to at least 8GB (current: $($totalRAM)GB) - recommended: 16GB DDR4"
            $urgency = 'High'
        } elseif ($totalRAM -lt 16) {
            $recommendations += "Consider RAM upgrade to 16GB for better multitasking (current: $($totalRAM)GB)"
        }
        
        # Check storage type
        $systemDisk = Get-PhysicalDisk | Where-Object { $_.DeviceID -eq 0 }
        if ($systemDisk.MediaType -ne 'SSD') {
            $recommendations += "URGENT: Upgrade to SSD for 5-10x performance improvement (current: $($systemDisk.MediaType))"
            $urgency = 'Critical'
        }
        
        # Check storage capacity
        $systemDrive = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
        if ($systemDrive) {
            $freePercent = ($systemDrive.SizeRemaining / $systemDrive.Size) * 100
            if ($freePercent -lt 10) {
                $recommendations += "Upgrade storage capacity - less than 10% free space"
                if ($urgency -eq 'Low') { $urgency = 'Medium' }
            }
        }
        
        # Check CPU age (simplified - would need more detailed CPU database)
        $cpu = Get-CachedCimInstance -ClassName Win32_Processor
        $cpuName = $cpu.Name
        if ($cpuName -match 'Celeron|Pentium|Atom') {
            $recommendations += "Consider CPU upgrade - current CPU is low-end: $cpuName"
        }
        
        # Check CPU core count
        $cores = $cpu.NumberOfCores
        if ($cores -lt 4) {
            $recommendations += "Upgrade to at least quad-core CPU for modern workloads (current: $cores cores)"
            if ($urgency -eq 'Low') { $urgency = 'Medium' }
        }
        
        # Check GPU (basic check)
        $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
        $gpuRAM = [math]::Round($gpu.AdapterRAM / 1GB, 1)
        if ($gpu.Name -match 'Intel.*Graphics' -and $gpuRAM -lt 2) {
            $recommendations += "Consider dedicated GPU for graphics-intensive tasks (current: integrated graphics)"
        }
        
        $impact = switch ($urgency) {
            'Critical' { 9 }
            'High' { 7 }
            'Medium' { 5 }
            default { 2 }
        }
        
        $confidence = 8
        $effort = 5
        $priority = 6
        $evidence = "Urgency: $urgency, Recommendations: $($recommendations.Count)"
        $fixId = ''
        $msg = if ($recommendations.Count -gt 2) { 
            "Hardware upgrades strongly recommended ($($recommendations.Count) items)." 
        } elseif ($recommendations.Count -gt 0) { 
            'Some hardware upgrades would improve performance.' 
        } else { 
            'Hardware is adequate for current needs.' 
        }
        
        return New-BottleneckResult -Id 'HardwareReco' -Tier 'Deep' -Category 'Hardware Recommendations' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}
