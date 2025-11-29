# Bottleneck.Memory.ps1
# RAM health and memory diagnostic checks

function Test-BottleneckMemoryHealth {
    try {
        # Check for memory errors in event log
        $memErrors = Get-WinEvent -FilterHashtable @{LogName='System'; Id=1101,1001; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue
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
        } catch {}

        $impact = if ($errorCount -gt 5) { 8 } elseif ($errorCount -gt 0) { 5 } else { 2 }
        $confidence = 7
        $effort = 3
        $priority = 2
        $evidence = "Memory errors (7 days): $errorCount"
        $fixId = if ($errorCount -gt 5) { 'MemoryDiagnostic' } else { '' }
        $msg = if ($errorCount -gt 5) { 'Multiple memory errors detected. Run memory diagnostic.' } elseif ($errorCount -gt 0) { 'Some memory errors found.' } else { 'No memory errors detected.' }

        return New-BottleneckResult -Id 'MemoryHealth' -Tier 'Standard' -Category 'Memory Health' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}
