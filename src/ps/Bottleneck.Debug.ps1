# Bottleneck.Debug.ps1
# Enterprise debugging and observability framework

$script:ScanId = $null
$script:DebugEnabled = $false
$script:VerboseEnabled = $false
$script:StructuredLogPath = $null
$script:PerformanceMetrics = @{}

<#
.SYNOPSIS
Initialize debugging session with trace ID

.DESCRIPTION
Creates new scan session with unique ID for log correlation.
Enables structured logging and performance tracking.

.PARAMETER Debug
Enable debug output

.PARAMETER Verbose
Enable verbose output

.PARAMETER StructuredLog
Enable structured JSON logging for Splunk/ELK

.EXAMPLE
Initialize-BottleneckDebug -Debug -StructuredLog
#>
function Initialize-BottleneckDebug {
    [CmdletBinding()]
    param(
        [switch]$EnableDebug,
        [switch]$EnableVerbose,
        [switch]$StructuredLog
    )

    # Generate unique scan ID
    $script:ScanId = [guid]::NewGuid().ToString()
    $script:DebugEnabled = $EnableDebug.IsPresent
    $script:VerboseEnabled = $EnableVerbose.IsPresent

    # Setup structured logging
    if ($StructuredLog) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $reportDir = Join-Path $PSScriptRoot "../../Reports/$(Get-Date -Format 'yyyy-MM-dd')"
        if (-not (Test-Path $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }
        $script:StructuredLogPath = Join-Path $reportDir "structured-$timestamp.jsonl"

        # Write initialization event
        Write-StructuredLog -Level "INFO" -Component "Debug" -Message "Debugging session initialized" -Data @{
            scanId = $script:ScanId
            debugEnabled = $script:DebugEnabled
            verboseEnabled = $script:VerboseEnabled
            psVersion = $PSVersionTable.PSVersion.ToString()
            hostname = $env:COMPUTERNAME
        }
    }

    Write-BottleneckDebug "Scan ID: $script:ScanId" -Component "Debug"

    return $script:ScanId
}

<#
.SYNOPSIS
Write debug message with component and trace ID

.DESCRIPTION
Writes formatted debug message with timestamp, component, and scan ID correlation.

.PARAMETER Message
Debug message text

.PARAMETER Component
Component name (NetworkMonitor, ComputerScan, etc.)

.PARAMETER Data
Additional structured data for JSON logging

.EXAMPLE
Write-BottleneckDebug "Starting ping loop" -Component "NetworkMonitor"
#>
function Write-BottleneckDebug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Component = "Core",

        [hashtable]$Data = @{}
    )

    if (-not $script:DebugEnabled -and -not $script:VerboseEnabled) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $scanIdShort = if ($script:ScanId) { $script:ScanId.Substring(0,8) } else { "--------" }

    $formatted = "[$timestamp] [DEBUG] [$scanIdShort] [$Component] $Message"

    if ($script:DebugEnabled) {
        Write-Host $formatted -ForegroundColor Cyan
    }

    # Structured log
    if ($script:StructuredLogPath) {
        Write-StructuredLog -Level "DEBUG" -Component $Component -Message $Message -Data $Data
    }
}

<#
.SYNOPSIS
Write verbose message with component and trace ID

.DESCRIPTION
Writes formatted verbose message for detailed operation tracking.

.PARAMETER Message
Verbose message text

.PARAMETER Component
Component name

.EXAMPLE
Write-BottleneckVerbose "Test-Connection returned 42ms" -Component "NetworkMonitor"
#>
function Write-BottleneckVerbose {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Component = "Core",

        [hashtable]$Data = @{}
    )

    if (-not $script:VerboseEnabled) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $scanIdShort = if ($script:ScanId) { $script:ScanId.Substring(0,8) } else { "--------" }

    $formatted = "[$timestamp] [VERBOSE] [$scanIdShort] [$Component] $Message"

    Write-Host $formatted -ForegroundColor Gray

    # Structured log
    if ($script:StructuredLogPath) {
        Write-StructuredLog -Level "VERBOSE" -Component $Component -Message $Message -Data $Data
    }
}

<#
.SYNOPSIS
Write performance metric

.DESCRIPTION
Records operation timing for performance analysis.

.PARAMETER Operation
Operation name (Test-Connection, TCP-Fallback, etc.)

.PARAMETER DurationMs
Duration in milliseconds

.PARAMETER Component
Component name

.EXAMPLE
Write-BottleneckPerformance -Operation "Test-Connection" -DurationMs 42
#>
function Write-BottleneckPerformance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [double]$DurationMs,

        [string]$Component = "Core"
    )

    # Aggregate metrics
    if (-not $script:PerformanceMetrics.ContainsKey($Operation)) {
        $script:PerformanceMetrics[$Operation] = @{
            Count = 0
            TotalMs = 0
            MinMs = [double]::MaxValue
            MaxMs = 0
            AvgMs = 0
        }
    }

    $metric = $script:PerformanceMetrics[$Operation]
    $metric.Count++
    $metric.TotalMs += $DurationMs
    $metric.MinMs = [math]::Min($metric.MinMs, $DurationMs)
    $metric.MaxMs = [math]::Max($metric.MaxMs, $DurationMs)
    $metric.AvgMs = [math]::Round($metric.TotalMs / $metric.Count, 2)

    Write-BottleneckVerbose "[$Operation] completed in $([math]::Round($DurationMs, 2))ms" -Component $Component -Data @{
        operation = $Operation
        durationMs = $DurationMs
    }
}

