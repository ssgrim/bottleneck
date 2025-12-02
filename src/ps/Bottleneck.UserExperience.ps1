# Bottleneck.UserExperience.ps1
# User experience and predictive analysis checks

function Test-BottleneckBootTime {
    try {
        # Get last boot time
        $os = Get-CachedCimInstance -ClassName Win32_OperatingSystem
        $lastBoot = $os.LastBootUpTime
        $uptime = (Get-Date) - $lastBoot

        # Get boot performance data from event log
        $startBoot = if ($lastBoot) { $lastBoot } else { (Get-Date).AddDays(-7) }
        $bootEvents = Get-SafeWinEvent -FilterHashtable @{
            LogName='System'
            ProviderName='Microsoft-Windows-Diagnostics-Performance'
            Id=100
            StartTime=$startBoot
        } -MaxEvents 1 -TimeoutSeconds 10

        $bootTimeSeconds = 0
        if ($bootEvents) {
            # Event ID 100 contains boot duration in milliseconds
            $bootTimeSeconds = [math]::Round(($bootEvents[0].Properties[0].Value / 1000), 1)
        }

        # Get slow boot drivers/services from event log
        $slowBootEvents = Get-SafeWinEvent -FilterHashtable @{
            LogName='System'
            ProviderName='Microsoft-Windows-Diagnostics-Performance'
            Id=101,102,103
            StartTime=$startBoot
        } -MaxEvents 20 -TimeoutSeconds 10

        $slowComponents = @()
        foreach ($event in $slowBootEvents) {
            if ($event.Properties.Count -gt 0) {
                $slowComponents += $event.Properties[0].Value
            }
        }

        $impact = if ($bootTimeSeconds -gt 60) { 7 } elseif ($bootTimeSeconds -gt 30) { 5 } elseif ($bootTimeSeconds -gt 0) { 3 } else { 2 }
        $confidence = if ($bootTimeSeconds -gt 0) { 8 } else { 5 }
        $effort = 3
        $priority = 2
        $evidence = if ($bootTimeSeconds -gt 0) {
            "Boot time: $bootTimeSeconds seconds, Slow components: $($slowComponents.Count), Uptime: $([math]::Round($uptime.TotalHours,1)) hours"
        } else {
            "Uptime: $([math]::Round($uptime.TotalHours,1)) hours (no boot events found)"
        }
        $fixId = ''
        $msg = if ($bootTimeSeconds -gt 60) {
            'Boot time is very slow.'
        } elseif ($bootTimeSeconds -gt 30) {
            'Boot time is slower than optimal.'
        } elseif ($bootTimeSeconds -gt 0) {
            'Boot time is acceptable.'
        } else {
            'Boot time data not available.'
        }

        return New-BottleneckResult -Id 'BootTime' -Tier 'Standard' -Category 'Boot Performance' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckAppLaunchPerformance {
    try {
        # Check for slow app launches in event log
        $slowAppEvents = Get-SafeWinEvent -FilterHashtable @{
            LogName='Application'
            Level=2,3
            StartTime=(Get-Date).AddDays(-7)
        } -MaxEvents 100 -TimeoutSeconds 10 |
        Where-Object { $_.Message -match 'timeout|slow|hang|not responding' }

        $slowAppCount = if ($slowAppEvents) { $slowAppEvents.Count } else { 0 }

        # Check installed programs count
        $installedApps = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, InstallDate

        $appCount = $installedApps.Count

        # Check for programs with high startup impact (from earlier check)
        $startupApps = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
        $startupCount = if ($startupApps) { $startupApps.Count } else { 0 }

        $impact = if ($slowAppCount -gt 20) { 6 } elseif ($slowAppCount -gt 10) { 4 } elseif ($appCount -gt 200) { 4 } else { 2 }
        $confidence = 6
        $effort = 3
        $priority = 4
        $evidence = "Slow app events (7d): $slowAppCount, Installed apps: $appCount, Startup apps: $startupCount"
        $fixId = ''
        $msg = if ($slowAppCount -gt 20) {
            'Frequent slow application launches detected.'
        } elseif ($slowAppCount -gt 10) {
            'Some applications are slow to launch.'
        } elseif ($appCount -gt 200) {
            'High number of installed applications may affect performance.'
        } else {
            'Application launch performance is acceptable.'
        }

        return New-BottleneckResult -Id 'AppLaunch' -Tier 'Standard' -Category 'App Launch' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckUIResponsiveness {
    try {
        # Check for UI hang events
        $hangEvents = Get-SafeWinEvent -FilterHashtable @{
            LogName='Application'
            ProviderName='Application Hang'
            StartTime=(Get-Date).AddDays(-7)
        } -MaxEvents 100 -TimeoutSeconds 10

        $hangCount = if ($hangEvents) { $hangEvents.Count } else { 0 }

        # Check for DWM (Desktop Window Manager) issues
        $dwmEvents = Get-SafeWinEvent -FilterHashtable @{
            LogName='System'
            ProviderName='Desktop Window Manager'
            Level=2,3
            StartTime=(Get-Date).AddDays(-7)
        } -MaxEvents 100 -TimeoutSeconds 10

        $dwmIssues = if ($dwmEvents) { $dwmEvents.Count } else { 0 }

        # Check for system responsiveness events
        $lagEvents = Get-SafeWinEvent -FilterHashtable @{
            LogName='System'
            Id=2004,2006
            StartTime=(Get-Date).AddDays(-7)
        } -MaxEvents 50 -TimeoutSeconds 10

        $lagCount = if ($lagEvents) { $lagEvents.Count } else { 0 }

        # Get top hung applications
        $topHungApps = @()
        if ($hangEvents) {
            $topHungApps = $hangEvents |
                Group-Object { $_.Properties[0].Value } |
                Sort-Object Count -Descending |
                Select-Object -First 3 |
                ForEach-Object { "$($_.Name) ($($_.Count)x)" }
        }

        $impact = if ($hangCount -gt 50) { 7 } elseif ($hangCount -gt 20) { 5 } elseif ($hangCount -gt 10) { 3 } else { 2 }
        $confidence = 8
        $effort = 3
        $priority = 3
        $evidence = "UI hangs (7d): $hangCount, DWM issues: $dwmIssues, Lag events: $lagCount"
        if ($topHungApps.Count -gt 0) {
            $evidence += ", Top: $($topHungApps -join ', ')"
        }
        $fixId = ''
        $msg = if ($hangCount -gt 50) {
            'Frequent UI hangs and freezes detected.'
        } elseif ($hangCount -gt 20) {
            'Some UI responsiveness issues detected.'
        } elseif ($hangCount -gt 10) {
            'Minor UI responsiveness issues.'
        } else {
            'UI responsiveness is good.'
        }

        return New-BottleneckResult -Id 'UIResponsiveness' -Tier 'Standard' -Category 'UI Responsiveness' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckPerformanceTrends {
    try {
        # Load historical scan data from Reports folder
        $reportsPath = "$PSScriptRoot/../../Reports"
        $historicalScans = Get-ChildItem -Path $reportsPath -Filter '*-scan-*.json' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 10

        $scanCount = $historicalScans.Count

        if ($scanCount -lt 2) {
            return New-BottleneckResult -Id 'PerformanceTrends' -Tier 'Standard' -Category 'Performance Trends' -Impact 2 -Confidence 5 -Effort 1 -Priority 8 -Evidence "Insufficient historical data ($scanCount scans)" -FixId '' -Message 'Need more scan history for trend analysis.'
        }

        # Analyze trends in key metrics
        $trends = @{
            Storage = @()
            RAM = @()
            CPU = @()
            BootTime = @()
        }

        foreach ($scan in $historicalScans) {
            try {
                $data = Get-Content $scan.FullName -Raw | ConvertFrom-Json
                foreach ($result in $data) {
                    if ($trends.ContainsKey($result.Id)) {
                        $trends[$result.Id] += $result.Score
                    }
                }
            } catch { }
        }

        # Calculate trend direction for each metric
        $degrading = @()
        $improving = @()

        foreach ($metric in $trends.Keys) {
            $scores = $trends[$metric]
            if ($scores.Count -ge 2) {
                $recent = $scores[0..1] | Measure-Object -Average
                $older = $scores[-2..-1] | Measure-Object -Average

                $change = $recent.Average - $older.Average
                if ($change -gt 5) {
                    $degrading += "$metric (+$([math]::Round($change,1)))"
                } elseif ($change -lt -5) {
                    $improving += "$metric ($([math]::Round($change,1)))"
                }
            }
        }

        $impact = if ($degrading.Count -gt 2) { 6 } elseif ($degrading.Count -gt 0) { 4 } else { 2 }
        $confidence = 7
        $effort = 2
        $priority = 5
        $evidence = "Historical scans: $scanCount, Degrading: $($degrading.Count), Improving: $($improving.Count)"
        if ($degrading.Count -gt 0) {
            $evidence += " - Degrading: $($degrading -join ', ')"
        }
        $fixId = ''
        $msg = if ($degrading.Count -gt 2) {
            'Multiple metrics are degrading over time.'
        } elseif ($degrading.Count -gt 0) {
            'Some performance degradation detected.'
        } else {
            'Performance is stable or improving.'
        }

        return New-BottleneckResult -Id 'PerformanceTrends' -Tier 'Standard' -Category 'Performance Trends' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Get-BottleneckSmartRecommendations {
    param([Parameter(Mandatory)]$Results)

    try {
        # Sort results by priority score (Impact × Confidence ÷ (Effort + 1))
        $prioritized = $Results |
            Where-Object { $_.Impact -gt 5 } |
            Sort-Object Score -Descending

        if ($prioritized.Count -eq 0) {
            return @{
                Priority = 'Low'
                Message = 'No critical issues detected. System is performing well.'
                QuickWins = @()
                CriticalFixes = @()
                LongTermActions = @()
            }
        }

        # Categorize by effort and impact
        $quickWins = $prioritized | Where-Object { $_.Effort -le 2 -and $_.Impact -ge 6 }
        $criticalFixes = $prioritized | Where-Object { $_.Impact -ge 8 }
        $longTerm = $prioritized | Where-Object { $_.Effort -ge 4 -and $_.Impact -ge 6 }

        # Determine overall priority
        $overallPriority = if ($criticalFixes.Count -gt 3) { 'Critical' } elseif ($criticalFixes.Count -gt 0) { 'High' } elseif ($quickWins.Count -gt 5) { 'Medium' } else { 'Low' }

        # Generate repair roadmap
        $message = if ($overallPriority -eq 'Critical') {
            "IMMEDIATE ATTENTION REQUIRED: $($criticalFixes.Count) critical issues detected that may cause system instability or data loss."
        } elseif ($overallPriority -eq 'High') {
            "HIGH PRIORITY: $($criticalFixes.Count) serious issues require prompt attention."
        } elseif ($overallPriority -eq 'Medium') {
            "MODERATE PRIORITY: Several performance improvements available with minimal effort."
        } else {
            "LOW PRIORITY: System is generally healthy with minor optimization opportunities."
        }

        return @{
            Priority = $overallPriority
            Message = $message
            QuickWins = $quickWins | Select-Object -First 5 | ForEach-Object { "$($_.Category): $($_.Message)" }
            CriticalFixes = $criticalFixes | Select-Object -First 5 | ForEach-Object { "$($_.Category): $($_.Message)" }
            LongTermActions = $longTerm | Select-Object -First 5 | ForEach-Object { "$($_.Category): $($_.Message)" }
        }
    } catch {
        return @{
            Priority = 'Unknown'
            Message = 'Unable to generate recommendations.'
            QuickWins = @()
            CriticalFixes = @()
            LongTermActions = @()
        }
    }
}
