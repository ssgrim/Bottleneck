# Bottleneck.Scheduler.ps1
# Task Scheduler integration for automated scans

function Register-BottleneckScheduledScan {
    <#
    .SYNOPSIS
    Creates a scheduled task to run Bottleneck scans automatically.
    
    .DESCRIPTION
    Registers Windows scheduled tasks for automated computer or network scans.
    Supports nightly, weekly, or custom schedules with automatic report archival.
    
    .PARAMETER ScanType
    Type of scan to schedule: 'Computer' or 'Network'.
    
    .PARAMETER Schedule
    Preset schedule: 'Nightly2AM', 'Weekly', 'Daily', 'OnIdle', or 'Custom'.
    
    .PARAMETER CustomTime
    For custom schedules, specify time (e.g., '03:00').
    
    .PARAMETER Duration
    For network monitors, specify duration (e.g., '1hour', '4hours').
    
    .PARAMETER RetentionDays
    Days to keep old reports (default: 30, 0 = keep all).
    
    .EXAMPLE
    Register-BottleneckScheduledScan -ScanType Computer -Schedule Nightly2AM
    
    .EXAMPLE
    Register-BottleneckScheduledScan -ScanType Network -Schedule Custom -CustomTime '14:00' -Duration '1hour'
    
    .NOTES
    Requires administrator privileges.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Computer','Network','Speedtest')]
        [string]$ScanType,
        
        [ValidateSet('Nightly2AM','Daily','Weekly','OnIdle','Custom')]
        [string]$Schedule = 'Nightly2AM',
        
        [string]$CustomTime,
        
        [string]$Duration = '1hour',
        
        [int]$RetentionDays = 30
    )
    
    # Check admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This function requires administrator privileges. Run PowerShell as Administrator."
    }
    
    $taskName = "Bottleneck_${ScanType}Scan_$Schedule"
    $modulePath = (Get-Module Bottleneck).Path
    
    # Build PowerShell command
    if ($ScanType -eq 'Computer') {
        $command = "Import-Module '$modulePath' -Force; Invoke-BottleneckComputerScan"
    } elseif ($ScanType -eq 'Network') {
        $command = "Import-Module '$modulePath' -Force; Invoke-BottleneckNetworkMonitor -Duration '$Duration'"
    } else {
        $command = "Import-Module '$modulePath' -Force; Invoke-BottleneckSpeedtest -ShowTrend"
    }
    
    # Add cleanup if retention specified
    if ($RetentionDays -gt 0) {
        $cleanupCmd = "`$limit = (Get-Date).AddDays(-$RetentionDays); Get-ChildItem '$env:USERPROFILE\Documents\ScanReports' -Filter '*.html' | Where-Object LastWriteTime -lt `$limit | Remove-Item -Force"
        $command += "; $cleanupCmd"
    }
    
    # Encode command
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
    $encodedCommand = [Convert]::ToBase64String($bytes)
    
    # Task action
    $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $encodedCommand"
    
    # Task trigger based on schedule
    $trigger = switch ($Schedule) {
        'Nightly2AM' { New-ScheduledTaskTrigger -Daily -At '02:00' }
        'Daily'      { New-ScheduledTaskTrigger -Daily -At '09:00' }
        'Weekly'     { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '02:00' }
        'OnIdle'     { New-ScheduledTaskTrigger -AtStartup }  # Will add idle condition
        'Custom'     { 
            if (-not $CustomTime) { throw "CustomTime required for Custom schedule" }
            New-ScheduledTaskTrigger -Daily -At $CustomTime 
        }
    }
    
    # Task settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    if ($Schedule -eq 'OnIdle') {
        $settings.RunOnlyIfIdle = $true
        $settings.IdleDuration = 'PT10M'
        $settings.IdleWaitTimeout = 'PT1H'
    }
    
    # Principal (run as current user with highest privileges)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
    
    # Register task
    try {
        $task = Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Automated Bottleneck $ScanType scan - $Schedule" -Force
        
        Write-Host "`n✓ Scheduled task created successfully!" -ForegroundColor Green
        Write-Host "`nTask Details:" -ForegroundColor Cyan
        Write-Host "  Name:     $taskName" -ForegroundColor White
        Write-Host "  Type:     $ScanType Scan" -ForegroundColor White
        Write-Host "  Schedule: $Schedule" -ForegroundColor White
        if ($ScanType -eq 'Network') {
            Write-Host "  Duration: $Duration" -ForegroundColor White
        }
        Write-Host "  Retention: $(if($RetentionDays -eq 0){'Keep all'}else{"$RetentionDays days"})" -ForegroundColor White
        
        Write-Host "`nManagement Commands:" -ForegroundColor Cyan
        Write-Host "  View:    Get-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray
        Write-Host "  Run Now: Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray
        Write-Host "  Disable: Disable-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray
        Write-Host "  Remove:  Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false`n" -ForegroundColor Gray
        
        return $task
    } catch {
        Write-Error "Failed to create scheduled task: $_"
    }
}

function Get-BottleneckScheduledScans {
    <#
    .SYNOPSIS
    Lists all Bottleneck scheduled tasks.
    #>
    Get-ScheduledTask | Where-Object { $_.TaskName -like 'Bottleneck_*' } | 
        Select-Object TaskName, State, @{N='NextRun';E={$_.Triggers[0].StartBoundary}}, @{N='LastRun';E={$_.LastRunTime}}
}

function Remove-BottleneckScheduledScan {
    <#
    .SYNOPSIS
    Removes a Bottleneck scheduled task.
    
    .PARAMETER TaskName
    Name of the task to remove (use Get-BottleneckScheduledScans to list).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$TaskName)
    
    if ($PSCmdlet.ShouldProcess($TaskName, 'Remove scheduled task')) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "✓ Task '$TaskName' removed" -ForegroundColor Green
    }
}

