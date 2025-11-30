# Bottleneck System Diagnostics

A comprehensive PowerShell-based system and network diagnostic toolkit for Windows, featuring intelligent monitoring, root cause analysis, and automated alerting.

## Features

### Phase 1 - Core Diagnostics (Current)

#### 🖥️ System Scanning
- **Unified Computer Scan**: Single command (`Invoke-BottleneckComputerScan`) runs 47+ comprehensive checks
- **Auto-elevation**: Automatically prompts for admin privileges when needed
- **Professional HTML Reports**: Clean, responsive reports with embedded CSS/JavaScript
- **Quick Mode**: Faster scan option for routine checks

#### 🌐 Network Monitoring
- **Long-Running Monitor**: Continuous network monitoring with duration presets (5min, 1hr, 4hr, etc.)
- **Graceful Shutdown**: Ctrl+C generates complete report before exit
- **Root Cause Analysis**: Statistical analysis identifies network bottlenecks
  - Quantile-based spike detection (P50/P95/P99)
  - IQR outlier identification
  - Jitter analysis (standard deviation)
  - Host comparison (best/worst performers)
  
#### 🛣️ MTR-Lite Path Quality Analysis
- **Per-Hop Tracking**: Aggregates latency and packet loss for each network hop
- **Traceroute Snapshots**: Periodic path tracing during monitoring
- **Path Quality Reports**: Identifies problematic intermediate routers
- **JSON Persistence**: Historical path quality data for trend analysis

#### ⚡ Speedtest Integration
- **Multiple Providers**: HTTP-based testing + Ookla CLI support
- **History Tracking**: Last 100 speedtest results with timestamps
- **Trend Display**: Shows percentage change from previous tests
- **Scheduler Support**: Automated bandwidth monitoring
- **Provider Selection**: Auto, Ookla, Fast.com, or HTTP fallback

#### 📊 Per-Process Network Analysis
- **Traffic Snapshot**: Captures active connections over configurable duration
- **Bandwidth Calculation**: Delta sampling for accurate throughput measurement
- **Top Talkers**: Identifies highest-bandwidth processes
- **Risky Port Detection**: Flags potentially suspicious connections (SMB, RDP, Telnet, etc.)

#### 📈 Metrics Export
- **JSON Format**: Structured data for API integration
- **Prometheus Format**: Plaintext metrics with HELP/TYPE annotations
- **Comprehensive Coverage**: System (CPU, memory, uptime), Disk (usage, free space), Network (latency, success rate), Path (worst hop stats), Speedtest (bandwidth, latency)
- **External Dashboards**: Easy integration with Grafana, Prometheus, custom tooling

#### 🚨 Threshold Alerting
- **Configurable Thresholds**: JSON-based alert configuration
- **Multi-Category**: Network, Path Quality, System, Disk monitoring
- **Toast Notifications**: Windows 10+ native notifications (BurntToast or fallback)
- **Alert Logging**: Persistent log in Reports/alerts.log
- **Severity Levels**: Critical and Warning alerts with actionable messages

#### 📅 Task Scheduler Integration
- **Automated Scans**: Schedule Computer/Network/Speedtest scans
- **Preset Schedules**: Nightly2AM, Daily, Weekly, OnIdle, or Custom
- **Retention Cleanup**: Configurable old report cleanup (default 30 days)
- **Easy Management**: Register/Get/Remove commands

### Network Probes (Advanced Diagnostics)
1. **Wi-Fi Quality**: Signal strength, channel, PHY type, radio status
2. **DNS Resolver Testing**: Response times for multiple DNS servers
3. **Adapter Error Detection**: Packet errors, discards, collisions
4. **MTU Path Discovery**: Identifies fragmentation issues
5. **ARP Health**: Stale entry detection, neighbor statistics

## Installation

1. Clone this repository
2. Import the module:
   ```powershell
   Import-Module 'C:\path\to\Bottleneck\bottleneck\src\ps\Bottleneck.psm1'
   ```

## Quick Start

### Computer Scan
```powershell
# Run comprehensive system diagnostics
Invoke-BottleneckComputerScan -AutoElevate

# Quick scan without network probes
Invoke-BottleneckComputerScan -Quick -SkipNetwork
```

### Network Monitoring
```powershell
# Run 1-hour network monitor with MTR-lite tracking
Invoke-BottleneckNetworkMonitor -Duration '1hour' -Interval 5 -TracerouteInterval 10

# Continuous monitoring until Ctrl+C
Invoke-BottleneckNetworkMonitor -Duration 'continuous' -Interval 2 -TracerouteInterval 15

# 5-minute quick check
Invoke-BottleneckNetworkMonitor -Duration '5min'
```

### Speedtest
```powershell
# Run speedtest with trend display
Invoke-BottleneckSpeedtest -ShowTrend

# Use specific provider
Invoke-BottleneckSpeedtest -Provider Ookla

# View history
Get-SpeedtestHistory | Select-Object -Last 5 | Format-Table
```

### Network Traffic Snapshot
```powershell
# Capture 10 seconds of network activity
Get-BottleneckNetworkTrafficSnapshot -DurationSeconds 10

# Longer sampling for bandwidth calculation
Get-BottleneckNetworkTrafficSnapshot -DurationSeconds 30
```

