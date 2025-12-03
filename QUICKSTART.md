# 🔍 Bottleneck Quick Reference

## Quick Commands

```powershell
# Full system scan (auto-elevates if needed)
pwsh -NoLogo -NoProfile
cd 'c:\Users\mrred\git\Bottleneck'
./scripts/run.ps1

# Include latest Wireshark capture (auto-picks newest in folder)
./scripts/run.ps1 -WiresharkDir '.\WireSharkLogs'

# Or target a specific capture file
./scripts/run.ps1 -WiresharkPath 'C:\Path\to\Scan 3.json'
```

## 🎯 Unified Workflow

The default scan runs all computer checks and generates a comprehensive HTML report. Optionally include Wireshark network analysis by pointing to your capture folder or file.

### Wireshark Integration

1. Run Wireshark to capture network traffic during slow performance
2. Export as JSON: File → Export Packet Dissections → As JSON
3. Run scan with capture: `./scripts/run.ps1 -WiresharkDir '.\WireSharkLogs'`
4. Report includes network summary: packets, drops, latency metrics

## What's Checked?

### 🎯 Quick Scan (6 checks)

- Storage space
- Power plan
- Startup programs
- Network latency
- RAM availability
- CPU load

### 🔍 Standard Scan (46 checks)

Everything in Quick, plus:

**Hardware & Performance:**

- CPU/GPU/System temperatures
- Fan speeds
- Battery health
- Disk SMART status
- CPU throttling
- Real-time CPU utilization (5s sampling)
- Memory utilization & leak detection
- Stuck/zombie processes
- Java heap monitoring

**System Health:**

- Windows updates
- Driver age
- OS age
- Service health
- Windows features
- Group policy issues

**Network:**

- DNS configuration
- Network adapter status
- Bandwidth usage
- VPN impact
- Firewall rules

**Security:**

- Antivirus health
- Windows Update status
- Security baseline
- Open ports
- Browser security

**User Experience:**

- Boot time analysis
- App launch performance
- UI responsiveness
- Performance trends

### 🚀 Deep Scan (52 checks)

Everything in Standard, plus:

- ETW (Event Tracing for Windows) analysis
- Full SMART disk diagnostics
- SFC/DISM system integrity
- Event log pattern analysis
- Background process audit
- Hardware upgrade recommendations

## Score Interpretation

| Score | Color     | Severity  | Action                |
| ----- | --------- | --------- | --------------------- |
| 0-10  | 🟢 Green  | Good      | No action needed      |
| 11-25 | 🟡 Yellow | Minor     | Monitor, optional fix |
| 26-45 | 🟠 Orange | Attention | Fix recommended       |
| 46+   | 🔴 Red    | Critical  | Fix immediately       |

**Score Formula:** `(Impact × Confidence) ÷ (Effort + 1)`

## Common Issues & Fixes

### 🔴 Low RAM (Score: 72)

```powershell
# Quick fix: Close memory-hungry apps
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5

# Long-term: Upgrade RAM
# Recommendation in report
```

### 🟠 High CPU Load (Score: 35)

```powershell
# Open Task Manager
Start-Process taskmgr

# Or check via PowerShell
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10
```

### 🟡 Power Plan Not Optimal (Score: 23)

```powershell
# Auto-fix available in report, or manually:
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
```

### 🟠 Disk Space Low (Score: 32)

```powershell
# Run Windows cleanup
cleanmgr /d C:

# Or use built-in fix from report
```

## Report Locations

Reports are automatically saved to 3 locations:

1. **Project folder:** `.\Reports\`
2. **Documents:** `%USERPROFILE%\Documents\ScanReports\`
3. **OneDrive:** `%OneDrive%\Documents\` (if available)

## AI Troubleshooting

High-impact issues (score > 5) include "Get AI Help" buttons that:

- Open ChatGPT, Copilot, or Gemini
- Pre-fill diagnostic context
- Request root cause analysis & fixes

## Performance Tips

**Faster Scans:**

- Run as Administrator (some checks skip without elevation)
- Close unnecessary applications
- Use Quick scan for rapid triage

**More Accurate Results:**

- Let system idle for 1-2 minutes before scanning
- Close monitoring tools (HWiNFO, etc.) during scan
- Run scans at consistent times for trend comparison

## Troubleshooting

### "Scripts are disabled"

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Some checks require admin privileges"

Right-click PowerShell 7 → "Run as Administrator"

### "No temperature sensors detected"

Normal for many systems. Install OpenHardwareMonitor or HWiNFO for sensor access.

### Event log errors

Expected on systems with limited logging or without admin rights.

## Advanced Usage

### Custom Scan

```powershell
Import-Module .\src\ps\Bottleneck.psm1
$results = Invoke-BottleneckScan
Invoke-BottleneckReport -Results $results
```

### Filter High-Impact Issues

```powershell
$results | Where-Object Impact -gt 7 | Format-Table Id, Message, Impact
```

### Sequential Mode (Debugging)

```powershell
$results = Invoke-BottleneckScan -Tier Standard -Sequential
```

### View Logs

```powershell
Get-Content .\Reports\bottleneck-$(Get-Date -Format 'yyyy-MM-dd').log -Tail 50
```

## System Requirements

- **OS:** Windows 10/11 (64-bit)
- **PowerShell:** 7.0+ ([Download](https://github.com/PowerShell/PowerShell/releases))
- **Admin Rights:** Recommended (not required for basic checks)
- **Disk Space:** ~50MB for installation + reports

## Need Help?

- 📖 Full docs: `README.md`
- 🐛 Report issues: GitHub Issues
- 💬 Discussions: GitHub Discussions
- 📋 Roadmap: `TODO.md`
- 🤝 Contributing: `CONTRIBUTING.md`

---

**Quick Start:** `.\scripts\run.ps1` → Open HTML report → Click "Get AI Help" for issues
