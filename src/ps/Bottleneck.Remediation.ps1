# ========================================
# Bottleneck.Remediation.ps1
# Automated Fix Execution Engine
# ========================================

using namespace System.Collections.Generic

#region Classes and Enums

enum FixCategory {
    Performance
    Network
    Security
    Maintenance
    Configuration
}

enum RiskLevel {
    Safe
    Low
    Medium
    High
    Critical
}

enum FixStatus {
    Pending
    Approved
    Rejected
    Executing
    Success
    Failed
    RolledBack
}

class RemediationFix {
    [string]$Id
    [string]$Name
    [string]$Description
    [FixCategory]$Category
    [RiskLevel]$Risk
    [bool]$RequiresApproval
    [bool]$RequiresReboot
    [bool]$IsReversible
    [string[]]$Prerequisites
    [string[]]$CheckIds
    [scriptblock]$PreCheck
    [scriptblock]$Execute
    [scriptblock]$PostCheck
    [scriptblock]$Rollback
    [int]$EstimatedDurationSec
    [hashtable]$Metadata

    RemediationFix() {
        $this.Metadata = @{}
        $this.Prerequisites = @()
        $this.CheckIds = @()
    }
}

class FixExecution {
    [string]$FixId
    [DateTime]$Timestamp
    [bool]$UserApproved
    [FixStatus]$Status
    [int]$ExecutionDurationSec
    [hashtable]$MetricsBefore
    [hashtable]$MetricsAfter
    [string]$ResultMessage
    [bool]$RollbackAvailable
    [string]$ErrorDetails

    FixExecution([string]$fixId) {
        $this.FixId = $fixId
        $this.Timestamp = Get-Date
        $this.MetricsBefore = @{}
        $this.MetricsAfter = @{}
        $this.RollbackAvailable = $false
    }
}

#endregion

#region Fix Registry

$script:FixRegistry = @{}

function Register-RemediationFix {
    <#
    .SYNOPSIS
    Register a new fix in the remediation engine
    #>
    param(
        [Parameter(Mandatory)]
        [RemediationFix]$Fix
    )

    if ($script:FixRegistry.ContainsKey($Fix.Id)) {
        Write-Warning "Fix '$($Fix.Id)' already registered. Overwriting."
    }

    $script:FixRegistry[$Fix.Id] = $Fix
    Write-Verbose "Registered fix: $($Fix.Id) - $($Fix.Name)"
}

function Get-RemediationFix {
    <#
    .SYNOPSIS
    Get registered fixes, optionally filtered by criteria
    #>
    param(
        [string]$Id,
        [FixCategory]$Category,
        [RiskLevel]$MaxRisk,
        [string[]]$CheckIds
    )

    $fixes = $script:FixRegistry.Values

    if ($Id) {
        $fixes = $fixes | Where-Object { $_.Id -eq $Id }
    }

    if ($Category) {
        $fixes = $fixes | Where-Object { $_.Category -eq $Category }
    }

    if ($MaxRisk) {
        $riskOrder = @('Safe', 'Low', 'Medium', 'High', 'Critical')
        $maxRiskIndex = $riskOrder.IndexOf($MaxRisk.ToString())
        $fixes = $fixes | Where-Object { 
            $riskOrder.IndexOf($_.Risk.ToString()) -le $maxRiskIndex 
        }
    }

    if ($CheckIds) {
        $fixes = $fixes | Where-Object {
            $checkIdArray = $_.CheckIds
            ($CheckIds | Where-Object { $checkIdArray -contains $_ }).Count -gt 0
        }
    }

    return $fixes
}

#endregion

#region Fix Execution

