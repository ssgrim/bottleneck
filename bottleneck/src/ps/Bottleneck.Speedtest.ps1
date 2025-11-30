# Bottleneck.Speedtest.ps1
# Integrated bandwidth speed testing with history tracking

function Invoke-BottleneckSpeedtest {
    <#
    .SYNOPSIS
    Runs a network bandwidth speed test and records results.
    
    .DESCRIPTION
    Measures download speed, upload speed, and base latency using HTTP file transfers.
    Results are saved to history for trending and degradation detection.
    Optionally uses Ookla CLI speedtest if installed for more accurate results.
    
    .PARAMETER Provider
    Test provider: 'Auto' (HTTP fallback), 'Ookla' (requires CLI), or 'Fast' (Netflix).
    
    .PARAMETER SaveHistory
    Save results to speedtest history file (default: true).
    
    .PARAMETER ShowTrend
    Display trend from last 5 tests after completion.
    
    .EXAMPLE
    Invoke-BottleneckSpeedtest
    
    .EXAMPLE
    Invoke-BottleneckSpeedtest -Provider Ookla -ShowTrend
    
    .NOTES
    For best results, close bandwidth-intensive apps before testing.
    Ookla provider requires: https://www.speedtest.net/apps/cli
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Auto','Ookla','Fast')]
        [string]$Provider = 'Auto',
        
        [bool]$SaveHistory = $true,
        
        [switch]$ShowTrend
    )
    
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              NETWORK BANDWIDTH SPEED TEST                 ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    $result = $null
    
    switch ($Provider) {
        'Ookla' {
            $result = Test-OoklaSpeedtest
        }
        'Fast' {
            $result = Test-FastSpeedtest
        }
        'Auto' {
            # Try Ookla first if available, fall back to HTTP
            if (Get-Command speedtest -ErrorAction SilentlyContinue) {
                Write-Host "📡 Using Ookla CLI speedtest..." -ForegroundColor Cyan
                $result = Test-OoklaSpeedtest
            } else {
                Write-Host "📡 Using built-in HTTP speed test..." -ForegroundColor Cyan
                $result = Test-HttpSpeedtest
            }
        }
    }
    
    if (-not $result) {
        Write-Warning "Speed test failed. Check network connectivity."
        return $null
    }
    
    # Display results
    Write-Host "`n✓ Speed Test Complete" -ForegroundColor Green
    Write-Host "`n┌─────────────────────────────────────────────────────────┐" -ForegroundColor Gray
    Write-Host "│ RESULTS                                                  │" -ForegroundColor Gray
    Write-Host "├─────────────────────────────────────────────────────────┤" -ForegroundColor Gray
    Write-Host ("│ Download:  {0,-10} Mbps                           │" -f ([math]::Round($result.DownMbps,2))) -ForegroundColor White
    Write-Host ("│ Upload:    {0,-10} Mbps                           │" -f ([math]::Round($result.UpMbps,2))) -ForegroundColor White
    Write-Host ("│ Latency:   {0,-10} ms                             │" -f ([math]::Round($result.LatencyMs,1))) -ForegroundColor White
    Write-Host ("│ Jitter:    {0,-10} ms                             │" -f ([math]::Round($result.JitterMs,1))) -ForegroundColor White
    Write-Host ("│ Server:    {0,-43}│" -f $result.Server.Substring(0,[math]::Min(43,$result.Server.Length))) -ForegroundColor White
    Write-Host "└─────────────────────────────────────────────────────────┘`n" -ForegroundColor Gray
    
    # Save to history
    if ($SaveHistory) {
        Save-SpeedtestHistory -Result $result
        Write-Host "💾 Result saved to history" -ForegroundColor Gray
    }
    
    # Show trend
    if ($ShowTrend) {
        Show-SpeedtestTrend -MaxResults 5
    }

    # Adaptive history update (Phase 2)
    try {
        if (Get-Command Get-CurrentMetrics -ErrorAction SilentlyContinue) {
            $metrics = Get-CurrentMetrics
            # Replace speedtest metrics with latest result
            $metrics.Speedtest = @{ DownloadMbps=$result.DownMbps; UploadMbps=$result.UpMbps; LatencyMs=$result.LatencyMs; JitterMs=$result.JitterMs; Provider=$result.Provider; Timestamp=$result.Timestamp }
            if (Get-Command Update-BottleneckHistory -ErrorAction SilentlyContinue) {
                Update-BottleneckHistory -Summary @{ System=$metrics.System; Network=$metrics.Network; PathQuality=$metrics.PathQuality; Speedtest=$metrics.Speedtest } | Out-Null
                Write-Host "📚 Historical metrics updated" -ForegroundColor Gray
            }
        }
    } catch { Write-Verbose "History update failed: $_" }
    
    return $result
}

