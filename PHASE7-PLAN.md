# Phase 7: Historical Trend Analysis & Dashboard Integration

**Target Branch**: `phase7-trends-dashboards`
**Status**: 📋 Planning
**Priority**: High
**Estimated Timeline**: 2-3 weeks
**Dependencies**: Phase 1 (Complete), Phase 6 (Advanced Alerts - Complete)

---

## 🎯 Phase Goals

Phase 7 focuses on **long-term trend analysis** and **dashboard integration** to transform Bottleneck from a point-in-time diagnostic tool into a comprehensive performance tracking platform. This phase enables:

1. **Historical Performance Tracking**: Store and analyze scan results over days, weeks, and months
2. **Trend Detection**: Identify gradual performance degradation before it becomes critical
3. **Comparative Analysis**: Compare current state against historical baselines
4. **Dashboard Integration**: Export data in formats optimized for Grafana, InfluxDB, and other monitoring platforms
5. **Regression Analysis**: Detect if recent changes improved or worsened system performance

---

## 📋 Feature Breakdown

### 1. Historical Database System ⭐ HIGH PRIORITY

**Goal**: Create a lightweight, efficient storage system for scan history without external database dependencies.

**Implementation Details**:

**File**: `src/ps/Bottleneck.History.ps1`

```powershell
# Core Functions:
- Initialize-HistoryDatabase      # Create SQLite or JSON-based storage
- Add-ScanToHistory              # Store scan results with metadata
- Get-HistoricalScans            # Query past scans with filters
- Get-HistoricalMetric           # Retrieve specific metric time series
- Remove-OldHistory              # Cleanup based on retention policy
- Export-HistoryArchive          # Backup history to ZIP
- Import-HistoryArchive          # Restore from backup
```

**Storage Options**:

- **Option A**: SQLite database (preferred for query performance)

  - File: `Reports/bottleneck-history.db`
  - Tables: scans, metrics, checks, network_drops, speedtests
  - Requires: .NET System.Data.SQLite or PowerShell SQLite module

- **Option B**: JSON file per scan (simpler, no dependencies)
  - Directory: `Reports/history/YYYY/MM/`
  - Files: `scan-YYYY-MM-DD_HH-mm-ss.json`
  - Index: `Reports/history/index.json` (metadata cache)

**Database Schema** (SQLite approach):

```sql
CREATE TABLE scans (
    scan_id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    hostname TEXT NOT NULL,
    profile TEXT NOT NULL,
    scan_type TEXT NOT NULL,  -- 'computer', 'network', 'combined'
    duration_seconds INTEGER,
    check_count INTEGER,
    critical_count INTEGER,
    high_count INTEGER,
    medium_count INTEGER,
    low_count INTEGER
);

CREATE TABLE metrics (
    metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_id TEXT NOT NULL,
    metric_name TEXT NOT NULL,
    metric_value REAL,
    metric_unit TEXT,
    FOREIGN KEY (scan_id) REFERENCES scans(scan_id)
);

CREATE TABLE checks (
    check_id INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_id TEXT NOT NULL,
    check_name TEXT NOT NULL,
    severity TEXT,
    impact INTEGER,
    confidence INTEGER,
    score REAL,
    message TEXT,
    FOREIGN KEY (scan_id) REFERENCES scans(scan_id)
);

CREATE TABLE network_drops (
    drop_id INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_id TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    classification TEXT,  -- WLAN, WAN, DNS, Unknown
    duration_seconds INTEGER,
    signal_strength INTEGER,
    FOREIGN KEY (scan_id) REFERENCES scans(scan_id)
);

CREATE TABLE speedtests (
    test_id INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_id TEXT,
    timestamp TEXT NOT NULL,
    download_mbps REAL,
    upload_mbps REAL,
    latency_ms REAL,
    jitter_ms REAL,
    provider TEXT
);

CREATE INDEX idx_scans_timestamp ON scans(timestamp);
CREATE INDEX idx_metrics_scan ON metrics(scan_id);
CREATE INDEX idx_metrics_name ON metrics(metric_name);
CREATE INDEX idx_checks_scan ON checks(scan_id);
```

**Retention Policy**:

