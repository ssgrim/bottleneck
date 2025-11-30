# Analyze-Network-Issues.ps1
# Comprehensive network diagnostics analysis and reporting

param(
    [string]$CsvPath,
    [switch]$GenerateHTML
)

$reportsDir = Join-Path $PSScriptRoot '..' '..' 'Reports'

# Find latest network monitor CSV if not specified
if (-not $CsvPath) {
    $latest = Get-ChildItem $reportsDir -Filter "network-monitor-*.csv" -ErrorAction SilentlyContinue | 
              Sort-Object LastWriteTime -Descending | 
              Select-Object -First 1
    if ($latest) {
        $CsvPath = $latest.FullName
    } else {
        Write-Error "No network monitor CSV found in $reportsDir"
        return
    }
}

if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    return
}

Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       COMPREHENSIVE NETWORK DIAGNOSTICS ANALYSIS         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "📊 Analyzing: $(Split-Path $CsvPath -Leaf)`n" -ForegroundColor Green

# Load data
$data = Import-Csv $CsvPath
$totalSamples = ($data | Where-Object { $_.Target -ne 'traceroute' }).Count
$duration = ((Get-Date $data[-1].Time) - (Get-Date $data[0].Time)).TotalMinutes

Write-Host "Session Summary:" -ForegroundColor Cyan
Write-Host "  Duration: $([math]::Round($duration,1)) minutes" -ForegroundColor White
Write-Host "  Total Samples: $totalSamples" -ForegroundColor White
Write-Host "  Targets: $(($data.Target | Sort-Object -Unique | Where-Object {$_ -ne 'traceroute'}) -join ', ')`n" -ForegroundColor White

# === CONNECTIVITY ANALYSIS ===
Write-Host "═══ CONNECTIVITY HEALTH ═══`n" -ForegroundColor Yellow

$perTarget = $data | Where-Object { $_.Target -ne 'traceroute' } | Group-Object Target

$targetStats = @()
foreach ($group in $perTarget) {
    $success = ($group.Group | Where-Object { $_.Success -eq 'True' }).Count
    $total = $group.Count
    $successPct = [math]::Round(100 * $success / $total, 2)
    
    $latencies = $group.Group | Where-Object { $_.Success -eq 'True' -and $_.LatencyMs -gt 0 } | Select-Object -ExpandProperty LatencyMs | ForEach-Object { [double]$_ }
    $avgLat = if ($latencies) { [math]::Round(($latencies | Measure-Object -Average).Average, 1) } else { 0 }
    
    $sorted = $latencies | Sort-Object
    $p95 = if ($sorted.Count -gt 0) { [math]::Round($sorted[[math]::Floor(0.95*$sorted.Count)], 1) } else { 0 }
    
    $jitter = if ($latencies.Count -gt 1) {
        $diffs = for($i=1; $i -lt $latencies.Count; $i++) { [math]::Abs($latencies[$i] - $latencies[$i-1]) }
        [math]::Round(($diffs | Measure-Object -Average).Average, 1)
    } else { 0 }
    
    $targetStats += [PSCustomObject]@{
        Target = $group.Name
        SuccessPct = $successPct
        Drops = $total - $success
        AvgLatency = $avgLat
        P95Latency = $p95
        Jitter = $jitter
        Samples = $total
    }
}

$targetStats | Format-Table -AutoSize

# === ISSUE IDENTIFICATION ===
Write-Host "`n═══ IDENTIFIED ISSUES ═══`n" -ForegroundColor Yellow

$issues = @()
$severity = @()

# Check for high packet loss
$worstTarget = $targetStats | Sort-Object SuccessPct | Select-Object -First 1
if ($worstTarget.SuccessPct -lt 95) {
    $issues += "High packet loss detected on $($worstTarget.Target): $($worstTarget.Drops) drops ($([math]::Round(100-$worstTarget.SuccessPct,1))% loss)"
    $severity += if ($worstTarget.SuccessPct -lt 80) { "CRITICAL" } else { "HIGH" }
}

# Check for high latency
$highLatTarget = $targetStats | Sort-Object P95Latency -Descending | Select-Object -First 1
if ($highLatTarget.P95Latency -gt 150) {
    $issues += "Elevated P95 latency on $($highLatTarget.Target): $($highLatTarget.P95Latency)ms (threshold: 150ms)"
    $severity += if ($highLatTarget.P95Latency -gt 300) { "HIGH" } else { "MEDIUM" }
}

# Check for high jitter
$highJitterTarget = $targetStats | Sort-Object Jitter -Descending | Select-Object -First 1
if ($highJitterTarget.Jitter -gt 20) {
    $issues += "High jitter/instability on $($highJitterTarget.Target): $($highJitterTarget.Jitter)ms avg variance"
    $severity += "MEDIUM"
}

