# ========================================
# Bottleneck.Analytics.ps1
# Predictive Analytics & Intelligent Insights
# ========================================

using namespace System.Collections.Generic

#region Statistical Functions

function Get-StatisticalSummary {
    <#
    .SYNOPSIS
    Calculate statistical summary of a dataset
    #>
    param(
        [Parameter(Mandatory)]
        [double[]]$Data
    )

    if ($Data.Count -eq 0) {
        return $null
    }

    $sorted = $Data | Sort-Object
    $n = $Data.Count
    
    $mean = ($Data | Measure-Object -Average).Average
    
    # Calculate standard deviation
    $variance = ($Data | ForEach-Object { [Math]::Pow($_ - $mean, 2) } | Measure-Object -Average).Average
    $stdDev = [Math]::Sqrt($variance)
    
    # Calculate percentiles
    $p50Index = [Math]::Floor($n * 0.50)
    $p95Index = [Math]::Floor($n * 0.95)
    $p99Index = [Math]::Floor($n * 0.99)
    
    return @{
        Count = $n
        Mean = $mean
        StdDev = $stdDev
        Min = $sorted[0]
        Max = $sorted[-1]
        P50 = $sorted[$p50Index]
        P95 = $sorted[$p95Index]
        P99 = $sorted[$p99Index]
    }
}

function Get-LinearTrend {
    <#
    .SYNOPSIS
    Calculate linear trend (slope, intercept, R-squared)
    #>
    param(
        [Parameter(Mandatory)]
        [double[]]$YValues,
        
        [double[]]$XValues
    )

    $n = $YValues.Count
    if ($n -lt 2) {
        return $null
    }

    # Generate X values if not provided (0, 1, 2, ...)
    if (-not $XValues) {
        $XValues = 0..($n - 1)
    }

    $xMean = ($XValues | Measure-Object -Average).Average
    $yMean = ($YValues | Measure-Object -Average).Average

    $numerator = 0
    $denominator = 0
    
    for ($i = 0; $i -lt $n; $i++) {
        $xDiff = $XValues[$i] - $xMean
        $yDiff = $YValues[$i] - $yMean
        $numerator += $xDiff * $yDiff
        $denominator += $xDiff * $xDiff
    }

    if ($denominator -eq 0) {
        return $null
    }

    $slope = $numerator / $denominator
    $intercept = $yMean - ($slope * $xMean)

    # Calculate R-squared
    $ssTotal = 0
    $ssResidual = 0
    
    for ($i = 0; $i -lt $n; $i++) {
        $predicted = $slope * $XValues[$i] + $intercept
        $ssTotal += [Math]::Pow($YValues[$i] - $yMean, 2)
        $ssResidual += [Math]::Pow($YValues[$i] - $predicted, 2)
    }

    $rSquared = if ($ssTotal -gt 0) { 1 - ($ssResidual / $ssTotal) } else { 0 }

    $trendDirection = 'Stable'
    if ($slope -gt 0) { $trendDirection = 'Increasing' }
    elseif ($slope -lt 0) { $trendDirection = 'Decreasing' }

    return @{
        Slope = $slope
        Intercept = $intercept
        RSquared = $rSquared
        TrendDirection = $trendDirection
    }
}

#endregion

#region Baseline Management

class PerformanceBaseline {
    [DateTime]$EstablishedDate
    [int]$LearningPeriodDays
    [int]$SampleCount
    [hashtable]$Metrics
    [hashtable]$TimePatterns  # By hour, weekday

    PerformanceBaseline() {
        $this.Metrics = @{}
        $this.TimePatterns = @{}
    }
}

function New-PerformanceBaseline {
    <#
    .SYNOPSIS
    Create performance baseline from historical scans
    #>
    param(
        [Parameter(Mandatory)]
        [array]$HistoricalScans,
        
        [int]$MinimumDays = 14
    )

    if ($HistoricalScans.Count -lt 5) {
        Write-Warning "Insufficient data for baseline (minimum 5 scans required)"
        return $null
    }

    $firstScan = $HistoricalScans | Sort-Object { [DateTime]$_.timestamp } | Select-Object -First 1
    $lastScan = $HistoricalScans | Sort-Object { [DateTime]$_.timestamp } | Select-Object -Last 1
    
    $daysDiff = ([DateTime]$lastScan.timestamp - [DateTime]$firstScan.timestamp).TotalDays
    
    if ($daysDiff -lt $MinimumDays) {
        Write-Warning "Insufficient time span for baseline (minimum $MinimumDays days required, got $([Math]::Round($daysDiff, 1)))"
        return $null
    }

    $baseline = [PerformanceBaseline]::new()
    $baseline.EstablishedDate = Get-Date
    $baseline.LearningPeriodDays = [int]$daysDiff
    $baseline.SampleCount = $HistoricalScans.Count

    # Extract all metric values by category
    $metricsByCategory = @{}
    
    foreach ($scan in $HistoricalScans) {
        foreach ($result in $scan.results) {
            $category = $result.Category
            
            if (-not $metricsByCategory.ContainsKey($category)) {
                $metricsByCategory[$category] = @()
            }
            
            $metricsByCategory[$category] += [double]$result.Score
        }
    }

    # Calculate statistics for each metric
    foreach ($category in $metricsByCategory.Keys) {
        $values = $metricsByCategory[$category]
        $stats = Get-StatisticalSummary -Data $values
        
        if ($stats) {
            $baseline.Metrics[$category] = $stats
        }
    }

    # Analyze time patterns
    $baseline.TimePatterns = Get-TimePatterns -Scans $HistoricalScans

    Write-Host "Baseline established: $($baseline.SampleCount) scans over $($baseline.LearningPeriodDays) days" -ForegroundColor Green
    
    return $baseline
}

