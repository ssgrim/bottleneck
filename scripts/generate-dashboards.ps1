param(
    [ValidateSet('A4','Letter')][string]$PageSize = 'Letter',
    [string]$TrendPath = "$PWD/Reports/trend-week.json",
    [string]$OutHtml = "$PWD/Reports/network-dashboard.html"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (!(Test-Path $TrendPath)) { throw "Trend file not found: $TrendPath" }
$trend = Get-Content $TrendPath | ConvertFrom-Json
$targets = @($trend.Targets)

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
<div class="small">Window: $($trend.Window) | Generated: $([System.Web.HttpUtility]::HtmlEncode($trend.GeneratedAt))</div>

<div class="card">
  <div>
    <span class="badge ok">Stable</span>
    <span class="badge warn">Warnings</span>
    <span class="badge crit">Critical</span>
  </div>
  <div class="small">Severity badges are placeholders; wired as we add alert fusion.</div>
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
</body>
</html>
"@

# Insert table rows
$rows = ""
foreach ($t in $targets) {
    $rows += "<tr><td>$($t.Target)</td><td>$($t.AvgLatencyMs)</td><td>$($t.P95LatencyMs)</td><td>$($t.FailCount)</td></tr>"
}
$html = $html -replace '<!--ROWS-->', $rows

$null = New-Item -ItemType Directory -Path (Split-Path $OutHtml) -ErrorAction SilentlyContinue
Set-Content -Path $OutHtml -Value $html -Encoding UTF8
Write-Host "Dashboard written:" -ForegroundColor Green
Write-Host "  $OutHtml" -ForegroundColor Yellow
