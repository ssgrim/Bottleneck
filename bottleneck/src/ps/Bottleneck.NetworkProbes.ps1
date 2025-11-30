# Bottleneck.NetworkProbes.ps1
# Advanced network investigative probes

function Test-BottleneckWiFiQuality {
    [CmdletBinding()] param()
    try {
        $wifiData = netsh wlan show interfaces | Out-String
        if ($wifiData -notmatch 'There is no wireless interface') {
            $ssid = if ($wifiData -match 'SSID\s+:\s+(.+)') { $matches[1].Trim() } else { 'N/A' }
            $signal = if ($wifiData -match 'Signal\s+:\s+(\d+)%') { [int]$matches[1] } else { 0 }
            $channel = if ($wifiData -match 'Channel\s+:\s+(\d+)') { [int]$matches[1] } else { 0 }
            $rxRate = if ($wifiData -match 'Receive rate \(Mbps\)\s+:\s+([\d.]+)') { [double]$matches[1] } else { 0 }
            $txRate = if ($wifiData -match 'Transmit rate \(Mbps\)\s+:\s+([\d.]+)') { [double]$matches[1] } else { 0 }
            $auth = if ($wifiData -match 'Authentication\s+:\s+(.+)') { $matches[1].Trim() } else { 'Unknown' }

            $impact = 0; $confidence = 8; $evidence = "SSID: $ssid, Signal: ${signal}%, Channel: $channel, RX: ${rxRate}Mbps, TX: ${txRate}Mbps, Auth: $auth"
            $message = "Wi-Fi connected with acceptable parameters."

            if ($signal -lt 50) { $impact = 6; $message = "Weak Wi-Fi signal ($signal%). Consider moving closer to router or switching to 5GHz band." }
            elseif ($signal -lt 70) { $impact = 3; $message = "Moderate Wi-Fi signal ($signal%). Performance may vary under load." }

            if ($channel -ge 1 -and $channel -le 11 -and $channel -notin @(1,6,11)) {
                $impact = [math]::Max($impact, 4)
                $message += " Channel $channel may have interference (use 1, 6, or 11 for 2.4GHz)."
            }

            New-BottleneckResult -Id 'WiFiQuality' -Tier 'Standard' -Category 'Network' -Impact $impact -Confidence $confidence -Effort 2 -Priority 4 -Evidence $evidence -FixId '' -Message $message
        }
    } catch {}
}

function Test-BottleneckDNSResolvers {
    [CmdletBinding()] param()
    $targets = @('www.microsoft.com', 'www.google.com')
    $resolvers = @(
        @{Name='System Default'; Server=$null},
        @{Name='Cloudflare'; Server='1.1.1.1'},
        @{Name='Google'; Server='8.8.8.8'}
    )

    $timings = foreach ($resolver in $resolvers) {
        $times = foreach ($target in $targets) {
            $elapsed = Measure-Command {
                try {
                    if ($resolver.Server) { Resolve-DnsName -Name $target -Server $resolver.Server -DnsOnly -ErrorAction Stop | Out-Null }
                    else { Resolve-DnsName -Name $target -DnsOnly -ErrorAction Stop | Out-Null }
                } catch {}
            }
            $elapsed.TotalMilliseconds
        }
        $avgMs = if ($times) { [math]::Round((($times | Measure-Object -Average).Average), 1) } else { 9999 }
        [pscustomobject]@{ Resolver=$resolver.Name; AvgMs=$avgMs }
    }

    $default = $timings | Where-Object { $_.Resolver -eq 'System Default' } | Select-Object -Expand AvgMs
    $best = ($timings | Sort-Object AvgMs | Select-Object -First 1)

    $impact = if ($default -gt 200) { 6 } elseif ($default -gt 100) { 3 } else { 0 }
    $confidence = 7
    $evidence = ($timings | ForEach-Object { "$($_.Resolver): $($_.AvgMs)ms" }) -join '; '
    $message = if ($impact -gt 0) { "DNS resolution slow (${default}ms avg). Consider switching to $($best.Resolver) ($($best.AvgMs)ms)." } else { "DNS resolution performing well (${default}ms avg)." }

    New-BottleneckResult -Id 'DNSResolvers' -Tier 'Standard' -Category 'Network' -Impact $impact -Confidence $confidence -Effort 1 -Priority 5 -Evidence $evidence -FixId '' -Message $message
}

