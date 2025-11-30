# Bottleneck.Metrics.ps1
# Metrics export for external monitoring dashboards

function Export-BottleneckMetrics {
    <#
    .SYNOPSIS
    Exports current system and network metrics in JSON or Prometheus format.
    
    .DESCRIPTION
    Collects and exports key performance metrics for consumption by external
    monitoring systems like Prometheus, Grafana, or custom dashboards.
    
    .PARAMETER Format
    Output format: 'JSON' or 'Prometheus'.
    
    .PARAMETER OutputPath
    File path for JSON export (default: Reports/metrics-latest.json).
    
    .PARAMETER IncludeHistory
    Include historical speedtest and network monitor data in JSON export.
    
    .EXAMPLE
    Export-BottleneckMetrics -Format JSON
    
    .EXAMPLE
    Export-BottleneckMetrics -Format Prometheus -OutputPath 'C:\metrics\bottleneck.prom'
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('JSON','Prometheus')]
        [string]$Format = 'JSON',
        
        [string]$OutputPath,
        
        [switch]$IncludeHistory
    )
    
    $reportsDir = Join-Path $PSScriptRoot '..' '..' 'Reports'
    if (-not $OutputPath) {
        $ext = if ($Format -eq 'JSON') { 'json' } else { 'prom' }
        $OutputPath = Join-Path $reportsDir "metrics-latest.$ext"
    }
    
    # Gather current metrics
    $metrics = Get-CurrentMetrics
    
    # Add history if requested
    if ($IncludeHistory -and $Format -eq 'JSON') {
        try {
            $speedFile = Join-Path $reportsDir 'speedtest-history.json'
            if (Test-Path $speedFile) {
                $metrics.SpeedtestHistory = (Get-Content $speedFile | ConvertFrom-Json) | Select-Object -Last 10
            }
            
            $baselineFile = Join-Path $reportsDir 'network-baseline.json'
            if (Test-Path $baselineFile) {
                $metrics.NetworkBaseline = Get-Content $baselineFile | ConvertFrom-Json
            }
        } catch {}
    }
    
    # Export in requested format
    switch ($Format) {
        'JSON' {
            $metrics | ConvertTo-Json -Depth 10 | Set-Content $OutputPath
            Write-Host "✓ Metrics exported to: $OutputPath" -ForegroundColor Green
        }
        'Prometheus' {
            $promText = ConvertTo-PrometheusFormat -Metrics $metrics
            $promText | Set-Content $OutputPath
            Write-Host "✓ Prometheus metrics exported to: $OutputPath" -ForegroundColor Green
        }
    }
    
    return $OutputPath
}

function Get-CurrentMetrics {
    $metrics = @{
        Timestamp = (Get-Date).ToString('o')
        Hostname = $env:COMPUTERNAME
    }
    
    # System metrics
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $memory = Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum
        
        $metrics.System = @{
            CPUUsagePercent = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue;
            MemoryUsedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2);
            MemoryTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2);
            MemoryUsagePercent = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1);
            UptimeHours = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1);
        }
    } catch {
        Write-Verbose "Could not gather system metrics: $_"
    }
    
    # Disk metrics
    try {
        $disk = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | Select-Object -First 1
        if ($disk) {
            $metrics.Disk = @{
                FreeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2);
                TotalSpaceGB = [math]::Round($disk.Size / 1GB, 2);
                UsagePercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1);
            }
        }
    } catch {}
    
    # Network metrics (latest from monitor or baseline)
    try {
        $reportsDir = Join-Path $PSScriptRoot '..' '..' 'Reports'
        $baselineFile = Join-Path $reportsDir 'network-baseline.json'
        if (Test-Path $baselineFile) {
            $baseline = Get-Content $baselineFile | ConvertFrom-Json
            $metrics.Network = @{
                SuccessRatePercent = $baseline.SuccessRate;
                AvgLatencyMs = $baseline.AvgLatency;
                P95LatencyMs = $baseline.P95Latency;
                LikelyCause = $baseline.LikelyCause;
                LastUpdated = $baseline.LastUpdated;
            }
        }
        
        # Path quality (latest)
        $pqFile = Get-ChildItem $reportsDir -Filter 'path-quality-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($pqFile) {
            $pq = Get-Content $pqFile.FullName | ConvertFrom-Json
            $worstHop = $pq.Hops | Sort-Object @{Expression='LossPct';Descending=$true}, @{Expression='P95Ms';Descending=$true} | Select-Object -First 1
            $metrics.PathQuality = @{
                        WorstHopIP = $worstHop.IP;
                        WorstHopLossPercent = $worstHop.LossPct;
                        WorstHopP95Ms = $worstHop.P95Ms;
                        TracerouteRuns = $pq.Runs;
            }
        }
    } catch {}
    
    # Speedtest metrics (latest)
    try {
        $speedFile = Join-Path $reportsDir 'speedtest-history.json'
        if (Test-Path $speedFile) {
            $latest = (Get-Content $speedFile | ConvertFrom-Json) | Select-Object -Last 1
            $metrics.Speedtest = @{
                            DownloadMbps = $latest.DownMbps;
                            UploadMbps = $latest.UpMbps;
                            LatencyMs = $latest.LatencyMs;
                            JitterMs = $latest.JitterMs;
                            Provider = $latest.Provider;
                            Timestamp = $latest.Timestamp;
            }
        }
    } catch {}
    
    return $metrics
}