- Keep all scans for 30 days (configurable)
- After 30 days, aggregate to daily summaries
- After 180 days, aggregate to weekly summaries
- After 365 days, keep monthly summaries only

**Configuration** (`config/history.json`):

```json
{
  "enabled": true,
  "storageType": "sqlite", // or "json"
  "retentionDays": 30,
  "aggregateDaily": 180,
  "aggregateWeekly": 365,
  "maxSizeGB": 1.0,
  "autoCleanup": true
}
```

---

### 2. Trend Analysis Engine ⭐ HIGH PRIORITY

**Goal**: Detect performance trends and identify degradation patterns automatically.

**File**: `src/ps/Bottleneck.Trends.ps1`

**Core Functions**:

```powershell
# Trend Detection
Get-PerformanceTrend           # Calculate linear regression for metric
Get-MetricBaseline             # Calculate normal range from history
Test-PerformanceRegression     # Detect if current value is outlier
Get-TrendingIssues            # Identify worsening problems over time

# Statistical Analysis
Get-MetricStatistics          # Calculate mean, median, stddev, percentiles
Get-ChangePointDetection      # Identify sudden shifts in metric behavior
Get-SeasonalPattern           # Detect daily/weekly patterns (e.g., busy hours)

# Comparative Analysis
Compare-ScansOverTime         # Compare current scan vs. historical average
Get-ImprovementScore          # Calculate % improvement since last week/month
Get-DegradationAlert          # Warn about metrics trending worse
```

**Trend Metrics to Track**:

**System Performance**:

- CPU usage (avg, P95, peak)
- Memory usage (avg, P95, leak indicators)
- Disk usage (free space trend, growth rate)
- Boot time (startup performance degradation)
- Process count (bloat detection)

**Network Performance**:

- Drop rate per hour (rolling average)
- Latency (avg, P95, jitter)
- Packet loss percentage
- DNS resolution time
- Bandwidth (if speedtest enabled)

**Reliability Metrics**:

- Critical issue frequency
- Service failure rate
- Error event log growth rate
- SMART attribute degradation

**Trend Classification**:

- **Improving**: Metric getting better over time (green)
- **Stable**: No significant change (gray)
- **Degrading Slowly**: Gradual decline, not yet critical (yellow)
- **Degrading Rapidly**: Accelerating decline, attention needed (orange)
- **Critical Trend**: On path to failure within 7-30 days (red)

**Example Trend Calculations**:

```powershell
# Linear regression for CPU usage over last 30 days
$trend = Get-PerformanceTrend -MetricName "cpu_usage_percent" -Days 30
# Returns: @{
#   Slope = 0.25,          # Increasing 0.25% per day
#   Intercept = 45.5,
#   R2 = 0.78,             # Strong correlation
#   Prediction7Days = 47.25,
#   Prediction30Days = 53.0,
#   Classification = "DegradingSlowly"
# }

# Change point detection
$changePoint = Get-ChangePointDetection -MetricName "memory_usage_percent" -Days 60
# Returns: @{
#   ChangeDetected = $true,
#   ChangeDate = "2025-12-15T14:30:00Z",
#   BeforeMean = 62.3,
#   AfterMean = 78.5,
#   PercentChange = 25.9,
#   Reason = "Software update or new application installed"
# }
```

---

### 3. Enhanced HTML Reports with Trends ⭐ HIGH PRIORITY

**Goal**: Add visual trend indicators and historical comparisons to HTML reports.

**File**: `src/ps/Bottleneck.EnhancedReport.ps1` (modify existing)

**New Report Sections**:

**A. Performance Trend Dashboard**

- Display key metrics with 7-day and 30-day trends
- Visual indicators: ↑ (improving), → (stable), ↓ (degrading)
- Sparkline charts showing metric history
- Color-coded based on trend severity

**B. Historical Comparison Panel**

```
Current Scan vs. Last Week:
✅ CPU Usage:      65% → 58% (↓ 10.8% improvement)
⚠️  Memory Usage:   72% → 78% (↑ 8.3% worse)
✅ Boot Time:      45s → 38s (↓ 15.6% faster)
→  Disk Space:     120GB free (no change)
```

**C. Long-term Health Score**