# Detect failure clusters (consecutive drops)
Write-Host "Failure Pattern Analysis:" -ForegroundColor Cyan
$consecutiveFails = 0
$maxConsecutive = 0
$clusterCount = 0
$lastFail = $null

foreach ($row in ($data | Where-Object { $_.Target -ne 'traceroute' })) {
    if ($row.Success -eq 'False') {
        $consecutiveFails++
        if ($consecutiveFails -gt $maxConsecutive) { $maxConsecutive = $consecutiveFails }
        $lastFail = $row.Time
    } else {
        if ($consecutiveFails -ge 3) {
            $clusterCount++
        }
        $consecutiveFails = 0
    }
}

Write-Host "  Max Consecutive Drops: $maxConsecutive" -ForegroundColor White
Write-Host "  Failure Clusters (≥3): $clusterCount`n" -ForegroundColor White

if ($maxConsecutive -ge 5) {
    $issues += "Sustained connectivity loss detected: $maxConsecutive consecutive drops"
    $severity += "CRITICAL"
}

# === ROOT CAUSE ANALYSIS ===
Write-Host "═══ ROOT CAUSE ANALYSIS ═══`n" -ForegroundColor Yellow

$rcaReasons = @()

# DNS failures
$dnsFails = ($data | Where-Object { $_.DNSFail -eq 'True' }).Count
if ($dnsFails -gt ($totalSamples * 0.05)) {
    $rcaReasons += "DNS resolution failures ($dnsFails occurrences) suggest DNS server or configuration issues"
}

# Router failures
$routerFails = ($data | Where-Object { $_.RouterFail -eq 'True' }).Count
if ($routerFails -gt ($totalSamples * 0.05)) {
    $rcaReasons += "Router unreachable errors ($routerFails occurrences) indicate local network/gateway problems"
}

# ISP failures
$ispFails = ($data | Where-Object { $_.ISPFail -eq 'True' }).Count
if ($ispFails -gt ($totalSamples * 0.05)) {
    $rcaReasons += "ISP/upstream failures ($ispFails occurrences) point to provider-side issues"
}

# Overall assessment
if ($rcaReasons.Count -eq 0) {
    if ($worstTarget.SuccessPct -lt 98) {
        $rcaReasons += "Intermittent packet loss without specific failure pattern - possibly WiFi interference, congestion, or transient routing issues"
    } else {
        $rcaReasons += "Network performance is generally healthy with minor expected variance"
    }
}

$rcaReasons | ForEach-Object { Write-Host "  • $_" -ForegroundColor White }

# === PATH QUALITY (TRACEROUTE) ===
Write-Host "`n═══ PATH QUALITY ANALYSIS ═══`n" -ForegroundColor Yellow

$traceData = $data | Where-Object { $_.Target -eq 'traceroute' }
if ($traceData) {
    Write-Host "  Traceroute Snapshots: $($traceData.Count)" -ForegroundColor White
    
    # Parse hop info from notes
    $allHops = @{}
    foreach ($trace in $traceData) {
        $hops = $trace.Notes -split '\|'
        foreach ($hop in $hops) {
            if ($hop -match 'Hop:(\d+)\s+([^\s]+)') {
                $hopNum = $Matches[1]
                $hopIP = $Matches[2]
                if (-not $allHops.ContainsKey($hopIP)) {
                    $allHops[$hopIP] = @{ Count=0; HopNum=$hopNum }
                }
                $allHops[$hopIP].Count++
            }
        }
    }
    
    Write-Host "  Unique Hops Observed: $($allHops.Count)" -ForegroundColor White
    Write-Host "`n  Top 5 Most Frequent Hops:" -ForegroundColor Cyan
    $allHops.GetEnumerator() | Sort-Object {$_.Value.Count} -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Host "    Hop $($_.Value.HopNum): $($_.Key) (seen $($_.Value.Count) times)" -ForegroundColor White
    }
} else {
    Write-Host "  No traceroute data collected" -ForegroundColor Yellow
}

# === RECOMMENDATIONS ===
Write-Host "`n═══ RECOMMENDED ACTIONS ═══`n" -ForegroundColor Yellow

$recommendations = @()

if ($worstTarget.SuccessPct -lt 90) {
    $recommendations += @"
[IMMEDIATE] Investigate Local Network:
  • Check physical cable connections (if wired)
  • Test with ethernet cable if using WiFi
  • Restart router/modem (power cycle 30 seconds)
  • Check for WiFi interference (neighbors, microwaves, cordless phones)
"@
}

if ($dnsFails -gt 0) {
    $recommendations += @"
[HIGH] DNS Configuration:
  • Test alternative DNS servers (1.1.1.1, 8.8.8.8)
  • Flush DNS cache: ipconfig /flushdns
  • Check DNS server response time: nslookup google.com
"@
}

