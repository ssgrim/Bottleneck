# Bottleneck.psm1
# Main module entry point

$ErrorActionPreference = 'Continue'  # Don't let errors stop module loading

function Import-ModuleFile($name) {
    $filePath = Join-Path $PSScriptRoot $name
    if (-not (Test-Path $filePath)) {
        Write-Warning "Module file not found: $name"
        return
    }
    try {
        # Use script scope to ensure functions stay in module scope
        . $ExecutionContext.SessionState.Module.NewBoundScriptBlock([scriptblock]::Create((Get-Content $filePath -Raw)))
    }
    catch {
        Write-Warning "Failed to load module file '$name': $_"
        Write-Warning "Error at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line)"
    }
}

# Load debugging and observability first
Import-ModuleFile 'Bottleneck.Debug.ps1'
Import-ModuleFile 'Bottleneck.HealthCheck.ps1'

# Load performance and logging utilities - dot-source at script scope to export Get-CachedCimInstance
. (Join-Path $PSScriptRoot 'Bottleneck.Performance.ps1')
Import-ModuleFile 'Bottleneck.Logging.ps1'

# Set module root for history
$global:BottleneckModuleRoot = Split-Path $PSScriptRoot -Parent

# Load history functions - dot-source at script scope
. (Join-Path $PSScriptRoot 'Bottleneck.History.ps1')

# Initialize logging (guarded)
try {
    if (Get-Command Initialize-BottleneckLogging -ErrorAction SilentlyContinue) {
        Initialize-BottleneckLogging
    }
    else {
        Write-Warning "Logging initialization unavailable; continuing without centralized log"
    }
}
catch {
    Write-Warning "Failed to initialize logging: $_"
}

# Load other modules (hardened paths)
. (Join-Path $PSScriptRoot 'Bottleneck.Checks.ps1')
Import-ModuleFile 'Bottleneck.Fixes.ps1'
. (Join-Path $PSScriptRoot 'Bottleneck.Parallel.ps1')

# Dot-source Report file directly at script scope to keep functions in module scope
. (Join-Path $PSScriptRoot 'Bottleneck.Report.ps1')

# Consolidated hardware module (Battery, Memory, CPUThrottle, Disk, Thermal) - dot-sourced to keep in module scope
. (Join-Path $PSScriptRoot 'Bottleneck.Hardware.ps1')

# Dot-source check modules at script scope to ensure proper function export
. (Join-Path $PSScriptRoot 'Bottleneck.Network.ps1')
. (Join-Path $PSScriptRoot 'Bottleneck.Security.ps1')
. (Join-Path $PSScriptRoot 'Bottleneck.UserExperience.ps1')
. (Join-Path $PSScriptRoot 'Bottleneck.SystemPerformance.ps1')
. (Join-Path $PSScriptRoot 'Bottleneck.DeepScan.ps1')
. (Join-Path $PSScriptRoot 'Bottleneck.Profiles.ps1')
. (Join-Path $PSScriptRoot 'Bottleneck.Wireshark.ps1')

# Check admin rights
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $script:IsAdmin) {
    Write-Warning "Some checks require administrator privileges. Run as admin for complete results."
    if (Get-Command Write-BottleneckLog -ErrorAction SilentlyContinue) {
        Write-BottleneckLog "Running without admin privileges - some checks will be limited" -Level "WARN"
    }
}
else {
    if (Get-Command Write-BottleneckLog -ErrorAction SilentlyContinue) {
        Write-BottleneckLog "Running with administrator privileges" -Level "INFO"
    }
}

# Safe logging wrapper (no-op if logging unavailable)
if (-not (Get-Command Write-BottleneckLog -ErrorAction SilentlyContinue)) {
    function Write-BottleneckLog { param($Message, $Level = "INFO", $CheckId = "") }
}

# Inline critical functions that aren't loading from sourced files
if (-not (Get-Command New-BottleneckResult -ErrorAction SilentlyContinue)) {
    function New-BottleneckResult {
        param([string]$Id, [string]$Tier, [string]$Category, [int]$Impact, [int]$Confidence, [int]$Effort, [int]$Priority, [string]$Evidence, [string]$FixId, [string]$Message)
        [PSCustomObject]@{ Id = $Id; Tier = $Tier; Category = $Category; Impact = $Impact; Confidence = $Confidence; Effort = $Effort; Priority = $Priority; Evidence = $Evidence; FixId = $FixId; Message = $Message; Score = [math]::Round(($Impact * $Confidence) / ($Effort + 1), 2) }
    }
}

if (-not (Get-Command Get-BottleneckChecks -ErrorAction SilentlyContinue)) {
    # Simplified version - just load from Utils and Checks files directly here
    . (Join-Path $PSScriptRoot 'Bottleneck.Utils.ps1')
    . (Join-Path $PSScriptRoot 'Bottleneck.Checks.ps1')
}

# Ensure new debugging and health-check functions are present (resilient sourcing)
if (-not (Get-Command Initialize-BottleneckDebug -ErrorAction SilentlyContinue)) {
    try { . (Join-Path $PSScriptRoot 'Bottleneck.Debug.ps1') } catch { Write-Warning "Failed to load Bottleneck.Debug.ps1: $_" }
}
if (-not (Get-Command Invoke-BottleneckHealthCheck -ErrorAction SilentlyContinue)) {
    try { . (Join-Path $PSScriptRoot 'Bottleneck.HealthCheck.ps1') } catch { Write-Warning "Failed to load Bottleneck.HealthCheck.ps1: $_" }
}