- Overall system health: 0-100 score
- Trend over last 30 days
- Projection: "At current trend, system health will reach 'Poor' in 45 days"

**D. Chart Integration** (using Chart.js):

```html
<!-- CPU Usage - Last 30 Days -->
<canvas id="cpuTrendChart" width="400" height="200"></canvas>
<script>
  const ctx = document.getElementById("cpuTrendChart").getContext("2d");
  new Chart(ctx, {
    type: "line",
    data: {
      labels: [
        /* dates from history */
      ],
      datasets: [
        {
          label: "CPU Usage %",
          data: [
            /* values from history */
          ],
          borderColor: "rgb(75, 192, 192)",
          tension: 0.1,
        },
      ],
    },
  });
</script>
```

**Chart Types to Add**:

1. Line charts for time series (CPU, memory, disk over time)
2. Bar charts for categorical data (drop classification distribution)
3. Pie charts for composition (disk usage by drive)
4. Scatter plots for correlation (CPU temp vs. usage)
5. Heatmaps for patterns (network drops by hour/day)

**Report Footer Enhancement**:

```
Historical Data:
- First scan: 2025-11-15 (43 days ago)
- Total scans: 127
- Average scan interval: 8.2 hours
- Data retention: 30 days (rolling)
```

---

### 4. Grafana Integration ⭐ MEDIUM PRIORITY

**Goal**: Enable seamless integration with Grafana dashboards for real-time monitoring.

**File**: `src/ps/Bottleneck.Integrations.Grafana.ps1`

**Components**:

**A. Enhanced Prometheus Export**

- Expand existing `Bottleneck.Metrics.ps1` with additional metrics
- Add metric metadata (descriptions, units, types)
- Support for custom labels (hostname, profile, environment)

**Example Prometheus Output**:

```prometheus
# HELP bottleneck_scan_duration_seconds Time taken to complete scan
# TYPE bottleneck_scan_duration_seconds gauge
bottleneck_scan_duration_seconds{profile="standard",type="computer"} 51.2

# HELP bottleneck_check_score Individual check score
# TYPE bottleneck_check_score gauge
bottleneck_check_score{check="CPU_High",severity="Medium"} 45.6
bottleneck_check_score{check="Memory_High",severity="High"} 72.3

# HELP bottleneck_network_drop_rate Network drops per hour
# TYPE bottleneck_network_drop_rate gauge
bottleneck_network_drop_rate{classification="wan"} 0.75
bottleneck_network_drop_rate{classification="wlan"} 0.0

# HELP bottleneck_disk_free_bytes Free disk space in bytes
# TYPE bottleneck_disk_free_bytes gauge
bottleneck_disk_free_bytes{drive="C"} 128849018880
bottleneck_disk_free_bytes{drive="D"} 512000000000
```

**B. Grafana Dashboard Templates**

Create pre-built JSON dashboards:

1. **System Health Overview** (`dashboards/grafana-system-health.json`)

   - Panels: CPU, Memory, Disk, Network status
   - Gauges for current values
   - Graphs for trends over time
   - Alert indicators

2. **Network Quality Dashboard** (`dashboards/grafana-network-quality.json`)

   - Latency graph (avg, P95)
   - Drop classification pie chart
   - Signal strength heatmap
   - Speedtest results over time
   - Path quality per hop

3. **Performance Trends** (`dashboards/grafana-trends.json`)
   - Multi-metric comparison over 7/30/90 days
   - Regression indicators
   - Anomaly highlighting
   - Correlation matrices

**C. Direct Grafana API Integration**

```powershell
# Functions for direct Grafana communication
Send-ToGrafana              # Push metrics via HTTP API
Register-GrafanaDataSource  # Auto-configure Prometheus data source
Import-GrafanaDashboard     # Upload dashboard JSON
Create-GrafanaAlert         # Configure alerting rules
```

**Configuration** (`config/grafana.json`):

```json
{
  "enabled": false,
  "grafanaUrl": "http://localhost:3000",
  "apiKey": "",
  "prometheusUrl": "http://localhost:9090",
  "pushMetrics": false,
  "uploadDashboards": false,
  "defaultDashboards": [
    "dashboards/grafana-system-health.json",
    "dashboards/grafana-network-quality.json"
  ]
}
```

