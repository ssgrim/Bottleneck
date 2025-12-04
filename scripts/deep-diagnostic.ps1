# Unified Deep Diagnostic and Remediation Entrypoint
# Orchestrates dumpcap, monitor, and optional auto-remediation
# One command to start and walk away

param(
    [int]$DurationMinutes = 240,
    [int]$CheckIntervalSeconds = 5,
    [switch]$Remediate = $false,  # Auto-apply fixes
    [switch]$Wireshark = $true,   # Start dumpcap ring buffer
    [int]$PktmonBufferMB = 128,
    [int]$PktSize = 256
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$wiresharkLogsDir = Join-Path $repoRoot 'WireSharkLogs'
$reportsDir = Join-Path $repoRoot 'Reports'
$capsDir = Join-Path $reportsDir 'captures'

# Ensure directories exist
foreach ($dir in $wiresharkLogsDir, $reportsDir, $capsDir) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

Write-Host "🚀 Bottleneck Deep Diagnostic Suite" -ForegroundColor Cyan
Write-Host "Duration: $DurationMinutes minutes" -ForegroundColor Gray
Write-Host "Wireshark: $Wireshark | Auto-Remediate: $Remediate" -ForegroundColor Gray
Write-Host ""

$jobs = @()

# 1. Optional: Apply WiFi fixes
if ($Remediate) {
    Write-Host "📋 Applying WiFi remediation..." -ForegroundColor Yellow
    try {
        $null = & powershell -Verb RunAs -ArgumentList @(
            "-NoExit", "-Command",
            "cd '$repoRoot'; & '.\scripts\remediate-wifi-issues.ps1' -Dry:`$false"
        ) -ErrorAction SilentlyContinue
    } catch {
        Write-Host "   (could not launch remediation; skipping)" -ForegroundColor DarkYellow
    }
    Write-Host ""
}

# 2. Optional: Start Wireshark dumpcap ring buffer
if ($Wireshark) {
    Write-Host "📡 Starting Wireshark capture..." -ForegroundColor Cyan
    try {
        $dumpcap = & 'C:\Program Files\Wireshark\dumpcap.exe' -D 2>&1 | Select-String -Pattern "Wi-Fi" | Select-Object -First 1
        if ($dumpcap -match "(\d+)\.\s") {
            $ifIdx = [int]$Matches[1]
            $job = Start-Job -ScriptBlock {
                param($idx, $out)
                & 'C:\Program Files\Wireshark\dumpcap.exe' -i $idx -q `
                  -f "not multicast and not broadcast" `
                  -b filesize:100000 -b files:10 `
                  -w "$out\ring.pcapng"
            } -ArgumentList $ifIdx, $wiresharkLogsDir
            $jobs += $job
            Write-Host "   ✓ Wireshark capture running on interface $ifIdx" -ForegroundColor Green
        } else {
            Write-Host "   ❌ Could not find Wi-Fi interface for capture" -ForegroundColor Red
        }
    } catch {
        Write-Host "   ⚠️  Wireshark not available or error: $_" -ForegroundColor Yellow
    }
    Write-Host ""
}

# 3. Start elevated network drop monitor
Write-Host "🔍 Starting network drop monitor (elevated)..." -ForegroundColor Cyan
try {
    $monitorJob = Start-Process pwsh -Verb RunAs -PassThru -ArgumentList @(
        "-NoExit", "-Command",
        "cd '$repoRoot'; `
         .\scripts\monitor-network-drops.ps1 `
           -DurationMinutes $DurationMinutes `
           -CheckIntervalSeconds $CheckIntervalSeconds `
           -Classify -CaptureWlanEvents -CapturePackets `
           -PktmonBufferMB $PktmonBufferMB -PktSize $PktSize"
    )
    $jobs += $monitorJob
    Write-Host "   ✓ Monitor PID: $($monitorJob.Id)" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Could not start monitor: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=" * 60
Write-Host "All jobs running. Waiting for monitor to complete ($DurationMinutes minutes)..." -ForegroundColor Cyan
Write-Host "Go about your normal tasks; drops will be captured." -ForegroundColor Gray
Write-Host ""

# Wait for monitor to complete
if ($monitorJob) {
    $null = $monitorJob | Wait-Process -Timeout ($DurationMinutes * 60 + 60) -ErrorAction SilentlyContinue
}

# Stop other jobs gracefully
foreach ($job in $jobs) {
    if ($job.ProcessName -ne 'pwsh' -and $job.Id -ne $monitorJob.Id) {
        try {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        } catch { }
    }
}

Write-Host ""
Write-Host "=" * 60
Write-Host "✓ Diagnostic collection complete!" -ForegroundColor Green
Write-Host ""
Write-Host "📂 Output locations:" -ForegroundColor Cyan
Write-Host "   Wireshark captures: $wiresharkLogsDir" -ForegroundColor Gray
Write-Host "   Monitor logs: $reportsDir\network-drop-*.log" -ForegroundColor Gray
Write-Host "   Drop pcapngs: $capsDir\drop-*.pcapng" -ForegroundColor Gray
Write-Host ""
Write-Host "📊 Auto-analyze results:" -ForegroundColor Cyan
Write-Host "   .\scripts\run.ps1 -Computer -WiresharkDir '$wiresharkLogsDir'" -ForegroundColor Gray
Write-Host ""
