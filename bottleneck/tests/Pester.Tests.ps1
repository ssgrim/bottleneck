# Pester.Tests.ps1
Describe 'Bottleneck Quick Scan' {
    It 'Should return results for all quick checks' {
        $moduleCandidates = @(
            [System.IO.Path]::Combine($PSScriptRoot, '..', 'src', 'ps', 'Bottleneck.psm1'),
            [System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'src', 'ps', 'Bottleneck.psm1')
        )
        $modulePath = $moduleCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $modulePath) { throw "Bottleneck.psm1 not found relative to tests at $PSScriptRoot" }
        Import-Module $modulePath -Force
        $results = Invoke-BottleneckScan -Tier Quick
        $results.Count | Should -BeGreaterThan 3
    }
}