---

### 5. InfluxDB Integration ⭐ MEDIUM PRIORITY

**Goal**: Support time-series database storage for high-frequency monitoring and advanced analytics.

**File**: `src/ps/Bottleneck.Integrations.InfluxDB.ps1`

**Core Functions**:

```powershell
# InfluxDB v2 API
Initialize-InfluxDBConnection   # Setup connection and verify
Write-MetricsToInfluxDB        # Batch write metrics
Query-InfluxDBMetrics          # Retrieve historical data
Create-InfluxDBBucket          # Setup storage bucket
Create-InfluxDBTask            # Schedule automated queries
```

**Line Protocol Export**:

```
# Measurement: bottleneck_system
bottleneck_system,host=DESKTOP-ABC123,profile=standard cpu_percent=65.3,memory_percent=72.1,disk_percent=45.2 1735401234000000000

# Measurement: bottleneck_network
bottleneck_network,host=DESKTOP-ABC123,adapter=WiFi latency_ms=23.5,packet_loss=0.0,signal_strength=91 1735401234000000000

# Measurement: bottleneck_check
bottleneck_check,host=DESKTOP-ABC123,check_id=CPU_High,severity=Medium score=45.6,impact=6,confidence=8 1735401234000000000
```

**Benefits of InfluxDB**:

- High-frequency data collection (every 5 seconds if needed)
- Advanced querying with Flux language
- Built-in downsampling and retention policies
- Native Grafana integration
- Handles millions of data points efficiently

**Configuration** (`config/influxdb.json`):

```json
{
  "enabled": false,
  "url": "http://localhost:8086",
  "token": "",
  "org": "bottleneck",
  "bucket": "system-diagnostics",
  "measurement": "bottleneck",
  "batchSize": 1000,
  "flushInterval": 10
}
```

---

### 6. Automated Report Comparison ⭐ MEDIUM PRIORITY

**Goal**: Generate side-by-side comparisons of scans to track changes over time.

**File**: `src/ps/Bottleneck.Comparison.ps1`

**Core Functions**:

```powershell
# Comparison Engine
Compare-TwoScans           # Detailed diff between two specific scans
Compare-AgainstBaseline    # Compare current vs. "known good" baseline
Generate-ComparisonReport  # HTML report showing differences
Set-PerformanceBaseline    # Mark current scan as baseline
Get-AvailableBaselines     # List saved baselines
```

**Comparison Features**:

**A. Metric Changes**

- Show delta for all numeric metrics
- Highlight improvements (green) and regressions (red)
- Calculate percentage change
- Flag significant changes (>10% threshold)

**B. Check Differences**

- New issues that appeared
- Issues that were resolved
- Issues that got worse/better
- Unchanged issues

**C. Visual Diff Display**

```
┌─────────────────────────────────────────────────────┐
│ Comparison: 2025-12-27 vs 2025-12-20               │
├─────────────────────────────────────────────────────┤
│ Metric              │ Before  │ After   │ Change   │
├─────────────────────┼─────────┼─────────┼──────────┤
│ CPU Usage           │ 68.2%   │ 58.5%   │ ↓ -14.2% │
│ Memory Usage        │ 71.3%   │ 78.9%   │ ↑ +10.7% │
│ Disk Free (C:)      │ 125 GB  │ 118 GB  │ ↓ -5.6%  │
│ Network Drops/hr    │ 0.75    │ 0.0     │ ↓ -100%  │
│ Boot Time           │ 52s     │ 45s     │ ↓ -13.5% │
└─────────────────────────────────────────────────────┘

New Issues (3):
❌ Disk_LowSpace_D: D: drive below 10% free space
❌ Service_Stopped_WSearch: Windows Search service not running
⚠️  Startup_TooMany: 18 startup programs (recommended: <10)

Resolved Issues (2):
✅ CPU_HighUsage: CPU usage returned to normal
✅ Memory_Leak_Chrome: Chrome memory usage improved
```

**Export Formats**:

- HTML (interactive, with charts)
- Markdown (for documentation/tickets)
- JSON (machine-readable)
- CSV (for spreadsheet analysis)

---

### 7. Regression Detection & Alerting ⭐ MEDIUM PRIORITY