function ConvertTo-PrometheusFormat {
    param($Metrics)
    
    $output = @()
    $output += "# HELP bottleneck_info Bottleneck scanner metadata"
    $output += "# TYPE bottleneck_info gauge"
    $output += "bottleneck_info{hostname=`"$($Metrics.Hostname)`"} 1"
    $output += ""
    
    if ($Metrics.System) {
        $output += "# HELP bottleneck_cpu_usage_percent Current CPU usage percentage"
        $output += "# TYPE bottleneck_cpu_usage_percent gauge"
        $output += "bottleneck_cpu_usage_percent $($Metrics.System.CPUUsagePercent)"
        $output += ""
        
        $output += "# HELP bottleneck_memory_usage_percent Current memory usage percentage"
        $output += "# TYPE bottleneck_memory_usage_percent gauge"
        $output += "bottleneck_memory_usage_percent $($Metrics.System.MemoryUsagePercent)"
        $output += ""
        
        $output += "# HELP bottleneck_memory_used_gb Memory used in gigabytes"
        $output += "# TYPE bottleneck_memory_used_gb gauge"
        $output += "bottleneck_memory_used_gb $($Metrics.System.MemoryUsedGB)"
        $output += ""
        
        $output += "# HELP bottleneck_uptime_hours System uptime in hours"
        $output += "# TYPE bottleneck_uptime_hours counter"
        $output += "bottleneck_uptime_hours $($Metrics.System.UptimeHours)"
        $output += ""
    }
    
    if ($Metrics.Disk) {
        $output += "# HELP bottleneck_disk_usage_percent Disk usage percentage"
        $output += "# TYPE bottleneck_disk_usage_percent gauge"
        $output += "bottleneck_disk_usage_percent $($Metrics.Disk.UsagePercent)"
        $output += ""
        
        $output += "# HELP bottleneck_disk_free_gb Free disk space in gigabytes"
        $output += "# TYPE bottleneck_disk_free_gb gauge"
        $output += "bottleneck_disk_free_gb $($Metrics.Disk.FreeSpaceGB)"
        $output += ""
    }
    
    if ($Metrics.Network) {
        $output += "# HELP bottleneck_network_success_rate Network success rate percentage"
        $output += "# TYPE bottleneck_network_success_rate gauge"
        $output += "bottleneck_network_success_rate $($Metrics.Network.SuccessRatePercent)"
        $output += ""
        
        $output += "# HELP bottleneck_network_latency_avg_ms Average network latency in milliseconds"
        $output += "# TYPE bottleneck_network_latency_avg_ms gauge"
        $output += "bottleneck_network_latency_avg_ms $($Metrics.Network.AvgLatencyMs)"
        $output += ""
        
        $output += "# HELP bottleneck_network_latency_p95_ms P95 network latency in milliseconds"
        $output += "# TYPE bottleneck_network_latency_p95_ms gauge"
        $output += "bottleneck_network_latency_p95_ms $($Metrics.Network.P95LatencyMs)"
        $output += ""
    }
    
    if ($Metrics.PathQuality) {
        $output += "# HELP bottleneck_path_worst_hop_loss_percent Worst hop packet loss percentage"
        $output += "# TYPE bottleneck_path_worst_hop_loss_percent gauge"
        $output += "bottleneck_path_worst_hop_loss_percent{ip=`"$($Metrics.PathQuality.WorstHopIP)`"} $($Metrics.PathQuality.WorstHopLossPercent)"
        $output += ""
        
        $output += "# HELP bottleneck_path_worst_hop_p95_ms Worst hop P95 latency in milliseconds"
        $output += "# TYPE bottleneck_path_worst_hop_p95_ms gauge"
        $output += "bottleneck_path_worst_hop_p95_ms{ip=`"$($Metrics.PathQuality.WorstHopIP)`"} $($Metrics.PathQuality.WorstHopP95Ms)"
        $output += ""
    }
    
    if ($Metrics.Speedtest) {
        $output += "# HELP bottleneck_speedtest_download_mbps Download speed in Mbps"
        $output += "# TYPE bottleneck_speedtest_download_mbps gauge"
        $output += "bottleneck_speedtest_download_mbps $($Metrics.Speedtest.DownloadMbps)"
        $output += ""
        
        $output += "# HELP bottleneck_speedtest_upload_mbps Upload speed in Mbps"
        $output += "# TYPE bottleneck_speedtest_upload_mbps gauge"
        $output += "bottleneck_speedtest_upload_mbps $($Metrics.Speedtest.UploadMbps)"
        $output += ""
        
        $output += "# HELP bottleneck_speedtest_latency_ms Speedtest base latency in milliseconds"
        $output += "# TYPE bottleneck_speedtest_latency_ms gauge"
        $output += "bottleneck_speedtest_latency_ms $($Metrics.Speedtest.LatencyMs)"
        $output += ""
    }
    
    return ($output -join "`n")
}

