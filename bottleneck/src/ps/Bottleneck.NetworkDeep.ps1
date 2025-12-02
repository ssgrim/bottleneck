# Bottleneck.NetworkDeep.ps1
# Deep network root-cause analysis utilities

# Ensure logging initializer is available when invoked standalone
try {
    if (-not (Get-Command Initialize-BottleneckLogging -ErrorAction SilentlyContinue)) {
        $logPath = Join-Path $PSScriptRoot 'Bottleneck.Logging.ps1'
        if (Test-Path $logPath) { . $logPath }
    }
    if (-not (Get-Command Get-FusedAlertLevel -ErrorAction SilentlyContinue)) {
        $alertsPath = Join-Path $PSScriptRoot 'Bottleneck.Alerts.ps1'
        if (Test-Path $alertsPath) { . $alertsPath }
    }
} catch {}

function Invoke-BottleneckNetworkRootCause {
    [CmdletBinding()]
    param(
        [Parameter()][string[]]$Targets = @('www.yahoo.com','www.google.com','1.1.1.1'),
        [Parameter()][string]$CsvPath,
        [Parameter()][int]$WindowMinutes = 5,
        [Parameter()][int]$TracerouteIntervalMinutes = 10,
        [switch]$DisableProbes,
        [switch]$DisableTraceroute
    )

    # Resolve CSV automatically if not provided
    if (-not $CsvPath) {
        $reports = Join-Path $PSScriptRoot '..' '..' 'Reports'
        $csv = Get-ChildItem $reports -Filter 'network-monitor-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($csv) { $CsvPath = $csv.FullName } else { throw 'No network-monitor CSV found' }
    }

    $rows = Import-Csv $CsvPath
    if (-not $rows -or $rows.Count -eq 0) { throw 'CSV empty or unreadable' }

    # Normalize schema across legacy and new monitor formats
    # Legacy columns: Timestamp, Status, ResponseTime, DNS, Router, ISP
    # New columns   : Time, Target, Success, LatencyMs, RouterFail, DNSFail, ISPFail, Error, JitterMs, Notes
    $hasLegacy = $rows[0].PSObject.Properties.Name -contains 'Timestamp'
    $normalized = foreach ($r in $rows) {
        if ($hasLegacy) {
            [pscustomobject]@{
                Timestamp   = $r.Timestamp
                Status      = $r.Status
                ResponseMs  = [double]($r.ResponseTime)
                DNSFail     = if ($r.DNS -eq 'Fail') { $true } else { $false }
                RouterFail  = if ($r.Router -eq 'Fail') { $true } else { $false }
                ISPFail     = if ($r.ISP -eq 'Fail') { $true } else { $false }
                Target      = $r.Target
            }
        } else {
            [pscustomobject]@{
                Timestamp   = $r.Time
                Status      = if ($r.Success -eq 'True' -or $r.Success -eq $true) { 'Success' } else { 'Fail' }
                ResponseMs  = [double]($r.LatencyMs)
                DNSFail     = ($r.DNSFail -eq 'True' -or $r.DNSFail -eq $true)
                RouterFail  = ($r.RouterFail -eq 'True' -or $r.RouterFail -eq $true)
                ISPFail     = ($r.ISPFail -eq 'True' -or $r.ISPFail -eq $true)
                Target      = $r.Target
            }
        }
    }

    # Aggregate basic stats
    $ok   = $normalized | Where-Object { $_.Status -eq 'Success' }
    $fail = $normalized | Where-Object { $_.Status -ne 'Success' }
    $lat  = $ok | Where-Object { $_.ResponseMs -ne $null -and $_.ResponseMs -gt 0 } | Select-Object -Expand ResponseMs

    $stats = [pscustomobject]@{
        Samples        = $normalized.Count
        SuccessPct     = if ($normalized.Count) { [math]::Round(100.0 * $ok.Count / $normalized.Count, 2) } else { 0 }
        AvgLatencyMs   = if ($lat.Count) { [math]::Round((($lat | Measure-Object -Average).Average),1) } else { 0 }
        P95LatencyMs   = if ($lat.Count) { ($lat | Sort-Object)[[math]::Max([int]([math]::Floor(0.95*$lat.Count))-1,0)] } else { 0 }
        MaxLatencyMs   = if ($lat.Count) { (($lat | Measure-Object -Maximum).Maximum) } else { 0 }
        Drops          = $fail.Count
        DNSFailures    = ($normalized | Where-Object { $_.DNSFail } | Measure-Object).Count
        RouterFailures = ($normalized | Where-Object { $_.RouterFail } | Measure-Object).Count
        ISPFailures    = ($normalized | Where-Object { $_.ISPFail } | Measure-Object).Count
    }

    # Per-minute jitter
    $byMinute = $ok | Where-Object { $_.Timestamp } | Group-Object { ([datetime]$_.Timestamp).ToString('yyyy-MM-dd HH:mm') } |
        ForEach-Object {
            $vals = $_.Group | Select-Object -Expand ResponseMs
            $avg = ($vals | Measure-Object -Average).Average
            $sd  = if ($vals.Count -gt 1) {
                $m=$avg; [math]::Sqrt((($vals | ForEach-Object { ($_-$m)*($_-$m) }) | Measure-Object -Sum).Sum / $vals.Count)
            } else { 0 }
            [pscustomobject]@{ Minute=$_.Name; Count=$vals.Count; AvgMs=[math]::Round($avg,1); JitterMs=[math]::Round($sd,1) }
        }

    # Failure clusters (>=3 failures within same minute)
    $clusters = $normalized | Where-Object { $_.Status -ne 'Success' -and $_.Timestamp } |
        Group-Object { ([datetime]$_.Timestamp).ToString('yyyy-MM-dd HH:mm') } |
        Where-Object { $_.Count -ge 3 } |
        Select-Object Name,Count

    # Multi-host probe (current state)
    $probes = @()
    if (-not $DisableProbes) {
        foreach ($t in $Targets) {
            try {
                $latency = (Test-Connection -ComputerName $t -Count 3 -ErrorAction SilentlyContinue | Measure-Object ResponseTime -Average).Average
                $result = [pscustomobject]@{ Target=$t; AvgLatencyMs=[math]::Round(($latency),1) }
                $probes += $result
            } catch {
                $probes += [pscustomobject]@{ Target=$t; AvgLatencyMs=$null }
            }
        }
    }

    # Traceroute snapshot (single run)
    $trace = @()
    if (-not $DisableTraceroute) {
        foreach ($t in $Targets | Select-Object -First 1) {
            try {
                $hop = Test-NetConnection -ComputerName $t -TraceRoute -ErrorAction SilentlyContinue
                if ($hop) { $trace = $hop.TraceRoute }
            } catch {}
        }
    }

    # Cause classification
    $cause = 'Stable'
    if ($stats.Drops -gt 0) {
        if ($stats.RouterFailures -ge [math]::Max(1, [math]::Floor($stats.Drops*0.5))) { $cause = 'Local Router/Wi-Fi' }
        elseif ($stats.DNSFailures -ge [math]::Max(1, [math]::Floor($stats.Drops*0.3))) { $cause = 'DNS Resolution' }
        elseif ($stats.ISPFailures -ge [math]::Max(1, [math]::Floor($stats.Drops*0.3))) { $cause = 'ISP/Upstream' }
        else { $cause = 'Unclassified Drops' }
    } elseif ($stats.P95LatencyMs -gt 150 -or $stats.MaxLatencyMs -gt 300) {
        $cause = 'Congestion/Interference'
    }

    # Recommendations
    $reco = @()
    switch ($cause) {
        'Stable' { $reco += 'No action needed; network is stable.' }
        'Local Router/Wi-Fi' { $reco += 'Update router firmware, switch to 5 GHz, change Wi-Fi channel, or use Ethernet.' }
        'DNS Resolution' { $reco += 'Set adapter DNS to 1.1.1.1 and 8.8.8.8; retry test.' }
        'ISP/Upstream' { $reco += 'Run multi-host monitor and periodic traceroutes; contact ISP if persistent.' }
        'Unclassified Drops' { $reco += 'Enable multi-host + traceroute snapshots; consider interference scan; retry on Ethernet.' }
        'Congestion/Interference' { $reco += 'Reduce concurrent heavy usage, prefer wired, optimize router placement and channel.' }
    }

    $output = [pscustomobject]@{
        Summary        = $stats
        JitterByMinute = $byMinute
        FailureClusters= $clusters
        Probes         = $probes
        TraceRoute     = $trace
        LikelyCause    = $cause
        Recommendations= $reco
        FusedAlertLevel= (Get-FusedAlertLevel -LatencySpikes ($byMinute | Where-Object { $_.JitterMs -gt 0 -and $_.AvgMs -gt 0 -and $_.AvgMs -ge ($stats.P95LatencyMs) }) -LossBursts $clusters -JitterVolatility ($byMinute | Where-Object { $_.JitterMs -ge 15 }))
        SourceCsv      = $CsvPath
    }
    $level = $output.FusedAlertLevel
    if ($level) { Write-Host "Network Fused Alert Level: $level" -ForegroundColor Yellow }
    return $output
}

