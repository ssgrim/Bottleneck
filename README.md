# 🔍 Bottleneck - Professional Windows Performance Diagnostics

A comprehensive Windows performance diagnostic and repair tool designed for IT professionals and power users. Automatically scans for common bottlenecks and provides actionable fixes with AI-powered troubleshooting assistance.

## ✨ Features

### 🎯 Unified Scan

- **Full System Scan** runs all computer checks by default and generates a full HTML report.
- Optional **Wireshark Analysis**: pass a capture file or folder to include network summary (packets, drops, latency).

### 📊 Professional Reporting

- **HTML Reports** with executive summary and color-coded severity scoring
- **Smart Recommendations Engine** with priority categorization (Critical/High/Medium/Low)
- **AI Troubleshooting Integration** - One-click help via ChatGPT, Copilot, or Gemini with pre-filled diagnostic context
- **Historical Comparison** - Track performance trends over time
- **Multi-Location Saving** - Reports auto-saved to Documents, OneDrive, and project folder

### 🛠️ Built-in Fixes

- Power plan optimization
- Disk cleanup and defragmentation
- Memory diagnostics
- Service restart automation
- One-click fixes with confirmation prompts

### ⚡ Performance Optimizations

- **CIM Query Caching** - Eliminates redundant WMI queries (2-3s savings)
- **Timeout Protection** - Prevents event log query hangs with 10-15s limits
- **Comprehensive Logging** - DEBUG/INFO/WARN/ERROR levels with timing metrics
- **Admin Rights Detection** - Warns users when elevated privileges are needed

## 📋 Requirements