**Goal**: Automatically detect when recent changes (updates, installations) caused performance regression.

**File**: `src/ps/Bottleneck.Regression.ps1`

**Core Functions**:

```powershell
# Regression Detection
Test-PerformanceRegression        # Check if current scan shows regression
Get-RegressionCandidates          # List recent system changes (updates, installs)
Correlate-ChangesWithRegression   # Link performance drop to likely cause
Generate-RegressionReport         # Detailed analysis of regression
Set-PreChangeBaseline             # Capture state before planned change
Compare-PostChange                # Compare current state vs. pre-change baseline
```

**Regression Indicators**:

1. **Metric-based**:

   - Any metric 15%+ worse than 7-day average
   - Multiple metrics declining simultaneously
   - Metric exceeds 2 standard deviations from mean

2. **Check-based**:

   - New Critical/High severity issues
   - Increase in total issue count
   - Worsening of existing issues

3. **Event-based**:
   - Correlation with Windows Update
   - Recent software installation
   - Driver updates
   - Configuration changes

**Regression Report Example**:

```markdown
🔴 Performance Regression Detected

Detected: 2025-12-28 10:30:00
Severity: HIGH
Confidence: 87%

Affected Metrics:

- Boot Time: 38s → 67s (+76% slower)
- Memory Usage: 62% → 81% (+30% increase)
- Startup Program Count: 12 → 18 (+50% more)

Likely Cause:
Windows Update KB5034123 installed on 2025-12-27 23:15:00

Correlation Evidence:
✅ Timing matches (regression detected 11 hours after update)
✅ Similar issues reported by other users (GitHub community)
✅ Event log shows new service startup failures after update

Recommended Actions:

1. Review Windows Update history
2. Check for update-specific known issues
3. Consider rollback if issues persist
4. File bug report with Microsoft if confirmed

Pre-Update Baseline: scan-2025-12-27_14-30-00
Current Scan: scan-2025-12-28_10-30-00
```

---

### 8. Performance Benchmarking Suite ⭐ LOW PRIORITY

**Goal**: Track framework performance over time to ensure scalability.

**File**: `src/ps/Bottleneck.Benchmark.ps1`

**Core Functions**:

```powershell
# Benchmarking
Invoke-BottleneckBenchmark      # Run standardized performance test
Get-BenchmarkHistory            # View past benchmark results
Compare-Benchmarks              # Compare current vs. historical performance
Test-CheckPerformance           # Profile individual check execution time
Optimize-SlowChecks             # Identify and suggest optimizations
```

**Benchmark Metrics**:

1. **Scan Performance**:

   - Quick scan duration (target: <30s)
   - Standard scan duration (target: <60s)
   - Deep scan duration (target: <120s)
   - Per-check execution time
   - Memory footprint during scan

2. **Report Generation**:

   - HTML report generation time
   - Report file size
   - PDF export time (if enabled)

3. **Data Export**:

   - JSON export time
   - Prometheus export time
   - Database write time (if history enabled)

4. **Network Monitoring**:
   - Drop detection latency
   - Classification accuracy time
   - Packet capture overhead

**Benchmark Report**:

```
Bottleneck Performance Benchmark
=================================
Date: 2025-12-28 10:45:00
Version: 1.0.0
Host: DESKTOP-ABC123 (Intel i7-9700K, 32GB RAM)

Scan Performance:
- Quick Scan:     18.2s  ✅ (Target: <30s)
- Standard Scan:  51.4s  ✅ (Target: <60s)
- Deep Scan:      107.8s ✅ (Target: <120s)

Slowest Checks (Top 5):
1. SMART_Full:              12.3s
2. EventLog_Errors:         8.7s
3. Network_Bandwidth:       6.2s
4. Thermal_Extended:        4.8s
5. Process_Audit:           3.9s

Report Generation:
- HTML (Standard):  2.1s
- JSON Export:      0.3s
- Prometheus:       0.1s

Historical Comparison (vs. last week):
- Standard Scan:    51.4s → 49.8s (↓ 3.1% faster)
- Memory Usage:     280MB → 265MB (↓ 5.4% less)

Recommendations:
✅ All benchmarks within acceptable range
⚠️  EventLog_Errors timeout protection effective
💡 Consider caching SMART queries for Deep Scan
```

