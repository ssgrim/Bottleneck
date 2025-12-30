# Bottleneck.HealthCheck.ps1
# Environment validation and self-test mode

<#
.SYNOPSIS
Perform comprehensive health check of Bottleneck environment

.DESCRIPTION
Validates PowerShell version, module integrity, dependencies, connectivity,
permissions, and disk space before running scans.

.PARAMETER Verbose
Show detailed check information

.EXAMPLE
Invoke-BottleneckHealthCheck
#>
function Invoke-BottleneckHealthCheck {
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    $checks = @()
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

    if (-not $Quiet) {
        Write-Host "`n" -NoNewline
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║" -NoNewline -ForegroundColor Cyan
        Write-Host "             Bottleneck Health Check                           " -NoNewline -ForegroundColor White
        Write-Host "║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
    }

    # Check 1: PowerShell Version
    $psVersion = $PSVersionTable.PSVersion
    $psCheck = @{
        Name = "PowerShell Version"
        Status = if ($psVersion.Major -ge 7) { "Pass" } elseif ($psVersion.Major -ge 5) { "Warning" } else { "Fail" }
        Value = $psVersion.ToString()
        Required = "7.0+ (5.1 minimum)"
        Message = if ($psVersion.Major -ge 7) { "Compatible" }
                  elseif ($psVersion.Major -ge 5) { "Works but upgrade to 7+ recommended" }
                  else { "Requires PowerShell 5.1 or higher" }
    }
    $checks += $psCheck

    # Check 2: Module Load
    try {
        $modulePath = Join-Path $script:RepoRoot "src/ps/Bottleneck.psm1"
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force -ErrorAction Stop -WarningAction SilentlyContinue
            $funcCount = (Get-Command -Module Bottleneck -ErrorAction SilentlyContinue).Count
            $checks += @{
                Name = "Module Load"
                Status = if ($funcCount -ge 15) { "Pass" } elseif ($funcCount -gt 0) { "Warning" } else { "Fail" }
                Value = "$funcCount functions exported"
                Required = "15+ functions"
                Message = if ($funcCount -ge 15) { "Module loaded successfully" }
                         elseif ($funcCount -gt 0) { "Module loaded with $funcCount functions (expected 15+)" }
                         else { "Module failed to load" }
            }
        } else {
            $checks += @{
                Name = "Module Load"
                Status = "Fail"
                Value = "Module file not found"
                Required = "Bottleneck.psm1 exists"
                Message = "Module file not found at: $modulePath"
            }
        }
    } catch {
        $checks += @{
            Name = "Module Load"
            Status = "Fail"
            Value = $_.Exception.Message
            Required = "Successful import"
            Message = "Module import failed: $($_.Exception.Message)"
        }
    }

    # Check 3: Internet Connectivity
    try {
        $pingResult = Test-Connection -ComputerName "8.8.8.8" -Count 1 -ErrorAction Stop
        $latency = if ($pingResult.Latency -gt 0) { $pingResult.Latency } else { "N/A" }
        $checks += @{
            Name = "Internet Connectivity"
            Status = "Pass"
            Value = "Reachable (${latency}ms)"
            Required = "Successful ping"
            Message = "Internet connectivity verified"
        }
    } catch {
        # Try TCP fallback
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $tcpClient.BeginConnect("8.8.8.8", 53, $null, $null)
            $waitHandle = $asyncResult.AsyncWaitHandle
            if ($waitHandle.WaitOne(2000, $false)) {
                $checks += @{
                    Name = "Internet Connectivity"
                    Status = "Pass"
                    Value = "Reachable (TCP)"
                    Required = "Successful connection"
                    Message = "Internet connectivity verified via TCP (ICMP blocked)"
                }
            } else {
                throw "TCP connection timeout"
            }
        } catch {
            $checks += @{
                Name = "Internet Connectivity"
                Status = "Warning"
                Value = "Unreachable"
                Required = "Successful connection"
                Message = "Cannot reach internet (network scans may fail)"
            }
        }
    }

    # Check 4: DNS Resolution
    $dnsWorking = 0
    $dnsServers = @("System", "1.1.1.1", "8.8.8.8")
    foreach ($dns in $dnsServers) {
        try {
            if ($dns -eq "System") {
                $null = Resolve-DnsName "www.google.com" -ErrorAction Stop
            } else {
                $null = Resolve-DnsName "www.google.com" -Server $dns -ErrorAction Stop
            }
            $dnsWorking++
        } catch {
            # DNS failed, continue
        }
    }

    $checks += @{
        Name = "DNS Resolution"
        Status = if ($dnsWorking -eq 3) { "Pass" } elseif ($dnsWorking -gt 0) { "Warning" } else { "Fail" }
        Value = "$dnsWorking of 3 DNS servers working"
        Required = "At least 1 working"
        Message = if ($dnsWorking -eq 3) { "All DNS servers operational" }
                 elseif ($dnsWorking -gt 0) { "Some DNS failures detected" }
                 else { "DNS resolution not working" }
    }

    # Check 5: Administrator Privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $checks += @{
        Name = "Administrator Privileges"
        Status = if ($isAdmin) { "Pass" } else { "Warning" }
        Value = if ($isAdmin) { "Running as admin" } else { "Not admin" }
        Required = "Optional (some checks need it)"
        Message = if ($isAdmin) { "Full access to all checks" } else { "Some checks may be limited (elevation recommended)" }
    }

    # Check 6: Disk Space
    try {
        $drive = Get-PSDrive -Name C -ErrorAction Stop
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        $usedPercent = [math]::Round((($drive.Used / ($drive.Used + $drive.Free)) * 100), 1)
        $checks += @{
            Name = "Disk Space (C:)"
            Status = if ($freeGB -gt 5) { "Pass" } elseif ($freeGB -gt 1) { "Warning" } else { "Fail" }
            Value = "$freeGB GB free ($usedPercent% used)"
            Required = "5+ GB recommended"
            Message = if ($freeGB -gt 5) { "Sufficient disk space" }
                     elseif ($freeGB -gt 1) { "Low disk space (cleanup recommended)" }
                     else { "Critical: Very low disk space" }
        }
    } catch {
        $checks += @{
            Name = "Disk Space (C:)"
            Status = "Warning"
            Value = "Cannot check"
            Required = "5+ GB recommended"
            Message = "Unable to check disk space"
        }
    }

    # Check 7: Reports Directory
    try {
        $reportsDir = Join-Path $script:RepoRoot "Reports"
        if (-not (Test-Path $reportsDir)) {
            New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
        }
        $testFile = Join-Path $reportsDir ".healthcheck"
        "test" | Set-Content -Path $testFile -ErrorAction Stop
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue

        $checks += @{
            Name = "Reports Directory"
            Status = "Pass"
            Value = "Writable"
            Required = "Write access"
            Message = "Reports directory is writable"
        }
    } catch {
        $checks += @{
            Name = "Reports Directory"
            Status = "Fail"
            Value = "Not writable"
            Required = "Write access"
            Message = "Cannot write to Reports directory: $($_.Exception.Message)"
        }
    }

    # Check 8: Background Jobs
    $runningJobs = @(Get-Job | Where-Object { $_.State -eq 'Running' })
    $failedJobs = @(Get-Job | Where-Object { $_.State -eq 'Failed' })
    $checks += @{
        Name = "Background Jobs"
        Status = if ($failedJobs.Count -eq 0) { "Pass" } else { "Warning" }
        Value = "$($runningJobs.Count) running, $($failedJobs.Count) failed"
        Required = "0 failed jobs"
        Message = if ($failedJobs.Count -eq 0) { "No failed background jobs" }
                 else { "Found $($failedJobs.Count) failed jobs (cleanup recommended)" }
    }

    # Optional Check 9: Speedtest CLI
    $speedtestPath = (Get-Command speedtest -ErrorAction SilentlyContinue)
    $checks += @{
        Name = "Speedtest CLI (Optional)"
        Status = if ($speedtestPath) { "Pass" } else { "Info" }
        Value = if ($speedtestPath) { "Installed" } else { "Not found" }
        Required = "Optional"
        Message = if ($speedtestPath) { "Speedtest CLI available" } else { "Install from speedtest.net for bandwidth tests" }
    }

    # Optional Check 10: BurntToast Module
    $burntToast = Get-Module -Name BurntToast -ListAvailable -ErrorAction SilentlyContinue
    $checks += @{
        Name = "BurntToast Module (Optional)"
        Status = if ($burntToast) { "Pass" } else { "Info" }
        Value = if ($burntToast) { "Installed" } else { "Not found" }
        Required = "Optional"
        Message = if ($burntToast) { "Toast notifications available" } else { "Install-Module BurntToast for enhanced notifications" }
    }

    # Display results
    if (-not $Quiet) {
        foreach ($check in $checks) {
            $icon = switch ($check.Status) {
                "Pass" { "✅"; $color = "Green" }
                "Warning" { "⚠️ "; $color = "Yellow" }
                "Fail" { "❌"; $color = "Red" }
                "Info" { "ℹ️ "; $color = "Cyan" }
                default { "  "; $color = "White" }
            }

            Write-Host "$icon " -NoNewline
            Write-Host ("{0,-30}" -f $check.Name) -NoNewline -ForegroundColor White
            Write-Host " " -NoNewline
            Write-Host $check.Value -ForegroundColor $color

            if ($PSBoundParameters.ContainsKey('Verbose')) {
                Write-Host ("   └─ {0}" -f $check.Message) -ForegroundColor Gray
            }
        }

        Write-Host ""

        # Calculate health score
        $passCount = @($checks | Where-Object { $_.Status -eq "Pass" }).Count
        $totalRequired = @($checks | Where-Object { $_.Required -notlike "Optional*" }).Count
        $healthScore = [math]::Round(($passCount / $totalRequired) * 10, 1)

        $scoreColor = if ($healthScore -ge 9) { "Green" }
                     elseif ($healthScore -ge 7) { "Yellow" }
                     else { "Red" }

        Write-Host "Health Score: " -NoNewline
        Write-Host "$healthScore/10" -ForegroundColor $scoreColor

        $status = if ($healthScore -ge 9) { "✅ Excellent - Ready for all operations" }
                 elseif ($healthScore -ge 7) { "⚠️  Good - Minor issues detected" }
                 else { "❌ Poor - Critical issues need attention" }
        Write-Host "Status: $status`n"
    }

    return $checks
}

