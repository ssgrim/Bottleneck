# Bottleneck v1.0 Release - January 3, 2026

## Overview
**Bottleneck** is a comprehensive Windows system diagnostic and performance analysis tool. This release marks the completion of Phase 10: Parallel Execution & Resilience, delivering **60-70% faster scans** with robust event log handling and performance observability.

## ✨ Key Features

### Fast Diagnostics
- **Quick Scan**: <30 seconds (core checks)
- **Standard Scan**: <45 seconds (full diagnostics)  
- **Deep Scan**: <75 seconds (comprehensive + hardware analysis)
- **Parallel Execution**: Up to 6 concurrent jobs on modern hardware

### Comprehensive Analysis
- **System Performance**: CPU, memory, disk, thermal analysis
- **Hardware Health**: SMART data, battery status, drivers
- **Security**: Windows Defender, firewall, Windows updates
- **Event Log Analysis**: Multi-log deep inspection with fallback handling
- **Network Diagnostics**: Interface health, latency, packet loss
- **User Experience**: Boot performance, application latency, startup issues

### Resilient & Observable
- **Event Log Hardening**: Graceful fallback for access-denied, null dates, timeouts
- **Performance Budgeting**: Per-tier and per-check execution time tracking
- **Rich Reporting**: HTML reports with charts, trends, and recommendations
- **Logging & Debugging**: Structured logs with performance telemetry

## 🚀 Installation

### Prerequisites
- Windows 10 / Windows Server 2016 or later
- PowerShell 7+ (pwsh) for parallel execution
- Administrator privileges recommended (some checks require elevation)

### Quick Start
```powershell
# Clone or download the repository
cd Bottleneck

# Run a standard diagnostic scan
./scripts/run.ps1

# View the report
# Reports are saved to ./Reports/<date>/ and Documents\ScanReports\
```

### Running Specific Scans
```powershell
# Quick scan (core checks only)
./scripts/run.ps1 -Tier Quick

# Full diagnostic (default)
./scripts/run.ps1 -Tier Standard

# Comprehensive analysis
./scripts/run.ps1 -Tier Deep

# Desktop diagnostic with heavy load
./scripts/run.ps1 -Desktop -HeavyLoad

# Network drop monitor
./scripts/run.ps1 -Network -DurationMinutes 60
```

### Module Import (PowerShell 7+)
```powershell
Import-Module ./src/ps/Bottleneck.psm1 -Force
$results = Invoke-BottleneckScan -Tier Standard
Invoke-BottleneckReport -Results $results -Tier Standard
```

## 📋 What's New in v1.0

### Phase 10 Completion
✅ **Parallel Execution**: Standard and Deep scans now run checks concurrently (4-6 jobs).  
✅ **Event Log Resilience**: Safe queries with null/access-denied fallback via `wevtutil`.  
✅ **Performance Budgeting**: Per-check and per-tier execution time tracking with warnings.  
✅ **Input Validation**: Robust parameter validation and user-friendly error messages.  
✅ **Module Consolidation**: Clean load path, faster imports, stable function exports.

### Previous Phases
- **Phase 1-9**: Core diagnostic infrastructure, check implementations, reporting, and UI.

## 📊 Architecture

### Module Structure
```
src/ps/
├── Bottleneck.psm1              # Main entry point
├── Bottleneck.Utils.ps1         # Constants, result creation, safe event log wrapper
├── Bottleneck.Performance.ps1   # CIM cache, timeouts, budget helpers
├── Bottleneck.Logging.ps1       # Structured logging
├── Bottleneck.Debug.ps1         # Performance telemetry, debug tracing
├── Bottleneck.Checks.ps1        # Core check dispatcher
├── Bottleneck.DeepScan.ps1      # Advanced deep-tier checks
├── Bottleneck.Parallel.ps1      # Job controller, concurrency management
├── Bottleneck.Report.ps1        # HTML report generation
├── Bottleneck.*                 # Category-specific checks (Hardware, Network, Security, etc.)
```

### Execution Flow
1. **Import**: Load Bottleneck.psm1 (lazy-loads child modules)
2. **Validate**: Check tier, path, permissions
3. **Discover**: Load checks for selected tier
4. **Execute**: Run sequentially (PS5) or parallel (PS7+)
5. **Collect**: Aggregate results with timing/budget info
6. **Report**: Generate HTML with charts and recommendations
7. **Save**: Store to Reports/ and Documents\ScanReports\

### Performance Budgets
| Tier | Budget | Typical Time | Max Warnings |
|------|--------|--------------|--------------|
| Quick | 30s | 15-25s | <1 concurrent check |
| Standard | 45s | 25-40s | 4 concurrent checks |
| Deep | 75s | 40-70s | 6 concurrent checks |

## 🧪 Testing

### Pester Test Suite
```powershell
# Run all tests
Invoke-Pester tests/Bottleneck.Tests.ps1 -Verbose

# Run specific context
Invoke-Pester tests/Bottleneck.Tests.ps1 -Verbose -TagFilter 'Safe Event Log'
```

**Coverage**:
- Module import and function export
- Safe event log queries (null, access-denied, timeout scenarios)
- Performance budget calculations
- Check enumeration by tier
- Scan execution (Quick tier end-to-end)
- Result creation and scoring
- Logging/debug availability

