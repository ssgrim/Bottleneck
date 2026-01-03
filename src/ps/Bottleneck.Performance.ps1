# Bottleneck.Performance.ps1
# Performance optimization utilities

# CIM Query Cache
$script:CIMCache = @{}
$script:CacheTimeout = 300 # 5 minutes

function Get-CachedCimInstance {
    <#
    .SYNOPSIS
    Cached wrapper for Get-CimInstance to avoid redundant queries
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ClassName,

        [Parameter()]
        [string]$Namespace = "root\cimv2",

        [Parameter()]
        [switch]$Force
    )

    $key = "$Namespace\$ClassName"
    $now = Get-Date

    # Check if cached and not expired
    if ($script:CIMCache.ContainsKey($key) -and -not $Force) {
        $cached = $script:CIMCache[$key]
        if (($now - $cached.Timestamp).TotalSeconds -lt $script:CacheTimeout) {
            Write-Verbose "Using cached CIM data for $ClassName"
            return $cached.Data
        }
    }

    # Query and cache
    Write-Verbose "Querying CIM: $ClassName"
    try {
        $data = Get-CimInstance -ClassName $ClassName -Namespace $Namespace -ErrorAction Stop
        $script:CIMCache[$key] = @{
            Data = $data
            Timestamp = $now
        }
        return $data
    } catch {
        Write-Warning "Failed to query $ClassName : $_"
        return $null
    }
}

function Invoke-WithTimeout {
    <#
    .SYNOPSIS
    Execute scriptblock with timeout protection
    #>
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30,

        [Parameter()]
        [hashtable]$ArgumentList = @{}
    )

    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    $completed = Wait-Job $job -Timeout $TimeoutSeconds

    if ($completed) {
        $result = Receive-Job $job
        Remove-Job $job -Force
        return $result
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        throw "Operation timed out after $TimeoutSeconds seconds"
    }
}

function Clear-CIMCache {
    <#
    .SYNOPSIS
    Clear the CIM query cache
    #>
    $script:CIMCache.Clear()
    Write-Verbose "CIM cache cleared"
}

# Performance budget helper to flag slow checks/tier runs
function Test-PerformanceBudget {
    param(
        [Parameter(Mandatory)][string]$CheckName,
        [Parameter(Mandatory)][timespan]$ElapsedTime,
        [ValidateSet('Quick','Standard','Deep')][string]$Tier = 'Standard'
    )

    $budgets = @{
        'Quick'    = 30  # seconds total budget
        'Standard' = 45
        'Deep'     = 75
    }

    $budgetSeconds = $budgets[$Tier]
    $elapsed = [math]::Round($ElapsedTime.TotalSeconds,2)

    $result = [pscustomobject]@{
        CheckName      = $CheckName
        Tier           = $Tier
        ElapsedSeconds = $elapsed
        BudgetSeconds  = $budgetSeconds
        Exceeded       = $false
        Severity       = 'None'
    }

    if ($elapsed -gt ($budgetSeconds * 0.8)) {
        $result.Exceeded = $true
        $result.Severity = if ($elapsed -gt $budgetSeconds) { 'Critical' } else { 'Warning' }
        Write-Warning "⚠️  $CheckName took ${elapsed}s (budget ${budgetSeconds}s, tier $Tier)"
    }

    return $result
}
