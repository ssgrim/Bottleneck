# Bottleneck.History.ps1
# Historical trend analysis and database storage

# History database path
$script:HistoryPath = 'c:\Users\mrred\git\Bottleneck\Reports\history'
$script:HistoryIndex = Join-Path $script:HistoryPath 'index.json'

function Initialize-HistoryDatabase {
    <#
    .SYNOPSIS
    Initialize the history database storage
    #>
    if (-not (Test-Path $script:HistoryPath)) {
        New-Item -ItemType Directory -Path $script:HistoryPath -Force | Out-Null
    }

    if (-not (Test-Path $script:HistoryIndex)) {
        $index = @{
            version = 1
            created = Get-Date -Format 'o'
            scans = @()
        }
        $index | ConvertTo-Json | Set-Content $script:HistoryIndex
    }
}

function Add-ScanToHistory {
    <#
    .SYNOPSIS
    Store scan results in history database
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Results,

        [Parameter(Mandatory)]
        [string]$Tier,

        [string]$ScanId = (New-Guid).ToString(),

        [hashtable]$Metadata = @{}
    )

    Initialize-HistoryDatabase

    $scanData = @{
        id = $ScanId
        timestamp = Get-Date -Format 'o'
        tier = $Tier
        results = $Results
        metadata = $Metadata
    }

    $scanFile = Join-Path $script:HistoryPath "$ScanId.json"
    $scanData | ConvertTo-Json -Depth 10 | Set-Content $scanFile

    # Update index
    $index = Get-Content $script:HistoryIndex | ConvertFrom-Json
    $index.scans += @{
        id = $ScanId
        timestamp = $scanData.timestamp
        tier = $Tier
        file = "$ScanId.json"
    }
    $index | ConvertTo-Json | Set-Content $script:HistoryIndex

    Write-Verbose "Scan $ScanId added to history"
}

function Get-HistoricalScans {
    <#
    .SYNOPSIS
    Retrieve historical scans with optional filters
    #>
    param(
        [int]$Limit = 10,
        [string]$Tier,
        [DateTime]$Since,
        [DateTime]$Until
    )

    if (-not (Test-Path $script:HistoryIndex)) {
        return @()
    }

    $index = Get-Content $script:HistoryIndex | ConvertFrom-Json
    $scans = $index.scans

    if ($Tier) {
        $scans = $scans | Where-Object { $_.tier -eq $Tier }
    }

    if ($Since) {
        $scans = $scans | Where-Object { [DateTime]::Parse($_.timestamp) -ge $Since }
    }

    if ($Until) {
        $scans = $scans | Where-Object { [DateTime]::Parse($_.timestamp) -le $Until }
    }

    $scans = $scans | Sort-Object timestamp -Descending | Select-Object -First $Limit

    $results = @()
    foreach ($scan in $scans) {
        $scanFile = Join-Path $script:HistoryPath $scan.file
        if (Test-Path $scanFile) {
            $data = Get-Content $scanFile | ConvertFrom-Json
            $results += $data
        }
    }

    return $results
}

function Get-HistoricalMetric {
    <#
    .SYNOPSIS
    Retrieve time series data for a specific metric
    #>
    param(
        [Parameter(Mandatory)]
        [string]$MetricName,

        [int]$Days = 30
    )

    $since = (Get-Date).AddDays(-$Days)
    $scans = Get-HistoricalScans -Since $since

    $series = @()
    foreach ($scan in $scans) {
        $metric = $scan.results | Where-Object { $_.Check -eq $MetricName } | Select-Object -First 1
        if ($metric) {
            $series += @{
                timestamp = $scan.timestamp
                value = $metric.Value
                status = $metric.Status
            }
        }
    }

    return $series
}

function Remove-OldHistory {
    <#
    .SYNOPSIS
    Clean up old history based on retention policy
    #>
    param(
        [int]$DaysToKeep = 90
    )

    if (-not (Test-Path $script:HistoryIndex)) {
        return
    }

    $cutoff = (Get-Date).AddDays(-$DaysToKeep)
    $index = Get-Content $script:HistoryIndex | ConvertFrom-Json

    $toRemove = $index.scans | Where-Object { [DateTime]::Parse($_.timestamp) -lt $cutoff }

    foreach ($scan in $toRemove) {
        $file = Join-Path $script:HistoryPath $scan.file
        if (Test-Path $file) {
            Remove-Item $file -Force
        }
    }

    $index.scans = $index.scans | Where-Object { [DateTime]::Parse($_.timestamp) -ge $cutoff }
    $index | ConvertTo-Json | Set-Content $script:HistoryIndex

    Write-Host "Removed $($toRemove.Count) old scans"
}

function Export-HistoryArchive {
    <#
    .SYNOPSIS
    Export history to a ZIP archive
    #>
    param(
        [string]$Path = (Join-Path $PSScriptRoot '..\..\Reports\bottleneck-history-$(Get-Date -Format yyyy-MM-dd).zip')
    )

    if (-not (Test-Path $script:HistoryPath)) {
        Write-Warning "No history to export"
        return
    }

    Compress-Archive -Path $script:HistoryPath -DestinationPath $Path -Force
    Write-Host "History exported to $Path"
}

