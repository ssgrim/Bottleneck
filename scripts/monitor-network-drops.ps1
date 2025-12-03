# Network Drop Monitor and Diagnostic Data Collector
# Monitors WiFi connection and captures diagnostic data when drops occur

param(
    [int]$DurationMinutes = 60,
    [int]$CheckIntervalSeconds = 5,
    [string]$LogPath = "$PSScriptRoot\..\Reports\network-drop-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Split-Path -Parent $LogPath
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

Start-Transcript -Path $LogPath -Append

Write-Host "🔍 Network Drop Monitor Started" -ForegroundColor Cyan
Write-Host "Duration: $DurationMinutes minutes | Check interval: $CheckIntervalSeconds seconds" -ForegroundColor Gray
Write-Host "Log: $LogPath" -ForegroundColor Gray
Write-Host ""

# Get WiFi adapter
$wifiAdapter = Get-NetAdapter | Where-Object { $_.MediaType -match 'Wireless' -or $_.Name -match 'Wi-Fi' } | Select-Object -First 1
if (-not $wifiAdapter) {
    Write-Host "❌ No WiFi adapter found" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host "Monitoring adapter: $($wifiAdapter.Name) ($($wifiAdapter.InterfaceDescription))" -ForegroundColor Green
Write-Host ""

$startTime = Get-Date
$endTime = $startTime.AddMinutes($DurationMinutes)
$dropCount = 0
$wasConnected = $true
$lastStatus = "Up"

while ((Get-Date) -lt $endTime) {
    $now = Get-Date
    
    # Check adapter status
    $current = Get-NetAdapter -Name $wifiAdapter.Name -ErrorAction SilentlyContinue
    $isConnected = ($current -and $current.Status -eq 'Up')
    
    # Check internet connectivity
    $hasInternet = $false
    try {
        $ping = Test-NetConnection -ComputerName 8.8.8.8 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $hasInternet = $ping
    } catch {
        $hasInternet = $false
    }
    
    # Detect drop (was connected, now not)
    if ($wasConnected -and (-not $isConnected -or -not $hasInternet)) {
        $dropCount++
        Write-Host "🔴 DROP DETECTED #$dropCount at $($now.ToString('HH:mm:ss'))" -ForegroundColor Red
        Write-Host "   Adapter Status: $($current.Status)" -ForegroundColor Yellow
        Write-Host "   Internet: $hasInternet" -ForegroundColor Yellow
        
        # Capture diagnostic data
        Write-Host "   📊 Capturing diagnostics..." -ForegroundColor Cyan
        
        # WiFi signal quality
        try {
            $signal = netsh wlan show interfaces | Select-String -Pattern 'Signal'
            Write-Host "   $signal" -ForegroundColor Gray
        } catch {}
        
        # Recent WiFi events
        try {
            $events = Get-WinEvent -LogName System -MaxEvents 10 -ErrorAction SilentlyContinue | 
                Where-Object { $_.ProviderName -match 'WLAN|Wireless|NetAdapter' -and $_.TimeCreated -gt $now.AddMinutes(-1) }
            if ($events) {
                Write-Host "   Recent Events:" -ForegroundColor Gray
                $events | ForEach-Object { Write-Host "     $($_.TimeCreated.ToString('HH:mm:ss')) - $($_.Message.Substring(0, [Math]::Min(80, $_.Message.Length)))" -ForegroundColor DarkGray }
            }
        } catch {}
        
        # Network statistics
        try {
            $stats = Get-NetAdapterStatistics -Name $wifiAdapter.Name -ErrorAction SilentlyContinue
            if ($stats) {
                Write-Host "   Adapter Stats: Recv=$($stats.ReceivedBytes) Sent=$($stats.SentBytes) RecvErrors=$($stats.ReceivedPacketErrors)" -ForegroundColor Gray
            }
        } catch {}
        
        Write-Host ""
        $wasConnected = $false
    }
    # Detect reconnection
    elseif (-not $wasConnected -and $isConnected -and $hasInternet) {
        $duration = ((Get-Date) - $now).TotalSeconds
        Write-Host "🟢 RECONNECTED at $($now.ToString('HH:mm:ss'))" -ForegroundColor Green
        Write-Host ""
        $wasConnected = $true
    }
    # Status change without full drop
    elseif ($current.Status -ne $lastStatus) {
        Write-Host "⚠️  Status changed: $lastStatus → $($current.Status) at $($now.ToString('HH:mm:ss'))" -ForegroundColor Yellow
        $lastStatus = $current.Status
    }
    
    Start-Sleep -Seconds $CheckIntervalSeconds
}

Write-Host "✓ Monitoring complete" -ForegroundColor Green
Write-Host "Total drops detected: $dropCount" -ForegroundColor Cyan
Write-Host ""

# Generate summary
Write-Host "📋 Diagnostic Summary:" -ForegroundColor Cyan
Write-Host "=" * 60

# Adapter info
$adapter = Get-NetAdapter -Name $wifiAdapter.Name
Write-Host "Adapter: $($adapter.Name)" -ForegroundColor White
Write-Host "  Status: $($adapter.Status)" -ForegroundColor White
Write-Host "  Link Speed: $($adapter.LinkSpeed)" -ForegroundColor White

# Power management
try {
    $power = Get-NetAdapterPowerManagement -Name $wifiAdapter.Name -ErrorAction SilentlyContinue
    if ($power) {
        Write-Host "Power Management:" -ForegroundColor White
        Write-Host "  Allow computer to turn off: $($power.AllowComputerToTurnOffDevice)" -ForegroundColor $(if ($power.AllowComputerToTurnOffDevice) { 'Red' } else { 'Green' })
    }
} catch {}

# Driver info
try {
    $driver = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.Name -eq $adapter.InterfaceDescription } | Select-Object -First 1
    if ($driver) {
        Write-Host "Driver:" -ForegroundColor White
        Write-Host "  Version: $($driver.DriverVersion)" -ForegroundColor White
        Write-Host "  Date: $($driver.DriverDate)" -ForegroundColor White
    }
} catch {}

# WiFi info
try {
    Write-Host "WiFi Details:" -ForegroundColor White
    netsh wlan show interfaces | Select-String -Pattern 'SSID|Signal|Channel|Authentication|Cipher'
} catch {}

Write-Host ""
Write-Host "💡 Recommendations:" -ForegroundColor Cyan

if ($dropCount -gt 0) {
    Write-Host "  1. Disable power saving on WiFi adapter:" -ForegroundColor Yellow
    Write-Host "     Device Manager → Network Adapters → $($adapter.InterfaceDescription) → Properties → Power Management" -ForegroundColor Gray
    Write-Host "     Uncheck 'Allow the computer to turn off this device to save power'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Update WiFi driver:" -ForegroundColor Yellow
    Write-Host "     Device Manager → Network Adapters → $($adapter.InterfaceDescription) → Update Driver" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. Check router settings:" -ForegroundColor Yellow
    Write-Host "     - Change WiFi channel (use WiFi analyzer to find best channel)" -ForegroundColor Gray
    Write-Host "     - Update router firmware" -ForegroundColor Gray
    Write-Host "     - Disable 'Smart Connect' if using 2.4GHz and 5GHz" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  4. Set WiFi roaming to medium:" -ForegroundColor Yellow
    Write-Host "     netsh wlan set profileparameter name=`"YourNetworkName`" roamingaggressiveness=medium" -ForegroundColor Gray
}

Write-Host ""
Write-Host "📁 Full log saved to: $LogPath" -ForegroundColor Cyan
Stop-Transcript
