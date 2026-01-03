# Bottleneck v1.0 Installation & Setup Guide

## System Requirements

- **OS**: Windows 10 / Windows Server 2016 or later
- **PowerShell**: 5.1 (basic support) or **7+ (recommended for parallel execution)**
- **Disk Space**: ~50 MB (tool + reports)
- **RAM**: 2 GB minimum; 4+ GB recommended
- **Permissions**: Standard user for most checks; administrator for full SMART/security logs

## Installation Steps

### Option A: Clone from Repository (Developers)
```powershell
git clone https://github.com/yourusername/Bottleneck.git
cd Bottleneck
./scripts/run.ps1
```

### Option B: Download Release ZIP (End Users)
1. Download `Bottleneck-v1.0.zip` from Releases
2. Extract to `C:\Tools\Bottleneck\` (or preferred location)
3. Open PowerShell 7+:
   ```powershell
   cd C:\Tools\Bottleneck
   ./scripts/run.ps1
   ```

### Option C: Install as Module (PowerShell 7+)
```powershell
# Copy module to system module path
Copy-Item -Recurse Bottleneck\src\ps -Destination $PROFILE\..\Modules\Bottleneck -Force

# Import in any PowerShell session
Import-Module Bottleneck
$results = Invoke-BottleneckScan -Tier Standard
```

## First Run

### Quick Test (2-3 minutes)
```powershell
cd c:\path\to\Bottleneck
./scripts/run.ps1 -Tier Quick
```
✅ **What to expect**: Scan completes, opens HTML report in default browser

### Full Diagnostic (5-10 minutes)
```powershell
./scripts/run.ps1 -Tier Standard
```
✅ **What to expect**: Comprehensive scan with detailed findings, performance metrics

### Desktop Performance Test (10-15 minutes)
```powershell
./scripts/run.ps1 -Desktop -Html -HeavyLoad
```
✅ **What to expect**: Sustained load test with before/after system metrics

## Configuration

### Run.ps1 Parameters
```powershell
# Tier selection
-Tier Quick|Standard|Deep        # Scan depth (default: Standard)

# Execution mode
-Sequential                      # Force sequential (default: parallel on PS7+)
-Desktop                         # Desktop diagnostic mode
-Network                         # Network drop monitor

# Options
-Debug                           # Enable debug logging
-Verbose                         # Detailed output
-Html                            # Force HTML report generation (default: on)
-Elevate                         # Prompt for admin if needed

# Examples:
./scripts/run.ps1 -Tier Deep -Debug
./scripts/run.ps1 -Desktop -TryElevateIfSmartBlocked
./scripts/run.ps1 -Network -DurationMinutes 60
```

### Scan Profiles
Edit `config/scan-profiles.json` to customize behavior:
```json
{
  "Quick": {
    "maxConcurrency": 2,
    "timeoutSeconds": 30,
    "skipCategories": ["ETW", "DISM", "FullSMART"],
    "includeDeepScan": false
  },
  "Standard": {
    "maxConcurrency": 4,
    "timeoutSeconds": 45,
    "skipCategories": [],
    "includeDeepScan": false
  },
  "Deep": {
    "maxConcurrency": 6,
    "timeoutSeconds": 75,
    "skipCategories": [],
    "includeDeepScan": true
  }
}
```

## Reports

### Where Are They Saved?
- **Local**: `.\Reports\<YYYY-MM-DD>\<tier>-scan-<timestamp>.html`
- **User Documents**: `%USERPROFILE%\Documents\ScanReports\`
- **OneDrive**: `%ONEDRIVE%\Documents\` (if available)

### Opening a Report
```powershell
# Auto-opens in default browser; or manually:
Start-Process "Reports\2026-01-03\standard-scan-2026-01-03_14-30-45.html"

# Or search for recent reports:
Get-ChildItem Reports -Recurse -Filter *.html | Sort-Object LastWriteTime -Desc | Select-Object -First 1
```

### Report Contents
- **Summary**: Total findings, top categories, risk assessment
- **Results Table**: Sortable by Impact, Score, Category
- **Performance**: Execution time, slowest checks, budget status
- **Recommendations**: Prioritized fixes with effort/impact estimates
- **Charts**: Category distribution, historical trends (if available)

## Troubleshooting

### Issue: "Module import failed"
**Cause**: PowerShell 5.1 or older; missing dependencies  
**Solution**:
```powershell
# Check version
$PSVersionTable.PSVersion