if ($highLatTarget.P95Latency -gt 200) {
    $recommendations += @"
[MEDIUM] Latency Optimization:
  • Run speed test to check bandwidth saturation
  • Check for background downloads/updates
  • Identify high-bandwidth applications with traffic monitor
  • Consider QoS settings on router
"@
}

if ($routerFails -gt 0) {
    $recommendations += @"
[MEDIUM] Gateway/Router Issues:
  • Check router firmware updates
  • Review router logs for errors
  • Test direct connection to modem (bypass router)
  • Consider router replacement if old (>5 years)
"@
}

if ($highJitterTarget.Jitter -gt 30) {
    $recommendations += @"
[MEDIUM] Stability Concerns:
  • Monitor concurrent connections/devices
  • Check for ISP traffic shaping/throttling
  • Test at different times of day
  • Consider business/dedicated connection if critical
"@
}

if ($ispFails -gt ($totalSamples * 0.1)) {
    $recommendations += @"
[HIGH] ISP Connectivity:
  • Contact ISP support with this diagnostic data
  • Request line quality test
  • Check service status page for known outages
  • Document issue timestamps for ISP escalation
"@
}

if ($recommendations.Count -eq 0) {
    $recommendations += @"
[INFO] Network Health Good:
  • Continue monitoring for pattern changes
  • Run periodic diagnostics (weekly baseline)
  • Document current performance as baseline
"@
}

$recommendations | ForEach-Object { 
    Write-Host $_ -ForegroundColor White
    Write-Host ""
}

# === ISSUE SUMMARY ===
if ($issues.Count -gt 0) {
    Write-Host "═══ ISSUE SUMMARY ═══`n" -ForegroundColor Red
    for ($i=0; $i -lt $issues.Count; $i++) {
        $color = switch ($severity[$i]) {
            'CRITICAL' { 'Red' }
            'HIGH' { 'Yellow' }
            'MEDIUM' { 'Cyan' }
            default { 'White' }
        }
        Write-Host "  [$($severity[$i])] $($issues[$i])" -ForegroundColor $color
    }
    Write-Host ""
}

# === ADAPTIVE METRICS UPDATE ===
Write-Host "═══ UPDATING ADAPTIVE METRICS ═══`n" -ForegroundColor Yellow

$modulePath = Join-Path $PSScriptRoot '..' 'src' 'ps' 'Bottleneck.psm1'
Import-Module $modulePath -Force -ErrorAction SilentlyContinue

if (Get-Command Update-BottleneckHistory -ErrorAction SilentlyContinue) {
    $summary = @{
        Network = @{
            SuccessRate = [math]::Round(($targetStats | Measure-Object -Property SuccessPct -Average).Average, 2)
            AvgLatency = [math]::Round(($targetStats | Measure-Object -Property AvgLatency -Average).Average, 1)
            P95Latency = [math]::Round(($targetStats | Measure-Object -Property P95Latency -Average).Average, 1)
            Drops = ($targetStats | Measure-Object -Property Drops -Sum).Sum
            LikelyCause = if ($rcaReasons.Count -gt 0) { $rcaReasons[0].Substring(0, [math]::Min(100, $rcaReasons[0].Length)) } else { "Normal" }
        }
    }
    Update-BottleneckHistory -Summary @{ Network=$summary.Network } | Out-Null
    Write-Host "✓ Adaptive history updated with session metrics" -ForegroundColor Green
} else {
    Write-Host "⚠️  Adaptive history module not available" -ForegroundColor Yellow
}

# === NEXT MONITORING RECOMMENDATION ===
Write-Host "`n═══ NEXT STEPS ═══`n" -ForegroundColor Yellow

if ($worstTarget.SuccessPct -lt 95) {
    Write-Host "  Recommended: Run extended 4-hour monitor to identify patterns" -ForegroundColor Cyan
    Write-Host "  Command: Invoke-BottleneckNetworkMonitor -Duration '4hours' -Interval 10 -UseAdaptiveTargets`n" -ForegroundColor Gray
} elseif ($highLatTarget.P95Latency -gt 150) {
    Write-Host "  Recommended: Run speedtest to check bandwidth" -ForegroundColor Cyan
    Write-Host "  Command: Invoke-BottleneckSpeedtest -Provider Auto -SaveHistory`n" -ForegroundColor Gray
} else {
    Write-Host "  Network appears stable - schedule periodic checks" -ForegroundColor Green
    Write-Host "  Command: Register-BottleneckScheduledScan -Type Network -Frequency Daily -Time '03:00'`n" -ForegroundColor Gray
}

Write-Host "✓ Analysis complete`n" -ForegroundColor Green
Write-Host "📄 Full CSV data: $CsvPath" -ForegroundColor Gray
Write-Host "📊 Generate HTML report: .\scripts\analyze-network-issues.ps1 -CsvPath '$CsvPath' -GenerateHTML`n" -ForegroundColor Gray