---

## 🗂️ File Structure Changes

### New Files to Create

```
src/ps/
├── Bottleneck.History.ps1           # Historical database system
├── Bottleneck.Trends.ps1            # Trend analysis engine
├── Bottleneck.Comparison.ps1        # Scan comparison utilities
├── Bottleneck.Regression.ps1        # Regression detection
├── Bottleneck.Benchmark.ps1         # Performance benchmarking
├── Bottleneck.Integrations.Grafana.ps1   # Grafana integration
└── Bottleneck.Integrations.InfluxDB.ps1  # InfluxDB integration

config/
├── history.json                     # History retention settings
├── grafana.json                     # Grafana configuration
└── influxdb.json                    # InfluxDB configuration

dashboards/
├── grafana-system-health.json       # Pre-built Grafana dashboard
├── grafana-network-quality.json     # Network monitoring dashboard
└── grafana-trends.json              # Trend analysis dashboard

Reports/
└── history/                         # Historical scan storage
    ├── index.json                   # Fast lookup index
    ├── 2025/
    │   └── 12/
    │       ├── scan-2025-12-27_10-30-00.json
    │       └── scan-2025-12-28_14-15-30.json
    └── baselines/                   # Performance baselines
        ├── production-baseline.json
        └── pre-update-2025-12-27.json
```

### Modified Files

```
src/ps/
├── Bottleneck.EnhancedReport.ps1    # Add trend charts and comparisons
├── Bottleneck.Metrics.ps1           # Enhanced Prometheus export
├── Bottleneck.Report.ps1            # Add historical context sections
└── Bottleneck.psm1                  # Import new modules

scripts/
├── run.ps1                          # Add trend/comparison parameters
└── compare-scans.ps1                # NEW: CLI for scan comparison
```

---

## 🧪 Testing Strategy

### Unit Tests (Pester)

```powershell
# tests/Bottleneck.History.Tests.ps1
Describe "Historical Database" {
    It "Creates database successfully" {
        Initialize-HistoryDatabase
        Test-Path "Reports/bottleneck-history.db" | Should -Be $true
    }

    It "Stores scan results" {
        $scan = @{ ScanId = "test123"; Timestamp = Get-Date }
        Add-ScanToHistory -Scan $scan
        $retrieved = Get-HistoricalScans -ScanId "test123"
        $retrieved | Should -Not -BeNullOrEmpty
    }

    It "Applies retention policy" {
        # Add 100 old scans
        Remove-OldHistory -RetentionDays 30
        $remaining = Get-HistoricalScans
        $remaining.Count | Should -BeLessOrEqual 30
    }
}

# tests/Bottleneck.Trends.Tests.ps1
Describe "Trend Analysis" {
    It "Calculates linear regression" {
        $trend = Get-PerformanceTrend -MetricName "cpu_usage" -Days 7
        $trend.Slope | Should -Not -BeNullOrEmpty
        $trend.R2 | Should -BeGreaterThan 0
    }

    It "Detects performance regression" {
        $isRegression = Test-PerformanceRegression -CurrentValue 85 -Historical @(60, 62, 58, 65)
        $isRegression | Should -Be $true
    }
}
```

### Integration Tests

```powershell
# tests/Integration.History.Tests.ps1
Describe "Historical Integration" {
    It "Full workflow: Scan → Store → Query → Compare" {
        # Run scan
        $scan = Invoke-BottleneckScan -Profile quick

        # Store in history
        Add-ScanToHistory -Scan $scan

        # Query history
        $history = Get-HistoricalScans -Last 1
        $history.Count | Should -Be 1

        # Compare
        $comparison = Compare-AgainstBaseline
        $comparison | Should -Not -BeNullOrEmpty
    }
}
```

### Manual Testing Checklist

- [ ] Run scan, verify history database created
- [ ] Run 5 scans over 24 hours, verify trend detection
- [ ] Generate comparison report between two scans
- [ ] Export to Grafana, verify dashboard displays correctly
- [ ] Export to InfluxDB, verify data ingestion
- [ ] Trigger intentional regression, verify detection
- [ ] Run benchmark suite, verify performance metrics
- [ ] Test history cleanup and retention policy
- [ ] Verify chart rendering in HTML reports
- [ ] Test baseline creation and comparison

