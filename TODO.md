# TODO List

## Completed ✅

- [x] Quick Scan MVP (6 basic checks)
- [x] Standard Scan expansion (46 checks total)
  - [x] Phase 1: Hardware monitoring (thermal, battery, disk, memory, CPU throttle)
  - [x] Phase 2: Software health (services, Windows features)
  - [x] Phase 3: Network diagnostics (DNS, adapters, bandwidth, VPN, firewall)
  - [x] Phase 4: Security baseline (antivirus, updates, ports, browser security)
  - [x] Phase 5: User experience (boot time, app launch, UI responsiveness, trends)
- [x] Deep Scan tier (52 checks total)
  - [x] Phase 6: Advanced diagnostics (ETW tracing, full SMART, SFC/DISM, event logs, background processes, hardware recommendations)
- [x] Phase 7: Historical trend analysis & dashboard integration
  - [x] JSON-based history database with scan storage and retrieval
  - [x] Trend analysis for performance metrics over time
  - [x] Export functions for Grafana and InfluxDB dashboards
  - [x] Historical trend reporting
  - [x] Grafana dashboard templates (System Health, Network Quality, Performance Trends)
- [x] HTML report generation with color-coded scoring
- [x] Smart recommendations engine
- [x] Multi-location report saving (Reports/, Documents/, OneDrive/)
- [x] Historical comparison and trend analysis
- [x] Network monitoring tool for long-running connectivity diagnostics
- [x] Professional system performance monitoring
  - [x] Real-time CPU utilization (5-second sampling)
  - [x] Memory utilization with leak detection
  - [x] Fan speed monitoring
  - [x] System temperature monitoring (CPU/GPU/Motherboard/Storage)
  - [x] Stuck/zombie process detection
  - [x] Java heap utilization monitoring
- [x] Performance optimizations
  - [x] CIM query caching (Win32_OperatingSystem, Win32_Processor)
  - [x] Event log timeout protection (10-15s limits)
  - [x] Logging framework with DEBUG/INFO/WARN/ERROR levels
  - [x] Admin rights detection with warnings
- [x] Dynamic path resolution (no hardcoded C:\, OneDrive detection)
- [x] AI troubleshooting integration
  - [x] "Get AI Help" buttons for high-impact issues
  - [x] Pre-filled prompts for ChatGPT, Copilot, Gemini
  - [x] Context includes issue ID, evidence, message, system info

## In Progress 🔄

- [ ] Phase 8: Automated Remediation Engine
  - [x] Core remediation framework (FixRegistry, execution engine)
  - [x] Safety features (approval workflow, rollback, restore points)
  - [x] 10 built-in fixes covering Performance, Network, Security, Maintenance
    - DNS cache flush, disk cleanup, network adapter reset
    - Power plan optimization, DNS server optimization
    - Windows Defender update, Windows Update cache clear
    - TCP/IP stack reset, startup program optimization
    - Event log cleanup
  - [x] Fix execution history tracking with JSON logging
  - [ ] HTML report integration with "Apply Fix" buttons
  - [ ] Integration with main diagnostic workflow

- [ ] Parallel execution implementation (using Start-ThreadJob for PS7+)
  - [x] Updated to use Start-ThreadJob instead of Start-Job for better module function access
  - [ ] Test parallel execution performance improvement
  - [ ] Validate all check functions work in parallel threads

## High Priority 📌

- [ ] Fix remaining event log issues
  - [ ] Handle null StartTime in Get-WinEvent FilterHashtable
  - [ ] Add more robust error handling for event log access denied scenarios
- [ ] Module consolidation
  - [ ] Merge small modules (< 50 lines) into logical groupings
  - [ ] Reduce dot-sourcing overhead from 20+ files
- [ ] Parameter validation
  - [ ] Add [ValidateNotNullOrEmpty()] to all file path parameters
  - [ ] Validate timeout values (min 5s, max 300s)
  - [ ] Validate report tier values

## Medium Priority 🔧

- [x] Trend visualization enhancements
  - [x] Add charts/graphs to HTML report (Chart.js integration)
  - [ ] Show performance degradation over time
  - [ ] Highlight metrics that are worsening
- [ ] Additional fix implementations
  - [ ] Auto-optimize power plan based on usage pattern
  - [ ] Automated disk cleanup with user approval
  - [ ] Driver update recommendations with download links
- [ ] Enhanced network monitoring
  - [ ] Add traceroute diagnostics
  - [ ] Identify bandwidth-hogging processes
  - [ ] ISP outage detection
- [ ] PDF export improvements
  - [ ] Native PDF generation (remove Edge dependency)
  - [ ] Include embedded charts in PDF

## Low Priority 💡

- [ ] GUI interface (Windows Forms or WPF)
- [ ] Scheduled scan automation (Task Scheduler integration)
- [ ] Email report delivery
- [ ] Cloud backup of scan history
- [ ] Multi-language support (i18n)
- [ ] MacOS/Linux compatibility layer

## Technical Debt 🔨

- [ ] Replace -ErrorAction SilentlyContinue with proper try/catch blocks
- [ ] Add unit tests for core check functions
- [ ] Add integration tests for report generation
- [ ] Document all public functions with proper comment-based help
- [ ] Add Pester test framework
- [ ] CI/CD pipeline (GitHub Actions)

## Future Enhancements 🚀

- [ ] Machine learning anomaly detection
- [ ] Predictive failure analysis
- [ ] Community check repository
- [ ] Plugin architecture for third-party checks
- [ ] RESTful API for remote diagnostics
- [ ] Mobile app for scan results viewing

## Notes 📝

- **Performance**: Standard scan currently ~51s, Deep scan ~90s (varies by system)
- **Compatibility**: Requires PowerShell 7+, Windows 10/11
- **Admin Rights**: Many checks require elevation for full diagnostics
- **Sensor Support**: Fan speed and temperature monitoring requires compatible hardware/drivers or OpenHardwareMonitor
