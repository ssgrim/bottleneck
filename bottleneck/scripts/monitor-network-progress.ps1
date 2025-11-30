# Monitor-Network-Progress.ps1
# Real-time monitoring dashboard for active network scan

param(
    [int]$RefreshSeconds = 10
)

$reportsDir = Join-Path $PSScriptRoot '..' '..' 'Reports'

function Get-LatestMonitorFile {
    Get-ChildItem $reportsDir -Filter "network-monitor-*.csv" -ErrorAction SilentlyContinue | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1
}

Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          NETWORK MONITOR LIVE DASHBOARD                  ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "`nRefreshing every ${RefreshSeconds}s - Press Ctrl+C to exit`n" -ForegroundColor Yellow

$iteration = 0
while ($true) {
    $iteration++
    $csv = Get-LatestMonitorFile
    
    if (-not $csv) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Waiting for monitor to start..." -ForegroundColor Yellow
        Start-Sleep -Seconds $RefreshSeconds
        continue
    }
    
    $data = Import-Csv $csv.FullName -ErrorAction SilentlyContinue
    if (-not $data -or $data.Count -lt 2) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Waiting for data..." -ForegroundColor Yellow
        Start-Sleep -Seconds $RefreshSeconds
        continue
    }
    
    Clear-Host
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          NETWORK MONITOR LIVE DASHBOARD                  ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    $pingData = $data | Where-Object { $_.Target -ne 'traceroute' }
    $elapsed = ((Get-Date) - $csv.LastWriteTime).TotalMinutes
    $samples = $pingData.Count
    
    Write-Host "Session: $(Split-Path $csv.Name -LeafBase)" -ForegroundColor Green
    Write-Host "  Started: $($csv.LastWriteTime.ToString('HH:mm:ss'))" -ForegroundColor White
    Write-Host "  Elapsed: $([math]::Round($elapsed,1)) min" -ForegroundColor White
    Write-Host "  Samples: $samples" -ForegroundColor White
    Write-Host "  Last Update: $(Get-Date -Format 'HH:mm:ss')`n" -ForegroundColor Gray
    
    # Per-target stats
    $targets = $pingData | Group-Object Target
    
    Write-Host "Target Status:" -ForegroundColor Cyan
    foreach ($t in $targets) {
        $success = ($t.Group | Where-Object { $_.Success -eq 'True' }).Count
        $total = $t.Count
        $pct = [math]::Round(100 * $success / $total, 1)
        
        $lats = $t.Group | Where-Object { $_.Success -eq 'True' -and $_.LatencyMs -gt 0 } | Select-Object -ExpandProperty LatencyMs | ForEach-Object { [double]$_ }
        $avgLat = if ($lats) { [math]::Round(($lats | Measure-Object -Average).Average, 1) } else { 0 }
        
        $color = if ($pct -lt 90) { 'Red' } elseif ($pct -lt 95) { 'Yellow' } else { 'Green' }
        $latColor = if ($avgLat -gt 200) { 'Red' } elseif ($avgLat -gt 100) { 'Yellow' } else { 'Green' }
        
        Write-Host "  $($t.Name):" -NoNewline -ForegroundColor White
        Write-Host " $pct%" -NoNewline -ForegroundColor $color
        Write-Host " success, " -NoNewline -ForegroundColor Gray
        Write-Host "${avgLat}ms" -NoNewline -ForegroundColor $latColor
        Write-Host " avg ($total samples)" -ForegroundColor Gray
    }
    
    # Recent activity (last 10 samples)
    Write-Host "`nRecent Activity:" -ForegroundColor Cyan
    $recent = $pingData | Select-Object -Last 10
    foreach ($r in $recent) {
        $time = (Get-Date $r.Time).ToString('HH:mm:ss')
        if ($r.Success -eq 'True') {
            Write-Host "  [$time] ✓ $($r.Target) : $($r.LatencyMs)ms" -ForegroundColor Green
        } else {
            Write-Host "  [$time] ✗ $($r.Target) : DROP" -ForegroundColor Red
        }
    }
    
    # Quick health indicators
    $recentWindow = $pingData | Select-Object -Last 60  # Last minute at 10s interval
    $recentDrops = ($recentWindow | Where-Object { $_.Success -eq 'False' }).Count
    $dropRate = if ($recentWindow.Count -gt 0) { [math]::Round(100 * $recentDrops / $recentWindow.Count, 1) } else { 0 }
    
    Write-Host "`nLast Minute Health:" -ForegroundColor Cyan
    $healthColor = if ($dropRate -gt 10) { 'Red' } elseif ($dropRate -gt 5) { 'Yellow' } else { 'Green' }
    Write-Host "  Drop Rate: " -NoNewline -ForegroundColor White
    Write-Host "$dropRate%" -NoNewline -ForegroundColor $healthColor
    Write-Host " ($recentDrops drops in $($recentWindow.Count) samples)" -ForegroundColor Gray
    
    # Progress bar
    $expectedDuration = 60  # 1 hour
    $progress = [math]::Min(100, [math]::Round(100 * $elapsed / $expectedDuration, 0))
    $barLength = 40
    $filled = [math]::Floor($barLength * $progress / 100)
    $bar = ('█' * $filled) + ('░' * ($barLength - $filled))
    
    Write-Host "`nProgress:" -ForegroundColor Cyan
    Write-Host "  [$bar] $progress%" -ForegroundColor White
    Write-Host "  ETA: $([math]::Max(0, [math]::Round($expectedDuration - $elapsed, 0))) min remaining`n" -ForegroundColor Gray
    
    Write-Host "Refreshing in ${RefreshSeconds}s... (Ctrl+C to exit)" -ForegroundColor Yellow
    
    Start-Sleep -Seconds $RefreshSeconds
}
