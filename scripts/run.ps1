param(
    [switch] $All,              # Unified: run all computer checks
    [switch] $HealthCheck,
    [switch] $AI,
    [switch] $CollectLogs,
    [switch] $Debug,
    [switch] $Verbose,
    [switch] $Desktop,          # Run desktop diagnostic (Win7-safe) and exit
    [switch] $Network,          # Run network drop monitor/classifier and exit
    [int] $DurationSeconds,     # Pass-through for desktop diagnostic duration
    [switch] $NoLoad,           # Pass-through for desktop diagnostic (skip synthetic load)
    [switch] $HeavyLoad,        # Pass-through for desktop diagnostic (safe heavy probe)
    [switch] $Html,             # Pass-through for desktop diagnostic (generate HTML report)
    [switch] $Elevate,          # Desktop: force elevation before running diagnostic
    [switch] $TryElevateIfSmartBlocked, # Desktop: auto-elevate if SMART access appears blocked
    [int] $DurationMinutes,     # Pass-through for network monitor duration (minutes)
    [int] $CheckIntervalSeconds,# Pass-through for network monitor check interval (seconds)
    [switch] $SkipElevation,    # Internal flag to prevent elevation loop
    [string] $WiresharkPath,    # Optional: path to Wireshark file (.pcapng, .json, .csv)
    [string] $WiresharkDir      # Optional: directory with Wireshark captures; uses latest by time
)

# Fast-path modes before elevation or transcript
if ($Desktop) {
    # Optional elevation for desktop flow (before invoking diagnostic script)
    if (-not $SkipElevation) {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $shouldElevate = $false
        if ($Elevate) { $shouldElevate = $true }
        elseif ($TryElevateIfSmartBlocked -and -not $isAdmin) {
            try {
                # Quick probe for SMART access (common admin-gated WMI class)
                $null = Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSStorageDriver_FailurePredictStatus' -ErrorAction Stop
                $shouldElevate = $false
            }
            catch { $shouldElevate = $true }
        }
        if ($shouldElevate -and -not $isAdmin) {
            Write-Host "Restarting Desktop diagnostic with admin privileges..." -ForegroundColor Yellow
            $scriptPath = $PSCommandPath
            $argsList = @('-Desktop', '-SkipElevation')
            if ($DurationSeconds) { $argsList += @('-DurationSeconds', $DurationSeconds) }
            if ($NoLoad) { $argsList += '-NoLoad' }
            if ($HeavyLoad) { $argsList += '-HeavyLoad' }
            if ($Html) { $argsList += '-Html' }
            if ($Elevate) { $argsList += '-Elevate' }
            if ($TryElevateIfSmartBlocked) { $argsList += '-TryElevateIfSmartBlocked' }
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = (Get-Command pwsh).Source
            $psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $($argsList -join ' ')"
            $psi.Verb = 'runas'
            try { [System.Diagnostics.Process]::Start($psi) | Out-Null } catch { Write-Host "Elevation canceled by user." -ForegroundColor Yellow }
            exit 0
        }
    }
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $deskScript = Join-Path $PSScriptRoot 'run-desktop-diagnostic.ps1'
    if (-not (Test-Path $deskScript)) {
        Write-Host "Desktop diagnostic script not found: $deskScript" -ForegroundColor Red
        exit 1
    }
    $argsList = @()
    if ($PSBoundParameters.ContainsKey('DurationSeconds')) { $argsList += @('-DurationSeconds', $DurationSeconds) }
    if ($NoLoad) { $argsList += '-NoLoad' }
    if ($HeavyLoad) { $argsList += '-HeavyLoad' }
    if ($Html) { $argsList += '-Html' }
    Write-Host "Running desktop diagnostic..." -ForegroundColor Cyan
    Push-Location $repoRoot
    try {
        & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $deskScript @argsList
    }
    finally {
        Pop-Location
    }
    exit 0
}

if ($Network) {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $netScript = Join-Path $PSScriptRoot 'monitor-network-drops.ps1'
    if (-not (Test-Path $netScript)) {
        Write-Host "Network monitor script not found: $netScript" -ForegroundColor Red
        exit 1
    }
    Write-Host "Running network drop monitor (with classification)..." -ForegroundColor Cyan
    Write-Host "Tip: Press Ctrl+C to stop early. Default runs 60 minutes." -ForegroundColor DarkYellow
    Push-Location $repoRoot
    try {
        $argsList = @('-Classify', '-CaptureWlanEvents')
        if ($PSBoundParameters.ContainsKey('DurationMinutes')) { $argsList += @('-DurationMinutes', $DurationMinutes) }
        if ($PSBoundParameters.ContainsKey('CheckIntervalSeconds')) { $argsList += @('-CheckIntervalSeconds', $CheckIntervalSeconds) }
        & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $netScript @argsList
    }
    finally {
        Pop-Location
    }
    exit 0
}

