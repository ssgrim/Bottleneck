# run-network-rca.ps1
# Helper to run deep root cause analysis over latest network monitor CSV

Import-Module "$PSScriptRoot\..\src\ps\Bottleneck.psm1" -Force

try {
    $rca = Invoke-BottleneckNetworkRootCause
    Write-Host "\n=== Network RCA Summary ===" -ForegroundColor Cyan
    $rca.Summary | Format-List
    Write-Host "Likely Cause: $($rca.LikelyCause)" -ForegroundColor Yellow
    Write-Host "Recommendations:" -ForegroundColor Green
    $rca.Recommendations | ForEach-Object { " - $_" }

    Write-Host "\nTop recent jitter windows:" -ForegroundColor Cyan
    $rca.JitterByMinute | Sort-Object Minute | Select-Object -Last 10 | Format-Table -AutoSize

    if ($rca.FailureClusters -and $rca.FailureClusters.Count -gt 0) {
        Write-Host "\nFailure clusters (>=3/min):" -ForegroundColor Red
        $rca.FailureClusters | Format-Table -AutoSize
    } else {
        Write-Host "\nNo failure clusters detected." -ForegroundColor Green
    }

    Write-Host "\nMulti-host probe latencies:" -ForegroundColor Cyan
    $rca.Probes | Format-Table -AutoSize

    if ($rca.TraceRoute) {
        Write-Host "\nTraceroute snapshot:" -ForegroundColor Cyan
        $rca.TraceRoute | Format-Table -AutoSize
    }

} catch {
    Write-Error "RCA failed: $_"
}