function Invoke-RemediationFix {
    <#
    .SYNOPSIS
    Execute a remediation fix with full safety checks
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FixId,

        [switch]$SkipApproval,
        [switch]$DryRun,
        [switch]$Force
    )

    $fix = $script:FixRegistry[$FixId]
    if (-not $fix) {
        Write-Error "Fix '$FixId' not found in registry"
        return
    }

    $execution = [FixExecution]::new($FixId)

    try {
        # Display fix information
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Remediation Fix: $($fix.Name)" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Category: $($fix.Category)" -ForegroundColor White
        Write-Host "Risk Level: $($fix.Risk)" -ForegroundColor $(Get-RiskColor $fix.Risk)
        Write-Host "Description: $($fix.Description)" -ForegroundColor Gray
        Write-Host "Reversible: $(if ($fix.IsReversible) { 'Yes' } else { 'No' })" -ForegroundColor $(if ($fix.IsReversible) { 'Green' } else { 'Yellow' })
        Write-Host "Estimated Time: $($fix.EstimatedDurationSec) seconds" -ForegroundColor Gray
        
        if ($fix.RequiresReboot) {
            Write-Host "⚠️  REQUIRES REBOOT AFTER EXECUTION" -ForegroundColor Yellow
        }

        # Check prerequisites
        if (-not (Test-Prerequisites $fix)) {
            $execution.Status = [FixStatus]::Failed
            $execution.ResultMessage = "Prerequisites not met"
            return $execution
        }

        # Get user approval
        if ($fix.RequiresApproval -and -not $SkipApproval -and -not $DryRun) {
            Write-Host "`n" -NoNewline
            $response = Read-Host "Do you approve this fix? (Y/N)"
            
            if ($response -ne 'Y' -and $response -ne 'y') {
                $execution.Status = [FixStatus]::Rejected
                $execution.ResultMessage = "User rejected fix"
                Write-Host "Fix rejected by user" -ForegroundColor Yellow
                return $execution
            }
            
            $execution.UserApproved = $true
        } else {
            $execution.UserApproved = $true
        }

        if ($DryRun) {
            Write-Host "`n[DRY RUN] Would execute fix: $($fix.Name)" -ForegroundColor Magenta
            $execution.Status = [FixStatus]::Pending
            return $execution
        }

        # Create restore point for high-risk fixes
        if (($fix.Risk -eq [RiskLevel]::High -or $fix.Risk -eq [RiskLevel]::Critical) -and -not $Force) {
            Write-Host "`nCreating system restore point..." -ForegroundColor Yellow
            try {
                Checkpoint-Computer -Description "Bottleneck Fix: $($fix.Name)" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                Write-Host "Restore point created successfully" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to create restore point: $_"
                $continue = Read-Host "Continue without restore point? (Y/N)"
                if ($continue -ne 'Y' -and $continue -ne 'y') {
                    $execution.Status = [FixStatus]::Failed
                    $execution.ResultMessage = "Restore point creation failed"
                    return $execution
                }
            }
        }

        # Run pre-check
        Write-Host "`nRunning pre-execution checks..." -ForegroundColor Cyan
        if ($fix.PreCheck) {
            $execution.MetricsBefore = & $fix.PreCheck
            Write-Host "Pre-check completed" -ForegroundColor Green
        }

        # Execute fix
        Write-Host "`nExecuting fix..." -ForegroundColor Cyan
        $execution.Status = [FixStatus]::Executing
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $result = & $fix.Execute
            $stopwatch.Stop()
            $execution.ExecutionDurationSec = [int]$stopwatch.Elapsed.TotalSeconds

            Write-Host "Fix executed successfully in $($execution.ExecutionDurationSec) seconds" -ForegroundColor Green

            # Run post-check
            Write-Host "`nRunning post-execution validation..." -ForegroundColor Cyan
            if ($fix.PostCheck) {
                $execution.MetricsAfter = & $fix.PostCheck
                
                # Verify improvement
                $improved = Test-FixImprovement $execution.MetricsBefore $execution.MetricsAfter
                if ($improved) {
                    $execution.Status = [FixStatus]::Success
                    $execution.ResultMessage = "Fix successful - metrics improved"
                    Write-Host "✓ Verification passed - system improved" -ForegroundColor Green
                } else {
                    Write-Warning "No improvement detected, considering rollback"
                    $execution.Status = [FixStatus]::Success
                    $execution.ResultMessage = "Fix completed but no measurable improvement"
                }
            } else {
                $execution.Status = [FixStatus]::Success
                $execution.ResultMessage = "Fix completed successfully"
            }

            $execution.RollbackAvailable = $fix.IsReversible

        } catch {
            $stopwatch.Stop()
            $execution.ExecutionDurationSec = [int]$stopwatch.Elapsed.TotalSeconds
            $execution.Status = [FixStatus]::Failed
            $execution.ErrorDetails = $_.Exception.Message
            $execution.ResultMessage = "Fix execution failed: $($_.Exception.Message)"
            
            Write-Host "`n✗ Fix execution failed: $($_.Exception.Message)" -ForegroundColor Red

            # Attempt rollback if available
            if ($fix.IsReversible -and $fix.Rollback) {
                Write-Host "`nAttempting automatic rollback..." -ForegroundColor Yellow
                try {
                    & $fix.Rollback
                    $execution.Status = [FixStatus]::RolledBack
                    $execution.ResultMessage += " (rolled back)"
                    Write-Host "Rollback successful" -ForegroundColor Green
                } catch {
                    Write-Host "Rollback failed: $($_.Exception.Message)" -ForegroundColor Red
                    $execution.ErrorDetails += "; Rollback failed: $($_.Exception.Message)"
                }
            }
        }

        # Log execution
        Save-FixExecution $execution

        return $execution

    } finally {
        Write-Host "`n========================================`n" -ForegroundColor Cyan
    }
}