---

## 📊 Success Criteria

### Functional Requirements

✅ **Historical Storage**:

- [ ] Store scan results for at least 30 days
- [ ] Query performance: <1s for 30-day history
- [ ] Database size: <100MB per 1000 scans
- [ ] Automatic cleanup based on retention policy

✅ **Trend Analysis**:

- [ ] Detect degrading trends with 80%+ accuracy
- [ ] Calculate regression for all key metrics
- [ ] Identify change points within 24 hours
- [ ] Provide 7-day and 30-day predictions

✅ **Dashboard Integration**:

- [ ] Prometheus export with 50+ metrics
- [ ] Grafana dashboards render correctly
- [ ] InfluxDB ingestion <1s per scan
- [ ] Real-time dashboard updates

✅ **Comparison Reports**:

- [ ] Side-by-side scan comparison in <5s
- [ ] Highlight significant changes (>10% delta)
- [ ] Export in HTML, Markdown, JSON formats
- [ ] Visual diff display with color coding

✅ **Regression Detection**:

- [ ] Detect regression within 1 scan after occurrence
- [ ] Correlate with system changes (updates, installs)
- [ ] Confidence score 75%+ for true positives
- [ ] <5% false positive rate

### Performance Requirements

- [ ] History query: <1s for 30-day range
- [ ] Trend calculation: <5s for all metrics
- [ ] Comparison report: <5s generation time
- [ ] Chart rendering: <2s for 10 charts
- [ ] Database write: <100ms per scan
- [ ] Export to InfluxDB: <500ms per scan

### Usability Requirements

- [ ] Clear trend indicators in reports (↑↓→)
- [ ] Easy baseline creation (one command)
- [ ] Intuitive comparison commands
- [ ] Pre-built Grafana dashboards (no config needed)
- [ ] Automated retention (no manual cleanup)

---

## 🚀 Implementation Plan

### Week 1: Foundation (Days 1-7)

**Day 1-2: Historical Database**

- [ ] Implement `Bottleneck.History.ps1`
- [ ] Create SQLite schema and functions
- [ ] Add database initialization to run.ps1
- [ ] Test storage and retrieval

**Day 3-4: Trend Analysis Engine**

- [ ] Implement `Bottleneck.Trends.ps1`
- [ ] Add linear regression calculations
- [ ] Create baseline comparison logic
- [ ] Implement change point detection

**Day 5-7: Enhanced Reports**

- [ ] Modify `Bottleneck.EnhancedReport.ps1`
- [ ] Add Chart.js integration
- [ ] Create trend visualization panels
- [ ] Implement historical comparison section

### Week 2: Integrations (Days 8-14)

**Day 8-9: Grafana Integration**

- [ ] Implement `Bottleneck.Integrations.Grafana.ps1`
- [ ] Enhance Prometheus export format
- [ ] Create pre-built dashboard templates
- [ ] Add auto-configuration scripts

**Day 10-11: InfluxDB Integration**

- [ ] Implement `Bottleneck.Integrations.InfluxDB.ps1`
- [ ] Add line protocol export
- [ ] Create batch write functionality
- [ ] Test high-frequency writes

**Day 12-14: Comparison & Regression**

- [ ] Implement `Bottleneck.Comparison.ps1`
- [ ] Create scan diff engine
- [ ] Implement `Bottleneck.Regression.ps1`
- [ ] Add correlation with system changes

### Week 3: Polish & Testing (Days 15-21)

**Day 15-16: Benchmarking**

- [ ] Implement `Bottleneck.Benchmark.ps1`
- [ ] Create performance test suite
- [ ] Add benchmark tracking over time
- [ ] Optimize slow checks

**Day 17-18: Testing**

- [ ] Write Pester unit tests
- [ ] Create integration test suite
- [ ] Manual testing across profiles
- [ ] Performance regression testing

**Day 19-20: Documentation**

- [ ] Update README with trend features
- [ ] Create GRAFANA_SETUP.md guide
- [ ] Document comparison CLI
- [ ] Add trend analysis examples

**Day 21: Release Prep**

