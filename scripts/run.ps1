param(
    [switch] $Computer,
    [switch] $Network,
    [switch] $HealthCheck,  # NEW: Environment validation mode
    [int] $Minutes,
    [string] $Profile,
    [switch] $ListProfiles,
    [switch] $AI,
    [switch] $CollectLogs,
    [int] $TraceIntervalMinutes,
    [string] $TargetHost,
    [switch] $NoTrace,
    [string] $DnsPrimary,
    [string] $DnsSecondary,
    [switch] $Debug,  # NEW: Enable debug output
    [switch] $Verbose,  # NEW: Enable verbose output
    [switch] $SaveBaseline,  # NEW: Save baseline from run outputs
    [string] $BaselineName,  # NEW: Optional baseline name
    [string] $BaselinePath,  # NEW: Optional baseline directory
    [string] $CompareBaseline,  # NEW: Compare against named baseline
    [switch] $SkipElevation  # Internal flag to prevent elevation loop
)

# Check elevation (skip if already attempted)
if (-not $SkipElevation -and -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Restarting with admin privileges..."
    $scriptPath = $PSCommandPath
    $argsList = @('-SkipElevation')  # Add flag to prevent re-elevation
    if ($Computer) { $argsList += '-Computer' }
    if ($Network) { $argsList += '-Network' }
    if ($Minutes) { $argsList += @('-Minutes', $Minutes) }
    if ($Profile) { $argsList += @('-Profile', $Profile) }
    if ($AI) { $argsList += '-AI' }
    if ($CollectLogs) { $argsList += '-CollectLogs' }
    if ($TraceIntervalMinutes) { $argsList += @('-TraceIntervalMinutes', $TraceIntervalMinutes) }
    if ($TargetHost) { $argsList += @('-TargetHost', $TargetHost) }
    if ($NoTrace) { $argsList += '-NoTrace' }
    if ($DnsPrimary) { $argsList += @('-DnsPrimary', $DnsPrimary) }
    if ($DnsSecondary) { $argsList += @('-DnsSecondary', $DnsSecondary) }
    if ($SaveBaseline) { $argsList += '-SaveBaseline' }
    if ($BaselineName) { $argsList += @('-BaselineName', $BaselineName) }
    if ($BaselinePath) { $argsList += @('-BaselinePath', $BaselinePath) }
    if ($CompareBaseline) { $argsList += @('-CompareBaseline', $CompareBaseline) }
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
} catch {
    Write-Warning "Failed to import Bottleneck module: $($_.Exception.Message)"
    Write-Warning "Error details: $($_.Exception.InnerException.Message)"
    Write-Host "Attempting to continue without full module..."
}

# List profiles and exit if requested
if ($ListProfiles) {
    try {
        $names = Get-BottleneckProfile -ListNames
        Write-Host "Available profiles:" -ForegroundColor Cyan
        $names | ForEach-Object { Write-Host " - $_" }
    } catch {
        Write-Warning "Failed to list profiles: $($_.Exception.Message)"
        Write-Host "You can also open '$repoRoot\config\scan-profiles.json' to view definitions." -ForegroundColor Yellow
    }
    Stop-Transcript
    Pop-Location
    exit 0
}

# Load profile if provided
$effectiveMinutes = $Minutes
$enableAI = [bool]$AI
$effectiveTraceInterval = $TraceIntervalMinutes
$effectiveTier = "Standard"  # Default tier
$profileConfig = $null

