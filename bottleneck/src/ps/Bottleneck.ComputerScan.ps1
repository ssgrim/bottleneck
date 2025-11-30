# Bottleneck.ComputerScan.ps1
# Unified comprehensive computer diagnostics

function Invoke-BottleneckComputerScan {
    <#
    .SYNOPSIS
    Runs comprehensive deep root cause analysis of all computer systems.
    
    .DESCRIPTION
    Performs exhaustive diagnostics across CPU, memory, disk, network, services, 
    events, thermal, battery, and more. Generates professional HTML report.
    
    .PARAMETER AutoElevate
    Prompts for elevation if not running as admin.
    
    .PARAMETER SkipNetwork
    Excludes network-specific diagnostics (adapter stats, DNS, bandwidth tests).
    
    .PARAMETER Quick
    Runs faster scan with fewer deep checks (not recommended).
    
    .EXAMPLE
    Invoke-BottleneckComputerScan
    
    .EXAMPLE
    Invoke-BottleneckComputerScan -AutoElevate
    #>
    [CmdletBinding()]
    param(
        [switch]$AutoElevate,
        [switch]$SkipNetwork,
        [switch]$Quick
    )
    
    $scanStart = Get-Date
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         COMPREHENSIVE COMPUTER DIAGNOSTICS SCAN           ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    # Check elevation
    if ($AutoElevate) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Host "⚠️  Requesting elevation for complete diagnostics..." -ForegroundColor Yellow
            $elevated = Request-ElevatedScan -Tier Deep
            if (-not $elevated) { return }
        }
    }
    
    Write-Host "🔍 Analyzing system health across all subsystems..." -ForegroundColor Cyan
    Write-Host "   This will check: CPU, Memory, Disk, Network, Services, Events," -ForegroundColor Gray
    Write-Host "   Thermal, Battery, Windows Updates, Security, and more.`n" -ForegroundColor Gray
    
    # Run comprehensive scan
    $tier = if ($Quick) { 'Standard' } else { 'Deep' }
    $results = Invoke-BottleneckScan -Tier $tier
    
    # Optionally add network probes
    if (-not $SkipNetwork) {
        Write-Host "`n🌐 Running advanced network diagnostics..." -ForegroundColor Cyan
        try {
            $networkResults = @()
            $networkResults += Test-BottleneckWiFiQuality
            $networkResults += Test-BottleneckDNSResolvers
            $networkResults += Test-BottleneckAdapterErrors
            $networkResults += Test-BottleneckMTUPath
            $networkResults += Test-BottleneckARPHealth
            $results += $networkResults | Where-Object { $_ }
        } catch {
            Write-Warning "Some network probes failed: $_"
        }
    }
    
    # Generate report
    Write-Host "`n📊 Generating comprehensive analysis report..." -ForegroundColor Cyan
    $reportPath = Invoke-BottleneckReport -Results $results -Tier $tier
    
    $scanDuration = ((Get-Date) - $scanStart).TotalSeconds
    Write-Host "`n✓ Computer scan complete in $([math]::Round($scanDuration,1)) seconds" -ForegroundColor Green
    Write-Host "  Results: $($results.Count) checks analyzed" -ForegroundColor Gray
    Write-Host "  Report: $reportPath`n" -ForegroundColor Gray
    
    # Open report
    $openReport = Read-Host "Open report now? (Y/n)"
    if ($openReport -ne 'n') {
        $userReports = Get-ChildItem "$env:USERPROFILE\Documents\ScanReports" -Filter '*.html' -ErrorAction SilentlyContinue | 
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($userReports) { Invoke-Item $userReports.FullName }
    }

    # Adaptive history update (Phase 2)
    try {
        if (Get-Command Get-CurrentMetrics -ErrorAction SilentlyContinue) {
            $metrics = Get-CurrentMetrics
            $summary = @{ System=$metrics.System; Network=$metrics.Network; PathQuality=$metrics.PathQuality; Speedtest=$metrics.Speedtest }
            if (Get-Command Update-BottleneckHistory -ErrorAction SilentlyContinue) {
                Update-BottleneckHistory -Summary $summary | Out-Null
                Write-Host "📚 Historical metrics updated" -ForegroundColor Gray
            }
        }
    } catch { Write-Verbose "History update failed: $_" }
    
    return $results
}

