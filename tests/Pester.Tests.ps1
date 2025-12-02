# Pester.Tests.ps1
Describe 'Bottleneck Quick Scan' {
    It 'Should return results for all quick checks' {
        $modulePath = Join-Path $PSScriptRoot '..\src\ps\Bottleneck.psm1'
        Import-Module $modulePath -Force
        $results = Invoke-BottleneckScan -Tier Quick
        $results.Count | Should BeGreaterThan 3
    }
}

# Fused Alerts tests temporarily disabled pending feature integration in this branch

Describe 'Profiles' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\src\ps\Bottleneck.psm1'
        Import-Module $modulePath -Force
    }

    It 'Exports Get-BottleneckProfile and Invoke-BottleneckReport' {
        (Get-Command Get-BottleneckProfile -Module Bottleneck).Name | Should Be 'Get-BottleneckProfile'
        (Get-Command Invoke-BottleneckReport -Module Bottleneck).Name | Should Be 'Invoke-BottleneckReport'
    }

    It 'Lists known profile names' {
        $names = Get-BottleneckProfile -ListNames
        (($names -contains 'DesktopGamer')) | Should Be $true
        (($names -contains 'RemoteWorker')) | Should Be $true
        (($names -contains 'DeveloperLaptop')) | Should Be $true
        (($names -contains 'ServerDefault')) | Should Be $true
    }

    It 'Returns expected fields for DesktopGamer' {
        $p = Get-BottleneckProfile -Name DesktopGamer
        $p.Name | Should Be 'DesktopGamer'
        $p.Tier | Should Be 'Standard'
        $p.IncludedChecks | Should BeGreaterThan 0
    }

    It 'End-to-end filtering works for RemoteWorker' {
        Push-Location (Join-Path $PSScriptRoot '..')
        try {
            $out = & .\scripts\run.ps1 -Computer -Profile RemoteWorker -SkipElevation | Out-String
            # Verify summary lines exist (use double quotes to avoid escape issues)
            ($out -match "Profile 'RemoteWorker' loaded") | Should Be $true
            ($out -match 'Filtered to included checks') | Should Be $true
            ($out -match 'Filtered out excluded checks') | Should Be $true
            ($out -match 'Report generated successfully') | Should Be $true
        } finally { Pop-Location }
    }
}