# Advanced CSV diagnostics (per-target distributions, spikes, jitter, comparison)
function Invoke-BottleneckNetworkCsvDiagnostics {
    [CmdletBinding()] param([string]$CsvPath)
    if (-not $CsvPath) {
        $reports = Join-Path $PSScriptRoot '..' '..' 'Reports'
        $CsvPath = (Get-ChildItem $reports -Filter 'network-monitor-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
        if (-not $CsvPath) { throw 'No network-monitor CSV found' }
    }
    $raw = Import-Csv $CsvPath
    if (-not $raw -or $raw.Count -eq 0) { throw 'CSV empty or unreadable' }

    $isLegacy = $raw[0].PSObject.Properties.Name -contains 'Timestamp'
    $rows = $raw | ForEach-Object {
        if ($isLegacy) {
            [pscustomobject]@{ Time=$_.Timestamp; Target=$_.Target; Success=($_.Status -eq 'Success'); LatencyMs=[double]($_.ResponseTime); DNSFail=($_.DNS -eq 'Fail'); RouterFail=($_.Router -eq 'Fail'); ISPFail=($_.ISP -eq 'Fail') }
        } else {
            [pscustomobject]@{ Time=$_.Time; Target=$_.Target; Success=($_.Success -eq 'True' -or $_.Success -eq $true); LatencyMs=[double]($_.LatencyMs); DNSFail=($_.DNSFail -eq 'True' -or $_.DNSFail -eq $true); RouterFail=($_.RouterFail -eq 'True' -or $_.RouterFail -eq $true); ISPFail=($_.ISPFail -eq 'True' -or $_.ISPFail -eq $true) }
        }
    } | Where-Object { $_.Target -and $_.Target -ne 'traceroute' }

    $computeQuantiles = {
        param([double[]]$vals)
        if (-not $vals -or $vals.Count -eq 0) { return [pscustomobject]@{ P50=0; P95=0; P99=0; Q1=0; Q3=0 } }
        $sorted = $vals | Sort-Object
        $getIndex = { param($p) $i = [math]::Floor($p*($sorted.Count))-1; if ($i -lt 0) { $i = 0 }; $sorted[$i] }
        $q1 = & $getIndex 0.25; $p50 = & $getIndex 0.50; $p95 = & $getIndex 0.95; $p99 = & $getIndex 0.99; $q3 = & $getIndex 0.75
        [pscustomobject]@{ P50=[math]::Round($p50,1); P95=[math]::Round($p95,1); P99=[math]::Round($p99,1); Q1=[math]::Round($q1,1); Q3=[math]::Round($q3,1) }
    }

    $perTarget = $rows | Group-Object Target | ForEach-Object {
        $lat = $_.Group | Where-Object { $_.Success -and $_.LatencyMs -gt 0 } | Select-Object -Expand LatencyMs
        $q = & $computeQuantiles $lat
        $drops = $_.Group.Count - ($_.Group | Where-Object { $_.Success }).Count
        [pscustomobject]@{
            Target=$_.Name
            Samples=$_.Group.Count
            SuccessPct= if ($_.Group.Count){ [math]::Round(100 * ($_.Group | Where-Object { $_.Success }).Count / $_.Group.Count,2)} else {0}
            AvgLatencyMs= if ($lat.Count){ [math]::Round((($lat | Measure-Object -Average).Average),1)} else {0}
            MaxLatencyMs= if ($lat.Count){ ($lat | Measure-Object -Maximum).Maximum } else {0}
            Drops=$drops
            P50=$q.P50; P95=$q.P95; P99=$q.P99; Q1=$q.Q1; Q3=$q.Q3
            DNSFailures= ($_.Group | Where-Object { $_.DNSFail }).Count
            RouterFailures= ($_.Group | Where-Object { $_.RouterFail }).Count
            ISPFailures= ($_.Group | Where-Object { $_.ISPFail }).Count
        }
    }

    # Spike threshold: Q3 + 1.5*IQR per target, mark minutes containing outliers
    $spikeMinutes = @()
    foreach ($t in $perTarget) {
        $iqr = $t.Q3 - $t.Q1; $threshold = $t.Q3 + 1.5 * $iqr
        $minutes = $rows | Where-Object { $_.Target -eq $t.Target -and $_.LatencyMs -ge $threshold -and $_.LatencyMs -gt 0 } |
            Group-Object { ([datetime]$_.Time).ToString('yyyy-MM-dd HH:mm') } |
            ForEach-Object { [pscustomobject]@{ Target=$t.Target; Minute=$_.Name; SpikeSamples=$_.Count; MaxSpike= ($_.Group | Measure-Object LatencyMs -Maximum).Maximum; Threshold=[math]::Round($threshold,1) } }
        $spikeMinutes += $minutes
    }

    # Jitter per minute (top 5 by std dev across all targets)
    $jitter = $rows | Where-Object { $_.Success -and $_.LatencyMs -gt 0 } |
        Group-Object { ([datetime]$_.Time).ToString('yyyy-MM-dd HH:mm') } |
        ForEach-Object {
            $vals = $_.Group | Select-Object -Expand LatencyMs
            $avg = ($vals | Measure-Object -Average).Average
            $sd = if ($vals.Count -gt 1){ $m=$avg; [math]::Sqrt((($vals | ForEach-Object { ($_-$m)*($_-$m) } ) | Measure-Object -Sum).Sum / $vals.Count) } else { 0 }
            [pscustomobject]@{ Minute=$_.Name; Samples=$vals.Count; AvgMs=[math]::Round($avg,1); JitterMs=[math]::Round($sd,1) }
        } | Sort-Object JitterMs -Descending | Select-Object -First 5

    # Host comparison summary
    $best = $null; $worst = $null
    if ($perTarget -and $perTarget.Count -gt 0) {
        $best = ($perTarget | Where-Object { $_.AvgLatencyMs -ge 0 } | Sort-Object AvgLatencyMs | Select-Object -First 1)
        $worst = ($perTarget | Where-Object { $_.AvgLatencyMs -ge 0 } | Sort-Object AvgLatencyMs -Descending | Select-Object -First 1)
    }
    $comparison = [pscustomobject]@{
        BestTarget= if($best){$best.Target}else{$null}; BestAvgMs= if($best){$best.AvgLatencyMs}else{$null};
        WorstTarget= if($worst){$worst.Target}else{$null}; WorstAvgMs= if($worst){$worst.AvgLatencyMs}else{$null};
        DifferentialMs= if($best -and $worst){ [math]::Round(($worst.AvgLatencyMs - $best.AvgLatencyMs),1) } else { $null }
    }

    $result = [pscustomobject]@{
        PerTargetStats = $perTarget
        SpikeMinutes   = $spikeMinutes
        TopJitterMinutes = $jitter
        HostComparison = $comparison
        FusedAlertLevel = (Get-FusedAlertLevel -LatencySpikes $spikeMinutes -LossBursts ($rows | Where-Object { -not $_.Success } | Group-Object { ([datetime]$_.Time).ToString('yyyy-MM-dd HH:mm') } | Where-Object { $_.Count -ge 3 }) -JitterVolatility ($jitter | Where-Object { $_.JitterMs -ge 15 }))
        SourceCsv = $CsvPath
    }
    if ($result.FusedAlertLevel) { Write-Host "CSV Diagnostics Fused Alert: $($result.FusedAlertLevel)" -ForegroundColor Yellow }
    return $result
}
