# Bottleneck.ReportUtils.ps1
function Get-BottleneckEventLogSummary {
    param([int]$Days = 7)
    $since = (Get-Date).AddDays(-$Days)
    if (-not $since) { $since = (Get-Date).AddDays(-7) }
    try {
        $filter = @{ LogName='System'; StartTime=$since }
        $events = Get-WinEvent -FilterHashtable $filter -MaxEvents 1000 -ErrorAction Stop
    } catch {
        Write-Warning "Event summary query failed: $_"
        return [PSCustomObject]@{ ErrorCount=0; WarningCount=0; RecentErrors=@(); RecentWarnings=@() }
    }
    $errors = $events | Where-Object { $_.LevelDisplayName -eq 'Error' }
    $warnings = $events | Where-Object { $_.LevelDisplayName -eq 'Warning' }
    [PSCustomObject]@{
        ErrorCount = ($errors | Measure-Object).Count
        WarningCount = ($warnings | Measure-Object).Count
        RecentErrors = $errors | Select-Object -First 5 -Property TimeCreated, Message
        RecentWarnings = $warnings | Select-Object -First 5 -Property TimeCreated, Message
    }
}

function Get-BottleneckPreviousScan {
    param([string]$ReportsPath)
    $files = Get-ChildItem -Path $ReportsPath -Filter 'scan-*.json' | Sort-Object LastWriteTime -Descending
    if ($files.Count -gt 0) {
        return Get-Content $files[0].FullName | ConvertFrom-Json
    }
    return $null
}
