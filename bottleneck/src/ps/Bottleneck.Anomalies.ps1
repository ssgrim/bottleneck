# Bottleneck.Anomalies.ps1
# Anomaly detection: latency z-score, loss bursts, jitter volatility

function Get-LatencyAnomalies {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$CsvPath,
        [int]$Window = 30,
        [double]$ZThreshold = 3.0
    )
    if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
    $data = Import-Csv $CsvPath | Where-Object { $_.Target -ne 'traceroute' -and $_.Success -eq 'True' }
    $lat = $data | Select-Object -ExpandProperty LatencyMs | ForEach-Object { [double]$_ }
    $anoms = @()
    for ($i=$Window; $i -lt $lat.Count; $i++) {
        $win = $lat[($i-$Window)..($i-1)]
        $avg = ($win | Measure-Object -Average).Average
        $sd = [math]::Sqrt(((($win | ForEach-Object { ($_ - $avg) * ($_ - $avg) }) | Measure-Object -Sum).Sum) / [double]$win.Count)
        if ($sd -le 0) { continue }
        $z = ($lat[$i] - $avg) / $sd
        if ($z -ge $ZThreshold) {
            $anoms += [pscustomobject]@{ Index=$i; Timestamp=$data[$i].Time; Target=$data[$i].Target; LatencyMs=$lat[$i]; ZScore=[math]::Round($z,2) }
        }
    }
    return $anoms
}

function Get-LossBursts {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$CsvPath,
        [int]$WindowSamples = 12,
        [double]$LossThresholdPct = 5.0
    )
    $data = Import-Csv $CsvPath | Where-Object { $_.Target -ne 'traceroute' }
    $bursts = @()
    for ($i=$WindowSamples; $i -lt $data.Count; $i++) {
        $win = $data[($i-$WindowSamples)..($i-1)]
        $drops = ($win | Where-Object { $_.Success -eq 'False' }).Count
        $lossPct = 100.0 * $drops / [double]$win.Count
        if ($lossPct -ge $LossThresholdPct) {
            $bursts += [pscustomobject]@{ Start=$win[0].Time; End=$win[-1].Time; LossPct=[math]::Round($lossPct,2); Drops=$drops; Window=$WindowSamples }
        }
    }
    # Deduplicate adjacent windows
    $merged = @(); $prev=$null
    foreach ($b in $bursts) {
        if ($prev -and ($b.Start -eq $prev.End)) { continue } else { $merged += $b; $prev=$b }
    }
    return $merged
}

function Get-JitterVolatility {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$CsvPath,
        [double]$Alpha = 0.3,
        [double]$VolThreshold = 20.0
    )
    $data = Import-Csv $CsvPath | Where-Object { $_.Target -ne 'traceroute' -and $_.Success -eq 'True' }
    $lat = $data | Select-Object -ExpandProperty LatencyMs | ForEach-Object { [double]$_ }
    if ($lat.Count -lt 3) { return @() }
    $ewma = $lat[0]
    $vols = @()
    for ($i=1; $i -lt $lat.Count; $i++) {
        $ewma = $Alpha*$lat[$i] + (1-$Alpha)*$ewma
        $diff = [math]::Abs($lat[$i] - $ewma)
        if ($diff -ge $VolThreshold) {
            $vols += [pscustomobject]@{ Index=$i; Timestamp=$data[$i].Time; Target=$data[$i].Target; LatencyMs=$lat[$i]; EWMA=[math]::Round($ewma,1); Divergence=[math]::Round($diff,1) }
        }
    }
    return $vols
}

Export-ModuleMember -Function Get-LatencyAnomalies, Get-LossBursts, Get-JitterVolatility
