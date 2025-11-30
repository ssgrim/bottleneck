# Bottleneck.NetworkMonitor.ps1
# Enhanced network monitoring with graceful shutdown and adaptive analysis

function Invoke-BottleneckNetworkMonitor {
    <#
    .SYNOPSIS
    Runs continuous network connectivity monitoring with automatic RCA report generation.
    
    .DESCRIPTION
    Long-running monitor that tracks latency, packet loss, and network path stability.
    Supports graceful Ctrl+C shutdown with automatic report generation.
    Learns from previous scans to provide adaptive recommendations.
    
    .PARAMETER Duration
    Monitoring duration: '5min', '15min', '1hour', '4hours', '8hours', 'continuous', or custom hours.
    
    .PARAMETER Interval
    Ping interval in seconds (default: 10).
    
    .PARAMETER Targets
    Hosts to monitor (default: intelligently selected based on history).
    
    .PARAMETER UseAdaptiveTargets
    When set, selects top scored targets from performance records.

    .PARAMETER TracerouteInterval
    Minutes between traceroute snapshots (default: 15, 0 to disable).
    
    .EXAMPLE
    Invoke-BottleneckNetworkMonitor -Duration '1hour'
    
    .EXAMPLE
    Invoke-BottleneckNetworkMonitor -Duration '4hours' -Interval 5 -Targets @('1.1.1.1','8.8.8.8')
    
    .EXAMPLE
    Invoke-BottleneckNetworkMonitor -Duration '30min' -UseAdaptiveTargets

    .NOTES
    Press Ctrl+C to stop gracefully and generate report.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('5min','15min','30min','1hour','2hours','4hours','8hours','continuous')]
        [string]$Duration = '1hour',
        
        [ValidateRange(1,300)]
        [int]$Interval = 10,
        
        [string[]]$Targets,

        [switch]$UseAdaptiveTargets,
        
        [int]$TracerouteInterval = 15
    )
    
    # Parse duration
    $durationHours = switch ($Duration) {
        '5min'   { 0.0833 }
        '15min'  { 0.25 }
        '30min'  { 0.5 }
        '1hour'  { 1 }
        '2hours' { 2 }
        '4hours' { 4 }
        '8hours' { 8 }
        'continuous' { 8760 } # 1 year (effectively continuous)
        default  { 1 }
    }
    
    # Adaptive / Scored target selection
    if (-not $Targets) {
        if ($UseAdaptiveTargets -and (Get-Command Get-RecommendedTargets -ErrorAction SilentlyContinue)) {
            $Targets = Get-RecommendedTargets -Count 3
        } else {
            $Targets = Get-AdaptiveNetworkTargets
        }
    }
    
    $primaryTarget = $Targets[0]
    $additionalTargets = $Targets | Select-Object -Skip 1
    
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           NETWORK CONNECTIVITY MONITOR                    ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    Write-Host "Configuration:" -ForegroundColor Green
    Write-Host "  Primary Target:  $primaryTarget" -ForegroundColor White
    Write-Host "  Additional:      $($additionalTargets -join ', ')" -ForegroundColor White
    Write-Host "  Duration:        $Duration" -ForegroundColor White
    Write-Host "  Interval:        ${Interval}s" -ForegroundColor White
    Write-Host "  Traceroute:      $(if($TracerouteInterval -eq 0){'Disabled'}else{"Every ${TracerouteInterval} min"})`n" -ForegroundColor White
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $reportsDir = Join-Path $PSScriptRoot '..' '..' 'Reports'
    if (!(Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
    $csvPath = Join-Path $reportsDir "network-monitor-$timestamp.csv"
    $pathQualityPath = Join-Path $reportsDir "path-quality-$timestamp.json"
    
    # CSV header
    Add-Content -Path $csvPath -Value 'Time,Target,Success,LatencyMs,RouterFail,DNSFail,ISPFail,Error,JitterMs,Notes'
    
    Write-Host "📊 Logging to: $(Split-Path $csvPath -Leaf)" -ForegroundColor Gray
    Write-Host "⚠️  Press Ctrl+C to stop and generate report`n" -ForegroundColor Yellow
    
    # Graceful shutdown handler
    $script:StopRequested = $false
    $script:CsvPath = $csvPath
    $script:MonitorResults = @()
    $script:HopStats = @{}
    $script:TracerouteRuns = 0
    
    [Console]::TreatControlCAsInput = $false
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        Write-Host "`n`n🛑 Shutdown signal received..." -ForegroundColor Yellow
        $script:StopRequested = $true
    }
    
    # Trap Ctrl+C
    trap {
        if ($_.Exception.Message -match 'Operation was canceled|terminated by the user') {
            Write-Host "`n`n🛑 Stopping monitor..." -ForegroundColor Yellow
            $script:StopRequested = $true
            continue
        }
    }
    
    $endTime = (Get-Date).AddHours($durationHours)
    $nextTrace = (Get-Date).AddMinutes($TracerouteInterval)
    $iteration = 0
    $startTime = Get-Date
    
    try {
        Write-Host "✓ Monitoring started at $($startTime.ToString('HH:mm:ss'))`n" -ForegroundColor Green
        
        while ((Get-Date) -lt $endTime -and -not $script:StopRequested) {
            $loopStart = Get-Date
            $iteration++
            
            # Check for Ctrl+C manually
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'C' -and $key.Modifiers -eq 'Control') {
                    $script:StopRequested = $true
                    break
                }
            }
            
            # Ping all targets
            foreach ($target in $Targets) {
                $result = Test-SingleHost -Target $target -Timestamp $loopStart
                $script:MonitorResults += $result
                
                # Log to CSV
                Add-Content -Path $csvPath -Value (@(
                    $result.Time, $result.Target, $result.Success, $result.LatencyMs,
                    $result.RouterFail, $result.DNSFail, $result.ISPFail,
                    ($result.Error -replace ',',';'), 0, $result.Notes
                ) -join ',')
                
                # Console output (every 12th iteration to avoid spam)
                if ($iteration % 12 -eq 0) {
                    if ($result.Success) {
                        Write-Host "[$($loopStart.ToString('HH:mm:ss'))] ✓ $($result.Target) : $($result.LatencyMs)ms" -ForegroundColor Green
                    } else {
                        Write-Host "[$($loopStart.ToString('HH:mm:ss'))] ✗ $($result.Target) : DROP" -ForegroundColor Red
                    }
                }
            }
            
            # Periodic traceroute
            if ($TracerouteInterval -gt 0 -and (Get-Date) -ge $nextTrace) {
                Write-Host "[$($loopStart.ToString('HH:mm:ss'))] 🔍 Running traceroute..." -ForegroundColor Cyan
                try {
                    $hops = Invoke-TracerouteSnapshot -Target $primaryTarget -TimeoutMs 1000
                    if ($hops) {
                        $script:TracerouteRuns++
                        foreach ($h in $hops) {
                            if (-not $h.IP -or $h.IP -eq '*') { continue }
                            if (-not $script:HopStats.ContainsKey($h.IP)) {
                                $script:HopStats[$h.IP] = [pscustomobject]@{ IP=$h.IP; HopIndices=@(); Samples=@(); ProbeCount=0; TimeoutCount=0 }
                            }
                            $entry = $script:HopStats[$h.IP]
                            if ($entry.HopIndices -notcontains $h.Hop) { $entry.HopIndices += $h.Hop }
                            # Record non-timeout latencies for average/p95
                            $valid = $h.ProbeLatencies | Where-Object { $_ -ge 0 }
                            if ($valid) { $entry.Samples += ($valid | ForEach-Object {[double]$_}) }
                            $entry.ProbeCount += ($h.ProbeLatencies.Count)
                            $entry.TimeoutCount += ($h.ProbeLatencies | Where-Object { $_ -lt 0 }).Count
                        }
                        $hopStr = ($hops | ForEach-Object { "Hop:$($_.Hop) $($_.IP)" }) -join '|'
                        Add-Content -Path $csvPath -Value "$($loopStart.ToString('s')),traceroute,true,0,false,false,false,,0,$hopStr"
                        Write-Host "  └─ $($hops.Count) hops recorded" -ForegroundColor Gray
                    }
                } catch {
                    Write-Host "  └─ Traceroute failed" -ForegroundColor Yellow
                }
                $nextTrace = (Get-Date).AddMinutes($TracerouteInterval)
            }
            
            Start-Sleep -Seconds $Interval
        }
    }
    finally {
        Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
        
        $actualDuration = ((Get-Date) - $startTime).TotalMinutes
        Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║              MONITORING SESSION COMPLETE                  ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
        
        Write-Host "📊 Session Summary:" -ForegroundColor Green
        Write-Host "  Duration:  $([math]::Round($actualDuration,1)) minutes" -ForegroundColor White
        Write-Host "  Samples:   $($script:MonitorResults.Count)" -ForegroundColor White
        Write-Host "  CSV:       $csvPath`n" -ForegroundColor White
        
        # Persist Path Quality summary (MTR-lite)
        try {
            if ($script:HopStats.Keys.Count -gt 0) {
                $hopTable = @()
                foreach ($ip in $script:HopStats.Keys) {
                    $e = $script:HopStats[$ip]
                    $avg = if ($e.Samples.Count -gt 0) { [math]::Round((($e.Samples | Measure-Object -Average).Average),1) } else { $null }
                    $sorted = $e.Samples | Sort-Object
                    $p95 = if ($sorted.Count -gt 0) { $sorted[[math]::Max([int]([math]::Floor(0.95*$sorted.Count))-1,0)] } else { $null }
                    $loss = if ($e.ProbeCount -gt 0) { [math]::Round(100.0 * $e.TimeoutCount / $e.ProbeCount,2) } else { $null }
                    $hopTable += [pscustomobject]@{
                        IP=$e.IP; HopIndices=($e.HopIndices -join ','); Samples=$e.Samples.Count; AvgMs=$avg; P95Ms=$p95; LossPct=$loss
                    }
                }
                $pq = @{ Target=$primaryTarget; Runs=$script:TracerouteRuns; Created=(Get-Date).ToString('s'); Hops=$hopTable }
                ($pq | ConvertTo-Json -Depth 6) | Set-Content -Path $pathQualityPath
                # Console summary of worst hop by loss then p95
                $worst = ($hopTable | Sort-Object @{Expression='LossPct';Descending=$true}, @{Expression='P95Ms';Descending=$true} | Select-Object -First 1)
                if ($worst) {
                    Write-Host "\n🕸️  Path Quality: worst hop $($worst.IP) loss=$($worst.LossPct)% p95=$($worst.P95Ms)ms (samples=$($worst.Samples))" -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Verbose "Could not persist path quality: $_"
        }

        # Generate RCA report automatically
        Write-Host "📈 Generating Root Cause Analysis..." -ForegroundColor Cyan
        try {
            $rca = Invoke-BottleneckNetworkRootCause -CsvPath $csvPath
            $diag = Invoke-BottleneckNetworkCsvDiagnostics -CsvPath $csvPath
            
            Write-Host "`n✓ Analysis Complete:" -ForegroundColor Green
            Write-Host "  Success Rate: $($rca.Summary.SuccessPct)%" -ForegroundColor White
            Write-Host "  Avg Latency:  $($rca.Summary.AvgLatencyMs)ms" -ForegroundColor White
            Write-Host "  P95 Latency:  $($rca.Summary.P95LatencyMs)ms" -ForegroundColor White
            Write-Host "  Drops:        $($rca.Summary.Drops)" -ForegroundColor White
            Write-Host "  Likely Cause: $($rca.LikelyCause)" -ForegroundColor Yellow
            
            if ($rca.Recommendations) {
                Write-Host "`n📋 Recommendations:" -ForegroundColor Cyan
                $rca.Recommendations | ForEach-Object { Write-Host "  • $_" -ForegroundColor White }
            }
            
            # Save adaptive baseline for future comparisons
            Save-NetworkBaseline -Results $script:MonitorResults -RCA $rca -Diagnostics $diag
            
            Write-Host "`n💡 Tip: Run 'Invoke-BottleneckNetworkScan' to generate full HTML report`n" -ForegroundColor Gray

            # Adaptive history update (Phase 2)
            try {
                if (Get-Command Get-CurrentMetrics -ErrorAction SilentlyContinue) {
                    $metrics = Get-CurrentMetrics
                    # Override network metrics with fresh RCA summary for consistency
                    $metrics.Network = @{ SuccessRate = $rca.Summary.SuccessPct; P95Latency = $rca.Summary.P95LatencyMs; AvgLatency = $rca.Summary.AvgLatencyMs; Drops = $rca.Summary.Drops; LikelyCause = $rca.LikelyCause }
                    # Worst hop if available
                    if ($worst) { $metrics.PathQuality = @{ WorstHopIP = $worst.IP; WorstHopLossPercent = $worst.LossPct; WorstHopP95Ms = $worst.P95Ms } }
                    if (Get-Command Update-BottleneckHistory -ErrorAction SilentlyContinue) {
                        Update-BottleneckHistory -Summary @{ System=$metrics.System; Network=$metrics.Network; PathQuality=$metrics.PathQuality; Speedtest=$metrics.Speedtest } | Out-Null
                        Write-Host "📚 Historical metrics updated" -ForegroundColor Gray
                    }
                }
            } catch { Write-Verbose "History update failed: $_" }
            
        } catch {
            Write-Warning "RCA generation failed: $_"
        }
    }
}

# Helper function to test single host
function Test-SingleHost {
    param([string]$Target, [datetime]$Timestamp)
    
    $success = $false; $lat = 0; $routerFail=$false; $dnsFail=$false; $ispFail=$false; $err=''; $notes=''
    
    try {
        $ping = Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop
        $lat = [math]::Round($ping.Latency, 2)
        $success = $true
    } catch {
        $err = $_.Exception.Message
        $dnsFail = ($err -match 'NameResolutionFailure|No such host is known')
        $routerFail = ($err -match 'Destination host unreachable|Request timed out')
        $ispFail = (-not $dnsFail -and -not $routerFail)
        $notes = 'drop'
    }
    
    [pscustomobject]@{
        Time = $Timestamp.ToString('s')
        Target = $Target
        Success = $success
        LatencyMs = $lat
        RouterFail = $routerFail
        DNSFail = $dnsFail
        ISPFail = $ispFail
        Error = $err
        Notes = $notes
    }
}

# Traceroute snapshot returning hop objects with per-probe latencies
function Invoke-TracerouteSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Target,
        [int]$TimeoutMs = 1000
    )
    try {
        $args = "-d -w $TimeoutMs $Target"
        $output = & tracert $args 2>$null
        if (-not $output) { return @() }
        $hops = @()
        foreach ($line in $output) {
            # Example: "  1     <1 ms    <1 ms     1 ms  192.168.1.1"
            if ($line -match '^\s*(\d+)\s+(.+)$') {
                $hopNum = [int]$Matches[1]
                # Extract three probe fields and IP at end
                $m = [regex]::Match($line, '^\s*(\d+)\s+([^\s]+\s+ms|\*)\s+([^\s]+\s+ms|\*)\s+([^\s]+\s+ms|\*)\s+([^\s]+)')
                if ($m.Success) {
                    $probes = @($m.Groups[2].Value, $m.Groups[3].Value, $m.Groups[4].Value) | ForEach-Object {
                        if ($_ -eq '*') { -1 } else { $v = ($_ -replace 'ms','').Trim(); $v = $v -replace '<',''; [double]$v }
                    }
                    $ip = $m.Groups[5].Value
                    $hops += [pscustomobject]@{ Hop=$hopNum; IP=$ip; ProbeLatencies=$probes }
                }
            }
        }
        return $hops
    } catch {
        return @()
    }
}

