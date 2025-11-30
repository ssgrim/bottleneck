# Phase 2 Summary and Usage

## New Scripts

- `scripts/analyze-and-report.ps1`: Runs textual analysis, correlates alerts, generates compact printable HTML, auto-opens.
- `scripts/generate-html-report.ps1`: Builds Chart.js report with per-target overlays. Parameter: `-PageSize A4|Letter`.
- `scripts/run-monitor-5min-elevated.ps1`: Elevated 5-minute monitor then analysis + HTML.
- `scripts/augment-adaptive-history.ps1`: Persists CPU/memory/disk/net metrics to `Reports/scan-history.json`.

## Monitor Auto-Report

- `Invoke-BottleneckNetworkMonitor` now auto-calls the HTML generator unless `-SkipReport` is passed.
- Writes `Reports/monitor.done` on completion with timestamp.
- Prints progress heartbeat every ~30 seconds.

## Alert Correlation

- Alerts grouped (`Group-NetworkAlerts`) and suppressed (`Suppress-RedundantAlerts`) with levels via `Get-NetworkAlertLevel`.
- When anomalies are absent, level prints as `None`.

## Printable HTML

- Two-column compact layout; fits on one page.
- Choose page size via `-PageSize Letter` for US printing or `-PageSize A4`.

## Live Status

```pwsh
cd "C:\Users\mrred\OneDrive\Documents\Project\Bottleneck\bottleneck"
Get-ChildItem "$PWD/Reports" -Filter "network-monitor-*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 Name, Length, LastWriteTime, @{N='AgeSec';E={[math]::Round(((Get-Date)-$_.LastWriteTime).TotalSeconds,0)}}
$latest = Get-ChildItem "$PWD/Reports" -Filter "network-monitor-*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Import-Csv $latest.FullName | Select-Object -Last 10 | Format-Table -AutoSize
Get-Content "$PWD/Reports/monitor.done" -ErrorAction SilentlyContinue
```

## Next: Phase 3

- Dashboards (alert badges, trend deltas)
- Traceroute path visuals
- Weekly baseline scheduling and trend JSON
- Notifications for High/Critical alerts
