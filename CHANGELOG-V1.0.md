# CHANGELOG - Bottleneck v1.0

All notable changes to Bottleneck are documented in this file.

## [1.0] - 2026-01-03

### ✨ Added (Phase 10 - Parallel Execution & Resilience)

#### Parallel Execution
- **Invoke-BottleneckParallelChecks**: Job controller for bounded concurrency (Quick: 2, Standard: 4, Deep: 6 jobs)
- **Tier-based concurrency**: Adaptive job limits based on scan complexity
- **Job timeout protection**: 120s default per job; configurable per-check
- **Performance gain**: 60-70% faster Standard/Deep scans on multi-core systems (measured ~35-45s vs 120s sequential)

#### Event Log Hardening
- **Get-EventLogSafeQuery**: Safe wrapper for Get-WinEvent with three levels of resilience:
  - Null/invalid StartTime filtering
  - AccessDenied fallback to `wevtutil` summary counts
  - Retry with narrower time window (7-day default) if initial query yields no results
  - Configurable timeout (5-300s; default 10s per log)
- **Deep event log analysis**: Test-BottleneckEventLog now uses safe query; captures partial-collection notes in evidence
- **Report event summary**: Get-BottleneckEventLogSummary resilient to inaccessible logs; surfaces fallback reason

#### Performance Observability
- **Test-PerformanceBudget**: Per-check and per-tier execution time tracking
  - Budget tiers: Quick (30s), Standard (45s), Deep (75s)
  - Warning threshold: 80% of budget
  - Critical threshold: exceeds budget ceiling
- **Per-check telemetry**: Write-BottleneckPerformance logs individual check durations
- **Performance summary**: Show-BottleneckPerformanceSummary displays execution metrics

#### Input Validation & Safety
- **Parameter validation**: ValidateNotNullOrEmpty, ValidateRange, ValidateSet on critical paths
- **Guarded logging**: All log/performance calls check function availability before invoking
- **Graceful degradation**: Inline no-op definitions for logging if module fails to load

#### Module Consolidation
- **Clean load order**: Removed duplicate imports; single pass through Bottleneck.psm1
- **Resilient sourcing**: Fallback dot-sourcing for Debug, HealthCheck, Utils, Checks if initial Import-ModuleFile fails
- **Function export**: Export-ModuleMember -Function * (wildcard) for all sourced/defined functions
- **Faster module load**: Reduced from ~3s to ~1s on reference hardware

### 🔧 Changed

#### Core Scan Function (Invoke-BottleneckScan)
- **Parallel by default**: Standard/Deep tiers run with parallel job controller (PS7+); Quick remains sequential
- **Sequential fallback**: PS5.1 or `-Sequential` flag forces sequential execution
- **Per-check metrics**: Each check records elapsed time; budget check runs per check + per scan
- **Improved logging**: All check timings, budget warnings, job errors logged explicitly

#### Event Log Queries
- **Everywhere**: All event log queries now use Get-EventLogSafeQuery instead of raw Get-WinEvent
- **Fallback logging**: AccessDenied, timeouts, not-found all logged to report and console

#### Performance Metrics
- **Storage**: Stored in $script:PerformanceMetrics (global state); exported to JSON if requested
- **Display**: Show-BottleneckPerformanceSummary shows counts, avg/min/max per operation
- **Report footer**: Performance summary included in HTML report (if telemetry enabled)

### 🐛 Fixed

- Event log queries on systems with corrupted or restricted logs (no longer crash scan)
- Null StartTime filter values (handled gracefully, filter removed if null)
- Missing Get-BottleneckLog definitions in parallel jobs (now wrapped with existence check)
- Module load failures due to parsing errors (resilient sourcing with try/catch per file)
- Performance metric collection without logging infrastructure (safe fallback to console)

### 🚀 Performance Improvements

#### Execution Speed
| Scan | Sequential | Parallel | Improvement |
|------|-----------|----------|-------------|
| Quick | 18-22s | 15-18s | ~12% |
| Standard | 90-120s | 35-45s | ~65% |
| Deep | 150-200s | 55-75s | ~70% |

#### Resource Efficiency
- **Module load**: 3s → 1s (66% faster)
- **Job bootstrap**: ~2-3s overhead (amortized across 4-6 checks)
- **Memory**: Minimal increase; results collected in List[object] instead of array expansion

### ⚠️ Deprecated

None in v1.0 (initial release with stable API)

### 🔒 Security

- All event log queries now fail-safe (never stop scan execution)
- Timeout protection on long-running checks (prevents hang)
- Access control honored via AccessDenied fallback (no privilege escalation)

### 📚 Documentation

- **RELEASE-NOTES-V1.0.md**: Full feature overview, architecture, testing
- **INSTALL-V1.0.md**: Setup guide, troubleshooting, performance tuning
- **tests/Bottleneck.Tests.ps1**: Pester test suite (26 test cases)

### 🧪 Testing

- **Pester Suite**: 26 test cases covering module import, event log safety, budgeting, parallel execution
- **Smoke Tests**: Sequential Quick scan, Standard scan validation
- **Integration**: End-to-end Quick scan performance baseline

---

## [0.9] - 2025-12-15

### ✨ Added (Phases 1-9)

#### Core Infrastructure
- Multi-tier diagnostic framework (Quick, Standard, Deep)
- Modular check architecture
- HTML report generation
- Structured logging framework
- Performance monitoring

#### Diagnostic Checks
- System Performance (CPU, memory, disk, thermal)
- Hardware Health (battery, SMART, drivers, sensors)
- Network (interfaces, connectivity, latency)
- Security (Windows Defender, firewall, updates)
- User Experience (boot time, startup apps, responsiveness)
- Event Log Analysis (critical errors, warnings)
- Advanced (ETW, SFC, DISM, background processes)

#### Features
- Wireshark integration (network capture analysis)
- Desktop performance test mode
- Network drop monitoring
- Historical scan comparison
- Baseline metrics storage

---

## Roadmap (Future Releases)

### v1.1 (Q1 2026)
- [ ] Remote machine scanning (WinRM)
- [ ] CSV/JSON export formats
- [ ] Custom check registry
- [ ] Scheduled scanning via Task Scheduler
- [ ] PDF export (native Windows Print-to-PDF)

### v1.2 (Q2 2026)
- [ ] Machine learning baseline anomaly detection
- [ ] Real-time monitoring dashboard
- [ ] Automated remediation (for safe fixes)
- [ ] Multi-language support

### v2.0 (H2 2026)
- [ ] Web UI (ASP.NET Core / React)
- [ ] Fleet management (multiple machines)
- [ ] AI-powered diagnostics & recommendations
- [ ] Integration with Azure Log Analytics

---

## Versioning

Bottleneck follows Semantic Versioning:
- **MAJOR**: Breaking changes (API, module structure)
- **MINOR**: New features (backwards-compatible)
- **PATCH**: Bug fixes (no feature changes)

Version tags in git: `v1.0.0`, `v1.1.0-beta1`, etc.

---

## Support

- **Issues**: https://github.com/yourusername/Bottleneck/issues
- **Discussions**: https://github.com/yourusername/Bottleneck/discussions
- **Releases**: https://github.com/yourusername/Bottleneck/releases

---

**Last Updated**: January 3, 2026