### Metrics Export
```powershell
# Export to JSON for API integration
Export-BottleneckMetrics -Format JSON

# Export to Prometheus format for scraping
Export-BottleneckMetrics -Format Prometheus
```

### Threshold Alerting
```powershell
# Check all thresholds with notifications
Test-BottleneckThresholds

# Log only (no toast notifications)
Test-BottleneckThresholds -LogOnly

# Create custom threshold configuration
New-AlertThresholdConfig -OutputPath '.\my-thresholds.json'
Test-BottleneckThresholds -ConfigPath '.\my-thresholds.json'
```

### Scheduled Scans
```powershell
# Schedule nightly speedtest at 2am
Register-BottleneckScheduledScan -ScanType Speedtest -Schedule Nightly2AM

# Schedule weekly network monitor (4-hour duration)
Register-BottleneckScheduledScan -ScanType Network -Schedule Weekly -NetworkDuration '4hours'

# Custom schedule: Daily at 6pm
Register-BottleneckScheduledScan -ScanType Computer -Schedule Custom -CustomTime '18:00'

# List all scheduled scans
Get-BottleneckScheduledScans

# Remove scheduled scan
Remove-BottleneckScheduledScan -ScanType Speedtest
```

## Architecture

### Module Structure
- **Bottleneck.psm1**: Main module loader and exports
- **Bottleneck.Check.ps1**: Core diagnostic functions
- **Bottleneck.Report.ps1**: HTML report generation with Path Quality, Speedtest Trend, Traffic Overview sections
- **Bottleneck.NetworkScan.ps1**: Quick network diagnostics
- **Bottleneck.NetworkDeep.ps1**: Root cause analysis and CSV diagnostics
- **Bottleneck.NetworkProbes.ps1**: Advanced network investigation tools
- **Bottleneck.NetworkMonitor.ps1**: Long-running monitor with MTR-lite, graceful shutdown
- **Bottleneck.ComputerScan.ps1**: Unified computer scan entry point
- **Bottleneck.Speedtest.ps1**: Bandwidth testing with history tracking
- **Bottleneck.Metrics.ps1**: Metrics export (JSON/Prometheus)
- **Bottleneck.Alerts.ps1**: Threshold-based alerting with notifications
- **Bottleneck.Scheduler.ps1**: Task scheduler integration
- **Bottleneck.Parallel.ps1**: Parallel check execution
- **Bottleneck.Elevation.ps1**: Privilege elevation handling
- **Bottleneck.Fix.ps1**: Automated remediation actions

### Report Locations
- **Workspace Reports**: `bottleneck/Reports/` (CSV, JSON, HTML, Prometheus metrics, alerts log)
- **User Documents**: `~/Documents/ScanReports/` (HTML reports for easy access)

### Persistence Layer
- **network-baseline.json**: Historical baseline for adaptive target selection
- **speedtest-history.json**: Last 100 speedtest results
- **path-quality-*.json**: Per-monitor traceroute aggregation
- **alerts.log**: Alert history with timestamps and severity
- **metrics-latest.json**: Latest metrics snapshot (JSON format)
- **metrics-latest.prom**: Latest metrics snapshot (Prometheus format)

## Configuration

### Alert Thresholds (Default)
```json
{
  "Network": {
    "MinSuccessRate": 99.5,
    "MaxP95Latency": 150
  },
  "PathQuality": {
    "MaxHopLoss": 3.0
  },
  "System": {
    "MaxCPU": 85,
    "MaxMemory": 90
  },
  "Disk": {
    "MaxUsage": 85
  }
}
```

### Prometheus Metrics
Exported metrics include:
- `bottleneck_cpu_usage_percent`: Current CPU usage
- `bottleneck_memory_usage_percent`: Current memory usage
- `bottleneck_disk_usage_percent`: Disk usage
- `bottleneck_network_success_rate`: Network reliability
- `bottleneck_network_latency_p95_ms`: 95th percentile latency
- `bottleneck_path_worst_hop_loss_percent`: Worst hop packet loss
- `bottleneck_speedtest_download_mbps`: Last speedtest download
- `bottleneck_speedtest_upload_mbps`: Last speedtest upload

## Roadmap

### Phase 2 (Upcoming)
- **Adaptive Analysis Engine**: Baseline drift detection, recurring issue identification, trend analysis
- **Anomaly Detection**: ML-based outlier detection for long-term patterns
- **Smart Target Selection**: Dynamic target rotation based on reliability scores
- **Interactive Charts**: Client-side charts in HTML reports (Chart.js integration)

### Phase 3 (Future)
- **What-If Simulation**: Predict impact of network/system changes
- **CLI/UX Polish**: Improved progress bars, color coding, interactive prompts
- **Export Formats**: PDF, CSV, Excel support
- **REST API**: Web service for remote monitoring

## Requirements
- PowerShell 7.0+
- Windows 10/11 or Windows Server 2016+
- Administrator privileges (optional, but recommended for complete diagnostics)

## Contributing
This project was developed through collaborative AI-assisted development. Contributions and feature requests are welcome!

## License
MIT License - See LICENSE file for details

## Version History
- **v1.0-phase1** (Current): Core diagnostics with MTR-lite, speedtest integration, per-process network analysis, metrics export, threshold alerting
- **v0.9**: Initial release with basic scanning and reporting
