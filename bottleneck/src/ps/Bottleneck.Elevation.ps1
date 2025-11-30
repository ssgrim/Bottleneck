# Request-ElevatedScan.ps1
# Interactive utility to request elevation for current PowerShell session

function Request-ElevatedScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('Quick','Standard','Deep','Network')]
        [string]$Tier = 'Standard'
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        Write-Host "✓ Session already has administrator privileges" -ForegroundColor Green
        return $true
    }

    Write-Host "`n⚠️  Administrator privileges required for complete scan results" -ForegroundColor Yellow
    Write-Host "`nWithout admin rights, these checks will be limited:" -ForegroundColor Cyan
    Write-Host "  • Event log security analysis"
    Write-Host "  • Firewall configuration details"
    Write-Host "  • System integrity verification (SFC/DISM)"
    Write-Host "  • Full SMART disk diagnostics"
    Write-Host "  • Windows Update status"
    Write-Host "  • Service health analysis"

    $response = Read-Host "`nRelaunch with administrator privileges? (Y/N)"

    if ($response -match '^[Yy]') {
        Write-Host "`nRelaunching with elevation..." -ForegroundColor Green

        # Get current script/module location
        $modulePath = (Get-Module Bottleneck).Path
        $scriptBlock = {
            param($modPath, $scanTier)
            Import-Module $modPath -Force
            $results = Invoke-BottleneckScan -Tier $scanTier -Sequential
            Invoke-BottleneckReport -Results $results -Tier $scanTier
            Write-Host "`n✓ Elevated scan complete: $($results.Count) checks" -ForegroundColor Green
            Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }

        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptBlock.ToString()))

        try {
            Start-Process pwsh.exe -ArgumentList "-NoProfile -EncodedCommand $encodedCommand -ArgumentList '$modulePath','$Tier'" -Verb RunAs
            Write-Host "✓ Elevated session launched" -ForegroundColor Green
            return $false
        } catch {
            Write-Host "✗ Failed to elevate: $_" -ForegroundColor Red
            Write-Host "`nAlternative: Right-click PowerShell → Run as Administrator" -ForegroundColor Yellow
            return $false
        }
    } else {
        Write-Host "`nContinuing with current privileges (some checks limited)..." -ForegroundColor Yellow
        return $false
    }
}

Export-ModuleMember -Function Request-ElevatedScan
