# Pester.Basics.Tests.ps1
# Minimal smoke tests for module load, baselines, and health check (Pester v3+v5 compatible)

$ErrorActionPreference = 'Stop'

Describe 'Bottleneck module basics' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $repoRoot 'src/ps/Bottleneck.psm1') -Force -WarningAction SilentlyContinue
    }

    It 'exports core commands' {
        # Pester v3 syntax
        $cmd = Get-Command Initialize-BottleneckDebug -ErrorAction SilentlyContinue
        $cmd | Should Not BeNullOrEmpty

        (Get-Command Invoke-BottleneckHealthCheck -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Save-BottleneckBaseline -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Compare-ToBaseline -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }

    It 'saves and compares a baseline' {
        $name = 'ci-smoke'
        $baseDir = Join-Path $PSScriptRoot 'baselines-ci'
        if (Test-Path $baseDir) { Remove-Item -Recurse -Force $baseDir }
        New-Item -ItemType Directory -Path $baseDir | Out-Null

        $m1 = @{ latencyAvg = 60; successRate = 99.7 }
        $file = Save-BottleneckBaseline -Metrics $m1 -Name $name -Path $baseDir
        Test-Path $file | Should Be $true

        $m2 = @{ latencyAvg = 120; successRate = 99.0 }
        $c = Compare-ToBaseline -Metrics $m2 -Name $name -Path $baseDir
        $c | Should Not BeNullOrEmpty
        $c.comparison.ContainsKey('latencyAvg') | Should Be $true
    }

    It 'runs health check without throwing' {
        { Invoke-BottleneckHealthCheck -Verbose:$false } | Should Not Throw
    }
}
