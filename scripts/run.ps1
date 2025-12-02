param(
    [switch] $All,              # Unified: run all computer checks
    [switch] $HealthCheck,
    [switch] $AI,
    [switch] $CollectLogs,
    [switch] $Debug,
    [switch] $Verbose,
    [switch] $SkipElevation,    # Internal flag to prevent elevation loop
    [string] $WiresharkCsv      # Optional: path to exported Wireshark CSV for analysis
)

# Check elevation (skip if already attempted)
if (-not $SkipElevation -and -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Restarting with admin privileges..."
    $scriptPath = $PSCommandPath
    $argsList = @('-SkipElevation')  # Add flag to prevent re-elevation
    if ($All) { $argsList += '-All' }
    if ($WiresharkCsv) { $argsList += @('-WiresharkCsv', ('"' + $WiresharkCsv + '"')) }
    if ($AI) { $argsList += '-AI' }
    if ($CollectLogs) { $argsList += '-CollectLogs' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command pwsh).Source
    $psi.Arguments = "-NoLogo -NoProfile -File `"$scriptPath`" $($argsList -join ' ')"
    $psi.Verb = 'runas'
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit 0
}

# Resolve repo root and import module fresh
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Push-Location $repoRoot

# Start transcript logging with date-based folder structure
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$dateFolder = Get-Date -Format 'yyyy-MM-dd'
$reportsDir = Join-Path $repoRoot "Reports" $dateFolder
if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
$logPath = Join-Path $reportsDir "run-$timestamp.log"
Start-Transcript -Path $logPath -Append
try {
    Import-Module "$repoRoot/src/ps/Bottleneck.psm1" -Force -ErrorAction Stop -WarningAction SilentlyContinue
    $importedCmds = Get-Command -Module Bottleneck | Measure-Object | Select-Object -ExpandProperty Count
    Write-Host "Module imported: $importedCmds functions available" -ForegroundColor Green
} catch {
    Write-Warning "Failed to import Bottleneck module: $($_.Exception.Message)"
    Write-Warning "Error details: $($_.Exception.InnerException.Message)"
    Write-Host "Attempting to continue without full module..."
}

# Unified flow configuration
$enableAI = [bool]$AI

# Initialize debugging if requested
if ($Debug -or $Verbose) {
    try {
        $scanId = Initialize-BottleneckDebug -EnableDebug:$Debug -EnableVerbose:$Verbose -StructuredLog
        Write-Host "Debugging initialized: Scan ID = $scanId" -ForegroundColor Cyan
    } catch {
        Write-Warning "Failed to initialize debugging: $($_.Exception.Message)"
    }
}

# Health check mode
if ($HealthCheck) {
    try {
        Invoke-BottleneckHealthCheck -Verbose:$Verbose
    } catch {
        Write-Warning "Health check failed: $($_.Exception.Message)"
    }
    Stop-Transcript
    Pop-Location
    exit 0
}

# Run unified computer scan
if ($All -or (-not $PSBoundParameters.ContainsKey('All'))) {
    Write-Host "Starting full system scan..." -ForegroundColor Cyan
    Write-BottleneckDebug "Unified scan initiated" -Component "Run"
    $results = $null
    try {
        $results = Invoke-BottleneckScan -Tier Standard -ErrorAction Stop
    } catch {
        Write-Host "❌ Scan failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Check log file: $logPath" -ForegroundColor Yellow
        Write-Host "   For detailed errors, run with -Debug or -Verbose" -ForegroundColor Yellow
    }

    if ($results) {
        Write-Host "Generating report..." -ForegroundColor Cyan
        $Global:Bottleneck_EnableAI = $enableAI
        try {
            Invoke-BottleneckReport -Results $results -Tier 'Standard' -ErrorAction Stop
            Write-Host "✓ Report generated successfully" -ForegroundColor Green
        } catch {
            Write-Host "❌ Report generation failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "   Results were collected but report creation failed" -ForegroundColor Yellow
            Write-Host "   Check log file: $logPath" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠ No results to report (scan may have failed)" -ForegroundColor Yellow
    }

    if ($Debug -or $Verbose) {
        Show-BottleneckPerformanceSummary
    }

    # Baseline: save/compare aggregated metrics from computer scan results
    if (($SaveBaseline -or $CompareBaseline) -and $results) {
        try {
            $metrics = @{}
            $count = $results.Count
            $avgScore = $null; $maxScore = $null
            if ($count -gt 0) {
                $avgScore = [math]::Round((($results | Measure-Object -Property Score -Average).Average), 2)
                $maxScore = [math]::Round((($results | Measure-Object -Property Score -Maximum).Maximum), 2)
            }
            $highImpact = ($results | Where-Object { $_.Impact -ge 6 } | Measure-Object).Count
            $thermalFindings = ($results | Where-Object { $_.Category -match 'Thermal|Temperature' } | Measure-Object).Count
            $cpuFindings = ($results | Where-Object { $_.Category -match 'CPU' } | Measure-Object).Count
            $memoryFindings = ($results | Where-Object { $_.Category -match 'Memory|RAM' } | Measure-Object).Count
            $diskFindings = ($results | Where-Object { $_.Category -match 'Disk|Storage' } | Measure-Object).Count

            $metrics.TotalFindings = [int]$count
            if ($avgScore -ne $null) { $metrics.AvgScore = [double]$avgScore }
            if ($maxScore -ne $null) { $metrics.MaxScore = [double]$maxScore }
            $metrics.HighImpact = [int]$highImpact
            $metrics.ThermalFindings = [int]$thermalFindings
            $metrics.CPUFindings = [int]$cpuFindings
            $metrics.MemoryFindings = [int]$memoryFindings
            $metrics.DiskFindings = [int]$diskFindings

            if ($SaveBaseline) {
                $name = if ($BaselineName) { $BaselineName } else { "computer-$(Get-Date -Format 'yyyy-MM-dd')" }
                $saved = Save-BottleneckBaseline -Metrics $metrics -Name $name -Path $BaselinePath
                Write-Host "Saved computer baseline: $saved" -ForegroundColor Green
            }
            if ($CompareBaseline) {
                $comparison = $null
                try { $comparison = Compare-ToBaseline -Metrics $metrics -Name $CompareBaseline -Path $BaselinePath } catch { Write-Warning "Compare failed: $($_.Exception.Message)" }
                if ($comparison) {
                    Write-Host "Baseline comparison: '$($comparison.name)' (captured $($comparison.timestamp))" -ForegroundColor Cyan
                    # Compute anomaly score using baseline metrics document
                    $repoRootLocal = Split-Path -Path $PSScriptRoot -Parent
                    $baseDir = if ($BaselinePath) { $BaselinePath } else { Join-Path $repoRootLocal 'baselines' }
                    $baseFile = Join-Path $baseDir ("$($comparison.name).json")
                    if (Test-Path $baseFile) {
                        $baseDoc = Get-Content -Path $baseFile -Raw | ConvertFrom-Json
                        $score = Get-AnomalyScore -Metrics $metrics -Baseline ($baseDoc.metrics | ConvertTo-Json | ConvertFrom-Json)
                        Write-Host "Anomaly score: $score" -ForegroundColor Yellow
                    }
                    foreach ($k in @('TotalFindings','AvgScore','MaxScore','HighImpact','ThermalFindings','CPUFindings','MemoryFindings','DiskFindings')) {
                        if ($comparison.comparison.ContainsKey($k)) {
                            $c = $comparison.comparison[$k]
                            $pct = if ($c.percent -ne $null) { "$($c.percent)%" } else { 'n/a' }
                            Write-Host (" - {0,-16} curr={1} base={2} Δ={3} ({4})" -f $k, $c.current, $c.baseline, $c.delta, $pct)
                        }
                    }
                }
            }
        } catch {
            Write-Host "⚠ Baseline processing error (Computer): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "   Baseline operations require valid scan results and write access to baselines/" -ForegroundColor Yellow
        }
    }
}

# Optional: Analyze Wireshark CSV if provided
if ($WiresharkCsv) {
    Write-Host "Analyzing Wireshark capture: $WiresharkCsv" -ForegroundColor Cyan
    try {
        $ws = Analyze-WiresharkCapture -Path $WiresharkCsv -ErrorAction Stop
        if ($ws) {
            Write-Host ("Wireshark summary: packets={0}, drops={1}, avgLatency={2}ms, maxLatency={3}ms" -f $ws.Packets, $ws.Drops, $ws.AvgLatencyMs, $ws.MaxLatencyMs) -ForegroundColor Green
            try {
                Add-WiresharkSummaryToReport -Summary $ws
            } catch {}
        }
    } catch {
        Write-Host "⚠ Wireshark analysis failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Open latest report if exists
$latestReport = Get-ChildItem "$repoRoot/Reports" -Filter 'Full-scan-*.html' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestReport) {
    Write-Host ("Report: " + $latestReport.FullName)
    try { Start-Process $latestReport.FullName } catch {}
}

# Collect logs optionally
if ($CollectLogs) {
    Write-Host "Collecting logs and artifacts..."
    & "$repoRoot/scripts/collect-logs.ps1" -IncludeAll -OpenFolder
}

Stop-Transcript
Pop-Location
