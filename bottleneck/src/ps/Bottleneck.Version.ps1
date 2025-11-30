# Bottleneck.Version.ps1
$script:BottleneckVersion = '1.0.0-phase1'
$script:BottleneckReleaseDate = Get-Date '2025-11-30'
function Get-BottleneckVersion {
    [CmdletBinding()] param()
    [pscustomobject]@{
        Version      = $script:BottleneckVersion
        ReleaseDate  = $script:BottleneckReleaseDate.ToString('yyyy-MM-dd')
        Phase        = 'Phase 1'
        Description  = 'Core diagnostics, advanced network monitoring, speedtest integration, path quality, metrics export, threshold alerts.'
    }
}
