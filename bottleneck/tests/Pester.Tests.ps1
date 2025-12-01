# Pester.Tests.ps1
Describe 'Bottleneck Quick Scan' {
    It 'Should return results for all quick checks' {
        Import-Module $PSScriptRoot/../src/ps/Bottleneck.psm1 -Force
        $results = Invoke-BottleneckScan -Tier Quick
        $results.Count | Should -BeGreaterThan 3
    }
}
