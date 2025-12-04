# Network Drop Monitor and Diagnostic Data Collector
# Monitors WiFi connection and captures diagnostic data when drops occur

param(
    [int]$DurationMinutes = 60,
    [int]$CheckIntervalSeconds = 5,
    [string]$LogPath = "$PSScriptRoot\..\Reports\network-drop-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log",
    [switch]$Classify,               # Classify drops as WLAN/LAN, WAN, or DNS
    [switch]$CaptureWlanEvents,      # Include WLAN-AutoConfig event excerpts
    [switch]$VerboseDiagnostics,     # Print additional diagnostics per event
    [switch]$CapturePackets,         # Use pktmon to capture a ring buffer and export pcapng on each drop (requires admin)
    [int]$PacketWindowSeconds = 30,  # Approximate window size around drop (depends on buffer size and traffic)
    [int]$PktmonBufferMB = 64,       # pktmon buffer size (MB)
    [int]$PktSize = 128              # pktmon per-packet capture size (bytes)
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

# Helper functions (must be defined before use)
function Test-IsAdmin { try { $id=[Security.Principal.WindowsIdentity]::GetCurrent(); $p=new-object Security.Principal.WindowsPrincipal($id); return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false } }

function Start-PktmonCapture {
    param([int]$IfIndex,[int]$BufferMB,[int]$PktBytes)
    try {
        & pktmon stop 2>&1 | Out-Null
        & pktmon filter remove 2>&1 | Out-Null
        & pktmon filter add -i $IfIndex 2>&1 | Out-Null
        & pktmon start --etw -p $PktBytes -s $BufferMB 2>&1 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Stop-PktmonAndExport {
    param([string]$OutPcapPath)
    $etlPath = $null
    try {
        & pktmon stop 2>&1 | Out-Null
        # Check common ETL locations
        $etlCandidates = @(
            (Join-Path (Get-Location) 'PktMon.etl'),
            (Join-Path $env:TEMP 'PktMon.etl'),
            (Join-Path $env:USERPROFILE 'PktMon.etl')
        )
        foreach ($etl in $etlCandidates) {
            if (Test-Path $etl) {
                $etlPath = $etl
                break
            }
        }
        if ($etlPath) {
            $outDir = Split-Path -Parent $OutPcapPath
            if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
            $fmt = & pktmon format $etlPath -o $OutPcapPath -f pcapng 2>&1
            Start-Sleep -Milliseconds 500  # Wait for file write
            if (Test-Path $OutPcapPath) {
                Remove-Item $etlPath -Force -ErrorAction SilentlyContinue
                return $true
            }
        }
    } catch { }
    return $false
}

function Get-WlanInterfaceDetails {
    try {
        $raw = netsh wlan show interfaces | Out-String
        $obj = [ordered]@{ SSID=$null; BSSID=$null; Signal=$null; Channel=$null }
        foreach ($line in $raw -split "`r?`n") {
            if ($line -match '^\s*SSID\s*:\s*(.+)$') { $obj.SSID = $Matches[1].Trim() }
            elseif ($line -match '^\s*BSSID\s*:\s*(.+)$') { $obj.BSSID = $Matches[1].Trim() }
            elseif ($line -match '^\s*Signal\s*:\s*(.+)$') { $obj.Signal = $Matches[1].Trim() }
            elseif ($line -match '^\s*Channel\s*:\s*(.+)$') { $obj.Channel = $Matches[1].Trim() }
        }
        return ($obj | ConvertTo-Json | ConvertFrom-Json)
    } catch { return $null }
}

function Test-NetworkPath {
    param([string]$Target)
    try { return [bool](Test-NetConnection -ComputerName $Target -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue) }
    catch { return $false }
}

function Test-DnsResolution {
    param([string]$Name='www.msftconnecttest.com')
    try { $r = Resolve-DnsName -Name $Name -ErrorAction Stop; return $true } catch { return $false }
}

# Initialize state variables
$startTime = Get-Date
$endTime = $startTime.AddMinutes($DurationMinutes)
$dropCount = 0
$wasConnected = $true
$lastStatus = "Up"
$lastBssid = $null
$lastChannel = $null
$classCounts = @{ WLAN=0; WAN=0; DNS=0; Unknown=0 }
$pktmonEnabled = $false
$pktmonAvailable = $false
$pktmonInterface = $null
$capturesDir = Join-Path (Split-Path $LogPath -Parent) 'captures'
if (-not (Test-Path $capturesDir)) { New-Item -ItemType Directory -Path $capturesDir -Force | Out-Null }

# Optional: initialize pktmon packet capture
if ($CapturePackets) {
    $pktmonAvailable = [bool](Get-Command pktmon -ErrorAction SilentlyContinue)
    if (-not $pktmonAvailable) {
        Write-Host "(pktmon not found; skipping packet capture)" -ForegroundColor DarkYellow
    } elseif (-not (Test-IsAdmin)) {
        Write-Host "(not elevated; run as Administrator to enable pktmon captures)" -ForegroundColor DarkYellow
    } else {
        $pktStarted = Start-PktmonCapture -IfIndex $wifiAdapter.ifIndex -BufferMB $PktmonBufferMB -PktBytes $PktSize
        if ($pktStarted) {
            $pktmonEnabled = $true
            Write-Host "📡 pktmon ring capture active (buffer ${PktmonBufferMB}MB, ${PktSize}B/packet)" -ForegroundColor DarkCyan
        } else {
            Write-Host "(failed to start pktmon; skipping packet capture)" -ForegroundColor DarkYellow
        }
    }
}

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

        # If pktmon is enabled, stop and export capture around this drop
        if ($pktmonEnabled) {
            try {
                $pcapName = "drop-$($now.ToString('yyyy-MM-dd_HH-mm-ss'))-#$dropCount.pcapng"
                $pcapPath = Join-Path $capturesDir $pcapName
                Write-Host "   📡 Exporting pktmon capture..." -ForegroundColor Cyan
                $ok = Stop-PktmonAndExport -OutPcapPath $pcapPath
                Start-Sleep -Milliseconds 1000
                if ((Test-Path $pcapPath) -and ((Get-Item $pcapPath).Length -gt 100)) {
                    $size = (Get-Item $pcapPath).Length / 1KB
                    Write-Host "   ✓ Packet capture saved: $pcapName ($([Math]::Round($size))KB)" -ForegroundColor Green
                } else {
                    Write-Host "   ⚠️  Packet export incomplete; retrying..." -ForegroundColor DarkYellow
                    Start-Sleep -Milliseconds 500
                    if ((Test-Path $pcapPath)) {
                        $size = (Get-Item $pcapPath).Length / 1KB
                        Write-Host "   ✓ Packet capture saved: $pcapName ($([Math]::Round($size))KB)" -ForegroundColor Green
                    } else {
                        Write-Host "   (pktmon export not available or eth file missing)" -ForegroundColor DarkYellow
                    }
                }
            } catch { Write-Host "   (pktmon export error: $($_.Exception.Message))" -ForegroundColor DarkYellow }
            # Restart ring buffer to capture subsequent events
            $null = Start-PktmonCapture -IfIndex $wifiAdapter.ifIndex -BufferMB $PktmonBufferMB -PktBytes $PktSize
        }

        # Capture diagnostic data
        Write-Host "   📊 Capturing diagnostics..." -ForegroundColor Cyan

        # WiFi interface details
        $iface = Get-WlanInterfaceDetails
        if ($iface) {
            Write-Host "   SSID: $($iface.SSID)  BSSID: $($iface.BSSID)  Channel: $($iface.Channel)  Signal: $($iface.Signal)" -ForegroundColor Gray
            if ($lastBssid -and $iface.BSSID -and ($lastBssid -ne $iface.BSSID)) {
                Write-Host "   ↪ BSSID changed: $lastBssid → $($iface.BSSID)" -ForegroundColor Yellow
            }
            if ($lastChannel -and $iface.Channel -and ($lastChannel -ne $iface.Channel)) {
                Write-Host "   ↪ Channel changed: $lastChannel → $($iface.Channel)" -ForegroundColor Yellow
            }
            $lastBssid = $iface.BSSID
            $lastChannel = $iface.Channel
        }

        # WLAN-AutoConfig events (optional)
        if ($CaptureWlanEvents) {
            try {
                $events = Get-WinEvent -LogName System -MaxEvents 20 -ErrorAction SilentlyContinue |
                    Where-Object { $_.ProviderName -match 'WLAN-AutoConfig|Netwtw|NetAdapter' -and $_.TimeCreated -gt $now.AddMinutes(-2) }
                if ($events) {
                    Write-Host "   Recent WLAN/Adapter Events:" -ForegroundColor Gray
                    $events | ForEach-Object {
                        $msg = $_.Message
                        if ($msg.Length -gt 140) { $msg = $msg.Substring(0,140) + '…' }
                        Write-Host ("     {0} [{1}] {2}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.Id, $msg) -ForegroundColor DarkGray
                    }
                }
            } catch {}
        }

        # Network statistics
        try {
            $stats = Get-NetAdapterStatistics -Name $wifiAdapter.Name -ErrorAction SilentlyContinue
            if ($stats) {
                Write-Host "   Adapter Stats: Recv=$($stats.ReceivedBytes) Sent=$($stats.SentBytes) RecvErrors=$($stats.ReceivedPacketErrors)" -ForegroundColor Gray
            }
        } catch {}

        # Classification (optional)
        if ($Classify) {
            $gw = $null
            try {
                $gw = (Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway} | Select-Object -First 1).IPv4DefaultGateway.NextHop
            } catch {}
            $gwOk = $false; $wan1Ok = $false; $wan2Ok = $false; $dnsOk = $false
            if ($gw) { $gwOk = Test-NetworkPath -Target $gw }
            $wan1Ok = Test-NetworkPath -Target '8.8.8.8'
            $wan2Ok = Test-NetworkPath -Target '1.1.1.1'
            $dnsOk = Test-DnsResolution
            $label = 'Unknown'
            if (-not $gwOk) { $label = 'WLAN' }
            elseif ($gwOk -and (-not $wan1Ok -and -not $wan2Ok)) { $label = 'WAN' }
            elseif (($wan1Ok -or $wan2Ok) -and (-not $dnsOk)) { $label = 'DNS' }
            $classCounts[$label]++
            Write-Host "   Classification: $label (GW:$gwOk WAN:$($wan1Ok -or $wan2Ok) DNS:$dnsOk)" -ForegroundColor Cyan
        }

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
    if ($Classify) {
        Write-Host "Classification Totals:" -ForegroundColor White
        Write-Host ("  WLAN/LAN: {0}  |  WAN: {1}  |  DNS: {2}  |  Unknown: {3}" -f $classCounts.WLAN, $classCounts.WAN, $classCounts.DNS, $classCounts.Unknown) -ForegroundColor White
        Write-Host ""
    }
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
# Cleanup pktmon if running
if ($pktmonEnabled) {
    try { & pktmon stop | Out-Null } catch {}
}
Stop-Transcript
