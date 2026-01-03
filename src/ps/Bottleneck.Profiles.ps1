<#
.SYNOPSIS
    Get available scan profiles and their configurations.

.DESCRIPTION
    Lists all available scan profiles with descriptions, included checks, and emphasis areas.
    Profiles are persona-based configurations optimized for specific use cases.

.PARAMETER Name
    Optional. Name of a specific profile to retrieve. If omitted, lists all profiles.

.PARAMETER ListNames
    Returns only profile names without details.

.EXAMPLE
    Get-BottleneckProfile
    Lists all available profiles with full details.

.EXAMPLE
    Get-BottleneckProfile -Name "RemoteWorker"
    Shows details for the RemoteWorker profile only.

.EXAMPLE
    Get-BottleneckProfile -ListNames
    Returns just the profile names.
#>
function Get-BottleneckProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [switch]$ListNames
    )

    try {
        $profilePath = Join-Path $PSScriptRoot "..\..\config\scan-profiles.json"

        if (-not (Test-Path $profilePath)) {
            Write-Error "Profile configuration not found: $profilePath"
            return
        }

        $profiles = Get-Content $profilePath -Raw | ConvertFrom-Json

        if ($ListNames) {
            return $profiles.PSObject.Properties.Name
        }

        if ($Name) {
            $profile = $profiles.$Name
            if (-not $profile) {
                Write-Error "Profile '$Name' not found. Available profiles: $($profiles.PSObject.Properties.Name -join ', ')"
                return
            }

            $output = [PSCustomObject]@{
                Name = $Name
                Description = $profile.description
                Tier = $profile.tier
                NetworkMinutes = $profile.minutes
                TraceInterval = $profile.traceIntervalMinutes
                TargetHost = $profile.targetHost
                Emphasis = $profile.emphasis -join ', '
                IncludedChecks = if ($profile.includedChecks) { $profile.includedChecks.Count } else { "All for tier" }
                ExcludedChecks = if ($profile.excludedChecks) { $profile.excludedChecks.Count } else { 0 }
            }

            Write-Host "`n=== $Name Profile ===" -ForegroundColor Cyan
            Write-Host "Description: $($output.Description)" -ForegroundColor White
            Write-Host "Tier: $($output.Tier)" -ForegroundColor Yellow
            Write-Host "Network Monitoring: $($output.NetworkMinutes) minutes" -ForegroundColor White
            Write-Host "Trace Interval: $($output.TraceInterval) minutes" -ForegroundColor White
            Write-Host "Target Host: $($output.TargetHost)" -ForegroundColor White

            if ($profile.emphasis) {
                Write-Host "Emphasis Areas: $($output.Emphasis)" -ForegroundColor Green
            }

            if ($profile.includedChecks) {
                Write-Host "`nIncluded Checks ($($profile.includedChecks.Count)):" -ForegroundColor Green
                $profile.includedChecks | ForEach-Object { Write-Host "  • $_" -ForegroundColor Gray }
            }

            if ($profile.excludedChecks) {
                Write-Host "`nExcluded Checks ($($profile.excludedChecks.Count)):" -ForegroundColor Red
                $profile.excludedChecks | ForEach-Object { Write-Host "  • $_" -ForegroundColor Gray }
            }

            Write-Host ""
            return $output
        }

        # List all profiles
        Write-Host "`n=== Available Scan Profiles ===" -ForegroundColor Cyan
        Write-Host ""

        foreach ($profileName in $profiles.PSObject.Properties.Name) {
            $profile = $profiles.$profileName
            $tierBadge = switch ($profile.tier) {
                "Quick" { "[QUICK]" }
                "Standard" { "[STANDARD]" }
                "Deep" { "[DEEP]" }
                default { "" }
            }

            Write-Host "$tierBadge $profileName" -ForegroundColor Yellow
            Write-Host "  $($profile.description)" -ForegroundColor Gray

            if ($profile.emphasis) {
                Write-Host "  Focus: $($profile.emphasis -join ', ')" -ForegroundColor Green
            }

            Write-Host ""
        }

        Write-Host "Use: Get-BottleneckProfile -Name <ProfileName> for details" -ForegroundColor Cyan
        Write-Host "Use: .\run.ps1 -Computer -Profile <ProfileName> to run a profile" -ForegroundColor Cyan
        Write-Host ""

    } catch {
        Write-Error "Error reading profiles: $_"
    }
}

# ============================================================================
# Baseline save/compare and anomaly scoring functions
# (Moved from Bottleneck.Baseline.ps1)
# ============================================================================

function Save-BottleneckBaseline {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][hashtable]$Metrics,
        [string]$Name,
        [string]$Path
    )
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $baseDir = if ($Path) { $Path } else { Join-Path $repoRoot 'baselines' }
    if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir -Force | Out-Null }
    if (-not $Name) { $Name = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') }
    $file = Join-Path $baseDir ("$Name.json")
    $doc = [ordered]@{
        name = $Name
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        hostname = $env:COMPUTERNAME
        metrics = $Metrics
    }
    $doc | ConvertTo-Json -Depth 8 | Set-Content -Path $file -Encoding UTF8
    Write-Host ("Baseline saved: " + $file) -ForegroundColor Green
    return $file
}

function Compare-ToBaseline {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][hashtable]$Metrics,
        [Parameter(Mandatory)][string]$Name,
        [string]$Path
    )
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $baseDir = if ($Path) { $Path } else { Join-Path $repoRoot 'baselines' }
    $file = Join-Path $baseDir ("$Name.json")
    if (-not (Test-Path $file)) { throw "Baseline not found: $file" }
    $baseline = Get-Content $file -Raw | ConvertFrom-Json
    $diff = @{}
    foreach ($k in $Metrics.Keys) {
        $curr = $Metrics[$k]
        $base = $baseline.metrics.$k
        if ($null -ne $base -and $null -ne $curr -and ($curr -is [double] -or $curr -is [int])) {
            $delta = [double]$curr - [double]$base
            $pct = if ([double]$base -ne 0) { [math]::Round(($delta / [double]$base) * 100, 2) } else { $null }
            $diff[$k] = @{ current = $curr; baseline = $base; delta = $delta; percent = $pct }
        } else {
            $diff[$k] = @{ current = $curr; baseline = $base; delta = $null; percent = $null }
        }
    }
    return [pscustomobject]@{
        name = $baseline.name
        timestamp = $baseline.timestamp
        comparison = $diff
    }
}

function Get-AnomalyScore {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][hashtable]$Metrics,
        [Parameter(Mandatory)][hashtable]$Baseline,
        [double]$ZScoreThreshold = 2.0
    )
    # Simple heuristic: score increments when current >> baseline
    $score = 0
    foreach ($k in $Metrics.Keys) {
        $curr = $Metrics[$k]
        $base = $Baseline[$k]
        if ($null -ne $base -and $null -ne $curr -and ($curr -is [double] -or $curr -is [int])) {
            if ([double]$base -eq 0 -and [double]$curr -gt 0) { $score += 1; continue }
            $ratio = if ([double]$base -ne 0) { [double]$curr / [double]$base } else { 0 }
            if ($ratio -ge 2.0) { $score += 2 } elseif ($ratio -ge 1.5) { $score += 1 }
        }
    }
    return $score
}