function Import-HistoryArchive {
    <#
    .SYNOPSIS
    Import history from a ZIP archive
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "Archive not found: $Path"
        return
    }

    $tempPath = Join-Path $env:TEMP 'bottleneck-history-import'
    if (Test-Path $tempPath) {
        Remove-Item $tempPath -Recurse -Force
    }

    Expand-Archive -Path $Path -DestinationPath $tempPath

    # Merge index
    $importIndex = Join-Path $tempPath 'index.json'
    if (Test-Path $importIndex) {
        $importData = Get-Content $importIndex | ConvertFrom-Json
        Initialize-HistoryDatabase
        $currentIndex = Get-Content $script:HistoryIndex | ConvertFrom-Json

        foreach ($scan in $importData.scans) {
            if ($scan.id -notin $currentIndex.scans.id) {
                $currentIndex.scans += $scan
                Copy-Item (Join-Path $tempPath $scan.file) $script:HistoryPath
            }
        }

        $currentIndex | ConvertTo-Json | Set-Content $script:HistoryIndex
    }

    Remove-Item $tempPath -Recurse -Force
    Write-Host "History imported from $Path"
}

function Get-TrendAnalysis {
    <#
    .SYNOPSIS
    Analyze trends in historical data
    #>
    param(
        [Parameter(Mandatory)]
        [string]$MetricName,

        [int]$Days = 30
    )

    $series = Get-HistoricalMetric -MetricName $MetricName -Days $Days

    if ($series.Count -lt 2) {
        return @{ trend = 'insufficient-data'; change = 0; direction = 'stable' }
    }

    $first = $series | Select-Object -First 1
    $last = $series | Select-Object -Last 1

    $change = $last.value - $first.value
    $direction = if ($change -gt 0) { 'increasing' } elseif ($change -lt 0) { 'decreasing' } else { 'stable' }

    # Simple linear trend
    $trend = @{
        metric = $MetricName
        period_days = $Days
        data_points = $series.Count
        first_value = $first.value
        last_value = $last.value
        change = $change
        direction = $direction
        change_percent = if ($first.value -ne 0) { [math]::Round(($change / $first.value) * 100, 2) } else { 0 }
    }

    return $trend
}

function Export-HistoryForGrafana {
    <#
    .SYNOPSIS
    Export history data in Grafana-compatible format
    #>
    param(
        [string]$OutputPath = (Join-Path $script:HistoryPath 'grafana-export.json')
    )

    $scans = Get-HistoricalScans
    $metrics = @{}

    foreach ($scan in $scans) {
        foreach ($result in $scan.results) {
            if (-not $metrics.ContainsKey($result.Check)) {
                $metrics[$result.Check] = @()
            }
            $metrics[$result.Check] += @{
                timestamp = [DateTime]::Parse($scan.timestamp).ToUnixTimeMilliseconds()
                value = $result.Value
            }
        }
    }

    $grafanaData = @{
        metrics = $metrics
        metadata = @{
            exported = Get-Date -Format 'o'
            total_scans = $scans.Count
        }
    }

    $grafanaData | ConvertTo-Json -Depth 10 | Set-Content $OutputPath
    Write-Host "Exported Grafana data to $OutputPath"
}

function Export-HistoryForInfluxDB {
    <#
    .SYNOPSIS
    Export history data in InfluxDB line protocol format
    #>
    param(
        [string]$OutputPath = (Join-Path $script:HistoryPath 'influxdb-export.txt')
    )

    $scans = Get-HistoricalScans
    $lines = @()

    foreach ($scan in $scans) {
        $timestamp = [DateTime]::Parse($scan.timestamp).ToUnixTimeMilliseconds() * 1000000  # nanoseconds
        foreach ($result in $scan.results) {
            $line = "bottleneck,check=$($result.Check | ForEach-Object { $_ -replace '[^a-zA-Z0-9]', '_' }) value=$($result.Value)i $timestamp"
            $lines += $line
        }
    }

    $lines | Set-Content $OutputPath
    Write-Host "Exported InfluxDB data to $OutputPath"
}

function Get-HistoricalTrendReport {
    <#
    .SYNOPSIS
    Generate a trend report for historical scans
    #>
    param(
        [int]$Days = 30,
        [string]$OutputPath
    )

    $scans = Get-HistoricalScans -Since ((Get-Date).AddDays(-$Days))
    if ($scans.Count -lt 2) {
        return "Insufficient historical data for trend analysis (need at least 2 scans)"
    }

    $report = @"
Historical Trend Report
=======================
Period: Last $Days days
Total Scans: $($scans.Count)
Date Range: $(($scans | Sort-Object timestamp | Select-Object -First 1).timestamp) to $(($scans | Sort-Object timestamp | Select-Object -Last 1).timestamp)

Key Metrics Trends:
"@

    # Get unique checks
    $allChecks = $scans | ForEach-Object { $_.results.Check } | Sort-Object -Unique

    foreach ($check in $allChecks) {
        $trend = Get-TrendAnalysis -MetricName $check -Days $Days
        if ($trend.trend -ne 'insufficient-data') {
            $report += @"

$($check):
  Direction: $($trend.direction)
  Change: $($trend.change) ($($trend.change_percent)% over $($trend.data_points) data points)
  Current: $($trend.last_value)
"@
        }
    }

    if ($OutputPath) {
        $report | Set-Content $OutputPath
        Write-Host "Trend report saved to $OutputPath"
    }

    return $report
}