# 🔍 Bottleneck Framework - Master Development Prompt

> **Purpose**: This comprehensive prompt provides all necessary context for AI coding assistants (GPT-4, Codex, Claude, etc.) to understand, extend, and build upon the Bottleneck Windows performance diagnostic framework.

---

## 📋 Table of Contents

1. [Project Overview](#project-overview)
2. [Core Architecture](#core-architecture)
3. [Key Features & Capabilities](#key-features--capabilities)
4. [Technical Implementation](#technical-implementation)
5. [Module Organization](#module-organization)
6. [Scan Profiles & Configuration](#scan-profiles--configuration)
7. [Network Monitoring System](#network-monitoring-system)
8. [Reporting & Export Formats](#reporting--export-formats)
9. [Development Guidelines](#development-guidelines)
10. [Extension Points](#extension-points)
11. [Real-World Validation](#real-world-validation)
12. [Future Roadmap](#future-roadmap)

---

## 🎯 Project Overview

### What is Bottleneck?

**Bottleneck** is a professional-grade Windows performance diagnostic and network monitoring tool designed for IT professionals, developers, and power users. It provides **unified system and network diagnostics** in a single framework with:

- **Zero-installation**: Pure PowerShell 7+ implementation
- **Comprehensive scanning**: 6-52+ configurable diagnostic checks
- **Network drop detection**: Real-time monitoring with classification
- **Professional reporting**: HTML, JSON, CSV, and Prometheus metrics
- **AI-powered insights**: One-click integration with ChatGPT/Copilot/Gemini
- **Production-ready**: Validated through real-world satellite internet troubleshooting

### Problem Statement

Users face fragmented diagnostic tools requiring multiple applications (PingPlotter, Resource Monitor, Event Viewer, Wireshark, etc.) to troubleshoot performance issues. Bottleneck unifies these capabilities while adding:

1. **Intelligent root cause analysis** - Distinguishes WLAN, WAN, DNS issues
2. **Historical tracking** - Compare scans over time
3. **Automated remediation** - Built-in fixes with restore points
4. **Export flexibility** - Dashboard integration (Prometheus/Grafana)

### Proven Success

The framework successfully identified and resolved real-world network issues including:

- Burnt RJ-45 connector at satellite dish (detected via pattern analysis)
- ISP equipment load-related drops (identified through usage correlation)
- Differentiation between local cable issues vs. upstream ISP problems
- Quantifiable improvement: 0.75 drops/hour → 0 drops/hour during low usage

---

## 🏗️ Core Architecture

### Design Principles

1. **Modular PowerShell**: Each capability lives in separate `src/ps/Bottleneck.*.ps1` modules
2. **Entry Point Facade**: `scripts/run.ps1` provides unified CLI with smart routing
3. **Profile-based Configuration**: JSON-driven scan profiles for different scenarios
4. **Extensible Object Model**: Standardized check/fix return structures
5. **Zero External Dependencies**: Works with base Windows + PowerShell 7

### Directory Structure

```
Bottleneck/
├── scripts/                    # Entry point scripts
│   ├── run.ps1                # Main unified entry point
│   ├── monitor-network-drops.ps1  # Network monitoring standalone
│   ├── run-computer-scan.ps1  # System diagnostics standalone
│   ├── collect-logs.ps1       # Log bundling utility
│   └── generate-enhanced-report.ps1  # Report generation
├── src/
│   └── ps/                    # PowerShell modules (30+ files)
│       ├── Bottleneck.psm1    # Main module loader
│       ├── Bottleneck.Checks.ps1      # Check orchestration
│       ├── Bottleneck.Network.ps1     # Network diagnostics
│       ├── Bottleneck.Thermal.ps1     # Temperature monitoring
│       ├── Bottleneck.Report.ps1      # Report generation
│       ├── Bottleneck.EnhancedReport.ps1  # HTML formatting
│       ├── Bottleneck.Fixes.ps1       # Automated remediation
│       ├── Bottleneck.Logging.ps1     # Structured logging
│       ├── Bottleneck.Utils.ps1       # Common utilities
│       ├── Bottleneck.Profiles.ps1    # Profile management
│       └── [25+ specialized modules]
├── config/
│   └── scan-profiles.json     # Scan profile definitions
├── Reports/                   # Generated artifacts
│   ├── *.log                  # Scan logs
│   ├── *.json                 # Structured data
│   ├── *.html                 # Interactive reports
│   ├── *.csv                  # Tabular exports
│   └── metrics-latest.prom    # Prometheus format
├── tests/                     # Test suite (planned)
├── docs/                      # Documentation
│   ├── DESIGN.md
│   ├── CHECK_MATRIX.md
│   └── ENHANCED-REPORTING.md
└── README.md, QUICKSTART.md, ROADMAP.md

Key files:
- README.md: User-facing overview
- QUICKSTART.md: Fast command reference
- ROADMAP.md: Future development plan
- PHASE1-SUMMARY.md: Completion validation
- CONTRIBUTING.md: Development guidelines
```

### Object Model

Every diagnostic check returns a standardized object:

```powershell
@{
    Id = "CPU_High"                    # Unique identifier
    Tier = "Quick"                     # Quick/Standard/Deep
    Category = "Hardware"              # Hardware/Network/System/Security/etc.
    Impact = 8                         # 0-10 severity
    Confidence = 9                     # 0-10 certainty
    Effort = 3                         # 0-10 fix difficulty
    Priority = "High"                  # Critical/High/Medium/Low
    Evidence = @{...}                  # Structured diagnostic data
    FixId = "OptimizeCPU"             # Optional auto-fix identifier
    Message = "CPU utilization..."     # Human-readable description
}
```

**Scoring Formula**: `Score = (Impact × Confidence) / (Effort + 1)`

This enables:

- Priority ranking across diverse checks
- AI-assisted troubleshooting context
- Automated fix recommendation
- Historical trend analysis

---

## 🎯 Key Features & Capabilities

### System Diagnostics (Computer Scan)

**Quick Scan (6 checks, ~2 min)**:

- Storage space
- Power plan
- Startup programs
- Network latency
- RAM availability
- CPU load

**Standard Scan (46 checks, ~15 min)**:

- All Quick checks, plus:
- Hardware: CPU/GPU/system temperatures, fan speeds, throttling detection
- Disk: SMART status, fragmentation, I/O performance
- Memory: Utilization, leak detection, stuck processes
- Network: DNS config, adapter status, bandwidth, VPN impact
- Security: AV health, Windows Update, firewall, open ports
- System: Driver age, service health, Windows features, boot time
- Java: Heap monitoring, version detection

**Deep Scan (52+ checks, ~30 min)**:

- All Standard checks, plus:
- ETW (Event Tracing for Windows) analysis
- Full SMART diagnostics with predictive failure
- SFC/DISM system integrity
- Event log pattern analysis
- Background process audit
- Hardware upgrade recommendations

### Network Monitoring

**Real-time Drop Detection**:

- Continuous internet connectivity monitoring (configurable interval: 5s default)
- Adapter state tracking (Up/Down/Disconnected)
- WiFi signal strength and channel monitoring
- BSSID tracking for roaming detection
- Packet loss counting

**Drop Classification** (3 categories):

1. **WLAN/LAN**: Local WiFi or cable problem
   - Gateway unreachable
   - Adapter down/disconnected
2. **WAN**: ISP/upstream internet issue
   - Gateway reachable but external sites fail
   - DNS failures while gateway accessible
3. **DNS**: Domain resolution problems
   - Pings work but DNS queries fail
4. **Unknown**: All tests pass but connection lost
   - Typically transient ISP issues
   - Gateway, WAN, and DNS all responsive

**Diagnostic Data Capture**:

- SSID, BSSID, channel, signal strength
- Adapter statistics (bytes sent/received, errors)
- Gateway ping results
- External connectivity tests (8.8.8.8, www.msftconnecttest.com)
- DNS resolution tests
- Optional: Windows WLAN-AutoConfig event log excerpts
- Optional: pktmon packet capture (requires admin)

**Usage Pattern Analysis**:

- Correlates drops with bandwidth consumption
- Identifies thermal/load-related issues
- Tracks drops per hour across different scenarios
- Exports to structured JSON logs

### Reporting & Export

**HTML Reports**:

- Executive summary with severity scoring
- Color-coded sections (Critical/High/Medium/Low)
- AI troubleshooting integration (pre-filled context)
- Collapsible details for readability
- Multi-location auto-save (Documents, OneDrive, project folder)
- Historical comparison tracking

**Data Exports**:

- **JSON**: Structured machine-readable format
- **CSV**: Tabular data for Excel/spreadsheets
- **Prometheus**: Metrics for Grafana dashboards
- **Log files**: Detailed transcript with timing

**Key Metrics Exported**:

```
System:
- cpu_usage_percent
- memory_usage_percent
- disk_usage_percent
- system_uptime_hours

Network:
- network_success_rate
- network_latency_avg_ms
- network_latency_p95_ms
- network_drops_total
- network_likely_cause (wlan/wan/dns/unknown)

Path Quality (MTR-lite):
- path_worst_hop_loss_percent
- path_worst_hop_latency_avg_ms

Speedtest:
- speedtest_download_mbps
- speedtest_upload_mbps
- speedtest_latency_ms
- speedtest_jitter_ms
```

---

## ⚙️ Technical Implementation

### Performance Optimizations

**CIM Query Caching**:

```powershell
# Eliminates redundant WMI queries (2-3s savings per scan)
$global:CachedCimComputer = Get-CimInstance -ClassName Win32_ComputerSystem
$global:CachedCimOS = Get-CimInstance -ClassName Win32_OperatingSystem
```

**Timeout Protection**:

```powershell
# Prevents event log query hangs (10-15s timeout)
$job = Start-Job -ScriptBlock { Get-WinEvent -FilterHashtable @{...} }
Wait-Job -Job $job -Timeout 15
```

**Parallel Execution**:

```powershell
# Independent checks run concurrently
$results = @(
    (Start-Job { Get-CPUCheck }),
    (Start-Job { Get-MemoryCheck }),
    (Start-Job { Get-DiskCheck })
) | Receive-Job -Wait -AutoRemoveJob
```

### Admin Rights Handling

**Graceful Degradation**:

- Detects elevation status: `Test-IsAdmin`
- Warns users when admin needed
- Provides subset of checks without elevation
- Auto-elevates for specific operations (Desktop mode)

**Checks Requiring Admin**:

- SMART disk diagnostics
- Driver version queries
- Service manipulation
- Windows feature inspection
- pktmon packet capture
- System file integrity (SFC/DISM)

### Logging System

**Structured Levels**:

```powershell
Write-BottleneckLog -Message "Starting scan" -Level INFO
Write-BottleneckLog -Message "WMI timeout" -Level WARN -Details @{Timeout=15}
Write-BottleneckLog -Message "Access denied" -Level ERROR -ErrorRecord $_
Write-BottleneckLog -Message "Cache miss" -Level DEBUG
```

**Timing Metrics**:

```powershell
$timer = [System.Diagnostics.Stopwatch]::StartNew()
# ... operation ...
Write-BottleneckLog "Completed in $($timer.ElapsedMilliseconds)ms"
```

### Error Handling

**Robust Patterns**:

```powershell
try {
    $result = Get-SomeDiagnostic
    return @{ Success = $true; Data = $result }
} catch {
    Write-BottleneckLog "Diagnostic failed" -Level ERROR -ErrorRecord $_
    return @{ Success = $false; Error = $_.Exception.Message }
}
```

**Fallback Chains**:

```powershell
# Try CIM, fallback to WMI, fallback to .NET
$temp = Get-CimTemperature
if (-not $temp) { $temp = Get-WmiTemperature }
if (-not $temp) { $temp = Get-DotNetTemperature }
```

---

## 📦 Module Organization

### Core Modules (src/ps/)

**Bottleneck.psm1**: Main module loader

- Imports all sub-modules
- Exports public functions
- Sets up module scope

**Bottleneck.Constants.ps1**: Configuration constants

- Thresholds (CPU: 80%, Memory: 85%, Disk: 90%)
- Timeouts (Event log: 15s, Network: 10s)
- Paths (Reports, Logs, Config)

**Bottleneck.Utils.ps1**: Common utilities

- `Test-IsAdmin`: Elevation check
- `Format-ByteSize`: Human-readable sizes
- `Get-ElapsedTime`: Timing helper
- `ConvertTo-SafePath`: Path sanitization

**Bottleneck.Logging.ps1**: Logging framework

- `Write-BottleneckLog`: Structured logging
- `Start-BottleneckTranscript`: Session recording
- Log rotation and cleanup

### Diagnostic Modules

**Bottleneck.Checks.ps1**: Check orchestration

- `Invoke-BottleneckScan`: Main scan entry point
- `Get-AllChecks`: Registry of available checks
- `Filter-ChecksByProfile`: Profile-based filtering
- `Invoke-SingleCheck`: Individual check execution

**Bottleneck.Hardware.ps1**: Hardware diagnostics

- CPU info (cores, threads, speed)
- GPU detection and utilization
- BIOS/firmware versions
- System manufacturer/model

**Bottleneck.Thermal.ps1**: Temperature monitoring

- CPU package temperature
- GPU temperature
- Motherboard sensors
- Fan speed (RPM)
- Supports: OpenHardwareMonitor, HWiNFO, WMI

**Bottleneck.CPUThrottle.ps1**: Throttling detection

- Power limit throttling
- Thermal throttling
- Frequency capping
- TurboBoost status

**Bottleneck.Memory.ps1**: Memory diagnostics

- Physical RAM usage
- Page file utilization
- Memory leak detection
- Stuck/zombie process identification
- Per-process memory breakdown

**Bottleneck.Disk.ps1**: Storage diagnostics

- SMART status and attributes
- Fragmentation level
- I/O latency
- Disk queue depth
- SSD wear leveling

**Bottleneck.Network.ps1**: Network diagnostics

- Adapter enumeration
- DNS configuration
- Gateway ping
- External connectivity tests
- Bandwidth estimation
- VPN detection and performance impact

**Bottleneck.Security.ps1**: Security checks

- Antivirus status
- Windows Defender health
- Firewall configuration
- Open ports (netstat parsing)
- Certificate expiration
- Browser security settings

**Bottleneck.Services.ps1**: Service health

- Critical service status (BITS, Windows Update, etc.)
- Service startup types
- Failed service detection
- Dependency analysis

**Bottleneck.Performance.ps1**: System performance

- Boot time analysis
- CPU utilization over time
- Memory pressure detection
- Background process audit
- Resource-intensive app identification

**Bottleneck.Events.ps1**: Event log analysis

- Critical/Error event counting
- Pattern detection (repeated failures)
- Security event audit
- Application crash detection
- Timeout-protected queries

### Network Monitoring

**monitor-network-drops.ps1**: Standalone network monitor

- Configurable duration and check intervals
- Drop classification (WLAN/LAN/WAN/DNS)
- SSID/BSSID tracking
- Signal strength monitoring
- Optional packet capture (pktmon)
- WLAN-AutoConfig event integration

**Bottleneck.NetworkMonitor.ps1**: MTR-lite path quality

- Periodic traceroute snapshots
- Per-hop latency aggregation
- Packet loss per hop
- Worst hop identification
- JSON persistence

**Bottleneck.Speedtest.ps1**: Bandwidth testing

- Multi-provider support (HTTP, Ookla CLI, Fast.com)
- Download/upload speed
- Latency and jitter measurement
- History tracking (last 100 results)
- Trend analysis (% change from previous)

**Bottleneck.NetworkProbes.ps1**: Per-process traffic

- Active connection enumeration
- Delta sampling for bandwidth
- Top bandwidth consumers
- Process name resolution
- Risky port detection

### Reporting

**Bottleneck.Report.ps1**: Report generation core

- Markdown formatting
- Section structuring
- Evidence serialization
- Priority sorting

**Bottleneck.EnhancedReport.ps1**: HTML generation

- Bootstrap-based styling
- Color-coded severity
- Collapsible sections
- AI integration buttons
- Copy-to-clipboard helpers
- Chart generation (placeholder)

**Bottleneck.ReportUtils.ps1**: Report utilities

- Multi-location save
- Historical comparison
- Report indexing
- Cleanup policies

**Bottleneck.Metrics.ps1**: Data export

- JSON export (API-friendly)
- Prometheus export (Grafana-ready)
- Metric aggregation
- Timestamp management

### Remediation

**Bottleneck.Fixes.ps1**: Automated fixes

- Power plan optimization
- Disk cleanup
- Memory diagnostics
- Service restart
- Driver update helpers
- Windows Update trigger

**Pre-fix Safety**:

```powershell
# All fixes create restore point first
Checkpoint-Computer -Description "Bottleneck Fix: $FixName"
```

**Confirmation Prompts**:

```powershell
$choice = Read-Host "Apply fix for $Issue? (y/N)"
if ($choice -eq 'y') { Apply-Fix }
```

---

## 🎛️ Scan Profiles & Configuration

### Built-in Profiles (config/scan-profiles.json)

**quick**: Fast 5-check scan

```json
{
  "description": "Fast 5-check scan for immediate insights",
  "minutes": 2,
  "tier": "Quick",
  "targetHost": "www.yahoo.com",
  "dnsPrimary": "1.1.1.1",
  "dnsSecondary": "8.8.8.8"
}
```

**standard**: Balanced 25-check scan

```json
{
  "description": "Balanced 25-check scan for general diagnostics",
  "minutes": 15,
  "tier": "Standard",
  "ai": true
}
```

**deep**: Comprehensive 70+ checks

```json
{
  "description": "Comprehensive 70+ check scan with extended monitoring",
  "minutes": 480,
  "tier": "Deep",
  "ai": true,
  "traceIntervalMinutes": 5
}
```

### Persona Profiles

**DesktopGamer**:

- Focus: Thermal, GPU, network latency, performance
- Included: CPU, RAM, Storage, GPU, Thermal, NetworkAdapter
- Excluded: Services, Security, Updates, GroupPolicy, Java
- Target: Low-latency gaming experience

**RemoteWorker**:

- Focus: Network reliability, VPN, battery, connectivity
- Included: Network, VPN, DNS, Bandwidth, Battery, Services
- Excluded: GPU, Java, GroupPolicy
- Target: Stable remote work experience

**DeveloperLaptop**:

- Focus: Disk I/O, memory, services, multitasking
- Included: Disk, DiskSMART, Memory, Services, Java
- Excluded: GPU, Thermal, GroupPolicy
- Target: Development environment optimization

**ServerDefault**:

- Focus: Services, security, reliability, updates
- Tier: Deep
- Emphasis: Stability and uptime
- Target: Server environment health

### Profile Usage

**CLI**:

```powershell
# Use predefined profile
.\scripts\run.ps1 -Profile RemoteWorker -Network -Minutes 20

# Override specific settings
.\scripts\run.ps1 -Profile standard -AI -CollectLogs
```

**Config File** (future):

```json
{
  "defaultProfile": "standard",
  "reportPath": "C:\\MyReports",
  "networkTargets": {
    "primary": "1.1.1.1",
    "secondary": "8.8.8.8"
  }
}
```

---

## 🌐 Network Monitoring System

### Architecture

**Three-tier Classification**:

1. **Gateway Check**: `Test-NetConnection -ComputerName $gateway`

   - If fails → WLAN/LAN issue (local network problem)

2. **WAN Check**: `Test-NetConnection -ComputerName 8.8.8.8`

   - If fails (but gateway OK) → WAN issue (ISP/upstream)

3. **DNS Check**: `Resolve-DnsName www.msftconnecttest.com`

   - If fails (but WAN OK) → DNS issue

4. **Unknown**: All tests pass but connection lost
   - Typically transient ISP glitch
   - Requires deeper packet analysis

### Real-World Classification Examples

**Example 1: Burnt RJ-45 Cable**

```
Drop Pattern: 0.75/hour initially, then 4/hour
Classification: Unknown → WAN (intermittent)
Signal: 80-91% (strong)
Duration: 10-45 seconds per drop
Resolution: Cable replacement + connector repair
Result: 0 drops during low usage
```

**Example 2: ISP Equipment Overload**

```
Drop Pattern: 0/hr (idle) → 4/hr (heavy use)
Classification: Unknown (all tests pass)
Signal: 78-92% (excellent)
Data Transfer: 850+ MB/hr triggers drops
Duration: 10-16 seconds per drop
Resolution: ISP equipment issue (thermal/capacity)
```

### Packet Capture Integration

**pktmon Integration** (Windows 10 1809+):

```powershell
# Start ring buffer capture
pktmon filter add -i $ifIndex
pktmon start --etw -p 128 -s 64

# On drop, export last N seconds
pktmon stop
pktmon pcapng $logFile
```

**Benefits**:

- No Wireshark installation required
- Low overhead (configurable packet size)
- Automatic drop correlation
- Exports to standard pcapng format

### Usage Patterns

**Quick Test** (2 minutes):

```powershell
.\scripts\run.ps1 -Profile quick -Network -Minutes 2
```

**Standard Monitor** (15 minutes):

```powershell
.\scripts\run.ps1 -Profile standard -Network -Minutes 15 -CollectLogs
```

**Deep Overnight** (8 hours):

```powershell
.\scripts\run.ps1 -Profile deep -Network -Minutes 480 -TraceIntervalMinutes 5
```

**Standalone Network Monitor**:

```powershell
.\scripts\monitor-network-drops.ps1 `
  -DurationMinutes 60 `
  -CheckIntervalSeconds 5 `
  -Classify `
  -CaptureWlanEvents `
  -CapturePackets
```

### Log Format

**Network Drop Log** (Reports/network-drop-\*.log):

```
🔍 Network Drop Monitor Started
Duration: 60 minutes | Check interval: 5 seconds

Monitoring adapter: Wi-Fi (Intel(R) Wi-Fi 6 AX200 160MHz)

🔴 DROP DETECTED #1 at 22:08:43
   Adapter Status: Up
   Internet: False
   📊 Capturing diagnostics...
   SSID: wireless  BSSID: 14:21:03:65:34:8c  Channel: 36  Signal: 91%
   Adapter Stats: Recv=17086054 Sent=5229849 RecvErrors=0
   Classification: Unknown (GW:True WAN:True DNS:True)

🟢 RECONNECTED at 22:08:58

✓ Monitoring complete
Total drops detected: 1

📋 Diagnostic Summary:
Adapter: Wi-Fi
  Status: Up
  Link Speed: 400 Mbps
  Signal: 91%

Classification Totals:
  WLAN/LAN: 0  |  WAN: 0  |  DNS: 0  |  Unknown: 1
```

---

## 📊 Reporting & Export Formats

### HTML Report Structure

**Executive Summary**:

- Overall health score (0-100)
- Critical issues count
- Top 3 recommendations
- Quick stats (CPU, Memory, Disk, Network)

**Detailed Sections** (collapsible):

1. **Critical Issues** (Impact 8-10, Confidence 8+)
2. **High Priority** (Score > 50)
3. **Medium Priority** (Score 25-50)
4. **Low Priority** (Score < 25)
5. **Informational** (Impact < 4)

**AI Integration**:

```html
<button onclick="copyDiagnostics()">Copy for ChatGPT</button>
<button onclick="openCopilot()">Ask GitHub Copilot</button>
<button onclick="openGemini()">Ask Google Gemini</button>
```

**Pre-filled Context**:

```
System: Windows 11 Pro 64-bit, Intel Core i7-9700K, 32GB RAM
Issue: High CPU usage (87% avg), multiple throttling events
Evidence:
- Process: chrome.exe consuming 4.2GB RAM, 45% CPU
- Thermal: CPU package 89°C, throttling detected
- Background: 127 processes, 15 startups enabled
Recommendation: Close unnecessary browser tabs, disable startup apps, check thermal paste
```

### JSON Export Schema

**metrics-latest.json**:

```json
{
  "timestamp": "2025-12-27T10:28:30Z",
  "hostname": "PAD",
  "system": {
    "cpu_usage_percent": 23.4,
    "memory_usage_percent": 67.8,
    "disk_usage_percent": 78.2,
    "uptime_hours": 142.3
  },
  "disk": {
    "free_gb": 245.8,
    "total_gb": 931.5,
    "usage_percent": 73.6
  },
  "network": {
    "success_rate": 1.0,
    "latency_avg_ms": 22.3,
    "latency_p95_ms": 35.7,
    "drops_total": 0,
    "likely_cause": "none"
  },
  "path": {
    "worst_hop": 3,
    "worst_hop_loss_percent": 2.1,
    "worst_hop_latency_avg_ms": 45.6
  },
  "speedtest": {
    "download_mbps": 22.39,
    "upload_mbps": 3.19,
    "latency_ms": 35.2,
    "jitter_ms": 4.7,
    "timestamp": "2025-12-27T08:15:23Z"
  }
}
```

### Prometheus Export Format

**metrics-latest.prom**:

```prometheus
# HELP bottleneck_cpu_usage_percent Current CPU usage percentage
# TYPE bottleneck_cpu_usage_percent gauge
bottleneck_cpu_usage_percent 23.4

# HELP bottleneck_memory_usage_percent Current memory usage percentage
# TYPE bottleneck_memory_usage_percent gauge
bottleneck_memory_usage_percent 67.8

# HELP bottleneck_network_success_rate Network probe success rate (0-1)
# TYPE bottleneck_network_success_rate gauge
bottleneck_network_success_rate 1.0

# HELP bottleneck_network_latency_p95_ms 95th percentile network latency
# TYPE bottleneck_network_latency_p95_ms gauge
bottleneck_network_latency_p95_ms 35.7

# HELP bottleneck_network_drops_total Total network drops detected
# TYPE bottleneck_network_drops_total counter
bottleneck_network_drops_total 0
```

### CSV Export

**Network Monitor CSV** (network-monitor-\*.csv):

```csv
Timestamp,Adapter,Status,LinkSpeed,Signal,Channel,SSID,Internet,GatewayPing,WanPing,DnsSuccess,Classification
2025-12-27T10:28:35,Wi-Fi,Up,400,91,36,wireless,True,2.3,22.1,True,None
2025-12-27T10:28:40,Wi-Fi,Up,400,91,36,wireless,True,2.1,21.8,True,None
2025-12-27T10:28:45,Wi-Fi,Up,400,91,36,wireless,False,2.5,999,True,WAN
```

---

## 🛠️ Development Guidelines

### Code Standards

**PowerShell Style**:

```powershell
# Use approved verbs: Get-, Set-, New-, Remove-, Invoke-, Test-
function Get-BottleneckCheck { ... }

# Parameter naming: PascalCase
param(
    [string]$ComputerName,
    [int]$TimeoutSeconds = 30
)

# Variables: camelCase
$connectionStatus = Test-NetConnection

# Constants: UPPERCASE
$MAX_RETRIES = 3
```

**Error Handling**:

```powershell
# Always use try/catch for external calls
try {
    $result = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
} catch {
    Write-BottleneckLog "CIM query failed" -Level ERROR -ErrorRecord $_
    return $null
}

# Use -ErrorAction appropriately
Get-Process -Name nonexistent -ErrorAction SilentlyContinue
```

**Function Documentation**:

```powershell
<#
.SYNOPSIS
    Detects CPU throttling events

.DESCRIPTION
    Monitors CPU frequency, power limits, and thermal state to identify
    performance throttling. Returns structured data with severity.

.PARAMETER DurationSeconds
    Sampling duration in seconds (default: 10)

.OUTPUTS
    Hashtable with: Throttled (bool), Reason (string), Evidence (hashtable)

.EXAMPLE
    $throttle = Get-CPUThrottleCheck -DurationSeconds 15
    if ($throttle.Throttled) { Write-Host "CPU throttling: $($throttle.Reason)" }
#>
function Get-CPUThrottleCheck {
    param([int]$DurationSeconds = 10)
    # Implementation...
}
```

### Testing Strategy

**Manual Testing** (current):

```powershell
# Test individual checks
Import-Module .\src\ps\Bottleneck.psm1
$result = Get-CPUCheck
$result | ConvertTo-Json -Depth 5

# Test profiles
.\scripts\run.ps1 -Profile quick -Debug

# Test network monitoring
.\scripts\monitor-network-drops.ps1 -DurationMinutes 2 -Classify
```

**Automated Testing** (planned - see Roadmap):

- Pester unit tests for each module
- Integration tests for scan workflows
- Mock WMI/CIM queries for CI/CD
- Performance regression tests

### Module Addition Checklist

To add a new diagnostic module:

1. **Create module file**: `src/ps/Bottleneck.YourFeature.ps1`

2. **Define public functions**:

```powershell
function Get-YourFeatureCheck {
    param([string]$Param1)
    # Implementation
    return @{
        Id = "YourFeature_Issue"
        Tier = "Standard"
        Category = "Category"
        Impact = 7
        Confidence = 8
        Effort = 3
        Priority = "High"
        Evidence = @{ Detail1 = $value1 }
        FixId = "FixYourFeature"
        Message = "Human-readable finding"
    }
}
```

3. **Export from main module** (`Bottleneck.psm1`):

```powershell
. "$PSScriptRoot\Bottleneck.YourFeature.ps1"
Export-ModuleMember -Function Get-YourFeatureCheck
```

4. **Register in Checks.ps1**:

```powershell
$checkRegistry = @{
    # ... existing checks ...
    "YourFeature" = @{
        Tier = "Standard"
        Function = "Get-YourFeatureCheck"
        RequiresAdmin = $false
    }
}
```

5. **Add to profiles** (config/scan-profiles.json):

```json
"includedChecks": ["CPU", "RAM", "YourFeature"]
```

6. **Document in CHECK_MATRIX.md**

7. **Test thoroughly**:

```powershell
# Unit test
$check = Get-YourFeatureCheck -Param1 "test"
$check | Should -Not -BeNullOrEmpty

# Integration test
.\scripts\run.ps1 -Profile standard
```

### Contribution Workflow

1. **Fork repository** on GitHub
2. **Create feature branch**: `git checkout -b feature/your-feature`
3. **Implement changes** following style guide
4. **Test locally** with multiple profiles
5. **Update documentation** (README, CHECK_MATRIX)
6. **Commit with clear messages**: `feat: Add thermal throttling detection`
7. **Push and create Pull Request**
8. **Respond to review feedback**

---

## 🔌 Extension Points

### Custom Check Integration

**Scenario**: Add SSD wear leveling check

```powershell
# File: src/ps/Bottleneck.SSDWear.ps1

function Get-SSDWearCheck {
    <#
    .SYNOPSIS
        Checks SSD wear leveling and endurance
    #>

    try {
        $disks = Get-PhysicalDisk | Where-Object { $_.MediaType -eq 'SSD' }
        $results = @()

        foreach ($disk in $disks) {
            # Query vendor-specific SMART attributes
            $wearLevel = Get-SSDWearLevel -DiskNumber $disk.DeviceID

            if ($wearLevel -gt 80) {
                $results += @{
                    Id = "SSD_HighWear_$($disk.DeviceID)"
                    Tier = "Standard"
                    Category = "Hardware"
                    Impact = 7
                    Confidence = 9
                    Effort = 8  # Requires SSD replacement
                    Priority = "High"
                    Evidence = @{
                        DiskModel = $disk.Model
                        WearLevel = $wearLevel
                        TBW = $disk.TotalBytesWritten / 1TB
                    }
                    FixId = $null  # No automated fix
                    Message = "SSD $($disk.Model) wear: ${wearLevel}% - Consider replacement"
                }
            }
        }

        return $results
    } catch {
        Write-BottleneckLog "SSD wear check failed" -Level ERROR -ErrorRecord $_
        return @()
    }
}

function Get-SSDWearLevel {
    param([int]$DiskNumber)
    # Implementation: Query SMART attribute 177 (Wear Leveling Count)
    # or vendor-specific attributes (Samsung: 202, Intel: 233)
    # Return percentage: 0 (new) to 100 (end of life)
}
```

**Integration**:

1. Add to `Bottleneck.psm1`: `. "$PSScriptRoot\Bottleneck.SSDWear.ps1"`
2. Register in `Bottleneck.Checks.ps1`
3. Add to profiles: `"includedChecks": ["SSDWear"]`

### Custom Fix Implementation

**Scenario**: Automated defragmentation

```powershell
# File: src/ps/Bottleneck.Fixes.ps1 (add to existing)

function Invoke-DiskDefragFix {
    <#
    .SYNOPSIS
        Defragments HDDs with high fragmentation
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$CheckResult
    )

    # Safety: Confirm with user
    $disk = $CheckResult.Evidence.DriveLetter
    $fragPercent = $CheckResult.Evidence.FragmentationPercent

    Write-Host "⚠️  Disk $disk is ${fragPercent}% fragmented" -ForegroundColor Yellow
    $confirm = Read-Host "Run defragmentation? This may take 1-2 hours (y/N)"

    if ($confirm -ne 'y') {
        Write-Host "Skipped." -ForegroundColor Gray
        return
    }

    # Create restore point
    Write-Host "Creating restore point..." -ForegroundColor Cyan
    Checkpoint-Computer -Description "Before Defrag: $disk" -RestorePointType MODIFY_SETTINGS

    # Run defragmentation
    Write-Host "Starting defragmentation on $disk..." -ForegroundColor Green
    try {
        Optimize-Volume -DriveLetter $disk -Defrag -Verbose
        Write-Host "✓ Defragmentation complete" -ForegroundColor Green
    } catch {
        Write-Host "✗ Defragmentation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-BottleneckLog "Defrag failed on $disk" -Level ERROR -ErrorRecord $_
    }
}
```

**Registration**:

```powershell
# In Bottleneck.Checks.ps1, add FixId to check:
@{
    Id = "Disk_HighFragmentation"
    # ... other fields ...
    FixId = "DefragDisk"
}

# In Bottleneck.Fixes.ps1, register fix handler:
$fixHandlers = @{
    "DefragDisk" = "Invoke-DiskDefragFix"
    # ... other handlers ...
}
```

### Report Customization

**Scenario**: Add custom branding

```powershell
# File: src/ps/Bottleneck.EnhancedReport.ps1 (modify)

# Add company logo and colors
$customCSS = @"
:root {
    --company-primary: #0066cc;
    --company-secondary: #ff6600;
}
.report-header {
    background: var(--company-primary);
    color: white;
    padding: 20px;
}
.report-header img {
    max-height: 60px;
}
"@

# Inject into HTML generation
function New-EnhancedHTMLReport {
    param($ScanResults, $LogoPath)

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <style>$customCSS</style>
</head>
<body>
    <div class="report-header">
        <img src="$LogoPath" alt="Company Logo">
        <h1>System Health Report</h1>
    </div>
    <!-- Rest of report -->
</body>
</html>
"@

    return $html
}
```

### Dashboard Integration

**Scenario**: Export to InfluxDB

```powershell
# File: src/ps/Bottleneck.Integrations.ps1 (new)

function Export-ToInfluxDB {
    <#
    .SYNOPSIS
        Exports metrics to InfluxDB time-series database
    #>
    param(
        [string]$InfluxUrl = "http://localhost:8086",
        [string]$Database = "bottleneck",
        [hashtable]$Metrics
    )

    # InfluxDB line protocol format
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $lines = @()

    # System metrics
    $lines += "system,host=$($Metrics.hostname) cpu_usage=$($Metrics.system.cpu_usage_percent) $timestamp"
    $lines += "system,host=$($Metrics.hostname) memory_usage=$($Metrics.system.memory_usage_percent) $timestamp"

    # Network metrics
    if ($Metrics.network) {
        $lines += "network,host=$($Metrics.hostname) success_rate=$($Metrics.network.success_rate) $timestamp"
        $lines += "network,host=$($Metrics.hostname) latency_p95=$($Metrics.network.latency_p95_ms) $timestamp"
    }

    # Send to InfluxDB
    $body = $lines -join "`n"
    try {
        Invoke-RestMethod -Uri "$InfluxUrl/write?db=$Database" `
            -Method POST `
            -Body $body `
            -ContentType "text/plain"
        Write-Host "✓ Metrics exported to InfluxDB" -ForegroundColor Green
    } catch {
        Write-BottleneckLog "InfluxDB export failed" -Level ERROR -ErrorRecord $_
    }
}
```

**Usage**:

```powershell
# After scan completes
$metrics = Get-Content "Reports\metrics-latest.json" | ConvertFrom-Json
Export-ToInfluxDB -Metrics $metrics
```

---

## ✅ Real-World Validation

### Case Study: Satellite Internet Troubleshooting

**Context**: Rural satellite internet with frequent disconnections impacting work and streaming.

**Investigation Timeline**:

**Day 1: Initial Diagnosis**

- Cable fix: Burnt RJ-45 connector at dish
- Results: Immediate improvement (0 drops in first test)
- Conclusion: Problem solved? No...

**Day 1 Evening: Problem Returns**

- Evening test: 4 drops in 60 minutes
- Classification: All "Unknown" (GW/WAN/DNS reachable)
- Pattern: Drops every 10-20 minutes

**Day 2 Morning: Low Usage Test**

- Away from home, minimal activity
- Results: 0 drops in 60 minutes
- Correlation: Usage-dependent issue?

**Day 2 Evening: Netflix Test**

- Streaming at 850+ MB/hour
- Results: 1 drop at 55 minutes
- Pattern: Drop occurred after sustained load

**Day 2 Overnight: Idle Test**

- Sleep hours, minimal traffic
- Results: 2 drops in 60 minutes
- Conclusion: NOT purely usage-related

**Root Cause Analysis**:

1. **Fixed**: Burnt local cable (reduced baseline issues)
2. **Remaining**: ISP equipment problem (thermal/capacity)
3. **Evidence**:
   - Time-based pattern (worse in evening)
   - Not purely load-correlated (drops during idle)
   - Short duration (10-16s suggests equipment reset)
   - "Unknown" classification (upstream issue)

**Outcome**:

- Local cable fix: Necessary but insufficient
- ISP equipment issue identified
- Quantified impact: 0.75→4 drops/hr (heavy use) vs. 0→2 drops/hr (idle)
- Next steps: Contact ISP with detailed logs

### Lessons Learned

**Framework Strengths**:

1. ✅ **Pattern Recognition**: Identified usage correlation
2. ✅ **Classification Accuracy**: Correctly flagged ISP vs. local issues
3. ✅ **Historical Comparison**: Tracked changes across fixes
4. ✅ **Quantifiable Metrics**: Drops/hour as clear KPI
5. ✅ **Evidence Collection**: SSID, signal, classification data

**Framework Improvements Needed**:

1. ⚠️ **Duration Parameter Bug**: 8-hour scans ran only 60 minutes
   - Issue: Script parameter not passed correctly
   - Fix needed: Verify parameter propagation in `run.ps1`
2. ⚠️ **Better Trend Visualization**: Graph drops over time
3. ⚠️ **Temperature Correlation**: Track dish equipment temperature if available
4. ⚠️ **Bandwidth Tracking**: Log concurrent bandwidth usage during drops

---

## 🚀 Future Roadmap

### v1.1 - Quality & Convenience

**Goal**: Polish v1 experience, reduce friction

**Planned Features**:

- ✅ **Predefined Scan Profiles** (Complete)
- ⏳ **Config File Support**: `bottleneck.config.json` for defaults
- ⏳ **Report Usability**: Jump-to-section TOC, clipboard copy
- ⏳ **Profile Discovery**: `Get-BottleneckProfile` command

### v1.2 - Network Quality Scoring

**Goal**: Match PingPlotter-style diagnostics

**Planned Features**:

- ⏳ **Jitter Metrics**: Per-probe delta calculation
- ⏳ **Connection Quality Score**: 0-100 rating based on loss/latency/jitter
- ⏳ **Historical Trending**: Compare quality over days/weeks
- ⏳ **VoIP/Gaming Presets**: Thresholds for real-time apps

### v1.3 - Continuous Monitoring

**Goal**: Agent-mode for long-term tracking

**Planned Features**:

- ⏳ **Scheduled Scans**: Windows Task Scheduler integration
- ⏳ **Alert Webhooks**: Slack/Teams/Discord notifications
- ⏳ **Metric Retention**: SQLite or CSV-based history
- ⏳ **Baseline Learning**: Auto-detect anomalies vs. normal

### v2.0 - Platform Evolution

**Goal**: Multi-host, GUI, advanced analytics

**Planned Features**:

- ⏳ **GUI Application**: Tauri + React frontend
- ⏳ **Remote Scanning**: WinRM/SSH-based multi-host
- ⏳ **ETW Deep Dive**: Real-time event tracing
- ⏳ **Machine Learning**: Predictive failure detection
- ⏳ **Fleet Management**: Dashboard for multiple systems

### v3.0 - Enterprise Features

**Goal**: Professional/enterprise scenarios

**Planned Features**:

- ⏳ **Active Directory Integration**: Domain-wide scanning
- ⏳ **Compliance Reporting**: CIS benchmarks, STIG validation
- ⏳ **Ticketing Integration**: Jira/ServiceNow connectors
- ⏳ **Role-Based Access**: Multi-tenant security
- ⏳ **Custom Check SDK**: Plugin architecture

---

## 📚 Additional Resources

### Documentation Files

- **README.md**: User-facing overview and installation
- **QUICKSTART.md**: Fast command reference
- **ROADMAP.md**: Detailed future planning (370+ lines)
- **PHASE1-SUMMARY.md**: Completion validation (337+ lines)
- **CONTRIBUTING.md**: Development guidelines
- **CHANGELOG.md**: Version history
- **LICENSE**: MIT License
- **docs/DESIGN.md**: Architecture deep-dive
- **docs/CHECK_MATRIX.md**: Complete check catalog
- **docs/ENHANCED-REPORTING.md**: Report format specification

### Key Commands Reference

```powershell
# Computer scans
.\scripts\run.ps1                                    # Full system scan
.\scripts\run.ps1 -Profile quick                     # Fast scan
.\scripts\run.ps1 -Profile standard -AI              # With AI insights
.\scripts\run.ps1 -Profile deep -CollectLogs         # Deep + auto-collect

# Network monitoring
.\scripts\run.ps1 -Network -Minutes 15               # 15-min network test
.\scripts\run.ps1 -Profile standard -Network -Minutes 120  # Combined
.\scripts\monitor-network-drops.ps1 -Classify        # Standalone monitor

# Report generation
.\scripts\generate-enhanced-report.ps1 -ScanResults $results
.\scripts\collect-logs.ps1 -IncludeAll -OpenFolder

# Desktop diagnostic (Win7-safe)
.\scripts\run.ps1 -Desktop -HeavyLoad -Html
```

### Module Import

```powershell
# For development/testing
Import-Module .\src\ps\Bottleneck.psm1 -Force

# Verify exports
Get-Command -Module Bottleneck

# Test individual function
$cpuCheck = Get-CPUCheck
$cpuCheck | ConvertTo-Json -Depth 5
```

### VS Code Tasks

See `.vscode/tasks.json`:

- **Run Computer Scan**: Full system diagnostic
- **Run Network Scan (15m)**: Standard network test
- **Run Network Scan (2m quick)**: Fast network test
- **Run Network Scan (8h)**: Overnight monitoring
- **Collect Bottleneck logs**: Bundle and zip reports

---

## 🎓 Getting Started for Developers

### Prerequisites

1. **Install PowerShell 7+**:

   ```powershell
   winget install Microsoft.PowerShell
   ```

2. **Clone Repository**:

   ```bash
   git clone https://github.com/ssgrim/Bottleneck.git
   cd Bottleneck
   ```

3. **Set Execution Policy**:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

### First Steps

1. **Run a quick scan**:

   ```powershell
   .\scripts\run.ps1 -Profile quick
   ```

2. **Examine the output**:

   - Check `Reports/` folder for HTML report
   - Review `Reports/*.log` for detailed transcript
   - Inspect `Reports/metrics-latest.json` for structured data

3. **Test network monitoring**:

   ```powershell
   .\scripts\run.ps1 -Network -Minutes 2 -Profile quick
   ```

4. **Review code structure**:
   - Start with `scripts/run.ps1` (entry point)
   - Explore `src/ps/Bottleneck.Checks.ps1` (orchestration)
   - Read individual modules (`Bottleneck.*.ps1`)

### Development Workflow

1. **Modify a check**:

   ```powershell
   # Edit src/ps/Bottleneck.CPU.ps1
   # Add logging:
   Write-BottleneckLog "CPU check starting" -Level DEBUG
   ```

2. **Test change**:

   ```powershell
   # Reload module
   Import-Module .\src\ps\Bottleneck.psm1 -Force

   # Run specific check
   Get-CPUCheck

   # Or run full scan
   .\scripts\run.ps1 -Profile quick -Debug
   ```

3. **Check logs**:

   ```powershell
   # View detailed output
   Get-Content Reports\*.log | Select-String "CPU"
   ```

4. **Commit changes**:
   ```bash
   git add .
   git commit -m "feat: Improve CPU utilization sampling"
   git push origin feature/cpu-improvements
   ```

### Common Development Tasks

**Add a new check**:

```powershell
# 1. Create module file
New-Item -Path src\ps\Bottleneck.NewFeature.ps1

# 2. Implement function (see Module Addition Checklist)

# 3. Test
Import-Module .\src\ps\Bottleneck.psm1 -Force
Get-NewFeatureCheck

# 4. Register in Bottleneck.Checks.ps1
# 5. Add to profile in config\scan-profiles.json
# 6. Update docs\CHECK_MATRIX.md
```

**Debug network classification**:

```powershell
# Run with verbose logging
.\scripts\monitor-network-drops.ps1 `
  -DurationMinutes 5 `
  -Classify `
  -VerboseDiagnostics

# Review classification logic
Get-Content Reports\network-drop-*.log | Select-String "Classification"
```

**Test report generation**:

```powershell
# Generate sample data
$mockResults = @(
    @{ Id="TEST"; Impact=8; Confidence=9; Message="Test issue" }
)

# Generate report
.\scripts\generate-enhanced-report.ps1 -ScanResults $mockResults

# Open in browser
Invoke-Item Reports\*.html
```

### Troubleshooting

**Module not loading**:

```powershell
# Check syntax errors
Test-ModuleSyntax .\src\ps\Bottleneck.psm1

# Import with verbose output
Import-Module .\src\ps\Bottleneck.psm1 -Verbose -Force

# Check exports
Get-Command -Module Bottleneck | Measure-Object
```

**Admin rights needed**:

```powershell
# Test elevation
Test-IsAdmin

# Re-run as admin
Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile", "-File", ".\scripts\run.ps1"
```

**WMI/CIM timeout**:

```powershell
# Increase timeout in Bottleneck.Constants.ps1
$WMI_TIMEOUT_SECONDS = 30  # Increase from 15

# Test specific query
Measure-Command {
    Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
}
```

---

## 🎯 Prompting Best Practices

### For AI Coding Assistants

**When asking for help**:

1. **Be specific about context**:

   ```
   "I want to add a check for GPU memory usage in the Bottleneck framework.
   It should follow the existing pattern in Bottleneck.Thermal.ps1 and return
   the standardized check object with Id, Impact, Confidence, etc."
   ```

2. **Reference existing patterns**:

   ```
   "Looking at Bottleneck.Network.ps1, I need to add DNS latency measurement
   similar to how gateway pings are implemented in Get-NetworkCheck."
   ```

3. **Specify integration points**:

   ```
   "Create a new module Bottleneck.Docker.ps1 that checks container health.
   Register it in Bottleneck.Checks.ps1 and add to the DeveloperLaptop profile."
   ```

4. **Include error handling requirements**:
   ```
   "The check should gracefully handle Docker not being installed, log
   errors using Write-BottleneckLog, and return an empty array on failure."
   ```

### For Building Extensions

**Provide this prompt structure**:

```
I'm extending the Bottleneck Windows diagnostic framework. Here's what I need:

FEATURE: [Brief description]

CONTEXT:
- Module pattern: src/ps/Bottleneck.[Feature].ps1
- Check registration: Bottleneck.Checks.ps1
- Object model: { Id, Tier, Category, Impact, Confidence, Effort, Priority, Evidence, FixId, Message }
- Logging: Write-BottleneckLog with DEBUG/INFO/WARN/ERROR levels
- Error handling: try/catch with graceful fallback

REQUIREMENTS:
1. [Specific requirement 1]
2. [Specific requirement 2]

INTEGRATION:
- Profile: [Which profile to add to]
- Dependencies: [What other modules it uses]
- Admin required: [Yes/No]

TESTING:
- Manual test command: [How to invoke]
- Expected output: [What success looks like]
```

### For Debugging

**Effective debug prompts**:

```
ISSUE: Network drop classification is showing "Unknown" when it should be "WAN"

CONTEXT:
- File: scripts/monitor-network-drops.ps1, lines 150-200
- Classification logic: Checks gateway, then 8.8.8.8, then DNS
- Current behavior: All three tests pass but connection lost
- Expected: WAN classification when 8.8.8.8 fails

EVIDENCE:
- Gateway ping: Success (2.3ms)
- WAN ping: Appears to succeed but internet down
- DNS: Success

What's the likely issue with the classification logic, and how should I fix it?
```

---

## 🏁 Conclusion

This master prompt provides comprehensive context for understanding, extending, and building upon the Bottleneck framework. Key takeaways:

1. **Modular Architecture**: 30+ PowerShell modules with clear separation of concerns
2. **Proven Design**: Validated through real-world satellite internet troubleshooting
3. **Extensible**: Clear patterns for adding checks, fixes, and reports
4. **Production-Ready**: Error handling, logging, admin detection, timeout protection
5. **Dashboard-Friendly**: JSON, Prometheus, CSV exports for integration
6. **AI-Native**: Structured diagnostics perfect for LLM-assisted troubleshooting

### Next Steps for Developers

1. **Clone and explore** the repository
2. **Run existing scans** to understand output
3. **Read CHECK_MATRIX.md** for complete check catalog
4. **Modify an existing check** to understand patterns
5. **Add a new check** following the Module Addition Checklist
6. **Contribute back** via pull request

### Support & Community

- **GitHub**: https://github.com/ssgrim/Bottleneck
- **Issues**: Report bugs or request features
- **Discussions**: Ask questions, share use cases
- **Pull Requests**: Contribute improvements

---

**Version**: 1.0 (Phase 1 Complete)
**Last Updated**: December 28, 2025
**Maintained By**: ssgrim & contributors

_This is a living document. As the framework evolves, this prompt will be updated to reflect new capabilities and best practices._
