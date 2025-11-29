# Bottleneck.Disk.ps1
# Disk fragmentation and health checks

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
    } catch {
        return $null
    }
}
