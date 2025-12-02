function Test-BottleneckRAM {
    Write-BottleneckLog "Starting RAM check" -Level "DEBUG" -CheckId "RAM"
    $mem = Get-CachedCimInstance -ClassName Win32_OperatingSystem
    $freeGB = [math]::Round($mem.FreePhysicalMemory/1MB,2)
    Write-BottleneckLog "RAM check: ${freeGB}GB free" -Level "DEBUG" -CheckId "RAM"
    $impact = if ($freeGB -lt 2) { 8 } else { 2 }
    $confidence = 9
    $effort = 2
    $priority = 1
    $evidence = "Free RAM: $freeGB GB"
    $fixId = ''
    $msg = if ($freeGB -lt 2) { 'Low available RAM.' } else { 'RAM OK.' }
    return New-BottleneckResult -Id 'RAM' -Tier 'Quick' -Category 'RAM' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckCPU {
    Write-BottleneckLog "Starting CPU check" -Level "DEBUG" -CheckId "CPU"
    $cpu = Get-CachedCimInstance -ClassName Win32_Processor
    $load = $cpu.LoadPercentage
    Write-BottleneckLog "CPU check: ${load}% load" -Level "DEBUG" -CheckId "CPU"
    $impact = if ($load -gt 80) { 7 } else { 2 }
    $confidence = 8
    $effort = 2
    $priority = 2
    $evidence = "CPU load: $load%"
    $fixId = ''
    $msg = if ($load -gt 80) { 'High CPU load.' } else { 'CPU load normal.' }
    return New-BottleneckResult -Id 'CPU' -Tier 'Quick' -Category 'CPU' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckDiskSMART {
    $smart = Get-WmiObject MSStorageDriver_FailurePredictStatus -Namespace root\wmi -ErrorAction SilentlyContinue
    $fail = $smart | Where-Object { $_.PredictFailure -eq $true }
    $impact = if ($fail) { 9 } else { 2 }
    $confidence = 9
    $effort = 4
    $priority = 1
    $evidence = if ($fail) { 'SMART failure predicted.' } else { 'SMART status OK.' }
    $fixId = ''
    $msg = if ($fail) { 'Disk SMART failure predicted.' } else { 'Disk health OK.' }
    return New-BottleneckResult -Id 'DiskSMART' -Tier 'Standard' -Category 'Disk SMART' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckOSAge {
    $os = Get-CachedCimInstance -ClassName Win32_OperatingSystem
    $installDate = $os.InstallDate
    try {
        $ageDays = ((Get-Date) - $installDate).Days
    } catch {
        $ageDays = 0
    }
    $impact = if ($ageDays -gt 1000) { 5 } else { 2 }
    $confidence = 7
    $effort = 2
    $priority = 2
    $evidence = "OS age: $ageDays days"
    $fixId = ''
    $msg = if ($ageDays -gt 1000) { 'OS install is very old.' } else { 'OS age normal.' }
    return New-BottleneckResult -Id 'OSAge' -Tier 'Standard' -Category 'OS Age' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckGPU {
    $gpu = Get-CimInstance Win32_VideoController
    $driverDate = $gpu.DriverDate
    $impact = if ($driverDate -lt (Get-Date).AddYears(-2)) { 6 } else { 2 }
    $confidence = 7
    $effort = 3
    $priority = 3
    $evidence = "GPU driver date: $driverDate"
    $fixId = ''
    $msg = if ($driverDate -lt (Get-Date).AddYears(-2)) { 'GPU driver is outdated.' } else { 'GPU driver OK.' }
    return New-BottleneckResult -Id 'GPU' -Tier 'Standard' -Category 'GPU' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckAV {
    $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $enabled = $defender.AntivirusEnabled
    $impact = if (-not $enabled) { 8 } else { 2 }
    $confidence = 8
    $effort = 2
    $priority = 4
    $evidence = "Defender enabled: $enabled"
    $fixId = ''
    $msg = if (-not $enabled) { 'Antivirus is disabled.' } else { 'Antivirus enabled.' }
    return New-BottleneckResult -Id 'AV' -Tier 'Standard' -Category 'AV' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckTasks {
    try {
        # Consider only enabled, non-hidden tasks
        $tasks = Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and ($_.Hidden -eq $false -or $_.Hidden -eq $null) }
        $count = $tasks.Count

        # Check for failed tasks
        $failedTasks = @()
        $heavyTasks = @()

        foreach ($task in $tasks) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
            if ($taskInfo) {
                # Check last run result (0 = success)
                # Only consider failures within the last 72 hours to avoid stale noise
                $recentWindow = (Get-Date).AddHours(-72)
                $lastRunTime = $taskInfo.LastRunTime
                if ($lastRunTime -and ($lastRunTime -gt $recentWindow) -and $taskInfo.LastTaskResult -ne 0 -and $taskInfo.LastTaskResult -ne $null) {
                    $failedTasks += $task.TaskName
                }

                # Check for tasks running frequently (multiple times per day)
                if ($taskInfo.NumberOfMissedRuns -gt 5) {
                    $heavyTasks += $task.TaskName
                }
            }
        }

        $impact = if ($failedTasks.Count -gt 5) { 6 } elseif ($count -gt 50) { 5 } else { 2 }
        $confidence = 7
        $effort = 2
        $priority = 5
        $evidence = "Total: $count, Failed: $($failedTasks.Count), Heavy: $($heavyTasks.Count)"
        $fixId = ''
        $msg = if ($failedTasks.Count -gt 5) { 'Multiple scheduled tasks have recently failed.' } elseif ($count -gt 50) { 'Too many scheduled tasks.' } else { 'Scheduled tasks normal.' }

        return New-BottleneckResult -Id 'Tasks' -Tier 'Standard' -Category 'Tasks' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

# Deep tier functions are now in Bottleneck.DeepScan.ps1
# Bottleneck.Checks.ps1
function Get-BottleneckChecks {
    param([ValidateSet('Quick','Standard','Deep')][string]$Tier)
    $quick = @(
        'Test-BottleneckStorage',
        'Test-BottleneckPowerPlan',
        'Test-BottleneckStartup',
        'Test-BottleneckNetwork',
        'Test-BottleneckRAM',
        'Test-BottleneckCPU'
    )
    $standard = $quick + @(
        'Test-BottleneckUpdate',
        'Test-BottleneckDriver',
        'Test-BottleneckBrowser',
        'Test-BottleneckDiskSMART',
        'Test-BottleneckOSAge',
        'Test-BottleneckGPU',
        'Test-BottleneckAV',
        'Test-BottleneckTasks',
        'Test-BottleneckThermal',
        'Test-BottleneckBattery',
        'Test-BottleneckDiskFragmentation',
        'Test-BottleneckMemoryHealth',
        'Test-BottleneckCPUThrottle',
        'Test-BottleneckServiceHealth',
        'Test-BottleneckStartupImpact',
        'Test-BottleneckWindowsFeatures',
        'Test-BottleneckGroupPolicy',
        'Test-BottleneckDNS',
        'Test-BottleneckNetworkAdapter',
        'Test-BottleneckBandwidth',
        'Test-BottleneckVPN',
        'Test-BottleneckFirewall',
        'Test-BottleneckAntivirusHealth',
        'Test-BottleneckWindowsUpdateHealth',
        'Test-BottleneckSecurityBaseline',
        'Test-BottleneckPortSecurity',
        'Test-BottleneckBrowserSecurity',
        'Test-BottleneckBootTime',
        'Test-BottleneckAppLaunchPerformance',
        'Test-BottleneckUIResponsiveness',
        'Test-BottleneckPerformanceTrends',
        'Test-BottleneckCPUUtilization',
        'Test-BottleneckMemoryUtilization',
        'Test-BottleneckFanSpeed',
        'Test-BottleneckSystemTemperature',
        'Test-BottleneckStuckProcesses'
    )
    $deep = $standard + @(
        'Test-BottleneckETW',
        'Test-BottleneckFullSMART',
        'Test-BottleneckSFC',
        'Test-BottleneckEventLog',
        'Test-BottleneckBackgroundProcs',
        'Test-BottleneckHardwareReco',
        'Test-BottleneckJavaHeap'
    )
    switch ($Tier) {
        'Quick' { return $quick }
        'Standard' { return $standard }
        'Deep' { return $deep }
    }
}

function Test-BottleneckStorage {
    $systemDrive = "$env:SystemDrive\\"
    $drive = Get-PSDrive -PSProvider 'FileSystem' | Where-Object { $_.Root -eq $systemDrive }

    if (-not $drive) {
        # Fallback to CIM if PSDrive lookup fails
        try {
            $logical = Get-CachedCimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DeviceID -eq $env:SystemDrive }
            if ($logical) {
                $freeGB = [math]::Round(($logical.FreeSpace/1GB),2)
            } else {
                $freeGB = 0
            }
        } catch {
            $freeGB = 0
        }
    } else {
        $freeGB = [math]::Round(($drive.Free/1GB),2)
    }
    $impact = if ($freeGB -lt 10) { 8 } else { 2 }
    $confidence = 9
    $effort = 2
    $priority = 1
    $evidence = "Free space: $freeGB GB"
    $fixId = 'Cleanup'
    $msg = if ($freeGB -lt 10) { 'Low disk space detected.' } else { 'Disk space OK.' }
    return New-BottleneckResult -Id 'Storage' -Tier 'Quick' -Category 'Storage' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckPowerPlan {
    $plan = (powercfg /GetActiveScheme) 2>&1
    $isHighPerf = $plan -match 'High performance'
    $impact = if ($isHighPerf) { 2 } else { 7 }
    $confidence = 8
    $effort = 1
    $priority = 2
    $evidence = $plan
    $fixId = 'PowerPlanHighPerformance'
    $msg = if ($isHighPerf) { 'High performance power plan active.' } else { 'Consider switching to High performance power plan.' }
    return New-BottleneckResult -Id 'PowerPlan' -Tier 'Quick' -Category 'Power' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckStartup {
    $autoruns = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command
    $count = $autoruns.Count
    $impact = if ($count -gt 10) { 7 } else { 3 }
    $confidence = 7
    $effort = 3
    $priority = 3
    $evidence = "Startup items: $count"
    $fixId = ''
    $msg = if ($count -gt 10) { 'Too many startup items.' } else { 'Startup load normal.' }
    return New-BottleneckResult -Id 'Startup' -Tier 'Quick' -Category 'Startup' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckNetwork {
    $ping = Test-Connection -ComputerName 'www.yahoo.com' -Count 2 -ErrorAction SilentlyContinue
    $avg = if ($ping) { ($ping | Measure-Object ResponseTime -Average).Average } else { 999 }
    $impact = if ($avg -gt 100) { 6 } else { 2 }
    $confidence = 6
    $effort = 2
    $priority = 4
    $evidence = "Ping avg (yahoo.com): $avg ms"
    $fixId = ''
    $msg = if ($avg -gt 100) { 'High network latency.' } else { 'Network latency normal.' }
    return New-BottleneckResult -Id 'Network' -Tier 'Quick' -Category 'Network' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
# Deep tier advanced network diagnostics
function Test-BottleneckNetworkDeep {
    $results = @()
    $start = Get-Date
    $end = $start.AddMinutes(10)
    while (Get-Date -lt $end) {
        $ping = Test-Connection -ComputerName 'www.yahoo.com' -Count 1 -ErrorAction SilentlyContinue
        $nic = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $browser = $null # Placeholder for browser connectivity check
        $router = Test-Connection -ComputerName '192.168.1.1' -Count 1 -ErrorAction SilentlyContinue
        $modem = $null # Placeholder for modem check
        $isp = $null # Placeholder for ISP check
        $results += [PSCustomObject]@{
            Time = Get-Date
            PingYahoo = if ($ping) { ($ping | Measure-Object ResponseTime -Average).Average } else { $null }
            NICStatus = if ($nic) { $nic.Status } else { 'Down' }
            RouterPing = if ($router) { ($router | Measure-Object ResponseTime -Average).Average } else { $null }
            # Add browser, modem, ISP, destination checks as needed
        }
        Start-Sleep -Seconds 30
    }
    return $results
}
}

function Test-BottleneckUpdate {
    $pending = $null
    try {
        if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
            $pending = (Get-WindowsUpdate -ErrorAction SilentlyContinue | Where-Object {$_.IsDownloaded -or $_.IsPending})
        }
    } catch {}
    $count = if ($pending) { $pending.Count } else { 0 }
    $impact = if ($count -gt 0) { 7 } else { 2 }
    $confidence = 8
    $effort = 2
    $priority = 5
    $evidence = if ($pending) { "Pending updates: $count" } else { "Windows Update module not available" }
    $fixId = if ($count -gt 0) { 'TriggerUpdate' } else { '' }
    $msg = if ($count -gt 0) { 'Windows updates pending.' } else { 'System up to date.' }
    return New-BottleneckResult -Id 'Update' -Tier 'Standard' -Category 'Update' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckDriver {
    $drivers = Get-WmiObject Win32_PnPSignedDriver | Select-Object DeviceName, DriverVersion, DriverDate
    $old = ($drivers | Where-Object { $_.DriverDate -lt (Get-Date).AddYears(-2) })
    $count = if ($old) { $old.Count } else { 0 }
    $impact = if ($count -gt 0) { 6 } else { 2 }
    $confidence = 7
    $effort = 3
    $priority = 6
    $evidence = "Old drivers: $count"
    $fixId = ''
    $msg = if ($count -gt 0) { 'Some drivers are outdated.' } else { 'Drivers are current.' }
    return New-BottleneckResult -Id 'Driver' -Tier 'Standard' -Category 'Driver' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}

function Test-BottleneckBrowser {
    $chromeExt = $null
    $firefoxExt = $null
    try {
        $chromeExt = Get-ChildItem "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions" -ErrorAction SilentlyContinue
    } catch {}
    try {
        $firefoxExt = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Recurse -Include extensions.json -ErrorAction SilentlyContinue
    } catch {}
    $chromeCount = if ($chromeExt) { $chromeExt.Count } else { 0 }
    $firefoxCount = if ($firefoxExt) { $firefoxExt.Count } else { 0 }
    $total = $chromeCount + $firefoxCount
    $impact = if ($total -gt 10) { 5 } else { 2 }
    $confidence = 6
    $effort = 2
    $priority = 7
    $evidence = "Browser extensions: $total"
    $fixId = ''
    $msg = if ($total -gt 10) { 'Too many browser extensions.' } else { 'Browser extension load normal.' }
    return New-BottleneckResult -Id 'Browser' -Tier 'Standard' -Category 'Browser' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
}
