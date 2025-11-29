# Bottleneck.Battery.ps1
# Battery health checks for laptops

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
        } catch {}

        $impact = if ($wear -gt 30) { 7 } elseif ($wear -gt 20) { 5 } else { 2 }
        $confidence = 8
        $effort = 4
        $priority = 3
        $evidence = "Battery wear: $wear%, Cycles: $cycles, Capacity: $fullChargeCapacity / $designCapacity"
        $fixId = ''
        $msg = if ($wear -gt 30) { 'Battery significantly degraded. Consider replacement.' } elseif ($wear -gt 20) { 'Battery showing wear.' } else { 'Battery health OK.' }

        return New-BottleneckResult -Id 'Battery' -Tier 'Standard' -Category 'Battery' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}
