param(
    [ValidateSet('A4','Letter')][string]$PageSize = 'Letter',
    [string]$TrendPath = "$PWD/Reports/trend-week.json",
    [string]$OutHtml = "$PWD/Reports/network-dashboard.html"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (!(Test-Path $TrendPath)) { throw "Trend file not found: $TrendPath" }
$trend = Get-Content $TrendPath | ConvertFrom-Json
# Coerce targets to an array and normalize property names
$targets = @()
if ($trend.Targets) {
  foreach ($item in @($trend.Targets)) {
    $targetName = $null
    if ($item.PSObject.Properties["Target"]) { $targetName = $item.Target }
    elseif ($item.PSObject.Properties["Name"]) { $targetName = $item.Name }
    elseif ($item.PSObject.Properties["Key"]) { $targetName = $item.Key }
    $avg = $item.PSObject.Properties["AvgLatencyMs"] ? $item.AvgLatencyMs : $null
    $p95 = $item.PSObject.Properties["P95LatencyMs"] ? $item.P95LatencyMs : $null
    $fails = $item.PSObject.Properties["FailCount"] ? $item.FailCount : $null
    $targets += [pscustomobject]@{ Target=$targetName; AvgLatencyMs=$avg; P95LatencyMs=$p95; FailCount=$fails }
  }
}

# Simple heuristic for alert level: high fails or high latency = warn/crit
$alertBadge = "ok"
$alertText = "Stable"
$totalFails = ($targets | Measure-Object FailCount -Sum -ErrorAction SilentlyContinue).Sum
$maxAvg = ($targets | Measure-Object AvgLatencyMs -Maximum -ErrorAction SilentlyContinue).Maximum
if ($totalFails -gt 10 -or $maxAvg -gt 200) { $alertBadge = "crit"; $alertText = "Critical" }
elseif ($totalFails -gt 3 -or $maxAvg -gt 100) { $alertBadge = "warn"; $alertText = "Warnings" }

# Traceroute hop-change parsing
function Parse-LineHop([string]$l) {
    if ($l -match '^\s*(\d+)\s+([^\s]+)\s+(\d+\.\d+)\s*ms') {
        return [pscustomobject]@{ Hop=[int]$Matches[1]; Host=$Matches[2]; RTTms=[double]$Matches[3] }
    }
    return $null
}
function Load-Traceroute([string]$path) {
    if (!(Test-Path $path)) { return @() }
    $res = @()
    foreach ($line in (Get-Content -Path $path -ErrorAction SilentlyContinue)) {
        $h = Parse-LineHop $line
        if ($h) { $res += $h }
    }
    return $res
}
function Diff-Hops($old,$new) {
    $max = [math]::Max((($old|Measure-Object Hop -Maximum -ErrorAction SilentlyContinue).Maximum), (($new|Measure-Object Hop -Maximum -ErrorAction SilentlyContinue).Maximum))
    if (!$max) { $max = 0 }
    $out = @()
    for ($i=1; $i -le $max; $i++) {
        $o = $old | Where-Object Hop -eq $i | Select-Object -First 1
        $n = $new | Where-Object Hop -eq $i | Select-Object -First 1
        $out += [pscustomobject]@{
            Hop=$i
            OldHost=$o?.Host
            NewHost=$n?.Host
            HostChanged = ($o -and $n) ? ($o.Host -ne $n.Host) : $true
            OldRTTms=$o?.RTTms
            NewRTTms=$n?.RTTms
            RTTDeltaMs = ($o -and $n) ? ([math]::Round(($n.RTTms - $o.RTTms),2)) : $null
        }
    }
    return $out
}

$reportsDir = Join-Path $PWD 'Reports'
$trFiles = @(Get-ChildItem $reportsDir -Filter 'traceroute-*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
$pathSummaryHtml = ""
if ($trFiles.Count -ge 2) {
    $oldPath = $trFiles[-2].FullName
    $newPath = $trFiles[-1].FullName
    $oldHops = Load-Traceroute $oldPath
    $newHops = Load-Traceroute $newPath
    $diffs = Diff-Hops $oldHops $newHops
    $rowsPath = ""
    foreach ($d in $diffs) {
        $chg = if ($d.HostChanged) { 'yes' } else { 'no' }
        $oh = if ($d.OldHost) { $d.OldHost } else { '' }
        $nh = if ($d.NewHost) { $d.NewHost } else { '' }
        $or = if ($d.OldRTTms -ne $null) { $d.OldRTTms } else { '' }
        $nr = if ($d.NewRTTms -ne $null) { $d.NewRTTms } else { '' }
        $delta = if ($d.RTTDeltaMs -ne $null) { $d.RTTDeltaMs } else { '' }
        $rowsPath += "<tr><td>$($d.Hop)</td><td>$oh</td><td>$nh</td><td>$chg</td><td>$or</td><td>$nr</td><td>$delta</td></tr>"
    }
    $oldFile = Split-Path $oldPath -Leaf
    $newFile = Split-Path $newPath -Leaf
    $pathSummaryHtml = @"
<div class="card" style="grid-column:1/-1">
  <h3>Path Changes (latest two traceroutes)</h3>
  <table class="table">
    <thead><tr><th>Hop</th><th>Old Host</th><th>New Host</th><th>Changed</th><th>Old RTT</th><th>New RTT</th><th>Δ RTT</th></tr></thead>
    <tbody>
      $rowsPath
    </tbody>
  </table>
  <div class="small">Files: $oldFile → $newFile</div>
</div>
"@
}

$cssPage = if ($PageSize -eq 'A4') { '@page{size:A4;margin:10mm}' } else { '@page{size:Letter;margin:0.5in}' }

$html = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8"/>
<title>Bottleneck Dashboard</title>
<style>
$cssPage
body{font-family:Segoe UI,Arial,sans-serif;margin:0;padding:16px;background:#fff;color:#222}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.card{border:1px solid #ddd;border-radius:8px;padding:12px}
.badge{display:inline-block;padding:4px 8px;border-radius:12px;margin-right:6px;color:#fff;font-size:12px}
.badge.ok{background:#2e7d32} .badge.warn{background:#f57c00} .badge.crit{background:#c62828}
.table{width:100%;border-collapse:collapse}
.table th,.table td{border-bottom:1px solid #eee;padding:6px;text-align:left;font-size:12px}
.small{font-size:12px;color:#666}
</style>
</head>
<body>
<h2>Bottleneck Dashboard</h2>
<div class="small">Window: $($trend.Window) | Generated: $([System.Net.WebUtility]::HtmlEncode([string]$trend.GeneratedAt))</div>

<div class="card">
  <div>
    <span class="badge $alertBadge">$alertText</span>
    <span class="small">Fails: $totalFails | Max Avg Latency: $maxAvg ms</span>
  </div>
  <div class="small">Heuristic: &gt;10 fails or &gt;200ms = Critical; &gt;3 fails or &gt;100ms = Warning</div>
</div>

<div class="grid">
  <div class="card">
    <h3>Target Latency (Avg / P95)</h3>
    <table class="table">
      <thead><tr><th>Target</th><th>Avg (ms)</th><th>P95 (ms)</th><th>Fails</th></tr></thead>
      <tbody>
        <!--ROWS-->
      </tbody>
    </table>
  </div>
  <div class="card">
    <h3>Notes</h3>
    <ul class="small">
      <li>Trend aggregation uses per-file 95th; future: true per-target 95th.</li>
      <li>Severity badges will reflect fused anomalies and alert levels.</li>
      <li>Traceroute visuals will show hop changes and RTT deltas.</li>
    </ul>
  </div>
</div>
<!--PATH_SUMMARY-->
</body>
</html>
"@

# Insert table rows
$rows = ""
foreach ($t in $targets) {
  $tgt = if ($t.Target) { $t.Target } else { '(unknown)' }
  $avg = if ($t.AvgLatencyMs -ne $null) { $t.AvgLatencyMs } else { '' }
  $p95 = if ($t.P95LatencyMs -ne $null) { $t.P95LatencyMs } else { '' }
  $fail = if ($t.FailCount -ne $null) { $t.FailCount } else { '' }
  $rows += "<tr><td>$tgt</td><td>$avg</td><td>$p95</td><td>$fail</td></tr>"
}
$html = $html -replace '<!--ROWS-->', $rows
$html = $html -replace '<!--PATH_SUMMARY-->', $pathSummaryHtml

$null = New-Item -ItemType Directory -Path (Split-Path $OutHtml) -ErrorAction SilentlyContinue
Set-Content -Path $OutHtml -Value $html -Encoding UTF8
Write-Host "Dashboard written:" -ForegroundColor Green
Write-Host "  $OutHtml" -ForegroundColor Yellow
