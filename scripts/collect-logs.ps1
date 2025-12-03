param(
    [string[]]$ReportsDirs,
    [string]$OutputDir = (Join-Path $PSScriptRoot '..' 'Reports'),
    [switch]$IncludeAll,
    [bool]$CopyToClipboard = $true,
    [switch]$OpenFolder
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] $msg"
}

# Default report directories: top-level Reports and nested bottleneck\Reports if present
if (-not $ReportsDirs) {
    $rootReports = (Join-Path $PSScriptRoot '..' 'Reports')
    $nestedReports = (Join-Path $PSScriptRoot '..' 'bottleneck' 'Reports')
    $ReportsDirs = @()
    if (Test-Path $rootReports) { $ReportsDirs += (Resolve-Path $rootReports).Path }
    if (Test-Path $nestedReports) { $ReportsDirs += (Resolve-Path $nestedReports).Path }
}

if (-not $ReportsDirs -or ($ReportsDirs | ForEach-Object { Test-Path $_ } | Where-Object { $_ } | Measure-Object).Count -eq 0) {
    throw "No Reports directories found. Checked: $($ReportsDirs -join ', ')"
}

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$outputFolder = Join-Path $OutputDir "bottleneck-logs-$timestamp"

Write-Info ("Collecting logs from: " + ($ReportsDirs -join '; '))

# Patterns of interest
$patterns = @(
    # Network monitor artifacts
    'network-monitor-*.out',
    'network-monitor-*.csv',
    'network-monitor-*.html',
    # Report HTMLs
    'Full-scan-*.html',
    'Deep-scan-*.html',
    'Quick-scan-*.html',
    # Report PDFs (when generated)
    'Full-scan-*.pdf',
    'Deep-scan-*.pdf',
    'Quick-scan-*.pdf',
    'Basic-scan-*.pdf'
)

$files = @()
foreach ($dir in $ReportsDirs) {
    foreach ($pat in $patterns) {
        $matched = Get-ChildItem -Path $dir -Filter $pat -File -ErrorAction SilentlyContinue
        if ($IncludeAll) {
            $files += $matched
        } else {
            if ($matched) {
                $latest = $matched | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                $files += $latest
            }
        }
    }
}

# Also include any .log files if present
$logFiles = @()
foreach ($dir in $ReportsDirs) {
    $logFiles += Get-ChildItem -Path $dir -Filter '*.log' -File -ErrorAction SilentlyContinue
}
if ($IncludeAll) {
    $files += $logFiles
} else {
    if ($logFiles) {
        $files += ($logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    }
}

$files = $files |
    Where-Object { $_ -ne $null } |
    Where-Object { $_.Extension -ne '.zip' } |
    Sort-Object FullName -Unique

if (-not $files -or $files.Count -eq 0) {
    Write-Info 'No matching report or log files found.'
    Write-Info "You can generate them via 'scripts\\run-network-monitor.ps1' or report commands."
    exit 0
}

Write-Info ("Including files:" )
$files | ForEach-Object { Write-Host (' - ' + $_.FullName) }

# Create output folder
if (Test-Path $outputFolder) { Remove-Item $outputFolder -Recurse -Force }
New-Item -ItemType Directory -Path $outputFolder | Out-Null

foreach ($f in $files) {
    Copy-Item -Path $f.FullName -Destination (Join-Path $outputFolder $f.Name)
}

Write-Info ("Created: $outputFolder")
Write-Info 'Files collected and ready for review.'

if ($CopyToClipboard) {
    try {
        Set-Clipboard -Value $outputFolder
        Write-Info 'Folder path copied to clipboard.'
    } catch {
        Write-Info ("Could not copy to clipboard: " + $_.Exception.Message)
    }
}

if ($OpenFolder) {
    try {
        Start-Process -FilePath explorer.exe -ArgumentList "`"$outputFolder`""
        Write-Info 'Opened File Explorer to the collected files.'
    } catch {
        Write-Info ("Could not open File Explorer: " + $_.Exception.Message)
    }
}
