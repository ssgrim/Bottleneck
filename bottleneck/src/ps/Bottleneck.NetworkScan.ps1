# Bottleneck.NetworkScan.ps1
# Aggregated network-only scan
function Invoke-BottleneckNetworkScan {
    [CmdletBinding()]
    param(
        [switch]$IncludeFirewall,
        [switch]$IncludeVPN,
        [switch]$SuppressAdminWarning,
        [switch]$AutoElevate,
        [switch]$IncludeProbes
    )
    if ($AutoElevate) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Host "⚠️  Network scan can collect deeper data (firewall profiles, adapter stats) with admin rights." -ForegroundColor Yellow
            $elevated = Request-ElevatedScan -Tier Network
            if (-not $elevated) {
                Write-Host "↗ Network scan deferred to elevated window (if launched)." -ForegroundColor Cyan
                return
            } else {
                Write-Host "✓ Continuing network scan with elevation." -ForegroundColor Green
            }
        }
    }
    $functions = @('Test-BottleneckNetwork','Test-BottleneckDNS','Test-BottleneckNetworkAdapter','Test-BottleneckBandwidth')
    if ($IncludeProbes) { $functions += @('Test-BottleneckWiFiQuality','Test-BottleneckDNSResolvers','Test-BottleneckAdapterErrors','Test-BottleneckMTUPath','Test-BottleneckARPHealth') }
    if ($IncludeVPN) { $functions += 'Test-BottleneckVPN' }
    if ($IncludeFirewall) { $functions += 'Test-BottleneckFirewall' }
    $results = @()
    # Optionally suppress admin warning for this network-only run
    if ($SuppressAdminWarning) { Set-BottleneckAdminWarning -Suppress:$true }

    foreach ($fn in $functions) {
        if (Get-Command $fn -Module Bottleneck -ErrorAction SilentlyContinue) {
            try {
                $checkStart = Get-Date
                $r = & $fn
                $dur = ((Get-Date) - $checkStart).TotalMilliseconds
                Write-BottleneckLog "Network check $fn completed in $([math]::Round($dur))ms" -Level "DEBUG" -CheckId $fn
                if ($r) { $results += $r }
            } catch {
                Write-BottleneckLog "Network check $fn failed: $_" -Level "ERROR" -CheckId $fn
            }
        } else {
            Write-BottleneckLog "Network check $fn not found in module scope" -Level "WARN" -CheckId $fn
        }
    }
    # Optionally run deep RCA and append summary to report evidence
    try {
        $rca = Invoke-BottleneckNetworkRootCause -ErrorAction SilentlyContinue
        if ($rca) {
            $rcaSummary = "RCA: Success ${($rca.Summary.SuccessPct)}%, P95 ${([math]::Round($rca.Summary.P95LatencyMs,1))}ms, Drops ${($rca.Summary.Drops)}, Cause ${($rca.LikelyCause)}"
            $results += (New-BottleneckResult -Id 'NetworkRCA' -Tier 'Standard' -Category 'Network' -Impact 2 -Confidence 8 -Effort 1 -Priority 5 -Evidence $rcaSummary -FixId '' -Message ($rca.Recommendations -join '; '))
        }
    } catch {}

    # Generate a network-only report using Standard tier styling
    Invoke-BottleneckReport -Results $results -Tier Standard | Out-Null

    # Restore admin warning preference after run
    if ($SuppressAdminWarning) { Set-BottleneckAdminWarning -Suppress:$false }
    return $results
}
