# Bottleneck.WindowsFeatures.ps1
# Windows features and configuration checks

function Test-BottleneckWindowsFeatures {
    try {
        $issues = @()

        # Check Superfetch/SysMain (should be running on HDDs, optional on SSDs)
        $sysmain = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue
        if ($sysmain -and $sysmain.Status -ne 'Running') {
            $issues += 'Superfetch/SysMain disabled'
        }

        # Check Windows Search (indexing)
        $wsearch = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        if ($wsearch -and $wsearch.Status -ne 'Running') {
            $issues += 'Windows Search disabled'
        }

        # Check Windows Update service
        $wuauserv = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        if ($wuauserv -and $wuauserv.Status -ne 'Running' -and $wuauserv.StartType -ne 'Disabled') {
            $issues += 'Windows Update service not running'
        }

        # Check BITS (Background Intelligent Transfer Service)
        $bits = Get-Service -Name 'BITS' -ErrorAction SilentlyContinue
        if ($bits -and $bits.Status -ne 'Running' -and $bits.StartType -ne 'Disabled') {
            $issues += 'BITS service not running'
        }

        $impact = if ($issues.Count -gt 2) { 6 } elseif ($issues.Count -gt 0) { 4 } else { 2 }
        $confidence = 7
        $effort = 2
        $priority = 4
        $evidence = "Feature issues: $($issues.Count) - $($issues -join ', ')"
        $fixId = ''
        $msg = if ($issues.Count -gt 2) { 'Multiple Windows features are disabled or not running.' } elseif ($issues.Count -gt 0) { 'Some Windows features may need attention.' } else { 'Windows features configured properly.' }

        return New-BottleneckResult -Id 'WindowsFeatures' -Tier 'Standard' -Category 'Windows Features' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckGroupPolicy {
    try {
        $restrictions = @()

        # Check for common restrictive policies
        $gpResult = gpresult /R /SCOPE:COMPUTER 2>&1 | Out-String

        # Check for power management policies
        if ($gpResult -match 'Power Management') {
            $restrictions += 'Power management policies active'
        }

        # Check for software restriction policies
        $srp = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers' -ErrorAction SilentlyContinue
        if ($srp) {
            $restrictions += 'Software restriction policies active'
        }

        # Check for Windows Update policies
        $wuPolicies = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
        if ($wuPolicies) {
            $restrictions += 'Windows Update policies configured'
        }

        $impact = if ($restrictions.Count -gt 3) { 5 } elseif ($restrictions.Count -gt 0) { 3 } else { 2 }
        $confidence = 6
        $effort = 3
        $priority = 5
        $evidence = "Policy restrictions: $($restrictions.Count) - $($restrictions -join ', ')"
        $fixId = ''
        $msg = if ($restrictions.Count -gt 3) { 'Multiple Group Policy restrictions may affect performance.' } elseif ($restrictions.Count -gt 0) { 'Some Group Policy restrictions detected.' } else { 'No restrictive policies detected.' }

        return New-BottleneckResult -Id 'GroupPolicy' -Tier 'Standard' -Category 'Group Policy' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}
