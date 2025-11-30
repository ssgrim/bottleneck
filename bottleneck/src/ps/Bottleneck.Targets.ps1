# Bottleneck.Targets.ps1
# Smart target selection and performance scoring (Phase 2)

function Get-BottleneckBaseTargets {
    <#
    .SYNOPSIS
    Returns a base pool of candidate network targets.
    .DESCRIPTION
    Provides a diversified set of stable public endpoints (DNS anycast, CDN edges, major sites)
    used for adaptive monitoring target rotation and scoring.
    #>
    [CmdletBinding()] param()
    @(
        '1.1.1.1','8.8.8.8','9.9.9.9','208.67.222.222', # DNS
        'www.google.com','www.microsoft.com','www.cloudflare.com','www.github.com',
        'akamai.com','fastly.com','vercel.com',
        'download.windowsupdate.com','edge.microsoft.com'
    ) | Sort-Object -Unique
}

function Get-TargetPerformanceStorePath {
    Join-Path $PSScriptRoot '..' '..' 'Reports' 'target-performance.json'
}

function Read-TargetPerformanceRecords {
    $path = Get-TargetPerformanceStorePath
    if (Test-Path $path) {
        try { (Get-Content $path | ConvertFrom-Json) } catch { @() }
    } else { @() }
}

function Write-TargetPerformanceRecords {
    param([Parameter(Mandatory)]$Records)
    $path = Get-TargetPerformanceStorePath
    $dir = Split-Path $path -Parent
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $Records | ConvertTo-Json -Depth 6 | Set-Content $path
}

function Measure-TargetPerformanceBatch {
    <#
    .SYNOPSIS
    Measures latency and success for a batch of targets.
    .PARAMETER Targets
    List of host targets to test; if omitted uses base list.
    .PARAMETER SampleCount
    Number of ping samples per target (default 3).
    .PARAMETER TimeoutMs
    Per ping timeout in milliseconds (default 1200).
    #>
    [CmdletBinding()] param(
        [string[]]$Targets,
        [ValidateRange(1,20)][int]$SampleCount = 3,
        [int]$TimeoutMs = 1200
    )
    if (-not $Targets) { $Targets = Get-BottleneckBaseTargets }

    $results = @()
    foreach ($t in $Targets) {
        $latencies = @(); $fails = 0
        for ($i=0; $i -lt $SampleCount; $i++) {
            try {
                $p = Test-Connection -ComputerName $t -Count 1 -TimeoutMilliseconds $TimeoutMs -ErrorAction Stop
                $latencies += [double]$p.Latency
            } catch { $fails++ }
        }
        $avg = if ($latencies.Count -gt 0) { [math]::Round(($latencies | Measure-Object -Average).Average,2) } else { 0 }
        $lossPct = if ($SampleCount -gt 0) { [math]::Round(100 * $fails / $SampleCount,2) } else { 0 }
        $score = New-TargetReliabilityScore -AvgLatencyMs $avg -LossPercent $lossPct
        $results += [pscustomobject]@{ Target=$t; Samples=$SampleCount; FailCount=$fails; SuccessRate=100-$lossPct; AvgLatencyMs=$avg; Score=$score }
    }

    # Merge with existing records (update or append)
    $existing = Read-TargetPerformanceRecords
    $map = @{}
    foreach ($e in $existing) { $map[$e.Target] = $e }
    foreach ($r in $results) {
        $entry = [pscustomobject]@{
            Target=$r.Target
            LastChecked=(Get-Date).ToString('s')
            Samples=$r.Samples
            FailCount=$r.FailCount
            SuccessRate=$r.SuccessRate
            AvgLatencyMs=$r.AvgLatencyMs
            Score=$r.Score
            History=@()
        }
        if ($map.ContainsKey($r.Target)) {
            # Append small ring history (max 20)
            $hist = $map[$r.Target].History
            if (-not $hist) { $hist = @() }
            $hist += [pscustomobject]@{ TS=(Get-Date).ToString('s'); SR=$r.SuccessRate; Lat=$r.AvgLatencyMs; Sc=$r.Score }
            if ($hist.Count -gt 20) { $hist = $hist | Select-Object -Last 20 }
            $entry.History = $hist
        } else {
            $entry.History = @([pscustomobject]@{ TS=(Get-Date).ToString('s'); SR=$r.SuccessRate; Lat=$r.AvgLatencyMs; Sc=$r.Score })
        }
        $map[$r.Target] = $entry
    }
    $merged = $map.GetEnumerator() | ForEach-Object { $_.Value }
    Write-TargetPerformanceRecords -Records $merged
    return $results
}

function New-TargetReliabilityScore {
    param(
        [Parameter(Mandatory)][double]$AvgLatencyMs,
        [Parameter(Mandatory)][double]$LossPercent
    )
    # Normalize simple score: start 100; subtract latency factor and loss penalty.
    $latFactor = [math]::Min($AvgLatencyMs / 10.0, 50)   # 0-50 range (every 10ms costs 1 point until 500ms)
    $lossPenalty = [math]::Min($LossPercent * 2, 40)     # each 1% loss costs 2 points up to 20% (40 points)
    $score = 100 - $latFactor - $lossPenalty
    if ($score -lt 0) { $score = 0 }
    [math]::Round($score,2)
}

function Get-RecommendedTargets {
    <#
    .SYNOPSIS
    Returns top performing targets by reliability score.
    .PARAMETER Count
    Number of targets to return (default 3).
    #>
    [CmdletBinding()] param([int]$Count = 3)
    $records = Read-TargetPerformanceRecords
    if (-not $records -or $records.Count -eq 0) {
        # Measure initial set for recommendations
        Measure-TargetPerformanceBatch | Out-Null
        $records = Read-TargetPerformanceRecords
    }
    ($records | Sort-Object Score -Descending | Select-Object -First $Count -ExpandProperty Target)
}

function Rotate-AdaptiveTargets {
    <#
    .SYNOPSIS
    Rotates out persistently poor targets and introduces fresh candidates.
    .PARAMETER MinScore
    Score threshold below which targets are considered poor (default 40).
    .PARAMETER MaxRemove
    Maximum number of poor targets to remove (default 2).
    .PARAMETER AddCount
    Number of new targets to add (default 2).
    #>
    [CmdletBinding()] param(
        [int]$MinScore = 40,
        [int]$MaxRemove = 2,
        [int]$AddCount = 2
    )
    $records = Read-TargetPerformanceRecords
    if (-not $records) { return @() }
    $poor = $records | Where-Object { $_.Score -lt $MinScore } | Sort-Object Score | Select-Object -First $MaxRemove
    $removeNames = $poor.Target
    $base = Get-BottleneckBaseTargets
    $currentNames = $records.Target
    $candidates = $base | Where-Object { $currentNames -notcontains $_ }
    $add = Get-Random -InputObject $candidates -Count ([math]::Min($AddCount, $candidates.Count))
    $filtered = $records | Where-Object { $removeNames -notcontains $_.Target }
    foreach ($new in $add) {
        $filtered += [pscustomobject]@{ Target=$new; LastChecked='never'; Samples=0; FailCount=0; SuccessRate=0; AvgLatencyMs=0; Score=0; History=@() }
    }
    Write-TargetPerformanceRecords -Records $filtered
    return [pscustomobject]@{ Removed=$removeNames; Added=$add }
}
