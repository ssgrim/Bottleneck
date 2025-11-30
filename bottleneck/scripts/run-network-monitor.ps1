# run-network-monitor.ps1
# Long-running network connectivity monitor for diagnosing intermittent drops

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)][string]$TargetHost,
    [int]$DurationHours = 2,
    [int]$PingIntervalSeconds = 10,
    [string[]]$AdditionalTargets = @('8.8.8.8','1.1.1.1','www.google.com'),
    [int]$TracerouteIntervalMinutes = 15,
    [switch]$DisableTraceroute
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Bottleneck Network Monitor" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Target: $TargetHost" -ForegroundColor White
Write-Host "  Additional: $($AdditionalTargets -join ', ')" -ForegroundColor White
Write-Host "  Duration: $DurationHours hours" -ForegroundColor White
Write-Host "  Interval: $PingIntervalSeconds seconds" -ForegroundColor White
Write-Host "  Traceroute: $(if($DisableTraceroute){'Disabled'}else{"Every $TracerouteIntervalMinutes min"})" -ForegroundColor White
Write-Host ""

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logDir = "$PSScriptRoot/../Reports"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir "network-monitor-$timestamp.csv"

# Write CSV header
Add-Content -Path $logFile -Value ('Time,Target,Success,LatencyMs,RouterFail,DNSFail,ISPFail,Error,JitterMs,Notes')

Write-Host "Logging to: $logFile" -ForegroundColor Gray
Write-Host ""
Write-Host "Starting monitoring..." -ForegroundColor Green
Write-Host ""

$endTime = (Get-Date).AddHours($DurationHours)
$nextTrace = (Get-Date).AddMinutes($TracerouteIntervalMinutes)
$iteration = 0

try {
    while ((Get-Date) -lt $endTime) {
        $start = Get-Date
        $iteration++

        # Ping all targets
        foreach ($t in @($TargetHost) + $AdditionalTargets) {
            $success = $false; $lat = 0; $routerFail=$false; $dnsFail=$false; $ispFail=$false; $err=''; $notes=''
            try {
                $p = Test-Connection -ComputerName $t -Count 1 -ErrorAction Stop
                $lat = [math]::Round($p.Latency,2)
                $success = $true
                if ($iteration % 12 -eq 0) {
                    Write-Host "[$($start.ToString('HH:mm:ss'))] ✓ $t : ${lat}ms" -ForegroundColor Green
                }
            } catch {
                $err = $_.Exception.Message
                $dnsFail = ($err -match 'NameResolutionFailure|No such host is known')
                $routerFail = ($err -match 'Destination host unreachable|Request timed out')
                $ispFail = (-not $dnsFail -and -not $routerFail)
                $notes = 'drop'
                Write-Host "[$($start.ToString('HH:mm:ss'))] ✗ $t : DROP" -ForegroundColor Red
            }
            Add-Content -Path $logFile -Value (@(
                $start.ToString('s'), $t, $success, $lat, $routerFail, $dnsFail, $ispFail, ($err -replace ',',';'), 0, $notes
            ) -join ',')
        }

        # Periodic traceroute snapshot
        if (-not $DisableTraceroute -and (Get-Date) -ge $nextTrace) {
            Write-Host "[$($start.ToString('HH:mm:ss'))] Running traceroute to $TargetHost..." -ForegroundColor Cyan
            try {
                $trace = Test-NetConnection -ComputerName $TargetHost -TraceRoute -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($trace -and $trace.TraceRoute) {
                    $hopStr = ($trace.TraceRoute | ForEach-Object { "Hop:$_" }) -join '|'
                    Add-Content -Path $logFile -Value ("$($start.ToString('s')),traceroute,true,0,false,false,false,,0,$hopStr")
                    Write-Host "  Traceroute: $($trace.TraceRoute.Count) hops" -ForegroundColor Gray
                }
            } catch {
                Write-Host "  Traceroute failed" -ForegroundColor Yellow
            }
            $nextTrace = (Get-Date).AddMinutes($TracerouteIntervalMinutes)
        }

        Start-Sleep -Seconds $PingIntervalSeconds
    }
} finally {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  MONITORING COMPLETE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Log file saved to:" -ForegroundColor Green
    Write-Host "  $logFile" -ForegroundColor White
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Import module and run Network Scan:" -ForegroundColor White
    Write-Host "     Import-Module `$PWD\src\ps\Bottleneck.psm1 -Force" -ForegroundColor Gray
    Write-Host "     Invoke-BottleneckNetworkScan -IncludeFirewall -IncludeVPN" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Or run deep RCA analysis:" -ForegroundColor White
    Write-Host "     Invoke-BottleneckNetworkRootCause" -ForegroundColor Gray
    Write-Host ""
}