function Get-TimePatterns {
    param([array]$Scans)
    
    $patterns = @{
        ByHour = @{}
        ByWeekday = @{}
    }
    
    foreach ($scan in $Scans) {
        $timestamp = [DateTime]$scan.timestamp
        $hour = $timestamp.Hour
        $weekday = $timestamp.DayOfWeek.ToString()
        
        if (-not $patterns.ByHour.ContainsKey($hour)) {
            $patterns.ByHour[$hour] = @{ Count = 0; TotalScore = 0 }
        }
        if (-not $patterns.ByWeekday.ContainsKey($weekday)) {
            $patterns.ByWeekday[$weekday] = @{ Count = 0; TotalScore = 0 }
        }
        
        $avgScore = ($scan.results | Measure-Object -Property Score -Average).Average
        
        $patterns.ByHour[$hour].Count++
        $patterns.ByHour[$hour].TotalScore += $avgScore
        
        $patterns.ByWeekday[$weekday].Count++
        $patterns.ByWeekday[$weekday].TotalScore += $avgScore
    }
    
    return $patterns
}

function Save-Baseline {
    param(
        [PerformanceBaseline]$Baseline,
        [string]$Path = "$PSScriptRoot\..\..\Reports\baseline.json"
    )

    $baselineData = @{
        established = $Baseline.EstablishedDate.ToString('o')
        learning_period_days = $Baseline.LearningPeriodDays
        sample_count = $Baseline.SampleCount
        metrics = $Baseline.Metrics
        time_patterns = $Baseline.TimePatterns
    }

    $baselineData | ConvertTo-Json -Depth 10 | Set-Content $Path
    Write-Verbose "Baseline saved to: $Path"
}

function Get-Baseline {
    param([string]$Path = "$PSScriptRoot\..\..\Reports\baseline.json")

    if (-not (Test-Path $Path)) {
        return $null
    }

    $data = Get-Content $Path -Raw | ConvertFrom-Json
    
    $baseline = [PerformanceBaseline]::new()
    $baseline.EstablishedDate = [DateTime]::Parse($data.established)
    $baseline.LearningPeriodDays = $data.learning_period_days
    $baseline.SampleCount = $data.sample_count
    $baseline.Metrics = $data.metrics
    $baseline.TimePatterns = $data.time_patterns
    
    return $baseline
}

#endregion

#region Anomaly Detection

function Find-PerformanceAnomalies {
    <#
    .SYNOPSIS
    Detect anomalies in current metrics compared to baseline
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$CurrentMetrics,
        
        [Parameter(Mandatory)]
        [PerformanceBaseline]$Baseline,
        
        [double]$ZScoreThreshold = 3.0
    )

    $anomalies = @()

    foreach ($category in $CurrentMetrics.Keys) {
        if (-not $Baseline.Metrics.ContainsKey($category)) {
            continue
        }

        $current = $CurrentMetrics[$category]
        $baselineStats = $Baseline.Metrics[$category]

        # Z-score calculation
        if ($baselineStats.StdDev -gt 0) {
            $zScore = ($current - $baselineStats.Mean) / $baselineStats.StdDev
            
            if ([Math]::Abs($zScore) -gt $ZScoreThreshold) {
                $anomalies += @{
                    Category = $category
                    Current = $current
                    Expected = $baselineStats.Mean
                    ZScore = $zScore
                    Severity = [Math]::Abs($zScore)
                    Type = if ($zScore > 0) { 'HighAnomaly' } else { 'LowAnomaly' }
                    Description = "Current value is $([Math]::Round([Math]::Abs($zScore), 1)) standard deviations from baseline"
                }
            }
        }
    }

    return $anomalies
}

#endregion

#region Predictive Analysis

