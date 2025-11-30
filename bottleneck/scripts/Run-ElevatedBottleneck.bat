# Run-ElevatedBottleneck.bat
@echo off
echo.
echo ========================================
echo  Bottleneck System Diagnostic Tool
echo  Running with Administrator Privileges
echo ========================================
echo.

REM Check for admin rights
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [OK] Running as Administrator
    echo.
) else (
    echo [WARN] Not running as Administrator
    echo Right-click this file and select "Run as Administrator"
    echo.
    pause
    exit /b 1
)

REM Run PowerShell with elevation
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-elevated.ps1" -ScanType Standard

pause
