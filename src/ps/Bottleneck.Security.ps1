# Bottleneck.Security.ps1
# Security and update health checks

function Test-BottleneckAntivirusHealth {
    try {
        $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
        $issues = @()

        if (-not $defender) {
            $issues += 'Windows Defender not available'
            $impact = 9
        } else {
            # Check if real-time protection is enabled
            if (-not $defender.RealTimeProtectionEnabled) {
                $issues += 'Real-time protection disabled'
            }

            # Check if antivirus is enabled
            if (-not $defender.AntivirusEnabled) {
                $issues += 'Antivirus disabled'
            }

            # Check signature age
            $signatureAge = (Get-Date) - $defender.AntivirusSignatureLastUpdated
            if ($signatureAge.Days -gt 7) {
                $issues += "Signatures outdated ($($signatureAge.Days) days old)"
            }

            # Check last scan
            $lastScan = $defender.QuickScanAge
            if ($lastScan -gt 7) {
                $issues += "No recent scan ($lastScan days)"
            }

            # Check if scan is in progress
            $scanInProgress = $defender.ScanInProgress

            $impact = if ($issues.Count -gt 2) { 9 } elseif ($issues.Count -gt 0) { 7 } else { 2 }
        }

        $confidence = 9
        $effort = 2
        $priority = 1
        $evidence = if ($issues.Count -gt 0) { $issues -join '; ' } else { "Defender active, signatures updated $($defender.AntivirusSignatureLastUpdated)" }
        $fixId = ''
        $msg = if ($issues.Count -gt 2) { 'Critical antivirus issues detected.' } elseif ($issues.Count -gt 0) { 'Antivirus needs attention.' } else { 'Antivirus protection is healthy.' }

        return New-BottleneckResult -Id 'AntivirusHealth' -Tier 'Standard' -Category 'Antivirus Health' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckWindowsUpdateHealth {
    try {
        # Check Windows Update service
        $wuService = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        $issues = @()

        if ($wuService.Status -ne 'Running') {
            $issues += 'Windows Update service not running'
        }

        # Check for failed updates in event log
        $wuStart = (Get-Date).AddDays(-30)
        $wuFilter = @{ LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'; Level=2; StartTime=$wuStart }
        $failedUpdates = Get-WinEvent -FilterHashtable $wuFilter -MaxEvents 500 -ErrorAction SilentlyContinue

        $failedCount = if ($failedUpdates) { $failedUpdates.Count } else { 0 }
        if ($failedCount -gt 5) {
            $issues += "Multiple failed updates ($failedCount in 30 days)"
        }

        # Check for pending updates (already done in Test-BottleneckUpdate)
        $pending = $null
        try {
            if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
                $pending = (Get-WindowsUpdate -ErrorAction SilentlyContinue | Where-Object {$_.IsDownloaded -or $_.IsPending})
            }
        } catch {}
        $pendingCount = if ($pending) { $pending.Count } else { 0 }

        # Check if updates are paused
        $updatePaused = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -ErrorAction SilentlyContinue).PauseUpdatesExpiryTime
        if ($updatePaused) {
            $issues += 'Updates are paused'
        }

        $impact = if ($issues.Count -gt 2) { 8 } elseif ($pendingCount -gt 10) { 7 } elseif ($issues.Count -gt 0) { 5 } else { 2 }
        $confidence = 8
        $effort = 2
        $priority = 2
        $evidence = if ($issues.Count -gt 0) { $issues -join '; ' } else { "Update service running, Failed: $failedCount, Pending: $pendingCount" }
        $fixId = if ($pendingCount -gt 0) { 'TriggerUpdate' } else { '' }
        $msg = if ($issues.Count -gt 2) { 'Windows Update has critical issues.' } elseif ($issues.Count -gt 0) { 'Windows Update needs attention.' } else { 'Windows Update is healthy.' }

        return New-BottleneckResult -Id 'WindowsUpdateHealth' -Tier 'Standard' -Category 'Windows Update Health' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckSecurityBaseline {
    try {
        $issues = @()

        # Check UAC (User Account Control)
        $uac = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue
        if ($uac.EnableLUA -ne 1) {
            $issues += 'UAC is disabled'
        }

        # Check Secure Boot
        try {
            $secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
            if (-not $secureBoot) {
                $issues += 'Secure Boot not enabled'
            }
        } catch {
            # Secure Boot not supported or not available
        }

        # Check BitLocker status on system drive
        $bitlocker = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
        if ($bitlocker) {
            if ($bitlocker.ProtectionStatus -eq 'Off') {
                $issues += 'BitLocker not enabled on system drive'
            }
        }

        # Check Windows Firewall
        $firewallProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $disabledFirewalls = $firewallProfiles | Where-Object { $_.Enabled -eq $false }
        if ($disabledFirewalls) {
            $issues += "Firewall disabled on: $($disabledFirewalls.Name -join ', ')"
        }

        # Check if guest account is enabled
        $guest = Get-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
        if ($guest -and $guest.Enabled) {
            $issues += 'Guest account is enabled'
        }

        # Check password policy
        $secPolicy = secedit /export /cfg "$env:TEMP\secpol.cfg" 2>&1
        $minPwdLength = (Get-Content "$env:TEMP\secpol.cfg" -ErrorAction SilentlyContinue | Select-String 'MinimumPasswordLength').ToString()
        if ($minPwdLength -match '= (\d+)' -and [int]$matches[1] -lt 8) {
            $issues += 'Weak password policy (min length < 8)'
        }
        Remove-Item "$env:TEMP\secpol.cfg" -Force -ErrorAction SilentlyContinue

        $impact = if ($issues.Count -gt 3) { 8 } elseif ($issues.Count -gt 1) { 6 } else { 2 }
        $confidence = 8
        $effort = 3
        $priority = 3
        $evidence = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'Security baseline settings are configured properly' }
        $fixId = ''
        $msg = if ($issues.Count -gt 3) { 'Multiple security baseline issues detected.' } elseif ($issues.Count -gt 1) { 'Some security settings need improvement.' } else { 'Security baseline is properly configured.' }

        return New-BottleneckResult -Id 'SecurityBaseline' -Tier 'Standard' -Category 'Security Baseline' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckPortSecurity {
    try {
        # Get listening ports
        $listeningPorts = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
        $dangerousPorts = @()
        $suspiciousPorts = @()

        # Define dangerous/unnecessary open ports
        $knownDangerousPorts = @(23, 21, 69, 135, 139, 445, 1433, 1434, 3306, 3389, 5900, 5800)

        foreach ($port in $listeningPorts) {
            $portNum = $port.LocalPort

            # Check if port is in dangerous list
            if ($knownDangerousPorts -contains $portNum) {
                try {
                    $process = Get-Process -Id $port.OwningProcess -ErrorAction SilentlyContinue
                    $dangerousPorts += "$portNum ($($process.ProcessName))"
                } catch {
                    $dangerousPorts += "$portNum"
                }
            }

            # Check for unusual high ports (possible malware)
            if ($portNum -gt 49152 -and $portNum -lt 65535) {
                try {
                    $process = Get-Process -Id $port.OwningProcess -ErrorAction SilentlyContinue
                    # Only flag if not a known system process
                    if ($process.ProcessName -notmatch 'svchost|System|lsass|services') {
                        $suspiciousPorts += "$portNum ($($process.ProcessName))"
                    }
                } catch { }
            }
        }

        $totalListening = $listeningPorts.Count
        $impact = if ($dangerousPorts.Count -gt 3) { 8 } elseif ($dangerousPorts.Count -gt 0) { 6 } elseif ($totalListening -gt 50) { 4 } else { 2 }
        $confidence = 7
        $effort = 3
        $priority = 4
        $evidence = "Listening ports: $totalListening, Dangerous: $($dangerousPorts.Count), Suspicious: $($suspiciousPorts.Count)"
        $fixId = ''
        $msg = if ($dangerousPorts.Count -gt 3) { 'Multiple dangerous ports are open.' } elseif ($dangerousPorts.Count -gt 0) { 'Some potentially dangerous ports detected.' } else { 'Port security looks normal.' }

        return New-BottleneckResult -Id 'PortSecurity' -Tier 'Standard' -Category 'Port Security' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckBrowserSecurity {
    try {
        $issues = @()
        $browsers = @()

        # Check Chrome version
        $chromePath = 'HKCU:\Software\Google\Chrome\BLBeacon'
        if (Test-Path $chromePath) {
            $chromeVersion = (Get-ItemProperty $chromePath -ErrorAction SilentlyContinue).version
            if ($chromeVersion) {
                $browsers += "Chrome $chromeVersion"
                # Simple version check (older than 100 is very old)
                if ($chromeVersion -match '^(\d+)' -and [int]$matches[1] -lt 100) {
                    $issues += 'Chrome is severely outdated'
                }
            }
        }

        # Check Edge version
        $edgeVersion = (Get-AppxPackage -Name 'Microsoft.MicrosoftEdge*' -ErrorAction SilentlyContinue).Version
        if ($edgeVersion) {
            $browsers += "Edge $edgeVersion"
        }

        # Check Firefox version
        $firefoxPath = 'HKLM:\SOFTWARE\Mozilla\Mozilla Firefox'
        if (Test-Path $firefoxPath) {
            $firefoxVersion = (Get-ItemProperty "$firefoxPath\*\Main" -ErrorAction SilentlyContinue | Select-Object -First 1).CurrentVersion
            if ($firefoxVersion) {
                $browsers += "Firefox $firefoxVersion"
                if ($firefoxVersion -match '^(\d+)' -and [int]$matches[1] -lt 100) {
                    $issues += 'Firefox is outdated'
                }
            }
        }

        # Check for dangerous Chrome extensions (would need more complex logic in real implementation)
        # Check HTTPS-only mode (registry check for browsers)

        # Check browser count
        if ($browsers.Count -eq 0) {
            $issues += 'No modern browser detected'
        }

        $impact = if ($issues.Count -gt 1) { 7 } elseif ($issues.Count -gt 0) { 5 } else { 2 }
        $confidence = 6
        $effort = 2
        $priority = 5
        $evidence = if ($browsers.Count -gt 0) { $browsers -join ', ' } else { 'No browsers detected' }
        if ($issues.Count -gt 0) {
            $evidence += " - Issues: $($issues -join '; ')"
        }
        $fixId = ''
        $msg = if ($issues.Count -gt 1) { 'Browser security needs attention.' } elseif ($issues.Count -gt 0) { 'Browser may have security issues.' } else { 'Browser security looks acceptable.' }

        return New-BottleneckResult -Id 'BrowserSecurity' -Tier 'Standard' -Category 'Browser Security' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}