if ($Profile) {
    $profilesPath = Join-Path $repoRoot 'config/scan-profiles.json'
    if (Test-Path $profilesPath) {
        try {
            $profiles = Get-Content $profilesPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $p = $profiles.$Profile
            if ($null -ne $p) {
                $profileConfig = $p  # Store for later use
                if (-not $Minutes -and $p.minutes) { $effectiveMinutes = [int]$p.minutes }
                if (-not $AI -and $p.ai -ne $null) { $enableAI = [bool]$p.ai }
                if (-not $TraceIntervalMinutes -and $p.traceIntervalMinutes) { $effectiveTraceInterval = [int]$p.traceIntervalMinutes }
                if (-not $TargetHost -and $p.targetHost) { $TargetHost = [string]$p.targetHost }
                if (-not $DnsPrimary -and $p.dnsPrimary) { $DnsPrimary = [string]$p.dnsPrimary }
                if (-not $DnsSecondary -and $p.dnsSecondary) { $DnsSecondary = [string]$p.dnsSecondary }
                if ($p.tier) { $effectiveTier = [string]$p.tier }

                Write-Host "✓ Profile '$Profile' loaded" -ForegroundColor Green
                Write-Host "  Tier: $effectiveTier | Network: ${effectiveMinutes}min | AI: $enableAI" -ForegroundColor Cyan
                if ($p.emphasis) {
                    Write-Host "  Focus: $($p.emphasis -join ', ')" -ForegroundColor Yellow
                }
                if ($p.includedChecks) {
                    Write-Host "  Checks: $($p.includedChecks.Count) included, $($p.excludedChecks.Count) excluded" -ForegroundColor Gray
                }
            } else {
                Write-Warning "Profile '$Profile' not found in $profilesPath"
                Write-Host "Available profiles: $($profiles.PSObject.Properties.Name -join ', ')" -ForegroundColor Yellow
                Write-Host "Use 'Get-BottleneckProfile' to list all profiles" -ForegroundColor Cyan
            }
        } catch {
            Write-Warning "Failed to read profiles: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Profiles file not found: $profilesPath"
    }
}

# Initialize debugging if requested
if ($Debug -or $Verbose) {
    try {
        $scanId = Initialize-BottleneckDebug -EnableDebug:$Debug -EnableVerbose:$Verbose -StructuredLog
        Write-Host "Debugging initialized: Scan ID = $scanId" -ForegroundColor Cyan
    } catch {
        Write-Warning "Failed to initialize debugging: $($_.Exception.Message)"
    }
}

# Health check mode
if ($HealthCheck) {
    try {
        Invoke-BottleneckHealthCheck -Verbose:$Verbose
    } catch {
        Write-Warning "Health check failed: $($_.Exception.Message)"
    }
    Stop-Transcript
    Pop-Location
    exit 0
}

# Default minutes
if (-not $effectiveMinutes) { $effectiveMinutes = 15 }
if (-not $effectiveTraceInterval) { $effectiveTraceInterval = 5 }

# Run Computer scan
if ($Computer) {
    Write-Host "Starting Computer scan (Tier: $effectiveTier)..." -ForegroundColor Cyan
    Write-BottleneckDebug "Computer scan initiated with tier=$effectiveTier" -Component "Run"
    $results = $null
    try {
        $results = Invoke-BottleneckScan -Tier $effectiveTier -ErrorAction Stop

        # Apply profile filtering if includedChecks or excludedChecks are specified
        if ($profileConfig -and ($profileConfig.includedChecks -or $profileConfig.excludedChecks)) {
            $originalCount = $results.Count

            if ($profileConfig.includedChecks) {
                $results = $results | Where-Object { $profileConfig.includedChecks -contains $_.Id }
                Write-Host "  Filtered to included checks: $($results.Count) of $originalCount results" -ForegroundColor Gray
            }

            if ($profileConfig.excludedChecks) {
                $results = $results | Where-Object { $profileConfig.excludedChecks -notcontains $_.Id }
                Write-Host "  Filtered out excluded checks: $($results.Count) of $originalCount results" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "❌ Computer scan failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Check log file: $logPath" -ForegroundColor Yellow
        Write-Host "   For detailed errors, run with -Debug or -Verbose" -ForegroundColor Yellow
    }

    if ($results) {
        Write-Host "Generating report..." -ForegroundColor Cyan
        $Global:Bottleneck_EnableAI = $enableAI
        try {
            Invoke-BottleneckReport -Results $results -Tier $effectiveTier -ErrorAction Stop
            Write-Host "✓ Report generated successfully" -ForegroundColor Green
            if ($Profile) {
                Write-Host "  Profile: $Profile" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "❌ Report generation failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "   Results were collected but report creation failed" -ForegroundColor Yellow
            Write-Host "   Check log file: $logPath" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠ No results to report (scan may have failed)" -ForegroundColor Yellow
    }

    # Show performance summary if debugging
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
                    foreach ($k in @('TotalFindings','AvgScore','MaxScore','HighImpact','ThermalFindings','CPUFindings','MemoryFindings','DiskFindings')) {
                        if ($comparison.comparison.ContainsKey($k)) {
                            $c = $comparison.comparison[$k]
                            $pct = if ($c.percent -ne $null) { "$($c.percent)%" } else { 'n/a' }
                            Write-Host (" - {0,-16} curr={1} base={2} Δ={3} ({4})" -f $k, $c.current, $c.baseline, $c.delta, $pct)
                        }
                    }
                }
            }
        } catch {
            Write-Host "⚠ Baseline processing error (Computer): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "   Baseline operations require valid scan results and write access to baselines/" -ForegroundColor Yellow
        }
    }
}

# Run Network scan + RCA/Diagnostics
if ($Network) {
    Write-Host "Starting network monitor for $effectiveMinutes minute(s)..." -ForegroundColor Cyan
    Write-BottleneckDebug "Network scan initiated: duration=$effectiveMinutes min, target=$TargetHost" -Component "Run"
    $durationHours = [math]::Round($effectiveMinutes / 60.0, 2)
    $nmParams = @{ DurationHours = $durationHours; TraceIntervalMinutes = $effectiveTraceInterval }
    if ($TargetHost) { $nmParams.TargetHost = $TargetHost }
    if ($NoTrace) { $nmParams.NoTrace = $true }
    if ($DnsPrimary) { $nmParams.DnsPrimary = $DnsPrimary }
    if ($DnsSecondary) { $nmParams.DnsSecondary = $DnsSecondary }
    if ($Debug) { $nmParams.Debug = $true }
    if ($Verbose) { $nmParams.Verbose = $true }

    try {
        & "$repoRoot/scripts/run-network-monitor.ps1" @nmParams -ErrorAction Stop
        Write-Host "✓ Network monitoring complete" -ForegroundColor Green
    } catch {
        Write-Host "❌ Network monitor failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   This may be due to missing network tools (Test-NetConnection, traceroute)" -ForegroundColor Yellow
        Write-Host "   Check log file: $logPath" -ForegroundColor Yellow
    }

    Write-Host "Running RCA and diagnostics..." -ForegroundColor Cyan
    $rca = $null
    $diag = $null
    try {
        $rca = Invoke-BottleneckNetworkRootCause
        if ($rca) {
            Write-Host "✓ RCA likely cause: $($rca.LikelyCause)" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠ RCA failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   Root cause analysis requires network-monitor JSON output" -ForegroundColor Yellow
    }

    try {
        $diag = Invoke-BottleneckNetworkCsvDiagnostics
        if ($diag) {
            Write-Host "✓ CSV fused alert: $($diag.FusedAlertLevel)" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠ Diagnostics failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   CSV diagnostics require network-monitor CSV output" -ForegroundColor Yellow
    }

    # Show performance summary if debugging
    if ($Debug -or $Verbose) {
        Show-BottleneckPerformanceSummary
        $perfFile = Join-Path $reportsDir "performance-$timestamp.json"
        Export-BottleneckPerformanceMetrics -Path $perfFile
    }

    # Baseline: save/compare using latest network JSON summary
    if ($SaveBaseline -or $CompareBaseline) {
        try {
            $latestJson = Get-ChildItem -Path $reportsDir -Filter 'network-monitor-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $latestJson) {
                Write-Host "⚠ No network summary JSON found in $reportsDir; cannot baseline" -ForegroundColor Yellow
                Write-Host "   Network baselines require successful network-monitor run first" -ForegroundColor Yellow
            } else {
                $summary = Get-Content -Path $latestJson.FullName -Raw | ConvertFrom-Json
                $metrics = @{}
                # Safely extract numeric metrics
                $metrics.PacketLossPercent = [double]($summary.totals.packetLossPercent)
                $metrics.SuccessPercent = [double]($summary.totals.successPercent)
                if ($summary.latency) {
                    if ($summary.latency.averageMs -ne $null) { $metrics.AvgResponseMs = [double]$summary.latency.averageMs }
                    if ($summary.latency.maxMs -ne $null) { $metrics.MaxResponseMs = [double]$summary.latency.maxMs }
                    if ($summary.latency.minMs -ne $null) { $metrics.MinResponseMs = [double]$summary.latency.minMs }
                }
                if ($summary.drops) {
                    if ($summary.drops.count -ne $null) { $metrics.Drops = [int]$summary.drops.count }
                    if ($summary.drops.averageSeconds -ne $null) { $metrics.AvgDropSec = [double]$summary.drops.averageSeconds }
                    if ($summary.drops.maxSeconds -ne $null) { $metrics.MaxDropSec = [double]$summary.drops.maxSeconds }
                }
                if ($summary.failures) {
                    if ($summary.failures.dns -ne $null) { $metrics.DnsFailures = [int]$summary.failures.dns }
                    if ($summary.failures.router -ne $null) { $metrics.RouterIssues = [int]$summary.failures.router }
                    if ($summary.failures.isp -ne $null) { $metrics.IspIssues = [int]$summary.failures.isp }
                }

                if ($SaveBaseline) {
                    $name = if ($BaselineName) { $BaselineName } else { "network-$(Get-Date -Format 'yyyy-MM-dd')" }
                    $saved = Save-BottleneckBaseline -Metrics $metrics -Name $name -Path $BaselinePath
                    Write-Host "Saved network baseline: $saved" -ForegroundColor Green
                }
                if ($CompareBaseline) {
                    $comparison = $null
                    try {
                        $comparison = Compare-ToBaseline -Metrics $metrics -Name $CompareBaseline -Path $BaselinePath
                    } catch {
                        Write-Warning "Compare failed: $($_.Exception.Message)"
                    }
                    if ($comparison) {
                        Write-Host "Baseline comparison: '$($comparison.name)' (captured $($comparison.timestamp))" -ForegroundColor Cyan
                        # Compute anomaly score
                        $repoRootLocal = Split-Path -Path $PSScriptRoot -Parent
                        $baseDir = if ($BaselinePath) { $BaselinePath } else { Join-Path $repoRootLocal 'baselines' }
                        $baseFile = Join-Path $baseDir ("$($comparison.name).json")
                        if (Test-Path $baseFile) {
                            $baseDoc = Get-Content -Path $baseFile -Raw | ConvertFrom-Json
                            $score = Get-AnomalyScore -Metrics $metrics -Baseline ($baseDoc.metrics | ConvertTo-Json | ConvertFrom-Json)
                            Write-Host "Anomaly score: $score" -ForegroundColor Yellow
                        }
                        # Print key deltas
                        foreach ($k in @('PacketLossPercent','AvgResponseMs','MaxResponseMs','Drops','AvgDropSec','MaxDropSec')) {
                            if ($comparison.comparison.ContainsKey($k)) {
                                $c = $comparison.comparison[$k]
                                $pct = if ($c.percent -ne $null) { "$($c.percent)%" } else { 'n/a' }
                                Write-Host (" - {0,-14} curr={1} base={2} Δ={3} ({4})" -f $k, $c.current, $c.baseline, $c.delta, $pct)
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Host "⚠ Baseline processing error (Network): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "   Check that network-monitor JSON exists and is valid" -ForegroundColor Yellow
        }
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
