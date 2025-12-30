# Bottleneck.Parallel.ps1
# Parallel execution controller (skeleton)

using namespace System.Collections.Generic

function Invoke-BottleneckParallel {
    param(
        [Parameter(Mandatory)][ValidateSet('Quick','Standard','Deep')][string]$Tier,
        [Parameter(Mandatory)][ValidateNotNull()][hashtable]$Config,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ReportsPath,
        [Parameter(Mandatory)][ValidateNotNull()][scriptblock]$CheckDispatcher,
        [ValidateRange(1,16)][int]$MaxConcurrency = 4
    )

    $jobs = New-Object List[object]
    $throttle = [Math]::Max(1, $MaxConcurrency)

    foreach ($group in (Get-ParallelCheckGroups -Tier $Tier)) {
        # Throttle job submissions
        while ($jobs.Count -ge $throttle) {
            $jobs = Receive-CheckJobs -Jobs $jobs
            Start-Sleep -Milliseconds 50
        }

        $jobs.Add((Start-CheckJob -Group $group -Config $Config -ReportsPath $ReportsPath -CheckDispatcher $CheckDispatcher))
    }

    # Drain remaining
    while ($jobs.Count -gt 0) {
        $jobs = Receive-CheckJobs -Jobs $jobs
        Start-Sleep -Milliseconds 50
    }
}

# Direct check runner with bounded concurrency (used by Invoke-BottleneckScan)
function Invoke-BottleneckParallelChecks {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]$Checks,
        [Parameter(Mandatory)][ValidateSet('Quick','Standard','Deep')][string]$Tier,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ModulePath,
        [ValidateRange(1,16)][int]$MaxConcurrency = 4
    )

    $results = @()
    $jobs = @()

    foreach ($check in $Checks) {
        while (($jobs | Where-Object { $_.State -eq 'Running' }).Count -ge $MaxConcurrency) {
            $ready = Receive-Job -Job ($jobs | Where-Object { $_.State -ne 'Running' }) -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
            if ($ready) { $results += ($ready | Where-Object { $_ -and -not $_.Failed }) }
            $jobs = $jobs | Where-Object { $_.State -eq 'Running' }
        }

        $job = Start-ThreadJob -ScriptBlock {
            param($checkName, $modulePath)
            try {
                Import-Module (Join-Path $modulePath 'Bottleneck.psm1') -Force -ErrorAction Stop
                $result = & $checkName
                if ($result) { $result }
            }
            catch {
                [PSCustomObject]@{
                    Id        = 'Error'
                    CheckName = $checkName
                    Error     = $_.Exception.Message
                    Failed    = $true
                }
            }
        } -ArgumentList $check, $ModulePath -ErrorAction SilentlyContinue
        $jobs += $job
    }

    while ($jobs.Count -gt 0) {
        $ready = Receive-Job -Job $jobs -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
        if ($ready) { $results += ($ready | Where-Object { $_ -and -not $_.Failed }) }
        $jobs = $jobs | Where-Object { $_.State -eq 'Running' }
    }

    return $results
}

# Return ordered list of check groups based on tier
function Get-ParallelCheckGroups {
    param([Parameter(Mandatory)][ValidateSet('Quick','Standard','Deep')][string]$Tier)

    switch ($Tier) {
        'Quick'    { @('core') }
        'Standard' { @('core','cpu','memory','disk','network','security') }
        default    { @('core','cpu','memory','disk','network','security','advanced') }
    }
}

# Start a job for a check group
function Start-CheckJob {
    param(
        [Parameter(Mandatory)][string]$Group,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$ReportsPath,
        [Parameter(Mandatory)][scriptblock]$CheckDispatcher
    )

    $bootstrap = {
        param($Group, $Config, $ReportsPath, $CheckDispatcher)
        # Bootstrap: import module context
        $here = Split-Path -Parent $MyInvocation.MyCommand.Path
        . "$here/Bottleneck.Utils.ps1"
        . "$here/Bottleneck.Logging.ps1"
        . "$here/Bottleneck.Checks.ps1"
        . "$here/Bottleneck.Performance.ps1"
        . "$here/Bottleneck.Network.ps1"
        . "$here/Bottleneck.Security.ps1"
        . "$here/Bottleneck.SystemPerformance.ps1"
        . "$here/Bottleneck.Remediation.ps1"  # for recommendations if needed
        & $CheckDispatcher -Group $Group -Config $Config -ReportsPath $ReportsPath
    }

    return Start-ThreadJob -ScriptBlock $bootstrap -ArgumentList @($Group, $Config, $ReportsPath, $CheckDispatcher) -ErrorAction SilentlyContinue
}

# Collect finished jobs and return pending list
function Receive-CheckJobs {
    param([Parameter(Mandatory)]$Jobs)

    $pending = New-Object List[object]
    foreach ($job in $Jobs) {
        if ($job.State -in 'Completed','Failed','Stopped') {
            try { Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null }
            finally { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
        }
        else {
            $pending.Add($job)
        }
    }
    return $pending
}

Export-ModuleMember -Function Invoke-BottleneckParallel, Get-ParallelCheckGroups, Invoke-BottleneckParallelChecks