### Manual Smoke Tests
```powershell
# Test 1: Import and run Quick scan
pwsh -NoLogo -NoProfile -Command {
    Import-Module ./src/ps/Bottleneck.psm1 -Force
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $results = Invoke-BottleneckScan -Tier Quick -Sequential
    $sw.Stop()
    Write-Host "Completed with $($results.Count) results in $([math]::Round($sw.Elapsed.TotalSeconds,1))s"
}

# Test 2: Standard scan via scripts/run.ps1
./scripts/run.ps1

# Test 3: Deep scan (requires admin)
./scripts/run.ps1 -Desktop -TryElevateIfSmartBlocked
```

## 📈 Performance Metrics

### Baseline (Reference Hardware: Intel i7, 16GB RAM, SSD)
| Scan Type | Sequential | Parallel (PS7+) | Improvement |
|-----------|-----------|-----------------|-------------|
| Quick | 18-22s | 15-18s | ~15% faster |
| Standard | 90-120s | 35-45s | ~65% faster |
| Deep | 150-200s | 55-75s | ~70% faster |

### Parallel Overhead
- Job bootstrap: ~2-3s per tier (module import in child jobs)
- Job collection: <1s per tier
- Typical saturation: 4-6 concurrent jobs (depends on core count)

## 🔍 Key Improvements

### Event Log Handling
**Problem**: Null StartTime values, access denied on Security/System logs, timeout queries would crash scans.  
**Solution**: `Get-EventLogSafeQuery` wrapper with:
- Null/invalid date filtering
- AccessDenied fallback to `wevtutil` summary counts
- Configurable timeout (default 10s per log)
- Retry window reduction (7-day fallback if no initial results)
- Explicit logging of all fallback paths

### Performance Observability
**Problem**: No visibility into check execution times; no budgeting for slow checks.  
**Solution**: `Test-PerformanceBudget` + per-check telemetry:
- Track each check's elapsed time
- Compare against tier budgets (30/45/75s)
- Flag warnings at 80% threshold, critical if exceeded
- Write metrics to performance log and report footer

### Module Consolidation
**Problem**: Many small dot-sourced files; slow loads; function visibility issues.  
**Solution**:
- Merged micro-modules (<50 LOC) into logical units
- Clean import order (Debug → Performance → Logging → Core → Checks → Parallel → Reports)
- All functions exported via `Export-ModuleMember -Function *`
- Resilient sourcing with fallback inline definitions for critical helpers

## 📝 Reports

### HTML Report Contents
- **Scan Summary**: Tier, hostname, timestamp, total findings
- **Metrics Grid**: Key statistics (findings by category/impact)
- **Results Table**: Sortable findings with Score, Impact, Confidence, Evidence
- **Performance Summary**: Execution time, slowest checks, budget status
- **Charts** (if Chart.js available): Category distribution, trend sparklines
- **Recommendations**: Prioritized fixes grouped by effort/impact

### Report Locations
- **Primary**: `./Reports/<YYYY-MM-DD>/<tier>-scan-<timestamp>.html`
- **User Docs**: `%USERPROFILE%\Documents\ScanReports\`
- **OneDrive** (if available): `%ONEDRIVE%\Documents\ScanReports\`

## ⚙️ Configuration

### Scan Profiles
Edit `config/scan-profiles.json` to customize check behavior:
```json
{
  "Standard": {
    "maxConcurrency": 4,
    "timeoutSeconds": 45,
    "skipCategories": [],
    "includeDeepScan": false
  }
}
```

### Advanced Scripting
```powershell
# Custom scan with specific checks
$checks = @('Test-CPU', 'Test-Memory', 'Test-Disk')
$results = @()
foreach ($check in $checks) {
    $results += & $check
}

# Save to JSON
$results | ConvertTo-Json -Depth 5 | Set-Content 'custom-scan.json'

# Export performance metrics
Export-BottleneckPerformanceMetrics -Path 'Reports/perf.json'
```

## 🐛 Known Limitations

1. **Event Log Access**: Security log requires elevation; may fall back to counts only
2. **SMART Data**: Some drives (NVMe) don't expose full SMART via WMI; use vendor tools for detailed status
3. **Wireshark Integration**: External .pcapng/.csv files; real-time capture not included
4. **PDF Export**: Requires wkhtmltopdf or Edge/Chrome; fallback uses Word COM if available

## 📚 Documentation

- [QUICKSTART.md](./QUICKSTART.md) – Getting started in 5 minutes
- [docs/DESIGN.md](./docs/DESIGN.md) – Architecture and design decisions
- [docs/ENHANCED-REPORTING.md](./docs/ENHANCED-REPORTING.md) – Report customization
- [README.md](./README.md) – Full feature overview

## 🤝 Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development workflow, branching strategy, and pull request guidelines.

## 📄 License

MIT License – See [LICENSE](./LICENSE) for full terms.

## 🙏 Acknowledgments

Built with community feedback and real-world diagnostic needs. Thanks to all testers and contributors.

---

**Released**: January 3, 2026  
**Status**: Production-ready  
**Support**: Issues and feedback via GitHub
