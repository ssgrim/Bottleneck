# generate-enhanced-report.ps1
# Helper script to generate enhanced visual reports from network monitor data

param(
    [string]$JsonPath,
    [switch]$Latest,
    [switch]$Open,
    [switch]$Offline  # Embed Chart.js/Leaflet inline for air-gapped environments
)

$ErrorActionPreference = 'Stop'

# Import the enhanced report module
$modulePath = Join-Path $PSScriptRoot '..' 'src' 'ps' 'Bottleneck.EnhancedReport.ps1'
. $modulePath

# Find latest JSON if not specified
if ($Latest -or -not $JsonPath) {
    $reportsDir = Join-Path $PSScriptRoot '..' 'Reports'
    $jsonFile = Get-ChildItem $reportsDir -Filter 'network-monitor-*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $jsonFile) {
        Write-Error "No network monitor JSON files found in $reportsDir"
        exit 1
    }

    $JsonPath = $jsonFile.FullName
    Write-Host "📁 Using latest report: $($jsonFile.Name)" -ForegroundColor Cyan
}

if (-not (Test-Path $JsonPath)) {
    Write-Error "JSON file not found: $JsonPath"
    exit 1
}

Write-Host "🎨 Generating enhanced visual report..." -ForegroundColor Cyan
Write-Host ""

$outputPath = New-BottleneckEnhancedNetworkReport -JsonPath $JsonPath -OpenBrowser:$Open -Offline:$Offline

Write-Host ""
Write-Host "✅ Done! Report saved to:" -ForegroundColor Green
Write-Host "   $outputPath" -ForegroundColor White
Write-Host ""
Write-Host "💡 Tip: Open this file in a web browser to see:" -ForegroundColor Yellow
Write-Host "   - Interactive charts and graphs" -ForegroundColor Gray
Write-Host "   - Timeline of network health" -ForegroundColor Gray
Write-Host "   - Story mode for easy understanding" -ForegroundColor Gray
Write-Host "   - Geographic map (coming soon!)" -ForegroundColor Gray
Write-Host ""