# Adaptive target selection based on history
function Get-AdaptiveNetworkTargets {
    $defaultTargets = @('1.1.1.1', '8.8.8.8', 'www.google.com')
    
    try {
        $historyFile = Join-Path $PSScriptRoot '..' '..' 'Reports' 'network-baseline.json'
        if (Test-Path $historyFile) {
            $baseline = Get-Content $historyFile | ConvertFrom-Json
            if ($baseline.RecommendedTargets) {
                return $baseline.RecommendedTargets
            }
        }
    } catch {}
    
    return $defaultTargets
}

# Save baseline for adaptive analysis
function Save-NetworkBaseline {
    param($Results, $RCA, $Diagnostics)
    
    try {
        $baselineFile = Join-Path $PSScriptRoot '..' '..' 'Reports' 'network-baseline.json'
        
        $baseline = @{
            LastUpdated = (Get-Date).ToString('s')
            Samples = $Results.Count
            SuccessRate = $RCA.Summary.SuccessPct
            AvgLatency = $RCA.Summary.AvgLatencyMs
            P95Latency = $RCA.Summary.P95LatencyMs
            WorstHost = if ($Diagnostics) { $Diagnostics.HostComparison.WorstTarget } else { $null }
            BestHost = if ($Diagnostics) { $Diagnostics.HostComparison.BestTarget } else { $null }
            RecommendedTargets = if ($Diagnostics) { 
                ($Diagnostics.PerTargetStats | Where-Object { $_.AvgLatencyMs -gt 0 } | Sort-Object AvgLatencyMs | Select-Object -First 3 -Expand Target)
            } else { @('1.1.1.1','8.8.8.8','www.google.com') }
            LikelyCause = $RCA.LikelyCause
        }
        
        $baseline | ConvertTo-Json -Depth 5 | Set-Content $baselineFile
    } catch {
        Write-Verbose "Could not save baseline: $_"
    }
}

