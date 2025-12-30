# Grafana Dashboard Templates

This directory contains Grafana dashboard templates for visualizing Bottleneck diagnostic data.

## Available Dashboards

### 1. System Health Overview (`grafana-system-health.json`)
- **Purpose**: Real-time monitoring of core system components
- **Metrics**: CPU usage, memory usage, disk usage, network status
- **Features**:
  - Overall system health score gauge
  - Critical issues table
  - Time-series graphs for each component

### 2. Network Quality Dashboard (`grafana-network-quality.json`)
- **Purpose**: Comprehensive network performance monitoring
- **Metrics**: Latency, packet loss, download/upload speeds, DNS resolution
- **Features**:
  - Network quality score gauge
  - Connection drop statistics
  - Issue classification pie chart

### 3. Performance Trends (`grafana-trends.json`)
- **Purpose**: Long-term trend analysis and correlation studies
- **Metrics**: Multi-metric performance correlations, degradation alerts
- **Features**:
  - Scatter plots for component correlations
  - Heatmaps for performance patterns
  - Weekly/monthly trend analysis

## Setup Instructions

1. **Import Dashboards**:
   - Open Grafana and navigate to Dashboards → Import
   - Upload each JSON file or paste the JSON content
   - Configure the data source (InfluxDB or Prometheus)

2. **Data Source Configuration**:
   - The dashboards expect metrics with the prefix `bottleneck_`
   - Use the `Export-HistoryForGrafana` function from `Bottleneck.History.ps1` to export data
   - For InfluxDB, use `Export-HistoryForInfluxDB`

3. **Metric Mapping**:
   - `bottleneck_check_score{check="CPU"}` - CPU utilization percentage
   - `bottleneck_check_score{check="RAM"}` - Memory usage percentage
   - `bottleneck_check_score{check="Disk"}` - Disk usage percentage
   - `bottleneck_check_score{check="Network"}` - Network quality score
   - `bottleneck_network_latency` - Network latency in milliseconds
   - `bottleneck_packet_loss` - Packet loss percentage
   - `bottleneck_download_speed` - Download speed in Mbps
   - `bottleneck_upload_speed` - Upload speed in Mbps

## Usage

After importing the dashboards:

1. Set the time range (default: last 7 days for health/network, 30 days for trends)
2. Configure refresh intervals (5-15 minutes recommended)
3. Set up alerts for critical thresholds
4. Use the dashboards to identify performance bottlenecks and track improvements over time

## Customization

The dashboard templates can be customized by:
- Modifying panel queries to match your metric naming conventions
- Adding additional panels for custom metrics
- Adjusting thresholds and alert conditions
- Changing the dashboard layout and styling