function Test-OoklaSpeedtest {
    try {
        $output = & speedtest --accept-license --accept-gdpr --format=json 2>$null | ConvertFrom-Json
        
        if ($output.download -and $output.upload) {
            return [pscustomobject]@{
                Timestamp   = (Get-Date).ToString('s')
                Provider    = 'Ookla'
                Server      = "$($output.server.name) - $($output.server.location)"
                DownMbps    = [math]::Round($output.download.bandwidth / 125000, 2) # bytes/s to Mbps
                UpMbps      = [math]::Round($output.upload.bandwidth / 125000, 2)
                LatencyMs   = [math]::Round($output.ping.latency, 1)
                JitterMs    = [math]::Round($output.ping.jitter, 1)
                ISP         = $output.isp
                ExternalIP  = $output.interface.externalIp
            }
        }
    } catch {
        Write-Verbose "Ookla speedtest failed: $_"
    }
    return $null
}

function Test-FastSpeedtest {
    # Fast.com requires browser automation or unofficial API - stub for now
    Write-Warning "Fast.com provider not yet implemented. Use 'Auto' or 'Ookla'."
    return $null
}

function Test-HttpSpeedtest {
    Write-Host "  Testing download speed..." -ForegroundColor Gray
    
    # Use multiple test files for reliability
    $testUrls = @(
        'http://ipv4.download.thinkbroadband.com/10MB.zip',
        'http://speedtest.tele2.net/10MB.zip',
        'http://proof.ovh.net/files/10Mb.dat'
    )
    
    $downloadResults = @()
    
    foreach ($url in $testUrls) {
        try {
            $start = Get-Date
            $response = Invoke-WebRequest -Uri $url -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
            $elapsed = ((Get-Date) - $start).TotalSeconds
            
            if ($elapsed -gt 0 -and $response.RawContentLength -gt 0) {
                $mbps = [math]::Round(($response.RawContentLength * 8) / ($elapsed * 1000000), 2)
                $downloadResults += $mbps
                Write-Host "    └─ $([math]::Round($mbps,1)) Mbps" -ForegroundColor Green
                break # Use first successful test
            }
        } catch {
            Write-Verbose "Download test failed for $url : $_"
        }
    }
    
    # Upload test (POST to httpbin or similar)
    Write-Host "  Testing upload speed..." -ForegroundColor Gray
    $uploadMbps = 0
    try {
        $payload = [byte[]]::new(1MB)
        (New-Object Random).NextBytes($payload)
        $start = Get-Date
        $null = Invoke-WebRequest -Uri 'https://httpbin.org/post' -Method Post -Body $payload -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        $elapsed = ((Get-Date) - $start).TotalSeconds
        if ($elapsed -gt 0) {
            $uploadMbps = [math]::Round(($payload.Length * 8) / ($elapsed * 1000000), 2)
            Write-Host "    └─ $([math]::Round($uploadMbps,1)) Mbps" -ForegroundColor Green
        }
    } catch {
        Write-Verbose "Upload test failed: $_"
        $uploadMbps = 0
    }
    
    # Latency test
    Write-Host "  Testing latency..." -ForegroundColor Gray
    $latency = 0
    $jitter = 0
    try {
        $pings = @()
        for ($i=0; $i -lt 5; $i++) {
            $ping = Test-Connection -ComputerName '8.8.8.8' -Count 1 -ErrorAction Stop
            $pings += $ping.Latency
        }
        $latency = [math]::Round((($pings | Measure-Object -Average).Average), 1)
        $jitter = if ($pings.Count -gt 1) {
            $avg = ($pings | Measure-Object -Average).Average
            [math]::Round([math]::Sqrt((($pings | ForEach-Object { ($_ - $avg) * ($_ - $avg) }) | Measure-Object -Sum).Sum / $pings.Count), 1)
        } else { 0 }
        Write-Host "    └─ $latency ms (jitter: $jitter ms)" -ForegroundColor Green
    } catch {
        Write-Verbose "Latency test failed: $_"
    }
    
    if ($downloadResults.Count -eq 0) {
        return $null
    }
    
    return [pscustomobject]@{
        Timestamp   = (Get-Date).ToString('s')
        Provider    = 'HTTP'
        Server      = 'Multiple test servers'
        DownMbps    = ($downloadResults | Measure-Object -Average).Average
        UpMbps      = $uploadMbps
        LatencyMs   = $latency
        JitterMs    = $jitter
        ISP         = 'Unknown'
        ExternalIP  = 'Unknown'
    }
}