# Update to PowerShell 7
winget install --id Microsoft.PowerShell

# Or download from: https://github.com/PowerShell/PowerShell/releases
```

### Issue: "Access Denied to event log"
**Cause**: Security log requires admin rights  
**Solution**:
```powershell
# Run as Administrator
# Right-click PowerShell → Run as administrator

# Or use UAC elevation flag:
./scripts/run.ps1 -Elevate
```

### Issue: "Scan times out or hangs"
**Cause**: Heavy system load, slow drives, or blocking I/O  
**Solution**:
```powershell
# Force sequential execution (slower but more reliable)
./scripts/run.ps1 -Tier Standard -Sequential

# Reduce timeout and skip Deep checks
./scripts/run.ps1 -Tier Quick
```

### Issue: "No report generated"
**Cause**: Report path missing or permission denied  
**Solution**:
```powershell
# Check Reports directory exists
New-Item -Path Reports -ItemType Directory -Force

# Verify permissions on Documents folder
icacls $env:USERPROFILE\Documents

# Try alternate location
./scripts/run.ps1 -ReportPath "C:\Temp\Reports"
```

### Issue: "Event log collection failed"
**Cause**: Corrupted or inaccessible logs  
**Solution**: Normal behavior; event log helper will:
- Try narrower time window (7-day fallback)
- Fall back to summary count via `wevtutil`
- Log all fallback steps in results

## Performance Tuning

### For Older Hardware (HDD, <4GB RAM)
```powershell
# Use Quick tier with sequential execution
./scripts/run.ps1 -Tier Quick -Sequential

# Increase timeouts
$env:BottleneckTimeoutSeconds = 30
./scripts/run.ps1 -Tier Standard
```

### For Modern Hardware (SSD, 16+ GB RAM)
```powershell
# Deep tier with parallel execution (default on PS7+)
./scripts/run.ps1 -Tier Deep

# Monitor performance
./scripts/run.ps1 -Tier Deep -Debug
```

## Advanced Usage

### Import as Module (PowerShell 7+)
```powershell
Import-Module .\src\ps\Bottleneck.psm1 -Force

# Run custom scans
$results = Invoke-BottleneckScan -Tier Standard
$results = Get-BottleneckChecks -Tier Standard | Select-Object -First 5

# Generate report
Invoke-BottleneckReport -Results $results -Tier Standard

# Export metrics
Export-BottleneckPerformanceMetrics -Path 'Reports\metrics.json'
```

### Batch Scanning
```powershell
# Scan multiple machines
$machines = @('DESKTOP-001', 'DESKTOP-002', 'LAPTOP-003')
foreach ($machine in $machines) {
    Write-Host "Scanning $machine..."
    & '\\$machine\c$\Bottleneck\scripts\run.ps1' -Tier Standard
}
```

### Log Analysis
```powershell
# View structured logs
Get-ChildItem Reports -Recurse -Filter *.log | ForEach-Object {
    Write-Host "=== $($_.FullName) ===" -ForegroundColor Cyan
    Get-Content $_.FullName | Select-Object -Last 20
}

# Parse JSON results
$scan = Get-ChildItem Reports -Recurse -Filter *scan*.json | Sort-Object LastWriteTime -Desc | Select-Object -First 1
$results = Get-Content $scan.FullName | ConvertFrom-Json
$results | Where-Object { $_.Impact -ge 7 } | Select-Object Id, Message, Impact
```

## Uninstalling

### Remove Module
```powershell
Remove-Module Bottleneck -Force
Remove-Item -Recurse $PROFILE\..\Modules\Bottleneck
```

### Remove Installation
```powershell
# Delete folder
Remove-Item -Recurse C:\Tools\Bottleneck

# Clean reports
Remove-Item -Recurse Reports
```

## Support & Feedback

- **Issues**: Report on GitHub or project tracker
- **Logs**: Check `Reports\<date>\run-<timestamp>.log` for diagnostics
- **Debug**: Run with `-Debug` flag for detailed tracing

---

**Version**: 1.0  
**Last Updated**: January 3, 2026