- **OS**: Windows 10/11 (64-bit)
- **PowerShell**: 7.0 or higher ([Download here](https://github.com/PowerShell/PowerShell/releases))
- **Admin Rights**: Recommended for full functionality (some checks work without elevation)
- **Optional**: OpenHardwareMonitor or HWiNFO for advanced temperature/fan speed monitoring

## 🚀 Quick Start

### Installation

1. **Install PowerShell 7+** (if not already installed):

   ```powershell
   winget install Microsoft.PowerShell
   ```

2. **Clone or download this repository**:

   ```powershell
   git clone https://github.com/yourusername/bottleneck.git
   cd bottleneck
   ```

3. **Run as Administrator** (right-click PowerShell 7, "Run as Administrator"):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Usage

### Basic Scan

Run the full system scan (auto-elevates to admin if needed):

```powershell
pwsh -NoLogo -NoProfile
cd 'c:\Users\mrred\git\Bottleneck'
./scripts/run.ps1
```

### With Wireshark Analysis

Include network analysis from your latest Wireshark capture (auto-picks newest `.json`, `.pcapng`, or `.csv`):

```powershell
./scripts/run.ps1 -WiresharkDir '.\WireSharkLogs'
```

Or target a specific capture file:

```powershell
./scripts/run.ps1 -WiresharkPath 'C:\Path\to\Scan 3.json'
```

**Note:** For `.pcapng` files, export to JSON from Wireshark (File → Export Packet Dissections → As JSON) or ensure `tshark` is in PATH.

## Export Logs

- VS Code task: Run `Collect Bottleneck logs` to bundle the latest network monitor outputs and reports into a timestamped zip under `Reports/`.
- PowerShell:
  - Latest of each type:
    - `pwsh -NoLogo -NoProfile -Command "Push-Location '$PWD'; & scripts/collect-logs.ps1; Pop-Location"`
  - Include everything:
    - `pwsh -NoLogo -NoProfile -Command "Push-Location '$PWD'; & scripts/collect-logs.ps1 -IncludeAll; Pop-Location"`
  - Custom directories:
    - `pwsh -NoLogo -NoProfile -Command "Push-Location '$PWD'; & scripts/collect-logs.ps1 -ReportsDirs @('.\\Reports','.\\bottleneck\\Reports') -IncludeAll; Pop-Location"`

The resulting zip (e.g., `Reports/bottleneck-logs-YYYY-MM-DD_HH-MM-SS.zip`) is ignored by git and ready to share for analysis.

### Notes

- **Legacy scripts removed**: Tier-based scripts (`run-quick.ps1`, `run-standard.ps1`, etc.) and built-in network monitoring have been retired.
- **Wireshark integration**: Use Wireshark for network captures and include them in your scan via `-WiresharkDir` or `-WiresharkPath`.
- **Default behavior**: Running `./scripts/run.ps1` with no parameters executes a full system scan.

### Manual Module Usage

```powershell
# Import the module
Import-Module .\src\ps\Bottleneck.psm1

# Run a scan
$results = Invoke-BottleneckScan -Tier Standard

# Generate HTML report
Invoke-BottleneckReport -Results $results -Tier Standard

# View specific check results
$results | Where-Object Impact -gt 6 | Format-Table Id, Message, Impact
```

## 📁 Project Structure

```
bottleneck/
├── src/ps/                      # PowerShell source modules
│   ├── Bottleneck.psm1         # Main module entry point
│   ├── Bottleneck.Checks.ps1   # Core diagnostic checks
│   ├── Bottleneck.Report.ps1   # HTML report generation
│   ├── Bottleneck.Performance.ps1  # CIM caching & timeout wrappers
│   ├── Bottleneck.Logging.ps1  # Logging framework
│   ├── Bottleneck.SystemPerformance.ps1  # CPU/Memory/Fan/Temp monitoring
│   └── [20+ specialized modules]
├── scripts/                     # Convenience scripts
│   ├── run.ps1                  # Unified entry script
│   └── [deprecated] legacy helpers
├── Reports/                     # Scan reports & logs
├── docs/                        # Documentation
├── tests/                       # Test files
├── README.md                    # This file
├── TODO.md                      # Roadmap & task tracking
└── LICENSE                      # MIT License
```

## 🎨 Sample Output

```
Quick Scan Results:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Storage: Disk space OK (245.3 GB free)
⚠️  PowerPlan: Consider High Performance mode
✅ Startup: 8 startup items (normal)
✅ Network: Latency 23ms (normal)
🔴 RAM: Low available RAM (1.8 GB free)
✅ CPU: Load 24% (normal)

📊 Report saved to:
   C:\Users\username\Documents\ScanReports\Basic-scan-2025-11-29_15-42-16.html
```

## 🤖 AI Troubleshooting

For high-impact issues (score > 5), reports include "Get AI Help" buttons that automatically:

1. Open your preferred AI assistant (ChatGPT, Copilot, Gemini)
2. Pre-fill a diagnostic prompt with:
   - Issue description and evidence
   - System information
   - Request for root cause analysis, troubleshooting steps, and fixes

## 🔧 Extending Bottleneck

### Adding a New Check

1. Create a check function in the appropriate module (or create a new one):

```powershell
function Test-BottleneckMyCheck {
    # Your diagnostic logic
    $issue = Get-SomeData

    return New-BottleneckResult `
        -Id 'MyCheck' `
        -Tier 'Standard' `
        -Category 'My Category' `
        -Impact 7 `
        -Confidence 8 `
        -Effort 2 `
        -Priority 3 `
        -Evidence "Found $issue" `
        -FixId 'MyFix' `
        -Message "Issue detected: $issue"
}
```

2. Add to `Bottleneck.Checks.ps1` in the appropriate tier:

```powershell
$standard = $quick + @(
    # ... existing checks ...
    'Test-BottleneckMyCheck'
)
```

3. Add recommendations to `Bottleneck.Report.ps1`:

```powershell
'MyCheck' { $recommendedSteps = 'Your fix instructions here.' }
```

## 🐛 Troubleshooting

### "Scripts are disabled on this system"

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Some checks require administrator privileges"

Right-click PowerShell 7 and select "Run as Administrator" for full functionality.

### "No fan sensors detected"

This is normal for many systems. Install [OpenHardwareMonitor](https://openhardwaremonitor.org/) or [HWiNFO](https://www.hwinfo.com/) for detailed sensor monitoring.

### Event log errors

Some event log queries may fail without admin rights or on systems with limited logging enabled. This is expected behavior.

## 📊 Performance Notes

- **Quick Scan**: ~13 seconds (varies by system)
- **Standard Scan**: ~51 seconds (recommended for most users)
- **Deep Scan**: ~90 seconds (includes intensive diagnostics)
- **CIM Caching**: Reduces redundant queries by 2-3 seconds
- **Timeout Protection**: Prevents event log hangs (10-15s limits)

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-check`)
3. Commit your changes (`git commit -m 'Add amazing check'`)
4. Push to the branch (`git push origin feature/amazing-check`)
5. Open a Pull Request

See `TODO.md` for planned features and priorities.

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with PowerShell 7+ and modern Windows management APIs
- Inspired by professional IT diagnostic tools and best practices
- Community feedback and contributions

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/bottleneck/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/bottleneck/discussions)
- **Documentation**: See `docs/` folder for detailed architecture and design docs

---

**Made with ❤️ for IT professionals and power users who want their systems running at peak performance.**
\n\n## Phase 6: Advanced Alert Fusion\nSee PHASE6-PLAN.md for objectives and usage.
