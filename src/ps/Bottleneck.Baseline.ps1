# Bottleneck.Baseline.ps1
# Baseline save/compare and anomaly scoring (Phase 2 scaffold)

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

# Exports are handled in Bottleneck.psm1