function Get-DiskFailurePrediction {
    <#
    .SYNOPSIS
    Predict disk failure based on SMART trend analysis
    #>
    param(
        [Parameter(Mandatory)]
        [array]$HistoricalSMART
    )

    if ($HistoricalSMART.Count -lt 3) {
        return @{ Predicted = $false; Reason = 'Insufficient historical data' }
    }

    # Critical SMART attributes
    $criticalAttributes = @{
        5 = @{ Name = 'Reallocated_Sector_Count'; Threshold = 10; Weight = 1.0 }
        187 = @{ Name = 'Reported_Uncorrectable_Errors'; Threshold = 5; Weight = 0.9 }
        188 = @{ Name = 'Command_Timeout'; Threshold = 50; Weight = 0.7 }
        197 = @{ Name = 'Current_Pending_Sector_Count'; Threshold = 5; Weight = 1.0 }
        198 = @{ Name = 'Offline_Uncorrectable'; Threshold = 5; Weight = 0.9 }
    }

    $predictions = @()

    foreach ($attrId in $criticalAttributes.Keys) {
        $attrInfo = $criticalAttributes[$attrId]
        $values = @()
        
        foreach ($smart in $HistoricalSMART) {
            $attr = $smart.attributes | Where-Object { $_.id -eq $attrId } | Select-Object -First 1
            if ($attr) {
                $values += [double]$attr.raw_value
            }
        }

        if ($values.Count -ge 3) {
            $trend = Get-LinearTrend -YValues $values
            
            if ($trend -and $trend.Slope > 0.1) {
                # Predict time until threshold exceeded
                $currentValue = $values[-1]
                $threshold = $attrInfo.Threshold
                
                if ($trend.Slope -gt 0) {
                    $daysUntilFailure = ($threshold - $currentValue) / $trend.Slope
                    
                    if ($daysUntilFailure -gt 0 -and $daysUntilFailure -lt 60) {
                        $predictions += @{
                            Attribute = $attrInfo.Name
                            DaysRemaining = [int]$daysUntilFailure
                            Confidence = $trend.RSquared
                            CurrentValue = $currentValue
                            Threshold = $threshold
                            Weight = $attrInfo.Weight
                        }
                    }
                }
            }
        }
    }

    if ($predictions.Count -gt 0) {
        # Use weighted average for final prediction
        $totalWeight = ($predictions | Measure-Object -Property Weight -Sum).Sum
        $weightedDays = ($predictions | ForEach-Object { $_.DaysRemaining * $_.Weight } | Measure-Object -Sum).Sum / $totalWeight
        $avgConfidence = ($predictions | Measure-Object -Property Confidence -Average).Average

        return @{
            Predicted = $true
            DaysRemaining = [int]$weightedDays
            Confidence = [Math]::Round($avgConfidence, 2)
            CriticalAttributes = $predictions
            Recommendation = if ($weightedDays -lt 7) { 'URGENT: Backup data and replace disk immediately' }
                             elseif ($weightedDays -lt 30) { 'HIGH PRIORITY: Schedule disk replacement within 2 weeks' }
                             else { 'Monitor closely and plan replacement' }
        }
    }

    return @{ Predicted = $false; Reason = 'No concerning trends detected' }
}

#endregion

#region Regression Detection

function Find-PerformanceRegressions {
    <#
    .SYNOPSIS
    Detect performance regressions compared to historical baseline
    #>
    param(
        [Parameter(Mandatory)]
        [array]$RecentScans,
        
        [Parameter(Mandatory)]
        [PerformanceBaseline]$Baseline,
        
        [double]$RegressionThreshold = 20.0  # 20% worse than baseline
    )

    if ($RecentScans.Count -lt 3) {
        return @()
    }

    $regressions = @()

    foreach ($category in $Baseline.Metrics.Keys) {
        $recentValues = @()
        
        foreach ($scan in $RecentScans) {
            $result = $scan.results | Where-Object { $_.Category -eq $category } | Select-Object -First 1
            if ($result) {
                $recentValues += [double]$result.Score
            }
        }

        if ($recentValues.Count -ge 3) {
            $recentAvg = ($recentValues | Measure-Object -Average).Average
            $baselineAvg = $Baseline.Metrics[$category].Mean

            $degradationPercent = (($recentAvg - $baselineAvg) / $baselineAvg) * 100

            if ($degradationPercent -gt $RegressionThreshold) {
                $regressions += @{
                    Category = $category
                    DegradationPercent = [Math]::Round($degradationPercent, 1)
                    RecentAverage = [Math]::Round($recentAvg, 1)
                    BaselineAverage = [Math]::Round($baselineAvg, 1)
                    StartDate = ([DateTime]$RecentScans[0].timestamp).ToString('yyyy-MM-dd')
                    Severity = if ($degradationPercent -gt 50) { 'Critical' }
                               elseif ($degradationPercent -gt 30) { 'High' }
                               else { 'Medium' }
                }
            }
        }
    }

    return $regressions
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Get-StatisticalSummary',
    'Get-LinearTrend',
    'New-PerformanceBaseline',
    'Save-Baseline',
    'Get-Baseline',
    'Find-PerformanceAnomalies',
    'Get-DiskFailurePrediction',
    'Find-PerformanceRegressions'
)
