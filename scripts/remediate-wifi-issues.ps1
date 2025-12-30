# WiFi Issue Auto-Remediation Script
# Applies common fixes for intermittent WiFi drops
# Run elevated for best results

param(
    [switch]$Dry = $false  # If $true, only report what would be done; don't apply
)

Write-Host "🔧 WiFi Issue Remediation Tool" -ForegroundColor Cyan
Write-Host ""

$elevated = $false
try { $elevated = ([Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544') } catch { }
if (-not $elevated) { Write-Host "⚠️  Not running as admin; some changes may not apply." -ForegroundColor Yellow }

$remediated = @()
$failed = @()

# 1. Disable WiFi power saving
Write-Host "📋 Checking WiFi adapter power management..." -ForegroundColor Gray
try {
    $wifiAdapter = Get-NetAdapter | Where-Object { $_.MediaType -match 'Wireless' -or $_.Name -match 'Wi-Fi' } | Select-Object -First 1
    if ($wifiAdapter) {
        $power = Get-NetAdapterPowerManagement -Name $wifiAdapter.Name -ErrorAction SilentlyContinue
        if ($power -and $power.AllowComputerToTurnOffDevice) {
            if ($Dry) {
                Write-Host "   [DRY] Would disable power saving on $($wifiAdapter.Name)" -ForegroundColor Yellow
            } else {
                # Disable via netsh (more reliable)
                $desc = $wifiAdapter.InterfaceDescription
                $devKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\*" | Get-ChildItem |
                    Where-Object { $_.GetValue('DriverDesc') -match [regex]::Escape($desc) } | Select-Object -First 1
                if ($devKey) {
                    $devKey.OpenSubKey('', $true) | ForEach-Object {
                        $_.SetValue('PnPCapabilities', 24, 'DWord')
                    }
                    Write-Host "   ✓ Disabled power saving on $($wifiAdapter.Name)" -ForegroundColor Green
                    $remediated += "Power Saving Disabled"
                } else {
                    Write-Host "   (registry key not found)" -ForegroundColor DarkYellow
                }
            }
        } else {
            Write-Host "   ✓ Already disabled (or unsupported)" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "   ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    $failed += "Power Saving"
}

# 2. Suggest driver update
Write-Host "📋 Checking WiFi driver..." -ForegroundColor Gray
try {
    $wifiAdapter = Get-NetAdapter | Where-Object { $_.MediaType -match 'Wireless' -or $_.Name -match 'Wi-Fi' } | Select-Object -First 1
    if ($wifiAdapter) {
        $driver = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.Name -eq $wifiAdapter.InterfaceDescription } | Select-Object -First 1
        $driverVer = $driver.DriverVersion
        Write-Host "   Current driver: $driverVer" -ForegroundColor Gray
        Write-Host "   📌 To update: Device Manager → Network Adapters → $($wifiAdapter.InterfaceDescription) → Update Driver" -ForegroundColor Cyan
        if (-not $Dry) { $remediated += "Driver Update Suggested" }
    }
} catch {
    Write-Host "   ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. WiFi roaming aggressiveness
Write-Host "📋 Checking WiFi roaming settings..." -ForegroundColor Gray
try {
    $profiles = netsh wlan show profiles | Select-String -Pattern "^\s*: (.+)$"
    if ($profiles) {
        foreach ($profile in $profiles) {
            $name = $profile.Matches[0].Groups[1].Value.Trim()
            if ($Dry) {
                Write-Host "   [DRY] Would set roaming to medium for profile '$name'" -ForegroundColor Yellow
            } else {
                $result = netsh wlan set profileparameter name="$name" roamingaggressiveness=medium 2>&1
                if ($result -match "ok" -or $result.Count -eq 0) {
                    Write-Host "   ✓ Set roaming to medium for '$name'" -ForegroundColor Green
                    $remediated += "Roaming Aggressiveness: $name"
                }
            }
        }
    }
} catch {
    Write-Host "   ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    $failed += "Roaming Settings"
}

# 4. WiFi channel optimization advice
Write-Host "📋 WiFi channel analysis..." -ForegroundColor Gray
try {
    $channels = netsh wlan show networks mode=Bssid | Select-String -Pattern "Channel\s+:\s+(\d+)"
    if ($channels) {
        $channelList = $channels.Matches.Groups[1].Value | Sort-Object -Unique
        Write-Host "   Currently detected channels: $($channelList -join ', ')" -ForegroundColor Gray
        Write-Host "   📌 Recommendation: Use 5 GHz channels 149, 153, 157, or 161 (less congestion)" -ForegroundColor Cyan
        Write-Host "      For 2.4 GHz: use channels 1, 6, or 11 (non-overlapping)" -ForegroundColor Cyan
        if (-not $Dry) { $remediated += "Channel Analysis Provided" }
    }
} catch {
    Write-Host "   ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Check for outdated drivers (Windows Update hint)
Write-Host "📋 Driver update availability..." -ForegroundColor Gray
try {
    Write-Host "   💡 Check Windows Update (Settings → System → About → Advanced options → Optional updates)" -ForegroundColor Cyan
    Write-Host "   💡 Or visit Intel's website for latest Wi-Fi driver: https://www.intel.com/content/www/en/en/products/wireless/wireless-products-and-solutions.html" -ForegroundColor Cyan
    if (-not $Dry) { $remediated += "Update Sources Provided" }
} catch { }

Write-Host ""
Write-Host "=" * 60
if ($remediated.Count -gt 0) {
    Write-Host "✓ Applied/Verified: $($remediated -join '; ')" -ForegroundColor Green
}
if ($failed.Count -gt 0) {
    Write-Host "⚠️  Issues: $($failed -join '; ')" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "📌 Next steps:" -ForegroundColor Cyan
Write-Host "  1. Update WiFi driver (manually or via Device Manager/Windows Update)" -ForegroundColor Gray
Write-Host "  2. Check router: change to less-congested channel (149/161 for 5GHz)" -ForegroundColor Gray
Write-Host "  3. Disable Smart Connect (if dual-band)" -ForegroundColor Gray
Write-Host "  4. Monitor with: .\scripts\monitor-network-drops.ps1" -ForegroundColor Gray
Write-Host ""