function Test-Prerequisites {
    param([RemediationFix]$Fix)

    if ($Fix.Prerequisites.Count -eq 0) {
        return $true
    }

    Write-Host "`nChecking prerequisites..." -ForegroundColor Cyan
    
    foreach ($prereq in $Fix.Prerequisites) {
        switch ($prereq) {
            'Admin' {
                if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                    Write-Host "✗ Administrator rights required" -ForegroundColor Red
                    return $false
                }
            }
            'Internet' {
                if (-not (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet)) {
                    Write-Host "✗ Internet connectivity required" -ForegroundColor Red
                    return $false
                }
            }
            default {
                Write-Warning "Unknown prerequisite: $prereq"
            }
        }
    }

    Write-Host "✓ All prerequisites met" -ForegroundColor Green
    return $true
}

function Test-FixImprovement {
    param(
        [hashtable]$Before,
        [hashtable]$After
    )

    if ($Before.Count -eq 0 -or $After.Count -eq 0) {
        return $false
    }

    # Simple improvement detection - can be enhanced
    $improvements = 0
    foreach ($key in $Before.Keys) {
        if ($After.ContainsKey($key)) {
            $beforeVal = $Before[$key]
            $afterVal = $After[$key]
            
            # Assuming higher values are better (e.g., free space, performance score)
            if ($afterVal -gt $beforeVal) {
                $improvements++
            }
        }
    }

    return $improvements -gt 0
}

function Get-RiskColor {
    param([RiskLevel]$Risk)
    
    switch ($Risk) {
        'Safe' { 'Green' }
        'Low' { 'Cyan' }
        'Medium' { 'Yellow' }
        'High' { 'Red' }
        'Critical' { 'Magenta' }
        default { 'White' }
    }
}

function Save-FixExecution {
    param([FixExecution]$Execution)

    $historyPath = Join-Path $PSScriptRoot "..\..\Reports\fix-history.json"
    
    $history = @()
    if (Test-Path $historyPath) {
        $history = Get-Content $historyPath -Raw | ConvertFrom-Json
    }

    $history += @{
        fix_id = $Execution.FixId
        timestamp = $Execution.Timestamp.ToString('o')
        user_approved = $Execution.UserApproved
        status = $Execution.Status.ToString()
        execution_duration_sec = $Execution.ExecutionDurationSec
        metrics_before = $Execution.MetricsBefore
        metrics_after = $Execution.MetricsAfter
        result_message = $Execution.ResultMessage
        rollback_available = $Execution.RollbackAvailable
        error_details = $Execution.ErrorDetails
    }

    $history | ConvertTo-Json -Depth 10 | Set-Content $historyPath
    Write-Verbose "Logged execution to: $historyPath"
}

#endregion

#region Built-in Fixes

