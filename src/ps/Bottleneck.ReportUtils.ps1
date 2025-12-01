# Bottleneck.ReportUtils.ps1
function Get-BottleneckEventLogSummary {
    param([int]$Days = 7)
    $since = (Get-Date).AddDays(-$Days)
    $filter = @{ StartTime = $since }
    # Guard LogName to avoid null errors
    $filter['LogName'] = 'System'
    $events = Get-WinEvent -FilterHashtable $filter -MaxEvents 1000 -ErrorAction SilentlyContinue
    $errors = $events | Where-Object { $_.LevelDisplayName -eq 'Error' }
    $warnings = $events | Where-Object { $_.LevelDisplayName -eq 'Warning' }
    [PSCustomObject]@{
        ErrorCount = $errors.Count
        WarningCount = $warnings.Count
        RecentErrors = $errors | Select-Object -First 5 -Property TimeCreated, Message
        RecentWarnings = $warnings | Select-Object -First 5 -Property TimeCreated, Message
    }
}

function Get-BottleneckPreviousScan {
    param([string]$ReportsPath)
    $files = Get-ChildItem -Path $ReportsPath -Filter 'scan-*.json' | Sort-Object LastWriteTime -Descending
    if ($files.Count -gt 0) {
        return Get-Content $files[0].FullName | ConvertFrom-Json
    }
    return $null
}
