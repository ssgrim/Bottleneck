# Elevation Guide for Bottleneck

## Overview

Several Bottleneck diagnostic checks require administrator privileges to access system-level information. This guide explains how to provide elevated access.

## Why Elevation is Needed

Without administrator privileges, these checks are limited or unavailable:

- **Event Log Security Analysis** - Access denied to Security event log
- **Firewall Configuration** - Limited firewall rule and blocked connection details
- **System Integrity Verification** - SFC and DISM commands require admin
- **Full SMART Diagnostics** - Complete disk health data needs admin access
- **Windows Update Status** - Update history and pending updates
- **Service Health Analysis** - Service configuration and failure details
- **System File Analysis** - Deep ETW tracing and CBS logs

## Methods to Run with Elevation

### Method 1: Run-ElevatedBottleneck.bat (Easiest)

1. Navigate to `bottleneck\scripts\`
2. Right-click `Run-ElevatedBottleneck.bat`
3. Select **"Run as administrator"**
4. The script will automatically run a Standard scan with full privileges

### Method 2: PowerShell Script

```powershell
cd bottleneck\scripts
.\run-elevated.ps1 -ScanType Standard
```

**Scan Types:**

- `Quick` - 6 checks (~10 seconds)
- `Standard` - 46 checks (~60 seconds)
- `Deep` - 52 checks (~90 seconds)
- `Network` - Network-only diagnostics

### Method 3: Interactive Elevation Request

From an already-open PowerShell session:

```powershell
Import-Module .\src\ps\Bottleneck.psm1
Request-ElevatedScan -Tier Standard
```

This will prompt you to relaunch with elevation and automatically run the scan.

### Method 4: Manual PowerShell as Admin

1. Right-click **PowerShell** or **Windows Terminal**
2. Select **"Run as administrator"**
3. Navigate to the Bottleneck directory
4. Run commands normally:

```powershell
Import-Module .\src\ps\Bottleneck.psm1
$results = Invoke-BottleneckScan -Tier Standard -Sequential
Invoke-BottleneckReport -Results $results -Tier Standard
```

## Checking Current Privilege Level

To verify if you're running with admin rights:

```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

Returns `True` if elevated, `False` if standard user.

## What Happens Without Elevation?

The tool will still run but display warnings:

```
⚠️  Some checks require administrator privileges. Run as admin for complete results.
```

Affected checks will return limited results or skip entirely. The HTML report will indicate which checks were restricted.

## Security Notes

- Elevation is only needed for **read-only diagnostic operations**
- No system modifications are made during scans
- Fix functions (cleanup, defrag) explicitly require admin and will fail safely if not elevated
- All operations are logged to `Reports\bottleneck-YYYY-MM-DD.log`

## Troubleshooting

**"Access Denied" errors during scan:**
→ Rerun with one of the elevation methods above

**UAC prompt doesn't appear:**
→ UAC may be disabled. Check: `Control Panel → User Accounts → Change User Account Control settings`

**Script execution blocked:**
→ Set execution policy: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

**Batch file doesn't elevate:**
→ Ensure you right-click and select "Run as administrator" (double-clicking won't elevate)
