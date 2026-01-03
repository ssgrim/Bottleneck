#Requires -Version 7.0
#Requires -Modules Pester

<#
.SYNOPSIS
Smoke and regression test suite for Bottleneck v1.0

.DESCRIPTION
Validates core functionality: module import, scan execution, safe event log queries,
performance budgeting, and report generation. Run with: Invoke-Pester tests/Bottleneck.Tests.ps1 -Verbose
#>

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Describe 'Bottleneck Module' {
    Context 'Module Import' {
        It 'Should import without errors' {
            { Import-Module "$repoRoot/src/ps/Bottleneck.psm1" -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should export primary scan function' {
            $cmd = Get-Command Invoke-BottleneckScan -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should export report function' {
            $cmd = Get-Command Invoke-BottleneckReport -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should export performance budget function' {
            $cmd = Get-Command Test-PerformanceBudget -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should export safe event log function' {
            $cmd = Get-Command Get-EventLogSafeQuery -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Safe Event Log Queries' {
        It 'Should handle null StartTime without error' {
            $filter = @{ LogName = 'System'; StartTime = $null }
            { Get-EventLogSafeQuery -LogName 'System' -StartTime $null -TimeoutSeconds 5 -MaxEvents 10 } | Should -Not -Throw
        }

        It 'Should return result object with Success property' {
            $result = Get-EventLogSafeQuery -LogName 'System' -TimeoutSeconds 5 -MaxEvents 10 -ErrorAction SilentlyContinue
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -BeIn @($true, $false)
        }

        It 'Should return Count property (even on fallback)' {
            $result = Get-EventLogSafeQuery -LogName 'System' -TimeoutSeconds 5 -MaxEvents 10 -ErrorAction SilentlyContinue
            $result.Count | Should -Not -BeNullOrEmpty
        }

        It 'Should gracefully handle inaccessible logs' {
            $result = Get-EventLogSafeQuery -LogName 'Security' -TimeoutSeconds 5 -MaxEvents 10 -ErrorAction SilentlyContinue
            # Either succeeds or fails gracefully with Reason set
            $result.Reason | Should -BeIn @('OK', 'AccessDenied', 'NotFound', $null)
        }
    }

    Context 'Performance Budget' {
        It 'Should calculate correct budget for Quick tier' {
            $result = Test-PerformanceBudget -CheckName 'Test' -ElapsedTime ([timespan]::FromSeconds(10)) -Tier 'Quick'
            $result.BudgetSeconds | Should -Be 30
        }

        It 'Should calculate correct budget for Standard tier' {
            $result = Test-PerformanceBudget -CheckName 'Test' -ElapsedTime ([timespan]::FromSeconds(20)) -Tier 'Standard'
            $result.BudgetSeconds | Should -Be 45
        }

        It 'Should calculate correct budget for Deep tier' {
            $result = Test-PerformanceBudget -CheckName 'Test' -ElapsedTime ([timespan]::FromSeconds(40)) -Tier 'Deep'
            $result.BudgetSeconds | Should -Be 75
        }

        It 'Should flag exceeded budgets at 80% threshold' {
            $result = Test-PerformanceBudget -CheckName 'Test' -ElapsedTime ([timespan]::FromSeconds(39)) -Tier 'Standard'
            $result.Exceeded | Should -Be $true
            $result.Severity | Should -Be 'Warning'
        }

        It 'Should flag critical when exceeding budget ceiling' {
            $result = Test-PerformanceBudget -CheckName 'Test' -ElapsedTime ([timespan]::FromSeconds(50)) -Tier 'Standard'
            $result.Exceeded | Should -Be $true
            $result.Severity | Should -Be 'Critical'
        }
    }

    Context 'Check Functions' {
        It 'Should have Get-BottleneckChecks available' {
            $cmd = Get-Command Get-BottleneckChecks -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should return Quick checks' {
            $checks = Get-BottleneckChecks -Tier 'Quick' -ErrorAction SilentlyContinue
            $checks | Should -Not -BeNullOrEmpty
            @($checks).Count | Should -BeGreaterThan 0
        }

        It 'Should return Standard checks' {
            $checks = Get-BottleneckChecks -Tier 'Standard' -ErrorAction SilentlyContinue
            $checks | Should -Not -BeNullOrEmpty
            @($checks).Count | Should -BeGreaterThan 0
        }

        It 'Should return Deep checks' {
            $checks = Get-BottleneckChecks -Tier 'Deep' -ErrorAction SilentlyContinue
            $checks | Should -Not -BeNullOrEmpty
            @($checks).Count | Should -BeGreaterThan 0
        }
    }

    Context 'Scan Execution' {
        It 'Should complete Quick scan without error' {
            { $null = Invoke-BottleneckScan -Tier 'Quick' -Sequential -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should return results array or empty' {
            $results = Invoke-BottleneckScan -Tier 'Quick' -Sequential -ErrorAction SilentlyContinue
            # Results can be empty or array; just ensure no exception
            $results | Should -BeOfType @([System.Object[]], [System.Object])
        }
    }

    Context 'Result Creation' {
        It 'Should create result with all required properties' {
            $result = New-BottleneckResult -Id 'TEST' -Tier 'Standard' -Category 'Test' `
                -Impact 5 -Confidence 8 -Effort 2 -Priority 3 `
                -Evidence 'Test evidence' -FixId 'FIX001' -Message 'Test message'

            $result.Id | Should -Be 'TEST'
            $result.Tier | Should -Be 'Standard'
            $result.Category | Should -Be 'Test'
            $result.Impact | Should -Be 5
            $result.Score | Should -Not -BeNullOrEmpty
        }

        It 'Should calculate Score correctly' {
            $result = New-BottleneckResult -Id 'TEST' -Tier 'Standard' -Category 'Test' `
                -Impact 10 -Confidence 10 -Effort 1 -Priority 1 `
                -Evidence '' -FixId '' -Message ''

            # Score = (Impact * Confidence) / (Effort + 1) = (10 * 10) / 2 = 50
            $result.Score | Should -Be 50
        }
    }

    Context 'Logging and Debugging' {
        It 'Should have logging functions available' {
            $cmd = Get-Command Write-BottleneckLog -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should have debug functions available' {
            $cmd = Get-Command Write-BottleneckDebug -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should have performance tracking available' {
            $cmd = Get-Command Write-BottleneckPerformance -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parallel Execution' {
        It 'Should have parallel controller function' {
            $cmd = Get-Command Invoke-BottleneckParallelChecks -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should export parallel groups function' {
            $cmd = Get-Command Get-ParallelCheckGroups -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
        }

        It 'Should return check groups for Standard tier' {
            $groups = Get-ParallelCheckGroups -Tier 'Standard' -ErrorAction SilentlyContinue
            $groups | Should -Not -BeNullOrEmpty
            @($groups).Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'Bottleneck Integration' {
    Context 'End-to-End Smoke Test' {
        It 'Should complete minimal Quick scan in under 60 seconds' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $results = Invoke-BottleneckScan -Tier 'Quick' -Sequential -ErrorAction SilentlyContinue
            $sw.Stop()

            $sw.Elapsed.TotalSeconds | Should -BeLessThan 60
        }

        It 'Should produce valid result objects' {
            $results = Invoke-BottleneckScan -Tier 'Quick' -Sequential -ErrorAction SilentlyContinue
            if ($results -and $results.Count -gt 0) {
                $results[0] | Get-Member -Name 'Id' | Should -Not -BeNullOrEmpty
                $results[0] | Get-Member -Name 'Score' | Should -Not -BeNullOrEmpty
            }
        }
    }
}
