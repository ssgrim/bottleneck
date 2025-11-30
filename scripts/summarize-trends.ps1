param(
    [string]$Window = "7d",
    [string]$Out = "$PWD/Reports/trend-week.json"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Resolve window cutoff
function Get-Cutoff([string]$win) {
    if ($win -match '^(\d+)d$') { return (Get-Date).AddDays(-[int]$Matches[1]) }
    if ($win -match '^(\d+)h$') { return (Get-Date).AddHours(-[int]$Matches[1]) }
    if ($win -match '^(\d+)m$') { return (Get-Date).AddMinutes(-[int]$Matches[1]) }
    return (Get-Date).AddDays(-7)
}

$cutoff = Get-Cutoff $Window
$reportsDir = Join-Path $PWD 'Reports'
if (!(Test-Path $reportsDir)) { throw "Reports directory not found: $reportsDir" }

# Gather network monitor CSVs in window
$csvs = Get-ChildItem $reportsDir -Filter 'network-monitor-*.csv' | Where-Object { $_.LastWriteTime -ge $cutoff }
if (!$csvs) { Write-Warning "No CSVs found in window $Window" }

# Simple aggregations: avg latency, 95th, fail count per target
$rows = @()
foreach ($csv in $csvs) {
    try {
        $data = Import-Csv $csv.FullName
        if (!$data) { continue }
        $groups = $data | Group-Object -Property Target
        foreach ($g in $groups) {
            $lat = @($g.Group | Where-Object { $_.LatencyMs -as [double] } | ForEach-Object { [double]$_.LatencyMs })
            $sorted = $lat | Sort-Object
            $p95 = if ($sorted.Count) { $sorted[[math]::Min([math]::Floor($sorted.Count*0.95), $sorted.Count-1)] } else { $null }
            $avg = if ($sorted.Count) { [math]::Round(($sorted | Measure-Object -Average).Average,2) } else { $null }
            $fails = @($g.Group | Where-Object { $_.Success -eq 'False' }).Count
            $rows += [pscustomobject]@{ Target=$g.Name; AvgLatencyMs=$avg; P95LatencyMs=$p95; FailCount=$fails }
        }
    } catch { Write-Warning "Failed to process $($csv.Name): $_" }
}

# Aggregate per target across files
$summary = $rows | Group-Object Target | ForEach-Object {
    $all = $_.Group
    [pscustomobject]@{
        Target = $_.Name
        Samples = $all.Count
        AvgLatencyMs = if ($all.Count) { [math]::Round((($all | Measure-Object AvgLatencyMs -Average).Average),2) } else { $null }
        P95LatencyMs = if ($all.Count) { [math]::Max(($all | ForEach-Object { $_.P95LatencyMs })) } else { $null }
        FailCount = ($all | Measure-Object FailCount -Sum).Sum
    }
}

# Write JSON
$manifest = [pscustomobject]@{
    Window = $Window
    Cutoff = $cutoff
    GeneratedAt = (Get-Date)
    Targets = $summary
}

$null = New-Item -ItemType Directory -Path (Split-Path $Out) -ErrorAction SilentlyContinue
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $Out -Encoding UTF8

Write-Host "Trend summary written:" -ForegroundColor Green
Write-Host "  $Out" -ForegroundColor Yellow
