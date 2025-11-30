# run-elevated.ps1
# Helper script to relaunch with administrator privileges

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Quick','Standard','Deep','Network')]
    [string]$ScanType = 'Standard'
)

# Check if already running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "✓ Already running with administrator privileges" -ForegroundColor Green

    # Import module and run scan
    $modulePath = Join-Path $PSScriptRoot '..\src\ps\Bottleneck.psm1'
    Import-Module $modulePath -Force

    Write-Host "`nRunning $ScanType scan with elevated privileges...`n" -ForegroundColor Cyan

    switch ($ScanType) {
        'Quick' {
            $results = Invoke-BottleneckScan -Tier Quick -Sequential
            Invoke-BottleneckReport -Results $results -Tier Quick
        }
        'Standard' {
            $results = Invoke-BottleneckScan -Tier Standard -Sequential
            Invoke-BottleneckReport -Results $results -Tier Standard
        }
        'Deep' {
            $results = Invoke-BottleneckScan -Tier Deep -Sequential
            Invoke-BottleneckReport -Results $results -Tier Deep
        }
        'Network' {
            $results = Invoke-BottleneckNetworkScan -IncludeFirewall -IncludeVPN
        }
    }

    Write-Host "`n✓ Scan completed: $($results.Count) checks" -ForegroundColor Green
    Write-Host "Reports saved to:" -ForegroundColor Cyan
    Write-Host "  - $(Join-Path $PSScriptRoot '..\Reports')"
    Write-Host "  - $([Environment]::GetFolderPath('MyDocuments'))\ScanReports"

    # Pause so user can see results
    Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

} else {
    Write-Host "⚠️  Not running as administrator. Relaunching with elevated privileges..." -ForegroundColor Yellow

    # Build arguments to pass to elevated process
    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ScanType $ScanType"

    try {
        # Start new PowerShell process as admin
        Start-Process pwsh.exe -ArgumentList $arguments -Verb RunAs -Wait
        Write-Host "✓ Elevated scan completed" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to elevate privileges: $_" -ForegroundColor Red
        Write-Host "`nTo run manually as administrator:" -ForegroundColor Yellow
        Write-Host "  1. Right-click PowerShell and select 'Run as Administrator'"
        Write-Host "  2. Navigate to: $(Split-Path $scriptPath)"
        Write-Host "  3. Run: .\run-elevated.ps1 -ScanType $ScanType"
    }
}
