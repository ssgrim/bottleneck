# Bottleneck.Network.ps1
# Advanced network diagnostics

function Test-BottleneckDNS {
    try {
        $testDomains = @('google.com', 'microsoft.com', 'cloudflare.com')
        $dnsServers = @{
            'Current' = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object -First 1).ServerAddresses[0]
            'Google' = '8.8.8.8'
            'Cloudflare' = '1.1.1.1'
        }

        $results = @()
        foreach ($domain in $testDomains) {
            $measure = Measure-Command {
                Resolve-DnsName -Name $domain -ErrorAction SilentlyContinue | Out-Null
            }
            $results += $measure.TotalMilliseconds
        }

        $avgDNS = [math]::Round(($results | Measure-Object -Average).Average, 1)

        # Check for DNS issues
        $currentDNS = $dnsServers['Current']
        $dnsConfig = if ($currentDNS) { $currentDNS } else { 'DHCP' }

        $impact = if ($avgDNS -gt 200) { 7 } elseif ($avgDNS -gt 100) { 5 } else { 2 }
        $confidence = 8
        $effort = 2
        $priority = 3
        $evidence = "Avg DNS lookup: $avgDNS ms, Server: $dnsConfig"
        $fixId = ''
        $msg = if ($avgDNS -gt 200) { 'DNS resolution is very slow.' } elseif ($avgDNS -gt 100) { 'DNS resolution slower than optimal.' } else { 'DNS resolution normal.' }

        return New-BottleneckResult -Id 'DNS' -Tier 'Standard' -Category 'DNS' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckNetworkAdapter {
    try {
        # Get active network adapters
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $issues = @()
        $adapterInfo = @()

        foreach ($adapter in $adapters) {
            # Check link speed
            $linkSpeed = $adapter.LinkSpeed
            $adapterInfo += "$($adapter.Name): $linkSpeed"

            # Check for outdated drivers
            $driver = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue

            # Check adapter statistics for packet loss
            $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
            if ($stats) {
                $receivedPackets = $stats.ReceivedUnicastPackets + $stats.ReceivedMulticastPackets
                $discarded = $stats.ReceivedDiscardedPackets
                if ($receivedPackets -gt 0) {
                    $lossPercent = ($discarded / $receivedPackets) * 100
                    if ($lossPercent -gt 1) {
                        $issues += "High packet loss on $($adapter.Name): $([math]::Round($lossPercent,2))%"
                    }
                }
            }

            # Check for low link speed on Ethernet
            if ($adapter.MediaType -eq '802.3' -and $linkSpeed -match '(\d+)') {
                $speedMbps = [int]$matches[1]
                if ($speedMbps -lt 1000) {
                    $issues += "$($adapter.Name) running at $linkSpeed (expected 1 Gbps)"
                }
            }
        }

        $impact = if ($issues.Count -gt 2) { 7 } elseif ($issues.Count -gt 0) { 5 } else { 2 }
        $confidence = 8
        $effort = 3
        $priority = 4
        $evidence = if ($issues.Count -gt 0) { $issues -join '; ' } else { $adapterInfo -join ', ' }
        $fixId = ''
        $msg = if ($issues.Count -gt 2) { 'Multiple network adapter issues detected.' } elseif ($issues.Count -gt 0) { 'Some network adapter issues found.' } else { 'Network adapters functioning normally.' }

        return New-BottleneckResult -Id 'NetworkAdapter' -Tier 'Standard' -Category 'Network Adapter' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckBandwidth {
    try {
        # Check for bandwidth-hogging processes
        $netstat = netstat -ano | Select-String 'ESTABLISHED'
        $connections = $netstat.Count

        # Get processes with network activity
        $networkProcs = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
            Group-Object OwningProcess |
            Sort-Object Count -Descending |
            Select-Object -First 5

        $topProcesses = @()
        foreach ($proc in $networkProcs) {
            try {
                $process = Get-Process -Id $proc.Name -ErrorAction SilentlyContinue
                if ($process) {
                    $topProcesses += "$($process.ProcessName) ($($proc.Count) connections)"
                }
            } catch { }
        }

        $impact = if ($connections -gt 200) { 6 } elseif ($connections -gt 100) { 4 } else { 2 }
        $confidence = 6
        $effort = 2
        $priority = 5
        $evidence = "Active connections: $connections. Top: $($topProcesses -join ', ')"
        $fixId = ''
        $msg = if ($connections -gt 200) { 'High number of network connections may impact bandwidth.' } elseif ($connections -gt 100) { 'Moderate network activity detected.' } else { 'Network activity normal.' }

        return New-BottleneckResult -Id 'Bandwidth' -Tier 'Standard' -Category 'Bandwidth' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckVPN {
    try {
        # Check for active VPN connections
        $vpnConnections = Get-VpnConnection -ErrorAction SilentlyContinue
        $activeVPN = $vpnConnections | Where-Object { $_.ConnectionStatus -eq 'Connected' }

        # Check for proxy settings
        $proxySettings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        $proxyEnabled = $proxySettings.ProxyEnable -eq 1
        $proxyServer = $proxySettings.ProxyServer

        $issues = @()
        if ($activeVPN) {
            $issues += "Active VPN: $($activeVPN.Name -join ', ')"
        }
        if ($proxyEnabled) {
            $issues += "Proxy enabled: $proxyServer"
        }

        # Check for third-party VPN adapters
        $vpnAdapters = Get-NetAdapter | Where-Object {
            $_.InterfaceDescription -match 'VPN|TAP|Cisco|OpenVPN|WireGuard|NordVPN|ExpressVPN'
        }
        if ($vpnAdapters) {
            $issues += "VPN adapters: $($vpnAdapters.Name -join ', ')"
        }

        $impact = if ($activeVPN -and $issues.Count -gt 1) { 5 } elseif ($issues.Count -gt 0) { 3 } else { 2 }
        $confidence = 7
        $effort = 2
        $priority = 6
        $evidence = if ($issues.Count -gt 0) { $issues -join '; ' } else { 'No VPN or proxy detected' }
        $fixId = ''
        $msg = if ($activeVPN) { 'VPN connection active - may impact network speed.' } elseif ($proxyEnabled) { 'Proxy settings enabled.' } else { 'No VPN or proxy interference.' }

        return New-BottleneckResult -Id 'VPN' -Tier 'Standard' -Category 'VPN/Proxy' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}

function Test-BottleneckFirewall {
    try {
        # Check Windows Firewall status
        $firewallProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $enabledProfiles = $firewallProfiles | Where-Object { $_.Enabled -eq $true }

        # Count firewall rules
        $rules = Get-NetFirewallRule -Enabled True -ErrorAction SilentlyContinue
        $ruleCount = $rules.Count

        # Check for blocked connections in last 24 hours
        $fwStart = (Get-Date).AddHours(-24)
        $fwFilter = @{ LogName='Security'; Id=5157; StartTime=$fwStart }
        $blockedEvents = Get-WinEvent -FilterHashtable $fwFilter -ErrorAction SilentlyContinue
        $blockedCount = if ($blockedEvents) { $blockedEvents.Count } else { 0 }

        # Check for third-party firewalls
        $thirdPartyFW = @()
        $fwProducts = @('Norton', 'McAfee', 'Kaspersky', 'Avast', 'AVG', 'Bitdefender', 'ZoneAlarm', 'Comodo')
        foreach ($product in $fwProducts) {
            $service = Get-Service -DisplayName "*$product*" -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }
            if ($service) {
                $thirdPartyFW += $product
            }
        }

        $impact = if ($ruleCount -gt 500) { 5 } elseif ($blockedCount -gt 100) { 4 } else { 2 }
        $confidence = 6
        $effort = 3
        $priority = 7
        $evidence = "Rules: $ruleCount, Blocked (24h): $blockedCount, 3rd party: $($thirdPartyFW -join ', ')"
        $fixId = ''
        $msg = if ($ruleCount -gt 500) { 'Excessive firewall rules may slow connections.' } elseif ($blockedCount -gt 100) { 'High number of blocked connections detected.' } else { 'Firewall configured normally.' }

        return New-BottleneckResult -Id 'Firewall' -Tier 'Standard' -Category 'Firewall' -Impact $impact -Confidence $confidence -Effort $effort -Priority $priority -Evidence $evidence -FixId $fixId -Message $msg
    } catch {
        return $null
    }
}
