# Bottleneck.ReportUtils.ps1
function Get-BottleneckEventLogSummary {
    param([ValidateRange(1, 365)][int]$Days = 7)
    $since = (Get-Date).AddDays(-$Days)
    $filter = @{ StartTime = $since; LogName = 'System' }
    $events = Get-SafeWinEvent -FilterHashtable $filter -MaxEvents 1000 -TimeoutSeconds 15
    $errors = $events | Where-Object { $_.LevelDisplayName -eq 'Error' }
    $warnings = $events | Where-Object { $_.LevelDisplayName -eq 'Warning' }
    [PSCustomObject]@{
        ErrorCount = $errors.Count
        WarningCount = $warnings.Count
        RecentErrors = $errors | Select-Object -First 5 -Property TimeCreated, Message
        RecentWarnings = $warnings | Select-Object -First 5 -Property TimeCreated, Message
    }
}
function New-WiresharkSection {
    param([hashtable]$Summary)
    $global:__reportSections += @{
        Title = 'Wireshark Network Summary'
        Html = @(
            '<div class="section">',
            '<h2>Wireshark Network Summary</h2>',
            '<div class="metrics-grid">',
            "<div class='metric-card'><div class='metric-label'>Packets</div><div class='metric-value'>${($Summary.Packets)}</div></div>",
            "<div class='metric-card'><div class='metric-label'>Drops</div><div class='metric-value'>${($Summary.Drops)}</div></div>",
            "<div class='metric-card'><div class='metric-label'>Avg Latency</div><div class='metric-value'>${($Summary.AvgLatencyMs)} ms</div></div>",
            "<div class='metric-card'><div class='metric-label'>Max Latency</div><div class='metric-value'>${($Summary.MaxLatencyMs)} ms</div></div>",
            '</div>',
            '</div>'
        ) -join "\n"
    }
}

function Get-BottleneckPreviousScan {
    param([ValidateNotNullOrEmpty()][string]$ReportsPath)
    $files = Get-ChildItem -Path $ReportsPath -Filter 'scan-*.json' | Sort-Object LastWriteTime -Descending
    if ($files.Count -gt 0) {
        return Get-Content $files[0].FullName | ConvertFrom-Json
    }
    return $null
}