function Invoke-BottleneckScan {
    [CmdletBinding()]
    param(
        [ValidateSet('Quick', 'Standard', 'Deep')]
        [string]$Tier = 'Quick',

        [Parameter()]
        [switch]$Sequential
    )

    Write-BottleneckLog "Starting $Tier scan" -Level "INFO"
    $scanStart = Get-Date

    $checks = Get-BottleneckChecks -Tier $Tier
    Write-BottleneckLog "Executing $($checks.Count) checks" -Level "INFO"
    Write-Host "Running $($checks.Count) diagnostic checks..." -ForegroundColor Cyan

    $results = @()
    $currentCheck = 0

    if ($Sequential -or $PSVersionTable.PSVersion.Major -lt 7) {
        # Sequential execution with progress indicator
        Write-BottleneckLog "Using sequential execution" -Level "INFO"
        foreach ($check in $checks) {
            $currentCheck++
            $pct = [math]::Round(($currentCheck / $checks.Count) * 100)
            Write-Progress -Activity "System Scan ($Tier)" -Status "Check $currentCheck of $($checks.Count): $check" -PercentComplete $pct

            try {
                $checkStart = Get-Date
                $result = & $check
                $checkDuration = ((Get-Date) - $checkStart).TotalMilliseconds
                Write-BottleneckLog "Check $check completed in $([math]::Round($checkDuration))ms" -Level "DEBUG"
                if (Get-Command Write-BottleneckPerformance -ErrorAction SilentlyContinue) {
                    Write-BottleneckPerformance -Operation "Check:$check" -DurationMs $checkDuration -Component $Tier
                }
                if (Get-Command Test-PerformanceBudget -ErrorAction SilentlyContinue) {
                    $budgetCheck = Test-PerformanceBudget -CheckName $check -ElapsedTime ([timespan]::FromMilliseconds($checkDuration)) -Tier $Tier
                    if ($budgetCheck.Exceeded) {
                        $elapsed = [math]::Round($budgetCheck.ElapsedSeconds, 2)
                        $budget = $budgetCheck.BudgetSeconds
                        $msg = "Performance budget exceeded for $check : ${elapsed}s (budget ${budget}s)"
                        Write-BottleneckLog $msg -Level "WARN"
                    }
                }
                if ($result) { $results += $result }
            }
            catch {
                Write-BottleneckLog "Check $check failed: $_" -Level "ERROR" -CheckId $check
                Write-Host "  Warning: $check failed (non-critical, continuing)" -ForegroundColor Yellow
            }
        }
        Write-Progress -Activity "System Scan ($Tier)" -Completed
    }
    else {
        # Parallel execution with bounded concurrency (PS7+)
        $maxConcurrency = switch ($Tier) {
            'Quick' { 2 }
            'Standard' { 4 }
            Default { 6 }
        }

        Write-BottleneckLog "Using parallel execution (max $maxConcurrency jobs)" -Level "INFO"
        Write-Progress -Activity "System Scan ($Tier)" -Status "Starting parallel jobs..." -PercentComplete 0

        $results = Invoke-BottleneckParallelChecks -Checks $checks -Tier $Tier -ModulePath $PSScriptRoot -MaxConcurrency $maxConcurrency

        Write-Progress -Activity "System Scan ($Tier)" -Completed
    }

    $scanDuration = ((Get-Date) - $scanStart).TotalSeconds
    Write-BottleneckLog "Scan completed in $([math]::Round($scanDuration,1)) seconds with $($results.Count) results" -Level "INFO"
    Write-Host "Scan complete: $($results.Count) findings in $([math]::Round($scanDuration,1))s" -ForegroundColor Green

    # Budget check for the overall tier duration
    try {
        if (Get-Command Test-PerformanceBudget -ErrorAction SilentlyContinue) {
            $budgetResult = Test-PerformanceBudget -CheckName "Scan-$Tier" -ElapsedTime ([timespan]::FromSeconds($scanDuration)) -Tier $Tier
            if ($budgetResult.Exceeded) {
                $msg = "Performance budget exceeded for {0}: {1}s (budget {2}s)" -f $Tier, $scanDuration, $budgetResult.BudgetSeconds
                Write-BottleneckLog $msg -Level "WARN"
            }
        }
    }
    catch {
        $errMsg = "Performance budget check failed: {0}" -f $_.Exception.Message
        Write-BottleneckLog $errMsg -Level "WARN"
    }

    return $results
}

# Stub functions for network RCA (implementations live elsewhere)
function Invoke-BottleneckNetworkRootCause {
    Write-Warning 'Invoke-BottleneckNetworkRootCause is not yet integrated into this module version'
    return $null
}

function Invoke-BottleneckNetworkCsvDiagnostics {
    Write-Warning 'Invoke-BottleneckNetworkCsvDiagnostics is not yet integrated into this module version'
    return $null
}

# Export all functions from sourced module files
# Using wildcard to export all functions defined in module scope
Export-ModuleMember -Function *