function Test-BottleneckAdapterErrors {
    [CmdletBinding()] param()
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Loopback|Hyper-V' }
        foreach ($adapter in $adapters) {
            $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
            if ($stats) {
                $outErrors = $stats.OutboundDiscardedPackets + $stats.OutboundErrors
                $inErrors = $stats.InboundDiscardedPackets + $stats.InboundErrors
                $totalPkts = $stats.ReceivedBytes + $stats.SentBytes
                $errorRate = if ($totalPkts -gt 0) { [math]::Round(100.0 * ($outErrors + $inErrors) / $totalPkts, 4) } else { 0 }

                $impact = if ($errorRate -gt 1) { 7 } elseif ($errorRate -gt 0.1) { 4 } elseif ($outErrors + $inErrors -gt 100) { 2 } else { 0 }
                $confidence = 8
                $evidence = "Adapter: $($adapter.Name), Out Errors: $outErrors, In Errors: $inErrors, Error Rate: ${errorRate}%"
                $message = if ($impact -gt 0) { "Adapter $($adapter.Name) showing packet errors. Check cable, driver, or hardware." } else { "Adapter $($adapter.Name) has minimal errors." }

                New-BottleneckResult -Id "AdapterErrors_$($adapter.Name)" -Tier 'Standard' -Category 'Network' -Impact $impact -Confidence $confidence -Effort 3 -Priority 6 -Evidence $evidence -FixId '' -Message $message
            }
        }
    } catch {}
}

function Test-BottleneckMTUPath {
    [CmdletBinding()] param()
    $target = '8.8.8.8'
    $sizes = @(1472, 1464, 1400, 1300, 1200) # common MTU - 28 bytes (IP+ICMP headers)

    foreach ($size in $sizes) {
        try {
            $result = Test-Connection -ComputerName $target -BufferSize $size -Count 1 -DontFragment -ErrorAction Stop
            if ($result.StatusCode -eq 0) {
                $mtu = $size + 28
                $impact = if ($mtu -lt 1500) { 3 } else { 0 }
                $confidence = 7
                $evidence = "Effective MTU: $mtu bytes (tested with $size byte payload to $target)"
                $message = if ($mtu -lt 1500) { "Path MTU is $mtu bytes (standard is 1500). This may cause fragmentation and slight performance impact." } else { "Path MTU is optimal at $mtu bytes." }

                return New-BottleneckResult -Id 'MTUPath' -Tier 'Deep' -Category 'Network' -Impact $impact -Confidence $confidence -Effort 2 -Priority 4 -Evidence $evidence -FixId '' -Message $message
            }
        } catch {}
    }

    # If all fail, MTU is very constrained
    New-BottleneckResult -Id 'MTUPath' -Tier 'Deep' -Category 'Network' -Impact 5 -Confidence 6 -Effort 3 -Priority 5 -Evidence "Path MTU <1200 bytes; all test sizes failed" -FixId '' -Message "Path MTU severely constrained (<1200 bytes). Check VPN, tunnel, or ISP settings."
}