<#
.SYNOPSIS
Quick connectivity test

.DESCRIPTION
Fast test of network connectivity without full health check.

.EXAMPLE
Test-BottleneckConnectivity
#>
function Test-BottleneckConnectivity {
    [CmdletBinding()]
    param()

    $targets = @("8.8.8.8", "1.1.1.1", "www.google.com")
    $results = @()

    foreach ($target in $targets) {
        try {
            $ping = Test-Connection -ComputerName $target -Count 1 -ErrorAction Stop
            $results += [PSCustomObject]@{
                Target = $target
                Status = "Success"
                Latency = if ($ping.Latency -gt 0) { $ping.Latency } else { "N/A" }
            }
        } catch {
            $results += [PSCustomObject]@{
                Target = $target
                Status = "Failed"
                Latency = "N/A"
            }
        }
    }

    return $results
}

<#
.SYNOPSIS
Validate module function exports

.DESCRIPTION
Checks that all expected functions are exported from module.

.EXAMPLE
Test-BottleneckModuleIntegrity
#>
function Test-BottleneckModuleIntegrity {
    [CmdletBinding()]
    param()

    $expectedFunctions = @(
        'Invoke-BottleneckScan',
        'Get-BottleneckChecks',
        'New-BottleneckResult',
        'Test-BottleneckStorage',
        'Test-BottleneckPowerPlan',
        'Write-BottleneckLog'
    )

    $results = @()

    foreach ($func in $expectedFunctions) {
        $exists = Get-Command $func -ErrorAction SilentlyContinue
        $results += [PSCustomObject]@{
            Function = $func
            Status = if ($exists) { "✅ Present" } else { "❌ Missing" }
        }
    }

    return $results
}

# Export functions
Export-ModuleMember -Function @(
    'Invoke-BottleneckHealthCheck',
    'Test-BottleneckConnectivity',
    'Test-BottleneckModuleIntegrity'
)