<#
.SYNOPSIS
Get performance summary

.DESCRIPTION
Returns aggregated performance metrics for all operations.

.EXAMPLE
Get-BottleneckPerformanceSummary
#>
function Get-BottleneckPerformanceSummary {
    [CmdletBinding()]
    param()

    return $script:PerformanceMetrics
}

<#
.SYNOPSIS
Write structured JSON log entry

.DESCRIPTION
Writes JSON-formatted log entry for ingestion by Splunk/ELK/CloudWatch.

.PARAMETER Level
Log level (DEBUG, INFO, WARNING, ERROR)

.PARAMETER Component
Component name

.PARAMETER Message
Log message

.PARAMETER Data
Additional structured data

.EXAMPLE
Write-StructuredLog -Level INFO -Component NetworkMonitor -Message "Ping successful" -Data @{latency=42}
#>
function Write-StructuredLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'VERBOSE', 'INFO', 'WARNING', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [string]$Message,

        [hashtable]$Data = @{}
    )

    if (-not $script:StructuredLogPath) {
        return
    }

    $entry = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        level = $Level
        component = $Component
        scanId = $script:ScanId
        hostname = $env:COMPUTERNAME
        message = $Message
    }

    # Merge additional data
    foreach ($key in $Data.Keys) {
        $entry[$key] = $Data[$key]
    }

    $json = $entry | ConvertTo-Json -Compress

    try {
        Add-Content -Path $script:StructuredLogPath -Value $json -ErrorAction SilentlyContinue
    } catch {
        # Fail silently - don't break scan due to logging issues
    }
}

<#
.SYNOPSIS
Measure operation execution time

.DESCRIPTION
Wrapper for Measure-Command that logs performance metrics.

.PARAMETER ScriptBlock
Code to measure

.PARAMETER Operation
Operation name for metrics

.PARAMETER Component
Component name

.EXAMPLE
Invoke-WithPerformanceTracking -Operation "Ping" -ScriptBlock { Test-Connection yahoo.com }
#>
function Invoke-WithPerformanceTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory)]
        [string]$Operation,

        [string]$Component = "Core"
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $result = & $ScriptBlock
        return $result
    } finally {
        $timer.Stop()
        Write-BottleneckPerformance -Operation $Operation -DurationMs $timer.Elapsed.TotalMilliseconds -Component $Component
    }
}

<#
.SYNOPSIS
Write performance summary to console

.DESCRIPTION
Displays formatted performance metrics summary.

.EXAMPLE
Show-BottleneckPerformanceSummary
#>
function Show-BottleneckPerformanceSummary {
    [CmdletBinding()]
    param()

    if ($script:PerformanceMetrics.Count -eq 0) {
        Write-Host "`nNo performance metrics collected" -ForegroundColor Yellow
        return
    }

    Write-Host "`n" -NoNewline
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║" -NoNewline -ForegroundColor Cyan
    Write-Host "              PERFORMANCE METRICS SUMMARY                       " -NoNewline -ForegroundColor White
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-Host ("{0,-30} {1,8} {2,10} {3,10} {4,10}" -f "Operation", "Count", "Avg (ms)", "Min (ms)", "Max (ms)") -ForegroundColor Yellow
    Write-Host ("{0,-30} {1,8} {2,10} {3,10} {4,10}" -f ("-" * 30), ("-" * 8), ("-" * 10), ("-" * 10), ("-" * 10)) -ForegroundColor DarkGray

    foreach ($op in ($script:PerformanceMetrics.Keys | Sort-Object)) {
        $metric = $script:PerformanceMetrics[$op]
        Write-Host ("{0,-30} {1,8} {2,10:F2} {3,10:F2} {4,10:F2}" -f `
            $op, `
            $metric.Count, `
            $metric.AvgMs, `
            $metric.MinMs, `
            $metric.MaxMs) -ForegroundColor White
    }

    Write-Host ""
}

<#
.SYNOPSIS
Get current scan ID

.DESCRIPTION
Returns the current scan session ID for external correlation.

.EXAMPLE
$scanId = Get-BottleneckScanId
#>
function Get-BottleneckScanId {
    return $script:ScanId
}

<#
.SYNOPSIS
Export performance metrics to JSON

.DESCRIPTION
Saves performance metrics to JSON file for analysis.

.PARAMETER Path
Output file path

.EXAMPLE
Export-BottleneckPerformanceMetrics -Path "Reports/2025-12-02/performance.json"
#>
function Export-BottleneckPerformanceMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $summary = @{
        scanId = $script:ScanId
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        hostname = $env:COMPUTERNAME
        metrics = $script:PerformanceMetrics
    }

    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $Path

    Write-BottleneckDebug "Performance metrics exported to: $Path" -Component "Debug"
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-BottleneckDebug',
    'Write-BottleneckDebug',
    'Write-BottleneckVerbose',
    'Write-BottleneckPerformance',
    'Get-BottleneckPerformanceSummary',
    'Write-StructuredLog',
    'Invoke-WithPerformanceTracking',
    'Show-BottleneckPerformanceSummary',
    'Get-BottleneckScanId',
    'Export-BottleneckPerformanceMetrics'
)