function Save-SpeedtestHistory {
    param([Parameter(Mandatory)]$Result)
    
    try {
        $historyFile = Join-Path $PSScriptRoot '..' '..' 'Reports' 'speedtest-history.json'
        
        $history = @()
        if (Test-Path $historyFile) {
            $history = Get-Content $historyFile | ConvertFrom-Json
        }
        
        $history += $Result
        
        # Keep last 100 entries
        if ($history.Count -gt 100) {
            $history = $history | Select-Object -Last 100
        }
        
        $history | ConvertTo-Json -Depth 5 | Set-Content $historyFile
    } catch {
        Write-Verbose "Could not save speedtest history: $_"
    }
}

function Get-SpeedtestHistory {
    <#
    .SYNOPSIS
    Retrieves speedtest history.
    
    .PARAMETER MaxResults
    Maximum number of recent results to return.
    #>
    param([int]$MaxResults = 10)
    
    try {
        $historyFile = Join-Path $PSScriptRoot '..' '..' 'Reports' 'speedtest-history.json'
        if (Test-Path $historyFile) {
            $history = Get-Content $historyFile | ConvertFrom-Json
            return $history | Select-Object -Last $MaxResults
        }
    } catch {}
    return @()
}

function Show-SpeedtestTrend {
    param([int]$MaxResults = 5)
    
    $history = Get-SpeedtestHistory -MaxResults $MaxResults
    
    if ($history.Count -eq 0) {
        Write-Host "`n📊 No historical data available yet." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n📊 Recent Speed Test Trend (last $($history.Count) tests):" -ForegroundColor Cyan
    Write-Host "┌────────────────────┬──────────┬──────────┬──────────┐" -ForegroundColor Gray
    Write-Host "│ Timestamp          │ Down     │ Up       │ Latency  │" -ForegroundColor Gray
    Write-Host "├────────────────────┼──────────┼──────────┼──────────┤" -ForegroundColor Gray
    
    foreach ($entry in $history) {
        $ts = ([datetime]$entry.Timestamp).ToString('yyyy-MM-dd HH:mm')
        Write-Host ("│ {0,-18} │ {1,6:N1} M │ {2,6:N1} M │ {3,6:N1} ms │" -f $ts, $entry.DownMbps, $entry.UpMbps, $entry.LatencyMs) -ForegroundColor White
    }
    
    Write-Host "└────────────────────┴──────────┴──────────┴──────────┘" -ForegroundColor Gray
    
    # Calculate trend
    if ($history.Count -gt 1) {
        $first = $history[0]
        $last = $history[-1]
        $downDelta = [math]::Round((($last.DownMbps - $first.DownMbps) / $first.DownMbps * 100), 1)
        $upDelta = [math]::Round((($last.UpMbps - $first.UpMbps) / $first.UpMbps * 100), 1)
        
        $downTrend = if ($downDelta -gt 5) { "↑ +$downDelta%" } elseif ($downDelta -lt -5) { "↓ $downDelta%" } else { "→ stable" }
        $upTrend = if ($upDelta -gt 5) { "↑ +$upDelta%" } elseif ($upDelta -lt -5) { "↓ $upDelta%" } else { "→ stable" }
        
        Write-Host "`nTrend: Download $downTrend | Upload $upTrend" -ForegroundColor $(if($downDelta -lt -10){'Red'}elseif($downDelta -gt 10){'Green'}else{'Yellow'})
    }
}

