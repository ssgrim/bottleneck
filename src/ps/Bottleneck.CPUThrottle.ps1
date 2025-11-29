# Bottleneck.CPUThrottle.ps1
# CPU throttling detection

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
        } catch {}

        $impact = if ($throttlePercent -gt 30 -or $thermalThrottle) { 7 } elseif ($throttlePercent -gt 15) { 5 } else { 2 }
        $confidence = 7
        $effort = 2
        $priority = 3
        $evidence = "Clock: $currentClockSpeed / $maxClockSpeed MHz (${throttlePercent}% throttle), Thermal: $thermalThrottle"
        $fixId = if ($isPowerSaver) { 'PowerPlanHighPerformance' } else { '' }
        $msg = if ($throttlePercent -gt 30 -or $thermalThrottle) { 'CPU throttling detected. Check thermals or power settings.' } elseif ($throttlePercent -gt 15) { 'Moderate CPU throttling.' } else { 'CPU running at normal speed.' }

        return New-BottleneckResult -Id 'CPUThrottle' -Tier 'Standard' -Category 'CPU Throttling' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}
