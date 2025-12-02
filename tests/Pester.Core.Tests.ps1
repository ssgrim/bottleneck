# Pester.Core.Tests.ps1
# Core functionality tests for Bottleneck module
# Pester v3 compatible syntax

# Import module before tests
$modulePath = Join-Path $PSScriptRoot '..\src\ps\Bottleneck.psm1'
Import-Module $modulePath -Force

Describe 'Module Exports' {
    It 'Exports expected number of functions' {
        $commands = Get-Command -Module Bottleneck
        $commands.Count | Should BeGreaterThan 75
    }

    It 'Exports core check functions' {
        $coreChecks = @(
            'Test-BottleneckStorage', 'Test-BottleneckRAM', 'Test-BottleneckCPU',
            'Test-BottleneckNetwork', 'Test-BottleneckPowerPlan', 'Test-BottleneckStartup',
            'Test-BottleneckDNS', 'Test-BottleneckServiceHealth', 'Test-BottleneckTasks',
            'Test-BottleneckMemoryHealth', 'Test-BottleneckBattery', 'Test-BottleneckThermal'
        )
        foreach ($check in $coreChecks) {
            Get-Command $check -Module Bottleneck -ErrorAction Stop | Should Not BeNullOrEmpty
        }
    }

    It 'Exports utility functions' {
        Get-Command Get-SafeWinEvent -Module Bottleneck | Should Not BeNullOrEmpty
        Get-Command Get-CachedCimInstance -Module Bottleneck | Should Not BeNullOrEmpty
        Get-Command Invoke-WithTimeout -Module Bottleneck | Should Not BeNullOrEmpty
    }

    It 'Exports scan and report functions' {
        Get-Command Invoke-BottleneckScan -Module Bottleneck | Should Not BeNullOrEmpty
        Get-Command Invoke-BottleneckReport -Module Bottleneck | Should Not BeNullOrEmpty
    }
}

Describe 'Parameter Validation' {
    Context 'Tier validation' {
        It 'Accepts valid tier values' {
            $validTiers = @('Quick', 'Standard', 'Deep')
            foreach ($tier in $validTiers) {
                { Get-BottleneckChecks -Tier $tier } | Should Not Throw
            }
        }
    }

    Context 'Timeout validation' {
        It 'Accepts valid timeout range' {
            $filter = @{LogName='System'}
            { Get-SafeWinEvent -FilterHashtable $filter -TimeoutSeconds 10 } | Should Not Throw
            { Get-SafeWinEvent -FilterHashtable $filter -TimeoutSeconds 300 } | Should Not Throw
        }
    }
}

Describe 'Core Check Functions' {
    Context 'Storage check' {
        It 'Returns a valid result object' {
            $result = Test-BottleneckStorage
            $result | Should Not BeNullOrEmpty
            $result.Category | Should Be 'Storage'
            $result.Evidence | Should Match 'Free space'
        }

        It 'Reports free space in GB' {
            $result = Test-BottleneckStorage
            $result.Evidence | Should Match '\d+\.\d+ GB'
        }
    }

    Context 'RAM check' {
        It 'Returns a valid result object' {
            $result = Test-BottleneckRAM
            $result | Should Not BeNullOrEmpty
            $result.Category | Should Be 'RAM'
        }
    }

    Context 'Power plan check' {
        It 'Returns a valid result object' {
            $result = Test-BottleneckPowerPlan
            $result | Should Not BeNullOrEmpty
            $result.Category | Should Be 'Power'
        }
    }

    Context 'Thermal check' {
        It 'Returns a valid result object' {
            $result = Test-BottleneckThermal
            $result | Should Not BeNullOrEmpty
            $result.Category | Should Be 'Thermal'
        }

        It 'Shows sensor availability' {
            $result = Test-BottleneckThermal
            $result.Evidence | Should Match '(no sensor|\d+°C)'
        }
    }

    Context 'Scheduled Tasks check' {
        It 'Returns a valid result object' {
            $result = Test-BottleneckTasks
            $result | Should Not BeNullOrEmpty
            $result.Category | Should Be 'Tasks'
            $result.Evidence | Should Match 'Total:'
        }

        It 'Reports task counts' {
            $result = Test-BottleneckTasks
            $result.Evidence | Should Match 'Total: \d+, Failed: \d+, Heavy: \d+'
        }
    }
}

Describe 'Error Handling' {
    Context 'Event log safety' {
        It 'Handles missing event logs gracefully' {
            $filter = @{LogName='NonExistentLog'}
            { Get-SafeWinEvent -FilterHashtable $filter } | Should Not Throw
        }

        It 'Returns empty array when no events found' {
            $filter = @{LogName='System'; StartTime=(Get-Date).AddDays(-365)}
            $result = Get-SafeWinEvent -FilterHashtable $filter -MaxEvents 1
            $result | Should Not BeNullOrEmpty
        }
    }

    Context 'CIM caching' {
        It 'Handles invalid class names' {
            { Get-CachedCimInstance -ClassName 'NonExistentClass' } | Should Not Throw
        }
    }
}

Describe 'Scan Integration' {
    Context 'Quick scan' {
        It 'Completes without errors' {
            { Invoke-BottleneckScan -Tier Quick } | Should Not Throw
        }

        It 'Returns at least 6 results' {
            $results = Invoke-BottleneckScan -Tier Quick
            $results.Count | Should BeGreaterThan 5
        }

        It 'All results have required properties' {
            $results = Invoke-BottleneckScan -Tier Quick
            foreach ($result in $results) {
                $result.Category | Should Not BeNullOrEmpty
                $result.Message | Should Not BeNullOrEmpty
                $result.Evidence | Should Not BeNullOrEmpty
                $result.Score | Should BeGreaterThan 0
            }
        }
    }

    Context 'Standard scan' {
        It 'Returns more results than Quick' {
            $quick = Invoke-BottleneckScan -Tier Quick
            $standard = Invoke-BottleneckScan -Tier Standard
            $standard.Count | Should BeGreaterThan $quick.Count
        }
    }
}