function Test-BottleneckARPHealth {
    [CmdletBinding()] param()
    try {
        $neighbors = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop
        $total = $neighbors.Count
        $stale = ($neighbors | Where-Object { $_.State -in @('Stale','Unreachable') }).Count
        $staleRate = if ($total -gt 0) { [math]::Round(100.0 * $stale / $total, 1) } else { 0 }

        $impact = if ($staleRate -gt 50) { 5 } elseif ($staleRate -gt 25) { 3 } else { 0 }
        $confidence = 6
        $evidence = "Total ARP entries: $total, Stale/Unreachable: $stale ($staleRate%)"
        $message = if ($impact -gt 0) { "High ARP stale rate ($staleRate%). May indicate network instability or router issues." } else { "ARP cache healthy." }

        New-BottleneckResult -Id 'ARPHealth' -Tier 'Deep' -Category 'Network' -Impact $impact -Confidence $confidence -Effort 2 -Priority 5 -Evidence $evidence -FixId '' -Message $message
    } catch {}
}

function Get-BottleneckNetworkTrafficSnapshot {
    <#
    .SYNOPSIS
    Captures per-process network activity snapshot with bandwidth and port risk assessment.
    
    .DESCRIPTION
    Samples network connections and bandwidth over a short window to identify top talkers,
    risky ports, and suspicious destinations.
    
    .PARAMETER DurationSeconds
    Sampling window duration (default: 5 seconds).
    
    .EXAMPLE
    Get-BottleneckNetworkTrafficSnapshot -DurationSeconds 10
    #>
    [CmdletBinding()]
    param([int]$DurationSeconds = 5)
    
    Write-Verbose "Sampling network traffic for $DurationSeconds seconds..."
    
    # Get initial connection snapshot
    $connections1 = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | 
        Select-Object OwningProcess, LocalAddress, LocalPort, RemoteAddress, RemotePort
    
    # Sample network adapter stats
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Loopback' }
    $stats1 = $adapters | ForEach-Object { Get-NetAdapterStatistics -Name $_.Name -ErrorAction SilentlyContinue }
    
    Start-Sleep -Seconds $DurationSeconds
    
    # Get second snapshot
    $connections2 = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | 
        Select-Object OwningProcess, LocalAddress, LocalPort, RemoteAddress, RemotePort
    $stats2 = $adapters | ForEach-Object { Get-NetAdapterStatistics -Name $_.Name -ErrorAction SilentlyContinue }
    
    # Calculate bandwidth delta
    $totalDelta = 0
    for ($i=0; $i -lt $stats1.Count; $i++) {
        if ($stats2[$i]) {
            $totalDelta += ($stats2[$i].ReceivedBytes - $stats1[$i].ReceivedBytes) + ($stats2[$i].SentBytes - $stats1[$i].SentBytes)
        }
    }
    $bandwidthMbps = [math]::Round(($totalDelta * 8) / ($DurationSeconds * 1000000), 2)
    
    # Aggregate by process
    $processConnections = $connections2 | Group-Object OwningProcess | ForEach-Object {
        $pid = $_.Name
        $conns = $_.Group
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        
        [pscustomobject]@{
            ProcessId = $pid
            ProcessName = if ($proc) { $proc.ProcessName } else { 'Unknown' }
            ConnectionCount = $conns.Count
            RemoteAddresses = ($conns | Select-Object -Expand RemoteAddress -Unique | Select-Object -First 5) -join ', '
            Ports = ($conns | Select-Object -Expand RemotePort -Unique | Sort-Object | Select-Object -First 10) -join ', '
        }
    } | Sort-Object ConnectionCount -Descending | Select-Object -First 10
    
    # Risk assessment for common dangerous ports
    $riskyPorts = @(21,23,25,110,135,139,445,1433,1434,3306,3389,5900,6667,8080)
    $openRiskyPorts = $connections2 | Where-Object { $_.LocalPort -in $riskyPorts -or $_.RemotePort -in $riskyPorts } |
        Select-Object -Expand LocalPort -Unique
    
    [pscustomobject]@{
        Timestamp = Get-Date -Format 's'
        DurationSeconds = $DurationSeconds
        BandwidthMbps = $bandwidthMbps
        TotalConnections = $connections2.Count
        TopProcesses = $processConnections
        RiskyPortsDetected = $openRiskyPorts
    }
}


