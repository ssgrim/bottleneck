# Pester.Tests.ps1
Describe 'Bottleneck Quick Scan' {
    It 'Should return results for all quick checks' {
        Import-Module ../src/ps/Bottleneck.psm1 -Force
        $results = Invoke-BottleneckScan -Tier Quick
        $results.Count | Should BeGreaterThan 3
    }
}

Describe 'Fused Alerts' {
    BeforeAll {
        Import-Module ../src/ps/Bottleneck.psm1 -Force
    }

    It 'Returns None for empty inputs' {
        $level = Get-FusedAlertLevel -LatencySpikes @() -LossBursts @() -JitterVolatility @()
        $level | Should Be 'None'
    }

    It 'Returns Low for small combined score' {
        $level = Get-FusedAlertLevel -LatencySpikes @('L1') -LossBursts @() -JitterVolatility @()
        $level | Should Be 'Low'
    }

    It 'Returns High for mid-high score' {
        $level = Get-FusedAlertLevel -LatencySpikes @('L1','L2') -LossBursts @('B1') -JitterVolatility @()
        $level | Should Be 'High'
    }

    It 'Returns High for higher score' {
        $level = Get-FusedAlertLevel -LatencySpikes @('L1','L2') -LossBursts @('B1','B2') -JitterVolatility @()
        $level | Should Be 'High'
    }

    It 'Returns Critical for very high score' {
        $level = Get-FusedAlertLevel -LatencySpikes @('L1','L2','L3') -LossBursts @('B1','B2','B3') -JitterVolatility @('J1')
        $level | Should Be 'Critical'
    }
}