- [ ] Code review and cleanup
- [ ] Final testing pass
- [ ] Update CHANGELOG
- [ ] Prepare Phase 7 completion summary

---

## 🔄 Migration Path

### For Existing Users

**Automatic Migration**:

1. First run after Phase 7 upgrade:
   - Creates history database automatically
   - Imports existing reports from `Reports/` directory
   - Builds initial index
   - No user action required

**Optional Configuration**:

```powershell
# Enable InfluxDB integration
Edit-BottleneckConfig -Component InfluxDB -Enable

# Import Grafana dashboards
Import-GrafanaDashboard -All

# Set custom retention
Set-HistoryRetention -Days 90
```

### Backward Compatibility

- [ ] All existing commands work unchanged
- [ ] Reports generated without history data (graceful degradation)
- [ ] History feature can be disabled via config
- [ ] No breaking changes to report formats

---

## 📚 Documentation Deliverables

### New Documentation

1. **TRENDS_GUIDE.md**: Complete guide to trend analysis features
2. **GRAFANA_SETUP.md**: Step-by-step Grafana integration
3. **INFLUXDB_SETUP.md**: InfluxDB configuration guide
4. **COMPARISON_CLI.md**: Scan comparison command reference
5. **REGRESSION_DETECTION.md**: Understanding regression alerts

### Updated Documentation

1. **README.md**: Add trend analysis overview
2. **QUICKSTART.md**: Add comparison and baseline commands
3. **CHECK_MATRIX.md**: Note which checks contribute to trends
4. **MASTER-PROMPT.md**: Update with Phase 7 details

---

## 🎯 Phase 7 Success Metrics

### Quantitative Goals

- [ ] 100% of scans stored in history database
- [ ] <1% storage overhead per scan
- [ ] 50+ metrics exported to Prometheus
- [ ] 3+ pre-built Grafana dashboards
- [ ] <5s trend calculation time
- [ ] 80%+ regression detection accuracy
- [ ] 30-day default retention policy
- [ ] <100MB database size for 1000 scans

### Qualitative Goals

- [ ] Users can identify performance trends without manual analysis
- [ ] Regression detection provides actionable insights
- [ ] Grafana dashboards require zero configuration
- [ ] Comparison reports clearly show improvements/regressions
- [ ] Historical data enhances troubleshooting confidence

---

## 🔮 Future Enhancements (Post-Phase 7)

**Phase 8 Candidates**:

1. Machine learning anomaly detection
2. Predictive failure analysis (SMART, event patterns)
3. Multi-host comparison (fleet management)
4. Automated remediation based on trends
5. Cloud storage sync for history (Azure, AWS, GCP)
6. Mobile app for viewing trend dashboards
7. Slack/Teams integration for trend alerts
8. Custom trend formulas (user-defined metrics)

---

## 📋 Acceptance Checklist

Before marking Phase 7 complete:

- [ ] All core features implemented and tested
- [ ] Unit test coverage >70% for new modules
- [ ] Integration tests passing
- [ ] Performance benchmarks met
- [ ] Documentation complete and reviewed
- [ ] Breaking changes documented (none expected)
- [ ] Migration guide tested with existing data
- [ ] Grafana dashboards validated
- [ ] InfluxDB integration tested
- [ ] User feedback collected on trend features
- [ ] Code reviewed by maintainers
- [ ] CHANGELOG.md updated
- [ ] Phase 7 completion summary written
- [ ] PR ready for merge to main

---

## 🎉 Expected Outcomes

After Phase 7 completion, users will be able to:

1. **Track Performance Over Time**: See how their system health changes across days, weeks, and months
2. **Detect Issues Early**: Get alerted to gradual degradation before it becomes critical
3. **Validate Fixes**: Confirm that remediation actions improved performance
4. **Monitor Fleet**: Use Grafana/InfluxDB for centralized monitoring of multiple systems
5. **Make Data-Driven Decisions**: Use historical data to plan upgrades, optimize settings
6. **Troubleshoot Regressions**: Quickly identify what changed when performance declined
7. **Benchmark Changes**: Establish baselines before updates and measure impact after

**Phase 7 transforms Bottleneck from a diagnostic tool into a comprehensive performance management platform!** 🚀
