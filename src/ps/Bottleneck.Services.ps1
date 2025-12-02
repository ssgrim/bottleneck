# Bottleneck.Services.ps1
# Windows service health checks

function Test-BottleneckServiceHealth {
    try {
        # Get failed services (suppress permission errors for protected services)
        $services = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic' }
        $failedCount = $services.Count

        # Check for slow-starting services from event log
        $svcStart = (Get-Date).AddDays(-7)
        $svcFilter = @{ LogName='System'; ProviderName='Service Control Manager'; Id=7000,7001,7011; StartTime=$svcStart }
        $slowServices = Get-SafeWinEvent -FilterHashtable $svcFilter -MaxEvents 100 -TimeoutSeconds 10
        $slowCount = if ($slowServices) { $slowServices.Count } else { 0 }

        $impact = if ($failedCount -gt 5 -or $slowCount -gt 10) { 7 } elseif ($failedCount -gt 0 -or $slowCount -gt 0) { 4 } else { 2 }
        $confidence = 8
        $effort = 2
        $priority = 3
        $evidence = "Failed services: $failedCount, Slow starts (7 days): $slowCount"
        $fixId = if ($failedCount -gt 0) { 'RestartServices' } else { '' }
        $msg = if ($failedCount -gt 5) { 'Multiple services have failed to start.' } elseif ($failedCount -gt 0) { 'Some services are not running.' } else { 'All automatic services running.' }

        return New-BottleneckResult -Id 'ServiceHealth' -Tier 'Standard' -Category 'Service Health' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckStartupImpact {
    try {
        # Check startup programs from Task Manager data
        $startupApps = Get-CimInstance Win32_StartupCommand
        $highImpact = @()

        # Check registry for startup impact ratings
        $paths = @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )

        $totalStartup = 0
        foreach ($path in $paths) {
            if (Test-Path $path) {
                $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
                if ($items) {
                    $totalStartup += ($items.PSObject.Properties | Where-Object { $_.Name -notmatch 'PS' }).Count
                }
            }
        }

        # Estimate high impact (apps known to slow startup)
        $knownSlowApps = @('Adobe', 'iTunes', 'Skype', 'Steam', 'Discord', 'Spotify')
        foreach ($app in $startupApps) {
            foreach ($slow in $knownSlowApps) {
                if ($app.Command -match $slow) {
                    $highImpact += $app.Name
                }
            }
        }

        $impact = if ($highImpact.Count -gt 5) { 7 } elseif ($highImpact.Count -gt 2) { 5 } else { 2 }
        $confidence = 7
        $effort = 2
        $priority = 3
        $evidence = "Total startup items: $totalStartup, High impact: $($highImpact.Count)"
        $fixId = ''
        $msg = if ($highImpact.Count -gt 5) { 'Multiple high-impact startup apps detected.' } elseif ($highImpact.Count -gt 2) { 'Some high-impact startup apps found.' } else { 'Startup impact acceptable.' }

        return New-BottleneckResult -Id 'StartupImpact' -Tier 'Standard' -Category 'Startup Impact' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}
