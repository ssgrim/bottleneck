# Bottleneck.Adaptive.ps1
# Phase 2 Adaptive Analysis Engine (initial scaffold)
$script:HistoryFile = Join-Path $PSScriptRoot '..' '..' 'Reports' 'scan-history.json'

function Update-BottleneckHistory {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][hashtable]$Summary,
        [int]$MaxDays = 30
    )
    $history = if (Test-Path $script:HistoryFile) { (Get-Content $script:HistoryFile | ConvertFrom-Json) } else { @() }
    $entry = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        System    = $Summary.System
        Network   = $Summary.Network
        PathQuality = $Summary.PathQuality
        Speedtest = $Summary.Speedtest
    }
    $history = $history + $entry
    # Trim by days
    $cutoff = (Get-Date).AddDays(-$MaxDays)
    $history = $history | Where-Object { [DateTime]$_.Timestamp -ge $cutoff }
    $history | ConvertTo-Json -Depth 6 | Set-Content $script:HistoryFile -Encoding UTF8
    return $entry
}

function Get-BottleneckDriftReport {
    [CmdletBinding()] param(
        [int]$WindowDays = 14,
        [int]$CompareDays = 7
    )
    if (-not (Test-Path $script:HistoryFile)) { return @() }
    $history = Get-Content $script:HistoryFile | ConvertFrom-Json
    if ($history.Count -lt 5) { return @() }

    $now = Get-Date
    $windowCut = $now.AddDays(-$WindowDays)
    $compareCut = $now.AddDays(-$CompareDays)
    $windowData = $history | Where-Object { [DateTime]$_.Timestamp -ge $windowCut }
    $recentData = $history | Where-Object { [DateTime]$_.Timestamp -ge $compareCut }
    if (-not $windowData -or -not $recentData) { return @() }

    $avgSuccessWindow = ($windowData | Where-Object Network | Measure-Object -Property Network.SuccessRate -Average).Average
    $avgSuccessRecent = ($recentData | Where-Object Network | Measure-Object -Property Network.SuccessRate -Average).Average
    $avgP95Window = ($windowData | Where-Object Network | Measure-Object -Property Network.P95Latency -Average).Average
    $avgP95Recent = ($recentData | Where-Object Network | Measure-Object -Property Network.P95Latency -Average).Average

    $successDiffPct = if ($avgSuccessWindow) { [math]::Round((($avgSuccessRecent - $avgSuccessWindow) / $avgSuccessWindow) * 100,2) } else { 0 }
    $p95DiffPct = if ($avgP95Window) { [math]::Round((($avgP95Recent - $avgP95Window) / $avgP95Window) * 100,2) } else { 0 }

    [pscustomobject]@{
        SuccessRateWindow = [math]::Round($avgSuccessWindow,2)
        SuccessRateRecent = [math]::Round($avgSuccessRecent,2)
        SuccessRateDriftPercent = $successDiffPct
        P95LatencyWindow = [math]::Round($avgP95Window,2)
        P95LatencyRecent = [math]::Round($avgP95Recent,2)
        P95LatencyDriftPercent = $p95DiffPct
        SuccessConcern = ($successDiffPct -lt -1.5)
        LatencyConcern = ($p95DiffPct -gt 20)
    }
}

function Get-BottleneckRecurringIssues {
    [CmdletBinding()] param(
        [int]$MinOccurrences = 3
    )
    if (-not (Test-Path $script:HistoryFile)) { return @() }
    $history = Get-Content $script:HistoryFile | ConvertFrom-Json
    $causes = $history | Where-Object { $_.Network.LikelyCause } | Group-Object { $_.Network.LikelyCause }
    $repeat = $causes | Where-Object { $_.Count -ge $MinOccurrences } | ForEach-Object {
        [pscustomobject]@{ Cause = $_.Name; Occurrences = $_.Count }
    }
    return $repeat | Sort-Object Occurrences -Descending
}

function Get-BottleneckAdaptiveRecommendations {
    [CmdletBinding()] param()
    $recs = @()
    $drift = Get-BottleneckDriftReport
    if ($drift) {
        if ($drift.SuccessConcern) { $recs += 'Network success rate declining (>1.5% drop). Investigate intermittent packet loss or DNS resolution issues.' }
        if ($drift.LatencyConcern) { $recs += 'Latency rising (>20% P95 increase). Check path-quality worst hop or ISP congestion.' }
    }
    $repeat = Get-BottleneckRecurringIssues
    foreach ($r in $repeat) {
        $recs += "Recurring issue detected: $($r.Cause) appears $($r.Occurrences)x. Consider targeted remediation." 
    }
    if (-not $recs) { $recs = 'No adaptive concerns detected.' }
    return $recs
}