# Register common fixes
function Initialize-BuiltInFixes {
    # Fix: DNS Cache Flush
    $fix = [RemediationFix]::new()
    $fix.Id = 'dns-cache-flush'
    $fix.Name = 'Flush DNS Cache'
    $fix.Description = 'Clear DNS resolver cache to fix DNS resolution issues'
    $fix.Category = [FixCategory]::Network
    $fix.Risk = [RiskLevel]::Safe
    $fix.RequiresApproval = $false
    $fix.RequiresReboot = $false
    $fix.IsReversible = $false
    $fix.EstimatedDurationSec = 5
    $fix.CheckIds = @('DNS')
    $fix.Execute = {
        Clear-DnsClientCache
        ipconfig /flushdns | Out-Null
        return @{ status = 'completed' }
    }
    Register-RemediationFix $fix

    # Fix: Disk Cleanup - Temp Files
    $fix = [RemediationFix]::new()
    $fix.Id = 'disk-cleanup-temp'
    $fix.Name = 'Clean Temporary Files'
    $fix.Description = 'Remove temporary files to free up disk space'
    $fix.Category = [FixCategory]::Maintenance
    $fix.Risk = [RiskLevel]::Low
    $fix.RequiresApproval = $true
    $fix.RequiresReboot = $false
    $fix.IsReversible = $false
    $fix.EstimatedDurationSec = 30
    $fix.CheckIds = @('Disk')
    $fix.PreCheck = {
        $drive = Get-PSDrive C
        return @{ disk_free_gb = [math]::Round($drive.Free / 1GB, 2) }
    }
    $fix.Execute = {
        $tempPaths = @(
            $env:TEMP,
            "$env:SystemRoot\Temp",
            "$env:LOCALAPPDATA\Temp"
        )
        
        $totalRemoved = 0
        foreach ($path in $tempPaths) {
            if (Test-Path $path) {
                $items = Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    try {
                        $size = $item.Length
                        Remove-Item $item.FullName -Force -Recurse -ErrorAction SilentlyContinue
                        $totalRemoved += $size
                    } catch {
                        # Ignore locked files
                    }
                }
            }
        }
        
        return @{ bytes_removed = $totalRemoved }
    }
    $fix.PostCheck = {
        $drive = Get-PSDrive C
        return @{ disk_free_gb = [math]::Round($drive.Free / 1GB, 2) }
    }
    Register-RemediationFix $fix

    # Fix: Network Adapter Reset
    $fix = [RemediationFix]::new()
    $fix.Id = 'network-adapter-reset'
    $fix.Name = 'Reset Network Adapter'
    $fix.Description = 'Reset network adapters to fix connectivity issues'
    $fix.Category = [FixCategory]::Network
    $fix.Risk = [RiskLevel]::Medium
    $fix.RequiresApproval = $true
    $fix.RequiresReboot = $false
    $fix.IsReversible = $true
    $fix.EstimatedDurationSec = 20
    $fix.CheckIds = @('Network', 'NetworkAdapter')
    $fix.Prerequisites = @('Admin')
    $fix.Execute = {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        foreach ($adapter in $adapters) {
            Restart-NetAdapter -Name $adapter.Name -Confirm:$false
        }
        Start-Sleep -Seconds 5
        return @{ adapters_reset = $adapters.Count }
    }
    $fix.Rollback = {
        # Network adapters will auto-reconnect
        Write-Host "Network adapters will reconnect automatically" -ForegroundColor Yellow
    }
    Register-RemediationFix $fix

    Write-Verbose "Initialized $($script:FixRegistry.Count) built-in fixes"
}

# Initialize on module load
Initialize-BuiltInFixes

function Get-AvailableFixes {
    <#
    .SYNOPSIS
    List all available remediation fixes
    #>
    param(
        [Parameter()][FixCategory]$Category,
        [Parameter()][RiskLevel]$MaxRisk
    )

    $params = @{}
    if ($PSBoundParameters.ContainsKey('Category')) { $params.Category = $Category }
    if ($PSBoundParameters.ContainsKey('MaxRisk')) { $params.MaxRisk = $MaxRisk }

    Get-RemediationFix @params | 
        Select-Object Id, Name, Category, Risk, Description, EstimatedDurationSec |
        Format-Table -AutoSize
}

function Invoke-AutoRemediation {
    <#
    .SYNOPSIS
    Automatically execute safe fixes without approval
    #>
    param(
        [string[]]$CheckIds,
        [switch]$DryRun
    )

    $safeFixes = Get-RemediationFix -MaxRisk ([RiskLevel]::Low) -CheckIds $CheckIds
    
    Write-Host "Found $($safeFixes.Count) safe fixes for specified checks" -ForegroundColor Cyan
    
    foreach ($fix in $safeFixes) {
        if (-not $fix.RequiresApproval) {
            Invoke-RemediationFix -FixId $fix.Id -SkipApproval -DryRun:$DryRun
        }
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Register-RemediationFix',
    'Get-RemediationFix',
    'Invoke-RemediationFix',
    'Get-AvailableFixes',
    'Invoke-AutoRemediation'
)