# Check elevation (skip if already attempted)
if (-not $SkipElevation -and -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Restarting with admin privileges..."
    $scriptPath = $PSCommandPath
    $argsList = @('-SkipElevation')  # Add flag to prevent re-elevation
    if ($All) { $argsList += '-All' }
    if ($WiresharkPath) { $argsList += @('-WiresharkPath', ('"' + $WiresharkPath + '"')) }
    if ($AI) { $argsList += '-AI' }
    if ($CollectLogs) { $argsList += '-CollectLogs' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command pwsh).Source
    $psi.Arguments = "-NoLogo -NoProfile -File `"$scriptPath`" $($argsList -join ' ')"
    $psi.Verb = 'runas'
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit 0
}

# Resolve repo root and import module fresh
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Push-Location $repoRoot

# Start transcript logging with date-based folder structure
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$dateFolder = Get-Date -Format 'yyyy-MM-dd'
$reportsDir = Join-Path $repoRoot "Reports" $dateFolder
if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
$logPath = Join-Path $reportsDir "run-$timestamp.log"
Start-Transcript -Path $logPath -Append
try {
    Import-Module "$repoRoot/src/ps/Bottleneck.psm1" -Force -ErrorAction Stop -WarningAction SilentlyContinue
    $importedCmds = Get-Command -Module Bottleneck | Measure-Object | Select-Object -ExpandProperty Count
    Write-Host "Module imported: $importedCmds functions available" -ForegroundColor Green
}
catch {
    Write-Warning "Failed to import Bottleneck module: $($_.Exception.Message)"
    Write-Warning "Error details: $($_.Exception.InnerException.Message)"
    Write-Host "Attempting to continue without full module..."
}

# Unified flow configuration
$enableAI = [bool]$AI

# Initialize debugging if requested
if ($Debug -or $Verbose) {
    try {
        $scanId = Initialize-BottleneckDebug -EnableDebug:$Debug -EnableVerbose:$Verbose -StructuredLog
        Write-Host "Debugging initialized: Scan ID = $scanId" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to initialize debugging: $($_.Exception.Message)"
    }
}

# Health check mode
if ($HealthCheck) {
    try {
        Invoke-BottleneckHealthCheck -Verbose:$Verbose
    }
    catch {
        Write-Warning "Health check failed: $($_.Exception.Message)"
    }
    Stop-Transcript
    Pop-Location
    exit 0
}

# Run unified computer scan
if ($All -or (-not $PSBoundParameters.ContainsKey('All'))) {
    Write-Host "Starting full system scan..." -ForegroundColor Cyan
    Write-BottleneckDebug "Unified scan initiated" -Component "Run"
    $results = $null
    try {
        $results = Invoke-BottleneckScan -Tier Standard -ErrorAction Continue
    }
    catch {
        Write-Host "❌ Scan failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Check log file: $logPath" -ForegroundColor Yellow
        Write-Host "   For detailed errors, run with -Debug or -Verbose" -ForegroundColor Yellow
    }

    if ($results) {
        Write-Host "Generating report..." -ForegroundColor Cyan
        $Global:Bottleneck_EnableAI = $enableAI
        try {
            Invoke-BottleneckReport -Results $results -Tier 'Standard' -ErrorAction Continue
            Write-Host "✓ Report generated successfully" -ForegroundColor Green

            # Save to history
            try {
                Add-ScanToHistory -Results $results -Tier 'Standard' -Metadata @{ scanId = $scanId }
                Write-Host "✓ Scan saved to history" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to save scan to history: $($_.Exception.Message)"
            }
        }
        catch {
            Write-Host "❌ Report generation failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "   Results were collected but report creation failed" -ForegroundColor Yellow
            Write-Host "   Check log file: $logPath" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "⚠ No results to report (scan may have failed)" -ForegroundColor Yellow
    }

    if ($Debug -or $Verbose) {
        Show-BottleneckPerformanceSummary
    }

    # Baseline: save/compare aggregated metrics from computer scan results
    if (($SaveBaseline -or $CompareBaseline) -and $results) {
        try {
            $metrics = @{}
            $count = $results.Count
            $avgScore = $null; $maxScore = $null
            if ($count -gt 0) {
                $avgScore = [math]::Round((($results | Measure-Object -Property Score -Average).Average), 2)
                $maxScore = [math]::Round((($results | Measure-Object -Property Score -Maximum).Maximum), 2)
            }
            $highImpact = ($results | Where-Object { $_.Impact -ge 6 } | Measure-Object).Count
            $thermalFindings = ($results | Where-Object { $_.Category -match 'Thermal|Temperature' } | Measure-Object).Count
            $cpuFindings = ($results | Where-Object { $_.Category -match 'CPU' } | Measure-Object).Count
            $memoryFindings = ($results | Where-Object { $_.Category -match 'Memory|RAM' } | Measure-Object).Count
            $diskFindings = ($results | Where-Object { $_.Category -match 'Disk|Storage' } | Measure-Object).Count

            $metrics.TotalFindings = [int]$count
            if ($avgScore -ne $null) { $metrics.AvgScore = [double]$avgScore }
            if ($maxScore -ne $null) { $metrics.MaxScore = [double]$maxScore }
            $metrics.HighImpact = [int]$highImpact
            $metrics.ThermalFindings = [int]$thermalFindings
            $metrics.CPUFindings = [int]$cpuFindings
            $metrics.MemoryFindings = [int]$memoryFindings
            $metrics.DiskFindings = [int]$diskFindings

            if ($SaveBaseline) {
                $name = if ($BaselineName) { $BaselineName } else { "computer-$(Get-Date -Format 'yyyy-MM-dd')" }
                $saved = Save-BottleneckBaseline -Metrics $metrics -Name $name -Path $BaselinePath
                Write-Host "Saved computer baseline: $saved" -ForegroundColor Green
            }
            if ($CompareBaseline) {
                $comparison = $null
                try { $comparison = Compare-ToBaseline -Metrics $metrics -Name $CompareBaseline -Path $BaselinePath } catch { Write-Warning "Compare failed: $($_.Exception.Message)" }
                if ($comparison) {
                    Write-Host "Baseline comparison: '$($comparison.name)' (captured $($comparison.timestamp))" -ForegroundColor Cyan
                    # Compute anomaly score using baseline metrics document
                    $repoRootLocal = Split-Path -Path $PSScriptRoot -Parent
                    $baseDir = if ($BaselinePath) { $BaselinePath } else { Join-Path $repoRootLocal 'baselines' }
                    $baseFile = Join-Path $baseDir ("$($comparison.name).json")
                    if (Test-Path $baseFile) {
                        $baseDoc = Get-Content -Path $baseFile -Raw | ConvertFrom-Json
                        $score = Get-AnomalyScore -Metrics $metrics -Baseline ($baseDoc.metrics | ConvertTo-Json | ConvertFrom-Json)
                        Write-Host "Anomaly score: $score" -ForegroundColor Yellow
                    }
                    foreach ($k in @('TotalFindings', 'AvgScore', 'MaxScore', 'HighImpact', 'ThermalFindings', 'CPUFindings', 'MemoryFindings', 'DiskFindings')) {
                        if ($comparison.comparison.ContainsKey($k)) {
                            $c = $comparison.comparison[$k]
                            $pct = if ($c.percent -ne $null) { "$($c.percent)%" } else { 'n/a' }
                            Write-Host (" - {0,-16} curr={1} base={2} Δ={3} ({4})" -f $k, $c.current, $c.baseline, $c.delta, $pct)
                        }
                    }
                }
            }
        }
        catch {
            Write-Host "⚠ Baseline processing error (Computer): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "   Baseline operations require valid scan results and write access to baselines/" -ForegroundColor Yellow
        }
    }
}

# Optional: Analyze Wireshark CSV if provided
if ($WiresharkPath -or $WiresharkDir) {
    if (-not $WiresharkPath) {
        $latest = Get-LatestWiresharkCapture -Directory $WiresharkDir
        if ($latest) { $WiresharkPath = $latest.FullName }
    }
    if (-not $WiresharkPath) {
        Write-Host "⚠ No Wireshark capture found in '$WiresharkDir'" -ForegroundColor Yellow
    }
}

if ($WiresharkPath) {
    Write-Host "Analyzing Wireshark capture: $WiresharkPath" -ForegroundColor Cyan
    try {
        $ext = [System.IO.Path]::GetExtension($WiresharkPath).TrimStart('.')
        $fmt = if ($ext -eq 'pcapng') { 'pcapng' } elseif ($ext -eq 'json') { 'json' } else { 'csv' }
        $ws = Analyze-WiresharkCapture -Path $WiresharkPath -Format $fmt -ErrorAction Stop
        if ($ws) {
            Write-Host ("Wireshark summary: packets={0}, drops={1}, avgLatency={2}ms, maxLatency={3}ms" -f $ws.Packets, $ws.Drops, $ws.AvgLatencyMs, $ws.MaxLatencyMs) -ForegroundColor Green
            try {
                Add-WiresharkSummaryToReport -Summary $ws
            }
            catch {}
        }
    }
    catch {
        Write-Host "⚠ Wireshark analysis failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Open latest report if exists
$latestReport = Get-ChildItem "$repoRoot/Reports" -Filter 'Full-scan-*.html' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestReport) {
    Write-Host ("Report: " + $latestReport.FullName)
    try { Start-Process $latestReport.FullName } catch {}
}

# Collect logs optionally
if ($CollectLogs) {
    Write-Host "Collecting logs and artifacts..."
    & "$repoRoot/scripts/collect-logs.ps1" -IncludeAll -OpenFolder
}

Stop-Transcript
Pop-Location
