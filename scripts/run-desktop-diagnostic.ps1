# Desktop Diagnostic with Light Load Probe (Win7 compatible)
# Collects system info, runs a short synthetic load, samples performance counters, and summarizes hotspots.

param(
    [int]$DurationSeconds = 30,
    [string]$LogPath = "$PSScriptRoot\..\Reports\desktop-diagnostic-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log",
    [switch]$NoLoad,                 # Skip synthetic load if you only want passive measurements
    [switch]$HeavyLoad,              # Apply a safe heavy load (CPU + disk) for up to 30s
    [string]$SummaryPath,            # Optional: path to write a customer-friendly summary (.md)
    [switch]$Html                    # Optional: also generate an HTML report with scoring
)

# Ensure log directory exists
$logDir = Split-Path -Parent $LogPath
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

Start-Transcript -Path $LogPath -Append

# Compute default SummaryPath if not provided
if (-not $PSBoundParameters.ContainsKey('SummaryPath')) {
    try {
        $dir = Split-Path -Parent $LogPath
        $base = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
        $summaryName = ($base -replace '^desktop-diagnostic-', 'desktop-diagnostic-summary-') + '.md'
        $SummaryPath = Join-Path $dir $summaryName
    }
    catch { $SummaryPath = $null }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""; Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Get-SystemInfo {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
    $mem = Get-WmiObject -Class Win32_PhysicalMemory
    $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3"
    [pscustomobject]@{
        ComputerName = $os.CSName
        OS           = $os.Caption
        OSVersion    = $os.Version
        LastBoot     = $os.LastBootUpTime
        CPU          = $cpu.Name
        Cores        = $cpu.NumberOfCores
        Threads      = $cpu.NumberOfLogicalProcessors
        RAM_GB       = [math]::Round(($mem.Capacity | Measure-Object -Sum).Sum / 1GB, 2)
        Disks        = ($disks | ForEach-Object { "{0} ({1} free of {2} GB)" -f $_.DeviceID, [math]::Round($_.FreeSpace / 1GB, 1), [math]::Round($_.Size / 1GB, 1) }) -join '; '
    }
}

function Get-OSFlavor {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $ver = $os.Version
    $build = 0; [void][int]::TryParse($os.BuildNumber, [ref]$build)
    $major = 0; $minor = 0
    if ($ver -and ($ver -match '^(\d+)\.(\d+)')) { $major = [int]$Matches[1]; $minor = [int]$Matches[2] }
    $name = 'Windows'
    if ($major -eq 6 -and $minor -eq 1) { $name = 'Windows 7' }
    elseif ($major -eq 6 -and $minor -eq 2) { $name = 'Windows 8' }
    elseif ($major -eq 6 -and $minor -eq 3) { $name = 'Windows 8.1' }
    elseif ($major -eq 10) { $name = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' } }
    $superfetch = if ($name -eq 'Windows 7') { 'Superfetch' } else { 'SysMain' }
    [pscustomobject]@{
        Name              = $name
        Version           = $ver
        Build             = $build
        Major             = $major
        Minor             = $minor
        SuperfetchService = $superfetch
    }
}

function Analyze-OSFocusAreas {
    param(
        [double]$AvgCpu,
        [double]$AvgDiskQ,
        [double]$AvgDiskLatency,
        [double]$MinAvailMemMB
    )
    $osf = Get-OSFlavor
    Write-Host ("OS detected: {0} (Version {1}, Build {2})" -f $osf.Name, $osf.Version, $osf.Build) -ForegroundColor Cyan

    # Gather quick signals
    $topCpu = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
    $topNames = @($topCpu | Select-Object -ExpandProperty Name)
    $hasMsMpEng = $topNames -contains 'MsMpEng'
    $hasSvchost = $topNames -contains 'svchost'
    $services = @{}
    foreach ($svcName in @('wuauserv', 'WSearch', $osf.SuperfetchService)) {
        try { $svc = Get-Service -Name $svcName -ErrorAction Stop; $services[$svcName] = $svc.Status } catch { $services[$svcName] = $null }
    }

    Write-Host "Focus suggestions:" -ForegroundColor White

    try {
        if ($osf.Name -eq 'Windows 7') {
            if ($services['wuauserv'] -eq 'Running' -and $hasSvchost) {
                Write-Host " - Windows Update may cause high CPU (svchost). Let it finish or stop updates when idle." -ForegroundColor Yellow
            }
            if ($services[$osf.SuperfetchService] -eq 'Running' -and $AvgDiskQ -gt 2) {
                Write-Host " - Superfetch is active and disk is busy; consider disabling temporarily to reduce I/O thrash." -ForegroundColor Yellow
            }
            Write-Host " - Consider cleaning startup items and ensuring antivirus scans are scheduled off-hours." -ForegroundColor Gray
        }
        else {
            if ($services[$osf.SuperfetchService] -eq 'Running' -and ($AvgDiskQ -gt 2 -or $AvgDiskLatency -gt 0.05)) {
                Write-Host (" - {0} is active with high disk pressure; consider disabling to test improvement." -f $osf.SuperfetchService) -ForegroundColor Yellow
            }
            if ($services['WSearch'] -eq 'Running' -and $AvgDiskQ -gt 2) {
                Write-Host " - Windows Search indexing may contribute to I/O; pause indexing while working or exclude large folders." -ForegroundColor Yellow
            }
            if ($hasMsMpEng -and $AvgCpu -gt 50) {
                Write-Host " - Defender (MsMpEng) appears active; schedule scans and add exclusions for heavy folders." -ForegroundColor Yellow
            }
            Write-Host " - Review startup apps and background updaters; they often impact responsiveness." -ForegroundColor Gray
        }
    }
    catch {
        Write-Host " - OS focus hints unavailable (perfcounter/service query not supported)." -ForegroundColor Yellow
    }
    if ($MinAvailMemMB -lt 800) {
        Write-Host " - Low available memory will degrade responsiveness; adding RAM yields significant gains on older PCs." -ForegroundColor Yellow
    }
}

function Start-SyntheticLoad {
    param([int]$Seconds)
    if ($Seconds -le 0) { return @() }
    $workers = [math]::Max(1, [math]::Floor([Environment]::ProcessorCount / 2))
    $jobs = @()
    for ($i = 0; $i -lt $workers; $i++) {
        $jobs += Start-Job -ScriptBlock {
            param($dur)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt $dur) {
                # Simple CPU spin with a tiny pause to avoid 100% pinning
                [Math]::Sqrt(12345) | Out-Null
            }
        } -ArgumentList $Seconds
    }
    return $jobs
}

function Start-HeavyCpuLoad {
    param([int]$Seconds)
    if ($Seconds -le 0) { return @() }
    $workers = [math]::Max(1, [Environment]::ProcessorCount - 1)  # leave one logical core free
    $jobs = @()
    for ($i = 0; $i -lt $workers; $i++) {
        $jobs += Start-Job -ScriptBlock {
            param($dur)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt $dur) {
                # Tighter loop; still trivial math to consume CPU
                [Math]::Sqrt(987654321) | Out-Null
            }
        } -ArgumentList $Seconds
    }
    return $jobs
}

function Start-DiskLoad {
    param([int]$Seconds)
    if ($Seconds -le 0) { return $null }
    $job = Start-Job -ScriptBlock {
        param($dur)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "bn_diskload_" + [Guid]::NewGuid().ToString() + ".tmp")
        try {
            $fs = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $buf = New-Object byte[] (1024 * 1024) # 1MB buffer
            $rand = New-Object System.Random
            while ($sw.Elapsed.TotalSeconds -lt $dur) {
                $rand.NextBytes($buf)
                $fs.Write($buf, 0, $buf.Length)
                $fs.Flush()
                Start-Sleep -Milliseconds 5 # avoid starving UI thread
            }
        }
        catch {}
        finally {
            try { if ($fs) { $fs.Dispose() } } catch {}
            try { if (Test-Path $tmp) { Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue } } catch {}
        }
    } -ArgumentList $Seconds
    return $job
}

function Sample-PerfCounters {
    param([int]$Seconds)
    if (-not $script:sysDriveLetter) {
        try { $script:sysDriveLetter = (Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue).SystemDrive } catch {}
        if (-not $script:sysDriveLetter) { $script:sysDriveLetter = 'C:' }
    }
    function Get-CounterWithFallback {
        param([string]$CounterPath)
        $val = $null
        try {
            $val = (Get-Counter -Counter $CounterPath -ErrorAction Stop).CounterSamples[0].CookedValue
        }
        catch { $val = $null }
        if ($val -eq $null) {
            try {
                $tpPath = $CounterPath -replace '\\\\', '\\' -replace '^\\\\', '\\'
                $raw = (typeperf "`"$tpPath`"" -sc 1 2>$null | Select-Object -Last 1)
                if ($raw) {
                    $parts = $raw -split ','
                    if ($parts.Count -ge 2) {
                        $txt = $parts[1].Trim('"')
                        $out = $null
                        if ([double]::TryParse($txt, [ref]$out)) { $val = $out }
                    }
                }
            }
            catch { $val = $null }
        }
        if ($val -eq $null) {
            try {
                if ($CounterPath -like '*Processor(_Total)*% Processor Time') {
                    $w = Get-WmiObject -Class Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
                    if ($w -and $w.PercentProcessorTime -ne $null) { $val = [double]$w.PercentProcessorTime }
                }
                elseif ($CounterPath -like '*Memory*Available MBytes') {
                    $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue
                    if ($os -and $os.FreePhysicalMemory -ne $null) { $val = [double]($os.FreePhysicalMemory / 1024) }
                }
                elseif ($CounterPath -like '*PhysicalDisk(_Total)*Avg. Disk Queue Length') {
                    $d = Get-WmiObject -Class Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue
                    if ($d -and $d.AvgDiskQueueLength -ne $null) { $val = [double]$d.AvgDiskQueueLength }
                    if ($val -eq $null -and $script:sysDriveLetter) {
                        $ld = Get-WmiObject -Class Win32_PerfFormattedData_PerfDisk_LogicalDisk -Filter ("Name='{0}'" -f $script:sysDriveLetter) -ErrorAction SilentlyContinue
                        if ($ld -and $ld.AvgDiskQueueLength -ne $null) { $val = [double]$ld.AvgDiskQueueLength }
                    }
                }
                elseif ($CounterPath -like '*PhysicalDisk(_Total)*Avg. Disk sec/Transfer') {
                    $d = Get-WmiObject -Class Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue
                    if ($d -and $d.AvgDiskSecPerTransfer -ne $null) { $val = [double]$d.AvgDiskSecPerTransfer }
                    if ($val -eq $null -and $script:sysDriveLetter) {
                        $ld = Get-WmiObject -Class Win32_PerfFormattedData_PerfDisk_LogicalDisk -Filter ("Name='{0}'" -f $script:sysDriveLetter) -ErrorAction SilentlyContinue
                        if ($ld -and $ld.AvgDiskSecPerTransfer -ne $null) { $val = [double]$ld.AvgDiskSecPerTransfer }
                    }
                }
                elseif ($CounterPath -like '*Processor(_Total)*% DPC Time') {
                    $w = Get-WmiObject -Class Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
                    if ($w -and $w.PercentDPCTime -ne $null) { $val = [double]$w.PercentDPCTime }
                }
                elseif ($CounterPath -like '*Processor(_Total)*% Interrupt Time') {
                    $w = Get-WmiObject -Class Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
                    if ($w -and $w.PercentInterruptTime -ne $null) { $val = [double]$w.PercentInterruptTime }
                }
                elseif ($CounterPath -like '*Processor(_Total)*Interrupts/sec') {
                    $w = Get-WmiObject -Class Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
                    if ($w -and $w.InterruptsPerSec -ne $null) { $val = [double]$w.InterruptsPerSec }
                }
                elseif ($CounterPath -like '*Processor(_Total)*DPCs Queued/sec') {
                    $w = Get-WmiObject -Class Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
                    if ($w -and $w.DPCsQueuedPersec -ne $null) { $val = [double]$w.DPCsQueuedPersec }
                }
            }
            catch { $val = $null }
        }
        return $val
    }
    $counters = @(
        '\\Processor(_Total)\\% Processor Time',
        '\\Processor(_Total)\\% DPC Time',
        '\\Processor(_Total)\\% Interrupt Time',
        '\\Processor(_Total)\\Interrupts/sec',
        '\\Processor(_Total)\\DPCs Queued/sec',
        '\\Memory\\Available MBytes',
        '\\PhysicalDisk(_Total)\\Avg. Disk Queue Length',
        '\\PhysicalDisk(_Total)\\Avg. Disk sec/Transfer',
        '\\LogicalDisk(_Total)\\% Free Space'
    )
    $samples = @()
    for ($i = 0; $i -lt $Seconds; $i++) {
        $row = [ordered]@{ Timestamp = Get-Date }
        foreach ($c in $counters) {
            $val = Get-CounterWithFallback -CounterPath $c
            $row[$c] = $val
        }
        $samples += [pscustomobject]$row
        Start-Sleep -Seconds 1
    }
    return $samples
}

function Measure-DiskProbeLatencyMs {
    param([int]$Ops = 64)
    $lat = @()
    try {
        $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "bn_probe_" + [Guid]::NewGuid().ToString() + ".bin")
        $fs = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough)
        $buf = New-Object byte[] 4096
        $rnd = New-Object System.Random
        for ($i = 0; $i -lt $Ops; $i++) {
            $rnd.NextBytes($buf)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $fs.Write($buf, 0, $buf.Length)
            $fs.Flush()
            $sw.Stop()
            $lat += [math]::Round($sw.Elapsed.TotalMilliseconds, 2)
            Start-Sleep -Milliseconds 2
        }
        $fs.Dispose()
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
    catch {
        try { if ($fs) { $fs.Dispose() } } catch {}
        try { if ($tmp -and (Test-Path $tmp)) { Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue } } catch {}
    }
    if ($lat.Count -gt 0) { return [math]::Round((($lat | Sort-Object | Select-Object -Skip ([math]::Max(0, [int]($lat.Count * 0.1))) -First ([math]::Max(1, [int]($lat.Count * 0.8))) | Measure-Object -Average).Average), 2) }
    return $null
}

# Startup and Scheduled Tasks enumeration (Win7-safe)
function Get-StartupEntries {
    $items = @()
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    foreach ($p in $paths) {
        try {
            if (Test-Path $p) {
                $key = Get-Item $p
                foreach ($v in $key.GetValueNames()) {
                    $cmd = $key.GetValue($v)
                    $items += [pscustomobject]@{ Source = $p; Name = $v; Command = $cmd }
                }
            }
        }
        catch {}
    }
    # Startup folders
    $folders = @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup')
    )
    foreach ($f in $folders) {
        try {
            if (Test-Path $f) {
                Get-ChildItem $f -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $items += [pscustomobject]@{ Source = $f; Name = $_.Name; Command = $_.FullName }
                }
            }
        }
        catch {}
    }
    return $items
}

function Get-ScheduledTasksSummary {
    $sum = [ordered]@{ Total = 0; Running = 0; Failed = 0; TopFailures = @() }
    try {
        $csv = (& schtasks.exe /Query /FO CSV /V) -join "`n"
        $rows = $csv | ConvertFrom-Csv -ErrorAction Stop
        $sum.Total = ($rows | Measure-Object).Count
        $sum.Running = ($rows | Where-Object { $_.Status -match 'Running' } | Measure-Object).Count
        $fails = $rows | Where-Object { $_.'Last Result' -and ($_.'Last Result' -ne '0') -and ($_.'Last Result' -ne '0x0') }
        $sum.Failed = ($fails | Measure-Object).Count
        $sum.TopFailures = @($fails | Select-Object TaskName,
            @{n = 'LastRunTime'; e = { $_."Last Run Time" } },
            @{n = 'LastResult'; e = { $_."Last Result" } } -First 5)
    }
    catch {}
    return [pscustomobject]$sum
}

# Per-process activity sampler (CPU time and IO bytes deltas)
function Sample-ProcessActivity {
    param([int]$Seconds)
    if ($Seconds -le 0) { return $null }
    $cpuCount = [Environment]::ProcessorCount
    $prev = @{}
    $agg = @{}
    for ($i = 0; $i -lt $Seconds; $i++) {
        try {
            $procs = Get-Process | Select-Object Id, Name, CPU, IOReadBytes, IOWriteBytes
            $now = @{}
            foreach ($p in $procs) { $now[$p.Id] = $p }
            foreach ($pid in $now.Keys) {
                $cur = $now[$pid]
                $prv = $null; $prev.TryGetValue($pid, [ref]$prv) | Out-Null
                if ($prv) {
                    $dcpu = [double]($cur.CPU - $prv.CPU)
                    if ($dcpu -lt 0) { $dcpu = 0 }
                    $dio = [double](($cur.IOReadBytes - $prv.IOReadBytes) + ($cur.IOWriteBytes - $prv.IOWriteBytes))
                    if ($dio -lt 0) { $dio = 0 }
                    if (-not $agg.ContainsKey($pid)) { $agg[$pid] = [pscustomobject]@{ Name = $cur.Name; CpuSec = 0.0; IOBytes = 0.0 } }
                    $agg[$pid].CpuSec += $dcpu
                    $agg[$pid].IOBytes += $dio
                }
            }
            $prev = $now
        }
        catch {}
        Start-Sleep -Seconds 1
    }
    $topCpu = $agg.GetEnumerator() | ForEach-Object {
        $avg = if ($Seconds -gt 0 -and $cpuCount -gt 0) { [math]::Round((($_.Value.CpuSec / $Seconds) / $cpuCount) * 100, 1) } else { 0 }
        [pscustomobject]@{ PID = $_.Key; Name = $_.Value.Name; AvgCPU = $avg; IOBytes = $_.Value.IOBytes }
    } | Sort-Object AvgCPU -Descending | Select-Object -First 5
    $topIO = $agg.GetEnumerator() | ForEach-Object {
        $bps = if ($Seconds -gt 0) { [math]::Round(($_.Value.IOBytes / $Seconds), 0) } else { 0 }
        [pscustomobject]@{ PID = $_.Key; Name = $_.Value.Name; AvgBps = $bps }
    } | Sort-Object AvgBps -Descending | Select-Object -First 5
    return [pscustomobject]@{ TopCPU = $topCpu; TopIO = $topIO }
}

function Sample-ProcessIOFallbackCounters {
    param([int]$Seconds = 3)
    try {
        $samples = @{}
        for ($i = 0; $i -lt $Seconds; $i++) {
            $c = Get-Counter -Counter '\\Process(*)\\IO Data Bytes/sec' -ErrorAction SilentlyContinue
            if ($c -and $c.CounterSamples) {
                foreach ($s in $c.CounterSamples) {
                    $name = $s.InstanceName
                    if ([string]::IsNullOrWhiteSpace($name) -or $name -eq '_Total') { continue }
                    if (-not $samples.ContainsKey($name)) { $samples[$name] = @() }
                    $samples[$name] += [double]$s.CookedValue
                }
            }
            Start-Sleep -Seconds 1
        }
        $top = $samples.GetEnumerator() | ForEach-Object {
            $avg = if ($_.Value.Count -gt 0) { [math]::Round(($_.Value | Measure-Object -Average).Average, 0) } else { 0 }
            [pscustomobject]@{ Name = $_.Key; AvgBps = $avg }
        } | Sort-Object AvgBps -Descending | Select-Object -First 5
        return $top
    }
    catch { return @() }
}

function Start-ProcessSamplerJob {
    param([int]$Seconds)
    if ($Seconds -le 0) { return $null }
    $sb = {
        param($Seconds)
        $cpuCount = [Environment]::ProcessorCount
        $prev = @{}
        $agg = @{}
        for ($i = 0; $i -lt $Seconds; $i++) {
            try {
                $procs = Get-Process | Select-Object Id, Name, CPU, IOReadBytes, IOWriteBytes
                $now = @{}
                foreach ($p in $procs) { $now[$p.Id] = $p }
                foreach ($pid in $now.Keys) {
                    $cur = $now[$pid]
                    $prv = $null; $prev.TryGetValue($pid, [ref]$prv) | Out-Null
                    if ($prv) {
                        $dcpu = [double]($cur.CPU - $prv.CPU); if ($dcpu -lt 0) { $dcpu = 0 }
                        $dio = [double](($cur.IOReadBytes - $prv.IOReadBytes) + ($cur.IOWriteBytes - $prv.IOWriteBytes)); if ($dio -lt 0) { $dio = 0 }
                        if (-not $agg.ContainsKey($pid)) { $agg[$pid] = [pscustomobject]@{ Name = $cur.Name; CpuSec = 0.0; IOBytes = 0.0 } }
                        $agg[$pid].CpuSec += $dcpu
                        $agg[$pid].IOBytes += $dio
                    }
                }
                $prev = $now
            }
            catch {}
            Start-Sleep -Seconds 1
        }
        $topCpu = $agg.GetEnumerator() | ForEach-Object {
            $avg = if ($Seconds -gt 0 -and $cpuCount -gt 0) { [math]::Round((($_.Value.CpuSec / $Seconds) / $cpuCount) * 100, 1) } else { 0 }
            [pscustomobject]@{ PID = $_.Key; Name = $_.Value.Name; AvgCPU = $avg; IOBytes = $_.Value.IOBytes }
        } | Sort-Object AvgCPU -Descending | Select-Object -First 5
        $topIO = $agg.GetEnumerator() | ForEach-Object {
            $bps = if ($Seconds -gt 0) { [math]::Round(($_.Value.IOBytes / $Seconds), 0) } else { 0 }
            [pscustomobject]@{ PID = $_.Key; Name = $_.Value.Name; AvgBps = $bps }
        } | Sort-Object AvgBps -Descending | Select-Object -First 5
        return [pscustomobject]@{ TopCPU = $topCpu; TopIO = $topIO }
    }
    return (Start-Job -ScriptBlock $sb -ArgumentList $Seconds)
}

# Thermal and throttling signals (best-effort)
function Get-ThermalAndThrottle {
    $out = [ordered]@{ Zones = @(); CpuPercentMaxFreq = $null; GpuUtilMax = $null; Notes = @(); NVMeTemp = $null }
    try {
        $zones = Get-WmiObject -Namespace root\wmi -Class MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        foreach ($z in $zones) {
            $c = [math]::Round(($z.CurrentTemperature / 10) - 273.15, 1)
            $name = if ($z.InstanceName) { $z.InstanceName } else { 'ThermalZone' }
            $out.Zones += [pscustomobject]@{ Name = $name; TempC = $c }
        }
    }
    catch { $out.Notes += 'ACPI thermal zones unavailable' }
    if (-not $zones) { $out.Notes += 'Thermal zones not exposed (firmware/OEM sensor not available)' }
    if (-not $zones) {
        try {
            $tz = Get-WmiObject -Class Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue
            if ($tz) {
                foreach ($t in $tz) {
                    if ($t.Temperature -ne $null -and $t.Temperature -lt 150) { $out.Zones += [pscustomobject]@{ Name = $t.Name; TempC = $t.Temperature } }
                }
            }
        }
        catch {}
    }
    # Try to get NVMe temperature if available
    try {
        $nvmeTemp = Get-WmiObject -Namespace root/microsoft/windows/storage -Class MSFT_PhysicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.MediaType -eq 5 } | Select-Object -First 1 -ExpandProperty OperationalStatus
        if ($nvmeTemp) { $out.Notes += "NVMe operational status: $nvmeTemp" }
    }
    catch {}

    $candidates = @(
        '\\Processor Information(_Total)\\% of Maximum Frequency',
        '\\Processor Information(_Total)\\% Processor Performance',
        '\\Processor(_Total)\\% Processor Performance'
    )
    foreach ($ctr in $candidates) {
        try {
            $v = (Get-Counter -Counter $ctr -ErrorAction Stop).CounterSamples[0].CookedValue
            if ($v -ne $null) { $out.CpuPercentMaxFreq = [math]::Round($v, 1); break }
        }
        catch {}
    }
    if ($out.CpuPercentMaxFreq -eq $null) {
        try {
            $p = Get-WmiObject -Namespace root\wmi -Class Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction SilentlyContinue
            if ($p -and $p.PercentPerformanceLimit -ne $null) { $out.CpuPercentMaxFreq = [math]::Round([double]$p.PercentPerformanceLimit, 1) }
        }
        catch {}
    }
    if ($out.GpuUtilMax -eq $null) {
        try {
            $gpuCounter = '\\GPU Engine(_Total)\\Utilization Percentage'
            $gv = (Get-Counter -Counter $gpuCounter -ErrorAction Stop).CounterSamples[0].CookedValue
            if ($gv -ne $null) { $out.GpuUtilMax = [math]::Round([double]$gv, 1) }
        }
        catch {
            try {
                $allGpu = Get-Counter -Counter '\\GPU Engine(*)\\Utilization Percentage' -ErrorAction Stop
                if ($allGpu -and $allGpu.CounterSamples) {
                    $max = ($allGpu.CounterSamples | Measure-Object -Property CookedValue -Maximum).Maximum
                    if ($max -ne $null) { $out.GpuUtilMax = [math]::Round([double]$max, 1) }
                }
            }
            catch {
                $out.Notes += 'GPU utilization counter unavailable (not exposed on this system)'
            }
        }
    }
    # Add hint about throttling if CPU freq is being limited
    if ($out.CpuPercentMaxFreq -ne $null -and $out.CpuPercentMaxFreq -lt 100) {
        $out.Notes += "CPU running at {0}% of max frequency (throttling active)" -f $out.CpuPercentMaxFreq
    }
    return [pscustomobject]$out
}

function Get-SMARTAttributes {
    $attrs = @()
    $nameMap = @{
        5 = 'ReallocatedSectors'; 9 = 'PowerOnHours'; 187 = 'ReportedUncorrect'; 188 = 'CommandTimeout'; 189 = 'HighFlyWrites'; 190 = 'Temperature'; 191 = 'GShock'; 192 = 'PowerOffRetract'; 193 = 'LoadCycleCount'; 194 = 'TempCelsius'; 195 = 'HardwareECC'; 196 = 'ReallocEvent'; 197 = 'PendingSectors'; 198 = 'UncorrectableSectors'; 199 = 'InterfaceCrc'; 231 = 'SSDLifeLeft'; 232 = 'Endurance'; 233 = 'MediaWearout'; 241 = 'TotalLBAsWritten'; 242 = 'TotalLBAsRead'
    }
    try {
        $thresholds = @{}
        try {
            $thr = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictThresholds -ErrorAction Stop
            foreach ($t in $thr) {
                $rawThr = $t.VendorSpecific
                for ($i = 2; $i -lt $rawThr.Length; $i += 12) {
                    $id = $rawThr[$i]; if ($id -eq 0) { continue }
                    $thresholds[$id] = $rawThr[$i + 1]
                }
            }
        }
        catch {}

        $data = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictData -ErrorAction Stop
        foreach ($d in $data) {
            $raw = $d.VendorSpecific
            for ($i = 2; $i -lt $raw.Length; $i += 12) {
                $id = $raw[$i]; if ($id -eq 0) { continue }
                $val = $raw[$i + 3]; $worst = $raw[$i + 4]
                $rawBytes = @(); for ($j = $i + 5; $j -le [math]::Min($i + 10, $raw.Length - 1); $j++) { $rawBytes += $raw[$j] }
                $rawHex = ($rawBytes | ForEach-Object { $_.ToString('X2') }) -join ''
                $rawDec = $null; if ($rawHex) { try { $rawDec = [Convert]::ToInt64($rawHex, 16) } catch { $rawDec = $null } }
                $thrVal = $null; $thresholds.TryGetValue($id, [ref]$thrVal) | Out-Null
                $name = if ($nameMap.ContainsKey($id)) { $nameMap[$id] } else { "Attr$id" }
                $attrs += [pscustomobject]@{ Id = $id; Name = $name; Current = $val; Worst = $worst; Threshold = $thrVal; Raw = $rawDec }
            }
        }
    }
    catch { return @() }
    return $attrs
}

function Get-NVMEDriveInfo {
    $drives = @()
    try {
        $cim = Get-CimInstance -ClassName MSFT_PhysicalDisk -Namespace root/microsoft/windows/storage -ErrorAction SilentlyContinue
        if ($cim) {
            foreach ($disk in $cim) {
                if ($disk.MediaType -eq 5) {
                    $health = 'Unknown'
                    if ($disk.HealthStatus -eq 0) { $health = 'OK' }
                    elseif ($disk.HealthStatus -eq 1) { $health = 'Warning' }
                    elseif ($disk.HealthStatus -eq 2) { $health = 'Unhealthy' }
                    $usage = $null
                    try { $usage = Get-CimInstance -ClassName MSFT_StorageReliabilityCounter -Filter "PhysicalDiskObjectId='$($disk.ObjectId)'" -Namespace root/microsoft/windows/storage -ErrorAction SilentlyContinue | Select-Object -First 1 }
                    catch {}
                    $drives += [pscustomobject]@{ Model = $disk.Model; Size_GB = [math]::Round([double]$disk.Size / 1GB, 1); Health = $health; Wear_Percent = if ($usage) { [math]::Round((100.0 - ([double]$usage.EnduranceRemaining / 100.0)), 1) } else { $null }; PowerOnHours = if ($usage) { $usage.PowerOnHours } else { $null }; DataWritten_GB = if ($usage) { [math]::Round([double]$usage.BytesWritten / 1GB, 1) } else { $null } }
                }
            }
        }
    }
    catch {}
    return $drives
}

function Get-SATAdDriveInfo {
    $drives = @()
    try {
        $phys = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue
        if ($phys) {
            foreach ($disk in $phys) {
                $drives += [pscustomobject]@{ Model = $disk.Model; Size_GB = [math]::Round([double]$disk.Size / 1GB, 1); Health = $disk.Status; Wear_Percent = $null; PowerOnHours = $null; DataWritten_GB = $null }
            }
        }
    }
    catch {}
    return $drives
}

# Disk health (SMART) and filesystem checks (Win7-safe best-effort)
function Get-DiskHealthSummary {
    $summary = [ordered]@{ SmartAvailable = $false; AnyPredictFailure = $null; PredictFailureCount = 0; Notes = @(); Attributes = @(); KeyAttributes = @(); DriveInfo = @(); NVMEDrives = @() }
    try {
        $smart = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop
        if ($smart) {
            $summary.SmartAvailable = $true
            $fails = @($smart | Where-Object { $_.PredictFailure -eq $true })
            $summary.PredictFailureCount = $fails.Count
            $summary.AnyPredictFailure = ($fails.Count -gt 0)
            if ($summary.AnyPredictFailure) { $summary.Notes += "One or more disks report SMART PredictFailure=True" }
        }
    }
    catch { $summary.Notes += "SMART status unavailable (driver or permissions)" }

    try {
        $attrs = Get-SMARTAttributes
        if ($attrs -and $attrs.Count -gt 0) {
            $summary.Attributes = $attrs
            $interesting = @(5, 187, 188, 197, 198, 199, 231, 232, 233, 241, 242, 194, 190, 9)
            $summary.KeyAttributes = @($attrs | Where-Object { $interesting -contains $_.Id })
        }
    }
    catch {}

    if (-not $summary.SmartAvailable) {
        try {
            $drives = Get-WmiObject -Class Win32_DiskDrive -ErrorAction SilentlyContinue
            if ($drives) {
                foreach ($d in $drives) {
                    if ($d.Status) { $summary.Notes += "Disk '$($d.Model)': Status=$($d.Status) (vendor/BIOS)" }
                }
            }
        }
        catch {}
    }

    if (-not $summary.SmartAvailable) {
        $summary.Notes += "Tip: run elevated to improve SMART access (some drivers block non-admin)."
    }

    # File system dirty bit (system drive) — best-effort
    try {
        $sysDrive = (Get-WmiObject -Class Win32_OperatingSystem).SystemDrive
        $dirty = & fsutil dirty query $sysDrive 2>$null
        if ($dirty -match 'is NOT Dirty') { $summary.Notes += "File system dirty bit: Not dirty" }
        elseif ($dirty -match 'is Dirty') { $summary.Notes += "File system dirty bit: Dirty (chkdsk may be required)" }
    }
    catch { $summary.Notes += "Could not query dirty bit (non-admin or fsutil unavailable)" }

    return [pscustomobject]$summary
}

function Write-DiskHealthSection {
    $h = Get-DiskHealthSummary
    Write-Section "Disk Health"
    if ($h.SmartAvailable) {
        $msg = if ($h.AnyPredictFailure) { "SMART: FAILURE PREDICTED on $($h.PredictFailureCount) disk(s)" } else { "SMART: No imminent failure reported" }
        Write-Host $msg -ForegroundColor $(if ($h.AnyPredictFailure) { 'Red' } else { 'Green' })
    }
    else {
        Write-Host "SMART status not available" -ForegroundColor Yellow
    }
    foreach ($n in $h.Notes) { Write-Host (" - {0}" -f $n) -ForegroundColor Gray }
    # Enumerate and display all physical drives
    try { $h.NVMEDrives = Get-NVMEDriveInfo; $h.DriveInfo = Get-SATAdDriveInfo } catch {}
    if ($h.NVMEDrives -and $h.NVMEDrives.Count -gt 0) {
        Write-Host "NVMe Drives:" -ForegroundColor White
        foreach ($d in $h.NVMEDrives) {
            $w = if ($d.Wear_Percent -ne $null) { " | Wear {0}%" -f $d.Wear_Percent } else { '' }
            $hr = if ($d.PowerOnHours -ne $null) { " | Hours {0:N0}" -f $d.PowerOnHours } else { '' }
            $dt = if ($d.DataWritten_GB -ne $null) { " | Data {0:N0} GB" -f $d.DataWritten_GB } else { '' }
            Write-Host (" - {0} ({1} GB) [{2}]{3}{4}{5}" -f $d.Model, $d.Size_GB, $d.Health, $w, $hr, $dt) -ForegroundColor Gray
        }
    }
    if ($h.DriveInfo -and $h.DriveInfo.Count -gt 0) {
        Write-Host "SATA/SAS Drives:" -ForegroundColor White
        foreach ($d in $h.DriveInfo) { Write-Host (" - {0} ({1} GB) [{2}]" -f $d.Model, $d.Size_GB, $d.Health) -ForegroundColor Gray }
    }
    if ($h.KeyAttributes -and $h.KeyAttributes.Count -gt 0) {
        Write-Host "Key SMART attributes:" -ForegroundColor White
        foreach ($a in ($h.KeyAttributes | Select-Object -First 8)) {
            $thrTxt = if ($a.Threshold -ne $null) { "/thresh $($a.Threshold)" } else { '' }
            $rawTxt = if ($a.Raw -ne $null) { "$($a.Raw)" } else { 'n/a' }
            Write-Host (" - {0} (ID {1}): {2} (worst {3}){4}, raw {5}" -f $a.Name, $a.Id, $a.Current, $a.Worst, $thrTxt, $rawTxt) -ForegroundColor DarkGray
        }
    }
    return $h
}

# Event log summaries (last N days) — Win7-safe
function Get-EventLogSummary {
    param([int]$Days = 7)
    $since = (Get-Date).AddDays( - [math]::Abs($Days))
    $result = [ordered]@{}
    foreach ($logName in @('System', 'Application')) {
        $summary = [ordered]@{ Critical = 0; Error = 0; TopProviders = @() }
        try {
            $events = Get-WinEvent -FilterHashtable @{LogName = $logName; Level = 1, 2; StartTime = $since } -ErrorAction Stop
            if ($events) {
                $summary.Critical = ($events | Where-Object { $_.LevelDisplayName -eq 'Critical' -or $_.Level -eq 1 } | Measure-Object).Count
                $summary.Error = ($events | Where-Object { $_.LevelDisplayName -eq 'Error' -or $_.Level -eq 2 } | Measure-Object).Count
                $top = $events | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5
                foreach ($t in $top) {
                    $prov = if ([string]::IsNullOrWhiteSpace($t.Name)) { 'Unknown' } else { $t.Name }
                    $one = $events | Where-Object { $_.ProviderName -eq $prov } | Select-Object -First 1
                    $msg = $one.Message
                    if ($msg -and $msg.Length -gt 140) { $msg = $msg.Substring(0, 140) + '…' }
                    $summary.TopProviders += [pscustomobject]@{ Provider = $prov; Count = $t.Count; Sample = $msg }
                }
            }
        }
        catch { }
        $result[$logName] = [pscustomobject]$summary
    }
    return [pscustomobject]$result
}
function Write-EventLogSection {
    param([int]$Days = 7)
    Write-Section "Event Logs (last $Days days)"
    $s = Get-EventLogSummary -Days $Days
    foreach ($ln in 'System', 'Application') {
        $x = $s.$ln
        Write-Host ("{0}: Critical={1} Error={2}" -f $ln, $x.Critical, $x.Error) -ForegroundColor Cyan
        foreach ($p in $x.TopProviders) {
            Write-Host (" - {0}: {1} events" -f $p.Provider, $p.Count) -ForegroundColor Gray
            if ($p.Sample) { Write-Host ("   e.g., {0}" -f $p.Sample) -ForegroundColor DarkGray }
        }
    }
    return $s
}

function Get-ReliabilitySummary {
    param([int]$Days = 7)
    $since = (Get-Date).AddDays( - [math]::Abs($Days))
    $summary = [ordered]@{ StabilityIndex = $null; RecentFailures = 0; TopIssues = @() }
    try {
        $metric = Get-CimInstance -ClassName Win32_ReliabilityStabilityMetrics -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($metric -and $metric.SystemStabilityIndex -ne $null) { $summary.StabilityIndex = [math]::Round([double]$metric.SystemStabilityIndex, 2) }
    }
    catch {}
    try {
        $dtmf = [Management.ManagementDateTimeConverter]::ToDmtfDateTime($since)
        $records = Get-CimInstance -ClassName Win32_ReliabilityRecords -Filter "TimeGenerated >= '$dtmf'" -ErrorAction SilentlyContinue
        if ($records) {
            $recent = $records | Where-Object { $_.SourceName -and $_.Severity -ge 1 }
            $summary.RecentFailures = ($recent | Measure-Object).Count
            $top = $recent | Group-Object SourceName | Sort-Object Count -Descending | Select-Object -First 5
            foreach ($t in $top) {
                $one = $recent | Where-Object { $_.SourceName -eq $t.Name } | Select-Object -First 1
                $msg = $one.Message
                if ($msg -and $msg.Length -gt 140) { $msg = $msg.Substring(0, 140) + '…' }
                $summary.TopIssues += [pscustomobject]@{ Source = $t.Name; Count = $t.Count; Sample = $msg }
            }
        }
    }
    catch {}
    return [pscustomobject]$summary
}

function Write-ReliabilitySection {
    Write-Section "Reliability (ReliMon)"
    $rel = Get-ReliabilitySummary -Days 7
    if ($rel.StabilityIndex -ne $null) { Write-Host ("Stability Index: {0}" -f $rel.StabilityIndex) -ForegroundColor Gray }
    if ($rel.RecentFailures -ne $null) { Write-Host ("Recent failures (last 7d): {0}" -f $rel.RecentFailures) -ForegroundColor Gray }
    if ($rel.TopIssues -and $rel.TopIssues.Count -gt 0) {
        foreach ($i in $rel.TopIssues) {
            Write-Host (" - {0}: {1} events" -f $i.Source, $i.Count) -ForegroundColor Gray
            if ($i.Sample) { Write-Host ("   e.g., {0}" -f $i.Sample) -ForegroundColor DarkGray }
        }
    }
    return $rel
}

function Invoke-NetworkSelfTest {
    param([string[]]$Targets = @('1.1.1.1', '8.8.8.8', 'github.com'), [int]$Count = 6)
    $results = @()
    foreach ($t in $Targets) {
        $stat = [ordered]@{ Target = $t; Sent = $Count; Received = 0; LossPct = $null; MinMs = $null; MaxMs = $null; AvgMs = $null; Tcp443 = $null }
        try {
            $pings = Test-Connection -ComputerName $t -Count $Count -ErrorAction Stop
            if ($pings) {
                $stat.Received = ($pings | Measure-Object).Count
                if ($stat.Received -gt 0) {
                    $stat.LossPct = [math]::Round((($Count - $stat.Received) / $Count) * 100, 0)
                    $stat.MinMs = ($pings | Measure-Object ResponseTime -Minimum).Minimum
                    $stat.MaxMs = ($pings | Measure-Object ResponseTime -Maximum).Maximum
                    $stat.AvgMs = [math]::Round(($pings | Measure-Object ResponseTime -Average).Average, 1)
                }
                else {
                    $stat.LossPct = 100
                }
            }
        }
        catch {
            try {
                $pingRaw = & ping -n $Count $t 2>$null
                $rcvdLine = $pingRaw | Where-Object { $_ -match 'Packets: Sent' } | Select-Object -First 1
                if ($rcvdLine -and $rcvdLine -match 'Sent = (\d+), Received = (\d+), Lost = (\d+)') {
                    $stat.Sent = [int]$matches[1]; $stat.Received = [int]$matches[2]
                    $stat.LossPct = if ($stat.Sent -gt 0) { [math]::Round((($stat.Sent - $stat.Received) / $stat.Sent) * 100, 0) } else { $null }
                }
                $latLine = $pingRaw | Where-Object { $_ -match 'Minimum' } | Select-Object -First 1
                if ($latLine -and $latLine -match 'Minimum = (\d+)ms, Maximum = (\d+)ms, Average = (\d+)ms') {
                    $stat.MinMs = [int]$matches[1]; $stat.MaxMs = [int]$matches[2]; $stat.AvgMs = [int]$matches[3]
                }
            }
            catch {}
        }
        if ($stat.AvgMs -eq $null -or $stat.AvgMs -le 0) {
            $stat.AvgMs = $null; $stat.MinMs = $null; $stat.MaxMs = $null; $stat.Received = 0; $stat.LossPct = 100
        }
        if ($stat.Received -eq 0 -and $stat.LossPct -eq $null) { $stat.LossPct = 100 }
        if ($stat.LossPct -eq $null -and $stat.Sent -gt 0) { $stat.LossPct = [math]::Round((($stat.Sent - $stat.Received) / $stat.Sent) * 100, 0) }
        if ($stat.Received -eq 0) {
            try {
                # Try TCP 443 reachability as ICMP may be blocked
                $tcpOk = $false
                try { $null = Test-Connection -ComputerName $t -TcpPort 443 -Count 1 -ErrorAction Stop; $tcpOk = $true } catch {}
                if (-not $tcpOk) {
                    try {
                        $client = New-Object System.Net.Sockets.TcpClient
                        $iar = $client.BeginConnect($t, 443, $null, $null)
                        $tcpOk = $iar.AsyncWaitHandle.WaitOne(3000)
                        try { $client.Close() } catch {}
                    }
                    catch {}
                }
                $stat.Tcp443 = $tcpOk
            }
            catch {}
        }
        $results += [pscustomobject]$stat
    }
    return $results
}

function Invoke-TcpConnectJitter {
    param([string[]]$Targets = @('github.com', '1.1.1.1', '8.8.8.8'), [int]$Attempts = 6, [int]$TimeoutMs = 3000)
    $out = @()
    foreach ($t in $Targets) {
        $times = New-Object System.Collections.Generic.List[double]
        $success = 0
        for ($i = 0; $i -lt $Attempts; $i++) {
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $client = New-Object System.Net.Sockets.TcpClient
                $iar = $client.BeginConnect($t, 443, $null, $null)
                if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { $success++ }
                $sw.Stop()
                try { $client.Close() } catch {}
                if ($sw.Elapsed.TotalMilliseconds -gt 0) { $times.Add($sw.Elapsed.TotalMilliseconds) }
            }
            catch {}
        }
        if ($times.Count -gt 0) {
            $avg = ($times | Measure-Object -Average).Average
            $min = ($times | Measure-Object -Minimum).Minimum
            $max = ($times | Measure-Object -Maximum).Maximum
            $mean = $avg
            $var = 0.0
            foreach ($v in $times) { $var += [math]::Pow(($v - $mean), 2) }
            if ($times.Count -gt 1) { $var = $var / ($times.Count - 1) } else { $var = 0 }
            $std = [math]::Sqrt($var)
        }
        else { $avg = $null; $min = $null; $max = $null; $std = $null }
        $out += [pscustomobject]@{ Target = $t; Attempts = $Attempts; Successes = $success; AvgMs = ([math]::Round($avg, 1)); MinMs = ([math]::Round($min, 1)); MaxMs = ([math]::Round($max, 1)); JitterStdMs = ([math]::Round($std, 1)) }
    }
    return $out
}

function Invoke-HttpThroughputTest {
    param([string[]]$Urls = @('https://speed.cloudflare.com/__down?bytes=1048576', 'https://speed.hetzner.de/1MB.bin'), [int]$TimeoutSec = 15)
    $results = @()
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $true
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    }
    catch { $client = $null }
    foreach ($u in $Urls) {
        $ok = $false; $err = $null; $bytes = 0; $ms = $null; $mbps = $null; $kbps = $null
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            if ($client) {
                $resp = $client.GetAsync($u, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                if ($resp.IsSuccessStatusCode) {
                    $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                    $buf = New-Object byte[] 65536
                    while (($read = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $bytes += $read }
                    $stream.Dispose()
                    $ok = $true
                }
                else { $err = "HTTP $($resp.StatusCode)" }
            }
            else {
                $tmp = New-TemporaryFile
                try { $dl = Invoke-WebRequest -Uri $u -OutFile $tmp -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop; $bytes = (Get-Item $tmp).Length; $ok = $true } catch { $err = $_.Exception.Message } finally { try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch {} }
            }
            $sw.Stop(); $ms = $sw.Elapsed.TotalMilliseconds
            if ($ok -and $ms -gt 0) { $kbps = [math]::Round(($bytes / 1024.0) / ($ms / 1000.0), 1); $mbps = [math]::Round((($bytes * 8.0) / ($ms / 1000.0)) / 1e6, 2) }
        }
        catch { $err = $_.Exception.Message }
        $results += [pscustomobject]@{ Url = $u; Bytes = $bytes; DurationMs = ([math]::Round($ms, 1)); KBps = $kbps; Mbps = $mbps; Success = $ok; Error = $err }
    }
    return $results
}

function Write-NetworkPerfSection {
    Write-Section "Network throughput/jitter"
    $tcp = Invoke-TcpConnectJitter
    if ($tcp -and $tcp.Count -gt 0) {
        Write-Host "TCP 443 connect jitter:" -ForegroundColor White
        foreach ($t in $tcp) { Write-Host (" - {0}: avg {1} ms (min {2} / max {3}), jitter std {4} ms, success {5}/{6}" -f $t.Target, $t.AvgMs, $t.MinMs, $t.MaxMs, $t.JitterStdMs, $t.Successes, $t.Attempts) -ForegroundColor Gray }
    }
    else { Write-Host "TCP connect jitter unavailable" -ForegroundColor Yellow }
    $http = Invoke-HttpThroughputTest
    if ($http -and ($http | Where-Object { $_.Success }).Count -gt 0) {
        Write-Host "HTTP download throughput:" -ForegroundColor White
        foreach ($h in $http) { $status = if ($h.Success) { "OK" } else { "Fail" }; Write-Host (" - {0}: {1} MB in {2} ms → {3} Mbps ({4} KB/s) [{5}]" -f ([math]::Round($h.Bytes / 1MB, 2)), $h.Url, $h.DurationMs, $h.Mbps, $h.KBps, $status) -ForegroundColor Gray }
    }
    else { Write-Host "HTTP throughput test unavailable or blocked" -ForegroundColor Yellow }
    return [pscustomobject]@{ Tcp = $tcp; Http = $http }
}

function Write-NetworkSelfTestSection {
    Write-Section "Network self-test (latency/jitter)"
    $tests = Invoke-NetworkSelfTest
    if (-not $tests -or $tests.Count -eq 0) {
        Write-Host "Network test unavailable" -ForegroundColor Yellow
        return $tests
    }
    foreach ($t in $tests) {
        $lossTxt = if ($t.LossPct -ne $null) { "loss {0}%" -f $t.LossPct } else { 'loss n/a' }
        $latTxt = if ($t.AvgMs -ne $null) { "avg {0} ms (min {1} / max {2})" -f $t.AvgMs, $t.MinMs, $t.MaxMs } else { 'latency n/a' }
        $tcpTxt = if ($t.Tcp443 -eq $true) { 'TCP 443 reachable' } elseif ($t.Tcp443 -eq $false) { 'TCP 443 blocked' } else { $null }
        $extra = if ($tcpTxt) { ", $tcpTxt" } else { '' }
        Write-Host (" - {0}: {1}, {2}{3}" -f $t.Target, $latTxt, $lossTxt, $extra) -ForegroundColor Gray
    }
    return $tests
}

Write-Section "System Info"
$sys = Get-SystemInfo
$sys | Format-List

Write-Section "Baseline top processes (CPU)"
Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | Select-Object Name, CPU, PM, NPM, StartTime | Format-Table -AutoSize

Write-Section "Baseline top processes (Memory)"
Get-Process | Sort-Object WS -Descending | Select-Object -First 5 | Select-Object Name, WS, PM, CPU, StartTime | Format-Table -AutoSize

if (-not $NoLoad) {
    if ($HeavyLoad) {
        $effective = [math]::Min([int]$DurationSeconds, 30)
        Write-Section "Synthetic load (HEAVY, safe)"
        Write-Host "Applying CPU + disk load for $effective seconds (leaving one core free)..." -ForegroundColor Yellow
        $jobs = @()
        $jobs += Start-HeavyCpuLoad -Seconds $effective
        $diskJob = Start-DiskLoad -Seconds $effective
        if ($diskJob) { $jobs += $diskJob }
        $sampleSeconds = $effective
        $probeType = 'Heavy'
    }
    else {
        Write-Section "Synthetic load (light)"
        Write-Host "Spinning CPU for $DurationSeconds seconds to observe behavior..." -ForegroundColor Yellow
        $jobs = Start-SyntheticLoad -Seconds $DurationSeconds
        $sampleSeconds = $DurationSeconds
        $probeType = 'Light'
    }
}
else {
    $sampleSeconds = $DurationSeconds
    $probeType = 'Passive'
}

# Start concurrent process sampling for the same window
$procSampleJob = Start-ProcessSamplerJob -Seconds $sampleSeconds
$perf = Sample-PerfCounters -Seconds $sampleSeconds
# Compute robust stats (ignore nulls)
$cpuVals = @($perf | ForEach-Object { $_.'\\Processor(_Total)\\% Processor Time' } | Where-Object { $_ -ne $null })
$dpcVals = @($perf | ForEach-Object { $_.'\\Processor(_Total)\\% DPC Time' } | Where-Object { $_ -ne $null })
$isrVals = @($perf | ForEach-Object { $_.'\\Processor(_Total)\\% Interrupt Time' } | Where-Object { $_ -ne $null })
$intrVals = @($perf | ForEach-Object { $_.'\\Processor(_Total)\\Interrupts/sec' } | Where-Object { $_ -ne $null })
$dpcRateVals = @($perf | ForEach-Object { $_.'\\Processor(_Total)\\DPCs Queued/sec' } | Where-Object { $_ -ne $null })
$memVals = @($perf | ForEach-Object { $_.'\\Memory\\Available MBytes' } | Where-Object { $_ -ne $null })
$qlVals = @($perf | ForEach-Object { $_.'\\PhysicalDisk(_Total)\\Avg. Disk Queue Length' } | Where-Object { $_ -ne $null })
$latVals = @($perf | ForEach-Object { $_.'\\PhysicalDisk(_Total)\\Avg. Disk sec/Transfer' } | Where-Object { $_ -ne $null })
$avgCpu = if ($cpuVals.Count -gt 0) { ($cpuVals | Measure-Object -Average).Average } else { $null }
$avgDpc = if ($dpcVals.Count -gt 0) { ($dpcVals | Measure-Object -Average).Average } else { $null }
$avgIsr = if ($isrVals.Count -gt 0) { ($isrVals | Measure-Object -Average).Average } else { $null }
$maxDpc = if ($dpcVals.Count -gt 0) { ($dpcVals | Measure-Object -Maximum).Maximum } else { $null }
$maxIsr = if ($isrVals.Count -gt 0) { ($isrVals | Measure-Object -Maximum).Maximum } else { $null }
$avgIntr = if ($intrVals.Count -gt 0) { ($intrVals | Measure-Object -Average).Average } else { $null }
$avgDpcRate = if ($dpcRateVals.Count -gt 0) { ($dpcRateVals | Measure-Object -Average).Average } else { $null }
$minMemMB = if ($memVals.Count -gt 0) { ($memVals | Measure-Object -Minimum).Minimum } else { $null }
$avgQlen = if ($qlVals.Count -gt 0) { ($qlVals  | Measure-Object -Average).Average } else { $null }
$avgDisk = if ($latVals.Count -gt 0) { ($latVals | Measure-Object -Average).Average } else { $null }

# Fallback: micro-probe disk latency if counters absent/zero
$diskProbeMs = $null
if (($avgDisk -eq $null) -or ([double]$avgDisk -le 0)) {
    $diskProbeMs = Measure-DiskProbeLatencyMs -Ops 48
    if ($diskProbeMs -ne $null) { $avgDisk = [double]($diskProbeMs / 1000.0) }
}

$cpuText = if ($avgCpu -ne $null) { "{0:N1}%" -f $avgCpu } else { 'n/a' }
$dpcText = if ($avgDpc -ne $null) { "{0:N2}% (max {1:N2}%)" -f $avgDpc, $maxDpc } else { 'n/a' }
$isrText = if ($avgIsr -ne $null) { "{0:N2}% (max {1:N2}%)" -f $avgIsr, $maxIsr } else { 'n/a' }
$memText = if ($minMemMB -ne $null) { "{0:N0} MB" -f $minMemMB } else { 'n/a' }
$qText = if ($avgQlen -ne $null) { "{0:N2}" -f $avgQlen } else { 'n/a' }
$latText = if ($avgDisk -ne $null) { "{0:N4}" -f $avgDisk } else { 'n/a' }
Write-Host ("CPU avg: {0} | Min avail mem: {1} | Disk queue avg: {2} | Disk sec/transfer avg: {3}" -f $cpuText, $memText, $qText, $latText) -ForegroundColor Gray
if ($diskProbeMs -ne $null) { Write-Host ("(Disk latency from micro-probe: ~{0} ms/op)" -f $diskProbeMs) -ForegroundColor DarkGray }

Write-Section "Kernel latency (DPC/ISR)"
if ($avgDpc -ne $null -or $avgIsr -ne $null) {
    if ($avgDpc -ne $null) { Write-Host ("DPC time avg {0:N2}% (max {1:N2}%)" -f $avgDpc, $maxDpc) -ForegroundColor Gray }
    if ($avgIsr -ne $null) { Write-Host ("ISR time avg {0:N2}% (max {1:N2}%)" -f $avgIsr, $maxIsr) -ForegroundColor Gray }
    if ($avgIntr -ne $null) { Write-Host ("Interrupts/sec avg {0:N0}" -f $avgIntr) -ForegroundColor Gray }
    if ($avgDpcRate -ne $null) { Write-Host ("DPCs queued/sec avg {0:N0}" -f $avgDpcRate) -ForegroundColor Gray }
}
else {
    Write-Host "DPC/ISR counters unavailable" -ForegroundColor Yellow
}

Write-Section "Top processes after load"
Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | Select-Object Name, CPU, PM, NPM, StartTime | Format-Table -AutoSize

Write-Section "Recommendations"
if ($avgCpu -ne $null) {
    if ($avgCpu -gt 85) { Write-Host "CPU saturates under light load; consider closing background apps or upgrading CPU." -ForegroundColor Yellow }
    else { Write-Host "CPU headroom seems reasonable under light load." -ForegroundColor Green }
}
else { Write-Host "CPU metric unavailable (perf counters not accessible)." -ForegroundColor Yellow }
if ($minMemMB -ne $null) {
    if ($minMemMB -lt 800) { Write-Host "Low available memory (<800 MB) observed; add RAM or close apps." -ForegroundColor Yellow }
    else { Write-Host "Memory headroom acceptable." -ForegroundColor Green }
}
else { Write-Host "Memory metric unavailable (perf counters not accessible)." -ForegroundColor Yellow }
if ($avgQlen -ne $null) {
    if ($avgQlen -gt 2) { Write-Host "Disk queue length high (>2); disk is likely bottleneck. Consider SSD or reduce I/O load." -ForegroundColor Yellow }
    else { Write-Host "Disk queue looks OK for light load." -ForegroundColor Green }
}
else { Write-Host "Disk queue metric unavailable (perf counters not accessible)." -ForegroundColor Yellow }
if ($avgDisk -ne $null) {
    if ($avgDisk -gt 0.05) { Write-Host "Disk latency high (>50 ms); storage is slow." -ForegroundColor Yellow }
    else { Write-Host "Disk latency looks acceptable for light load." -ForegroundColor Green }
}
else { Write-Host "Disk latency metric unavailable (perf counters not accessible)." -ForegroundColor Yellow }

# Simple system drive free space check (Win7-safe)
try {
    $sysDrive = (Get-WmiObject -Class Win32_OperatingSystem).SystemDrive
    $c = Get-WmiObject -Class Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $sysDrive)
    if ($c -and $c.Size) {
        $pctFree = if ($c.Size -gt 0) { [math]::Round(($c.FreeSpace / $c.Size) * 100, 1) } else { $null }
        if ($pctFree -ne $null) {
            if ($pctFree -lt 10) { Write-Host ("Low free space on {0} ({1}% free). Free up disk space." -f $c.DeviceID, $pctFree) -ForegroundColor Yellow }
            else { Write-Host ("System drive free space OK (~{0}% free)." -f $pctFree) -ForegroundColor Green }
        }
    }
}
catch { }

Write-Section "Focus Areas (OS-aware)"
Analyze-OSFocusAreas -AvgCpu ($avgCpu | ForEach-Object { [double]$_ }) -AvgDiskQ ($avgQlen | ForEach-Object { [double]$_ }) -AvgDiskLatency ($avgDisk | ForEach-Object { [double]$_ }) -MinAvailMemMB ($minMemMB | ForEach-Object { [double]$_ })

# New: Disk health + Event logs
$diskHealth = Write-DiskHealthSection
$eventSummary = Write-EventLogSection -Days 7
$reliability = Write-ReliabilitySection

Write-Section "Startup and Tasks"
$startup = Get-StartupEntries
$tasks = Get-ScheduledTasksSummary
Write-Host ("Startup items: {0} | Scheduled tasks: total={1}, running={2}, failed(last)={3}" -f ($startup | Measure-Object).Count, $tasks.Total, $tasks.Running, $tasks.Failed) -ForegroundColor Cyan
if ($tasks.TopFailures) {
    foreach ($t in $tasks.TopFailures) { Write-Host (" - {0} (LastRun={1}, Result={2})" -f $t.TaskName, $t.LastRunTime, $t.LastResult) -ForegroundColor Gray }
}

Write-Section "Process Activity (rolling)"
if ($procSampleJob) {
    try { $procSample = Receive-Job -Job $procSampleJob -Wait -AutoRemoveJob } catch { $procSample = $null }
}
if (-not $procSample) {
    $procSample = Sample-ProcessActivity -Seconds ([math]::Min(10, [math]::Max(5, [int]$sampleSeconds)))
}
else {
    # Fallback: if no offenders captured, take a short immediate sample
    $hasCpu = $procSample.TopCPU | Where-Object { $_ -and $_.Name } | Measure-Object | Select-Object -ExpandProperty Count
    $hasIo = $procSample.TopIO  | Where-Object { $_ -and $_.Name } | Measure-Object | Select-Object -ExpandProperty Count
    if (($hasCpu -eq 0) -and ($hasIo -eq 0)) {
        $procSample = Sample-ProcessActivity -Seconds 3
        $hasCpu = $procSample.TopCPU | Where-Object { $_ -and $_.Name } | Measure-Object | Select-Object -ExpandProperty Count
        $hasIo = $procSample.TopIO  | Where-Object { $_ -and $_.Name } | Measure-Object | Select-Object -ExpandProperty Count
        if (($hasCpu -eq 0) -and ($hasIo -eq 0)) {
            # Last resort: quick 1s delta snapshot
            try {
                $p1 = Get-Process | Select-Object Id, Name, CPU, IOReadBytes, IOWriteBytes
                Start-Sleep -Seconds 1
                $p2 = Get-Process | Select-Object Id, Name, CPU, IOReadBytes, IOWriteBytes
                $agg = @()
                foreach ($p in $p2) {
                    $prev = $p1 | Where-Object { $_.Id -eq $p.Id }
                    if ($prev) {
                        $dcpu = [double]($p.CPU - $prev.CPU); if ($dcpu -lt 0) { $dcpu = 0 }
                        $dio = [double](($p.IOReadBytes - $prev.IOReadBytes) + ($p.IOWriteBytes - $prev.IOWriteBytes)); if ($dio -lt 0) { $dio = 0 }
                        $agg += [pscustomobject]@{ PID = $p.Id; Name = $p.Name; AvgCPU = [math]::Round($dcpu * 100, 1); AvgBps = [math]::Round($dio, 0) }
                    }
                }
                $topCpuSnap = $agg | Sort-Object AvgCPU -Descending | Select-Object -First 5
                $topIoSnap = $agg | Sort-Object AvgBps -Descending | Select-Object -First 5
                $procSample = [pscustomobject]@{ TopCPU = $topCpuSnap; TopIO = $topIoSnap }
            }
            catch {}
        }
    }
}
if ($procSample) {
    $topCpu = @($procSample.TopCPU | Where-Object { $_ -and $_.Name })
    $topIo = @($procSample.TopIO  | Where-Object { $_ -and $_.Name })
    $ioLimited = $false
    if ($topIo.Count -eq 0 -or (($topIo | Measure-Object AvgBps -Sum).Sum -eq 0)) {
        $ioFallback = Sample-ProcessIOFallbackCounters -Seconds ([math]::Min(3, [math]::Max(2, [int]$sampleSeconds)))
        if ($ioFallback -and $ioFallback.Count -gt 0) {
            $topIo = @($ioFallback)
            $ioLimited = $true
        }
        else {
            $ioLimited = $true
        }
    }
    Write-Host "Top CPU (avg across window):" -ForegroundColor White
    if ($topCpu.Count -gt 0) {
        $topCpu | ForEach-Object { Write-Host (" - {0} (PID {1}): {2}%" -f $_.Name, $_.PID, $_.AvgCPU) -ForegroundColor Gray }
    }
    else {
        Write-Host " - None observed" -ForegroundColor Gray
    }
    Write-Host "Top I/O (bytes/sec):" -ForegroundColor White
    if ($topIo.Count -gt 0) {
        $topIo | ForEach-Object { Write-Host (" - {0}: {1} B/s" -f $_.Name, $_.AvgBps) -ForegroundColor Gray }
        if ($ioLimited) {
            Write-Host "  (Note: I/O data from perf counters; per-process data unavailable on this system)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host " - None observed (I/O tracking limited on this system)" -ForegroundColor Gray
    }
}

$netSelfTest = Write-NetworkSelfTestSection
$netPerf = Write-NetworkPerfSection

Write-Section "Thermals & Throttling"
$therm = Get-ThermalAndThrottle
if ($therm.Zones -and $therm.Zones.Count -gt 0) {
    foreach ($z in $therm.Zones) { Write-Host (" - {0}: {1}°C" -f $z.Name, $z.TempC) -ForegroundColor Gray }
}
else {
    Write-Host "No ACPI thermal zones detected (sensor not exposed)" -ForegroundColor Yellow
}
if ($therm.CpuPercentMaxFreq -ne $null) {
    Write-Host ("CPU % of max frequency: {0}%" -f $therm.CpuPercentMaxFreq) -ForegroundColor Gray
}
else {
    Write-Host "CPU frequency/throttle counter unavailable" -ForegroundColor Yellow
}
if ($therm.GpuUtilMax -ne $null) {
    Write-Host ("GPU utilization (peak during sample): {0}%" -f $therm.GpuUtilMax) -ForegroundColor Gray
}
else {
    Write-Host "GPU utilization counter unavailable" -ForegroundColor Yellow
}
if ($therm.Notes -and $therm.Notes.Count -gt 0) {
    foreach ($note in $therm.Notes) { Write-Host (" - {0}" -f $note) -ForegroundColor DarkGray }
}

if (-not $NoLoad -and $jobs) {
    Write-Host "Stopping synthetic load jobs..." -ForegroundColor Gray
    $jobs | ForEach-Object { Stop-Job -Job $_ -ErrorAction SilentlyContinue; Remove-Job -Job $_ -Force -ErrorAction SilentlyContinue }
}

# Build customer-friendly summary
function Get-Recommendations {
    param(
        [Nullable[Double]]$AvgCpu, [Nullable[Double]]$MinMemMB, [Nullable[Double]]$AvgQlen, [Nullable[Double]]$AvgDiskSec, [double]$RamTotalGB, [object]$OsFlavor, [string]$DisksText, [Nullable[Double]]$AvgDpc, [Nullable[Double]]$AvgIsr
    )
    $findings = @()
    $actions = @()
    $upgrades = @()

    if ($AvgCpu -ne $null) {
        if ($AvgCpu -gt 85) { $findings += "High CPU under light load (~$([math]::Round($AvgCpu,1))%)."; $actions += "Close background apps; schedule antivirus scans off-hours." }
        else { $findings += "CPU headroom appears acceptable under light load." }
    }
    else { $findings += "CPU metric unavailable (perf counters not accessible)." }

    if ($MinMemMB -ne $null) {
        if ($MinMemMB -lt 800) {
            $findings += "Low available memory (min $([math]::Round($MinMemMB)) MB)."
            if ($RamTotalGB -lt 8) { $upgrades += "Increase RAM to at least 8 GB (cost-effective)." }
            $actions += "Close heavy apps/tabs; avoid running scans while working."
        }
        else { $findings += "Memory headroom acceptable." }
    }
    else { $findings += "Memory metric unavailable (perf counters not accessible)." }

    if ($AvgQlen -ne $null -and $AvgDiskSec -ne $null) {
        if ($AvgQlen -gt 2 -or $AvgDiskSec -gt 0.05) {
            $findings += "Disk is likely bottleneck (queue ~$([math]::Round($AvgQlen,2)), latency ~$([math]::Round($AvgDiskSec*1000,0)) ms)."
            $upgrades += "Move OS to a SATA SSD (largest impact on responsiveness)."
            $actions += "Free space on system drive; pause indexing during work sessions."
        }
        else { $findings += "Disk pressure/latency within reasonable range for light load." }
    }
    else { $findings += "Disk metrics unavailable (perf counters not accessible)." }

    if ($AvgDpc -ne $null -and $AvgDpc -gt 5) {
        $findings += "Kernel DPC time elevated (~$([math]::Round($AvgDpc,1))%)."
        $actions += "Check/update network/storage drivers; unplug USB devices to isolate; scan for driver latency with ETW/WPR." 
    }
    if ($AvgIsr -ne $null -and $AvgIsr -gt 3) {
        $findings += "Interrupt time elevated (~$([math]::Round($AvgIsr,1))%)."
        $actions += "Update chipset/network drivers; check for malfunctioning peripherals." 
    }

    # Disk SMART
    try {
        if ($script:diskHealthCached -eq $null) { $script:diskHealthCached = $diskHealth }
        $dh = $script:diskHealthCached
        if ($dh.SmartAvailable -and $dh.AnyPredictFailure) {
            $findings += "Disk SMART reports imminent failure on one or more drives."
            $actions += "Back up important data immediately. Replace the failing drive."
            $upgrades += "Replace failing disk (SSD recommended)."
        }
    }
    catch {}

    # Event log error bursts
    try {
        if ($script:eventSummaryCached -eq $null) { $script:eventSummaryCached = $eventSummary }
        $es = $script:eventSummaryCached
        $totalErrors = [int]$es.System.Error + [int]$es.Application.Error + [int]$es.System.Critical + [int]$es.Application.Critical
        if ($totalErrors -gt 0) {
            $findings += "System/Application logs show recent errors; review top providers in summary."
            $actions += "Address frequent error sources (drivers/services) noted in Event Logs section."
        }
    }
    catch {}

    # Free space heuristic from disks text if available
    if ($DisksText -match '\(([^\)]*) free of ([^\)]*) GB\)') {
        try {
            $free = [double]([regex]::Match($DisksText, '\(([^\)]*) free of').Groups[1].Value -replace '[^0-9\.]', '')
            $size = [double]([regex]::Match($DisksText, 'free of ([^\)]*) GB').Groups[1].Value -replace '[^0-9\.]', '')
            if ($size -gt 0) {
                $pct = [math]::Round(($free / $size) * 100, 1)
                if ($pct -lt 10) { $findings += "Low system drive free space (~$pct% free)."; $actions += "Clean temp files, uninstall unused apps, move large files to external drive." }
            }
        }
        catch {}
    }

    # OS-specific maint.
    if ($OsFlavor.Name -eq 'Windows 7') {
        $actions += "Allow Windows Update to finish when idle; consider disabling Superfetch if disk is thrashing."
    }
    else {
        $actions += "If responsiveness dips: temporarily disable SysMain and pause Windows Search indexing to test impact."
    }

    # Thermals
    try {
        if ($script:thermCached -eq $null) { $script:thermCached = $therm }
        $th = $script:thermCached
        if ($th.Zones) {
            $maxC = ($th.Zones | Measure-Object -Property TempC -Maximum).Maximum
            if ($maxC -ne $null -and $maxC -gt 80) {
                $findings += "High temperatures observed (~$([math]::Round($maxC))°C)."
                $actions += "Clean dust from fans/heatsinks; ensure unobstructed airflow; replace thermal paste if aged."
            }
        }
        if ($th.CpuPercentMaxFreq -ne $null -and $AvgCpu -gt 50 -and $th.CpuPercentMaxFreq -lt 90) {
            $findings += "CPU appears throttled under load (% of max ~${($th.CpuPercentMaxFreq)}%)."
            $actions += "Improve cooling/airflow; check power plan (set to Balanced or High performance)."
        }
    }
    catch {}

    # Prioritize upgrades by ROI
    $upgrades = $upgrades | Select-Object -Unique
    $actions = $actions | Select-Object -Unique
    return [pscustomobject]@{ Findings = $findings; Actions = $actions; Upgrades = $upgrades }
}

function Write-CustomerSummary {
    param(
        $SummaryPath, $Sys, $OsFlavor, [Nullable[Double]]$AvgCpu, [Nullable[Double]]$MinMemMB, [Nullable[Double]]$AvgQlen, [Nullable[Double]]$AvgDiskSec, [object]$Recs, [string]$Probe, [int]$ProbeSeconds, [Nullable[Double]]$AvgDpc, [Nullable[Double]]$MaxDpc, [Nullable[Double]]$AvgIsr, [Nullable[Double]]$MaxIsr, [object]$Reliability, [object]$NetTest, [object]$Therm, [object]$NetPerf
    )
    if (-not $SummaryPath) { return }
    $lines = @()
    $lines += "# Desktop Diagnostic Summary"
    $lines += ""
    $lines += ("- Computer: {0}" -f $Sys.ComputerName)
    $lines += ("- OS: {0} (v{1})" -f $Sys.OS, $OsFlavor.Version)
    $lines += ("- CPU: {0} | Cores/Threads: {1}/{2}" -f $Sys.CPU, $Sys.Cores, $Sys.Threads)
    $lines += ("- RAM: {0} GB" -f $Sys.RAM_GB)
    $lines += ("- Disks: {0}" -f $Sys.Disks)
    if ($Probe) { $lines += ("- Probe: {0} ({1}s window)" -f $Probe, $ProbeSeconds) }
    $lines += ""
    $lines += "**Key Metrics (light probe)**"
    $cpuMetric = if ($AvgCpu -ne $null) { "{0:N1}%" -f $AvgCpu } else { 'n/a' }
    $memMetric = if ($MinMemMB -ne $null) { "{0:N0} MB" -f $MinMemMB } else { 'n/a' }
    $qMetric = if ($AvgQlen -ne $null) { "{0:N2}" -f $AvgQlen } else { 'n/a' }
    $latMetric = if ($AvgDiskSec -ne $null) { "{0:N0} ms/transfer" -f ($AvgDiskSec * 1000) } else { 'n/a' }
    $lines += ("- CPU average: {0}" -f $cpuMetric)
    $lines += ("- Minimum available memory: {0}" -f $memMetric)
    $lines += ("- Disk queue (avg): {0}" -f $qMetric)
    $lines += ("- Disk latency (avg): {0}" -f $latMetric)
    $dpcMetric = if ($AvgDpc -ne $null) { "{0:N2}% (max {1:N2}%)" -f $AvgDpc, $MaxDpc } else { 'n/a' }
    $isrMetric = if ($AvgIsr -ne $null) { "{0:N2}% (max {1:N2}%)" -f $AvgIsr, $MaxIsr } else { 'n/a' }
    $lines += ("- Kernel DPC time: {0}" -f $dpcMetric)
    $lines += ("- Kernel ISR time: {0}" -f $isrMetric)
    $lines += ""
    $lines += "**Findings**"
    foreach ($f in $Recs.Findings) { $lines += ("- {0}" -f $f) }
    $lines += ""
    $lines += "**Do These First (No/Low Cost)**"
    foreach ($a in $Recs.Actions) { $lines += ("- {0}" -f $a) }
    $lines += ""
    $lines += "**High-ROI Upgrades**"
    if ($Recs.Upgrades.Count -gt 0) { foreach ($u in $Recs.Upgrades) { $lines += ("- {0}" -f $u) } }
    else { $lines += "- None suggested from this run." }
    $lines += ""
    # Disk health details
    try {
        $dh = $script:diskHealthCached
        if ($dh) {
            $lines += "**Disk Health**"
            if ($dh.SmartAvailable) {
                $status = if ($dh.AnyPredictFailure) { "FAILURE PREDICTED ($($dh.PredictFailureCount) drive(s))" } else { "OK (no imminent failure reported)" }
                $lines += ("- SMART status: {0}" -f $status)
            }
            else {
                $lines += "- SMART status: Not available"
            }
            foreach ($n in $dh.Notes) { $lines += ("- {0}" -f $n) }
            $lines += ""
        }
    }
    catch {}

    # Event summaries
    try {
        $es = $script:eventSummaryCached
        if ($es) {
            $lines += "**Event Logs (last 7 days)**"
            foreach ($ln in 'System', 'Application') {
                $x = $es.$ln
                $lines += ("- {0}: Critical={1} Error={2}" -f $ln, $x.Critical, $x.Error)
                foreach ($p in $x.TopProviders) {
                    $lines += ("  - {0}: {1} events" -f $p.Provider, $p.Count)
                    if ($p.Sample) { $lines += ("    e.g., {0}" -f $p.Sample) }
                }
            }
            $lines += ""
        }
    }
    catch {}

    try {
        if ($Reliability) {
            $lines += "**Reliability (last 7 days)**"
            if ($Reliability.StabilityIndex -ne $null) { $lines += ("- Stability Index: {0}" -f $Reliability.StabilityIndex) }
            $lines += ("- Recent failures: {0}" -f $Reliability.RecentFailures)
            foreach ($i in $Reliability.TopIssues) {
                $lines += ("  - {0}: {1} events" -f $i.Source, $i.Count)
                if ($i.Sample) { $lines += ("    e.g., {0}" -f $i.Sample) }
            }
            $lines += ""
        }
    }
    catch {}
    # Startup/tasks snapshot
    try {
        $lines += ""
        $lines += "**Startup & Tasks**"
        $lines += ("- Startup items: {0}" -f (($startup | Measure-Object).Count))
        if ($tasks) {
            $lines += ("- Scheduled tasks: total={0}, running={1}, failed(last)={2}" -f $tasks.Total, $tasks.Running, $tasks.Failed)
            if ($tasks.TopFailures) {
                foreach ($t in $tasks.TopFailures) { $lines += ("  - {0} (LastRun={1}, Result={2})" -f $t.TaskName, $t.LastRunTime, $t.LastResult) }
            }
        }
    }
    catch {}

    # Process activity snapshot
    try {
        if ($procSample) {
            $lines += ""
            $lines += "**Top Offenders (short window)**"
            if ($procSample.TopCPU -and ($procSample.TopCPU | Where-Object { $_ -and $_.Name }).Count -gt 0) {
                $lines += "- Top CPU:"; foreach ($c in ($procSample.TopCPU | Where-Object { $_ -and $_.Name })) { $lines += ("  - {0}: {1}%" -f $c.Name, $c.AvgCPU) }
            }
            else { $lines += "- Top CPU: None observed" }
            if ($procSample.TopIO -and ($procSample.TopIO | Where-Object { $_ -and $_.Name }).Count -gt 0) {
                $lines += "- Top I/O:"; foreach ($io in ($procSample.TopIO | Where-Object { $_ -and $_.Name })) { $lines += ("  - {0}: {1} B/s" -f $io.Name, $io.AvgBps) }
                $lines += "  (Note: I/O data may be from perf counters if per-process tracking is unavailable)"
            }
            else { $lines += "- Top I/O: None observed (process I/O tracking limited on this system)" }
        }
    }
    catch {}

    try {
        if ($NetTest) {
            $lines += ""
            $lines += "**Network self-test**"
            foreach ($t in $NetTest) {
                $lossTxt = if ($t.LossPct -ne $null) { "$($t.LossPct)% loss" } else { 'loss n/a' }
                $latTxt = if ($t.AvgMs -ne $null) { "avg $($t.AvgMs) ms (min $($t.MinMs) / max $($t.MaxMs))" } else { 'latency n/a' }
                $tcpTxt = if ($t.Tcp443 -eq $true) { ', TCP 443 reachable' } elseif ($t.Tcp443 -eq $false) { ', TCP 443 blocked' } else { '' }
                $lines += ("- {0}: {1}, {2}{3}" -f $t.Target, $latTxt, $lossTxt, $tcpTxt)
            }
        }
    }
    catch {}

    # Drive health detail
    try {
        if ($diskHealth) {
            $lines += ""
            $lines += "**Storage Details**"
            if ($diskHealth.NVMEDrives -and $diskHealth.NVMEDrives.Count -gt 0) {
                $lines += "- NVMe Drives:"
                foreach ($d in $diskHealth.NVMEDrives) {
                    $w = if ($d.Wear_Percent -ne $null) { " | Wear {0}%" -f $d.Wear_Percent } else { '' }
                    $hr = if ($d.PowerOnHours -ne $null) { " | Hours {0:N0}" -f $d.PowerOnHours } else { '' }
                    $dt = if ($d.DataWritten_GB -ne $null) { " | Data {0:N0} GB" -f $d.DataWritten_GB } else { '' }
                    $lines += ("  - {0} ({1} GB) [{2}]{3}{4}{5}" -f $d.Model, $d.Size_GB, $d.Health, $w, $hr, $dt)
                }
            }
            if ($diskHealth.DriveInfo -and $diskHealth.DriveInfo.Count -gt 0) {
                $lines += "- SATA/SAS Drives:"
                foreach ($d in $diskHealth.DriveInfo) { $lines += ("  - {0} ({1} GB) [{2}]" -f $d.Model, $d.Size_GB, $d.Health) }
            }
            # Add SMART attributes if available
            if ($diskHealth.KeyAttributes -and $diskHealth.KeyAttributes.Count -gt 0) {
                $lines += "- Key SMART Attributes:"
                foreach ($a in ($diskHealth.KeyAttributes | Select-Object -First 12)) {
                    $thrTxt = if ($a.Threshold -ne $null) { " / Threshold $($a.Threshold)" } else { '' }
                    $rawTxt = if ($a.Raw -ne $null) { " / Raw $($a.Raw)" } else { '' }
                    $lines += ("  - {0} (ID {1}): Current {2} / Worst {3}{4}{5}" -f $a.Name, $a.Id, $a.Current, $a.Worst, $thrTxt, $rawTxt)
                }
            }
        }
    }
    catch {}


    # Network throughput/jitter
    try {
        if ($NetPerf) {
            $lines += ""
            $lines += "**Network throughput/jitter**"
            if ($NetPerf.Tcp -and $NetPerf.Tcp.Count -gt 0) {
                $lines += "- TCP 443 connect jitter:"
                foreach ($t in $NetPerf.Tcp) { $lines += ("  - {0}: avg {1} ms (min {2} / max {3}), jitter std {4} ms, success {5}/{6}" -f $t.Target, $t.AvgMs, $t.MinMs, $t.MaxMs, $t.JitterStdMs, $t.Successes, $t.Attempts) }
            }
            if ($NetPerf.Http -and $NetPerf.Http.Count -gt 0) {
                $lines += "- HTTP download throughput:"
                foreach ($h in $NetPerf.Http) { $status = if ($h.Success) { 'OK' } else { 'Fail' }; $lines += ("  - {0} MB in {1} ms → {2} Mbps ({3} KB/s) [{4}] ({5})" -f ([math]::Round($h.Bytes / 1MB, 2)), $h.DurationMs, $h.Mbps, $h.KBps, $status, $h.Url) }
            }
        }
    }
    catch {}

    # Thermals
    try {
        if ($therm) {
            $lines += ""
            $lines += "**Thermals & Throttling**"
            if ($therm.Zones -and $therm.Zones.Count -gt 0) { foreach ($z in $therm.Zones) { $lines += ("- {0}: {1}°C" -f $z.Name, $z.TempC) } } else { $lines += "- No thermal zones detected" }
            if ($therm.CpuPercentMaxFreq -ne $null) { $lines += ("- CPU % of max frequency: {0}%" -f $therm.CpuPercentMaxFreq) } else { $lines += "- CPU throttle counter unavailable" }
            if ($therm.GpuUtilMax -ne $null) { $lines += ("- GPU utilization peak: {0}%" -f $therm.GpuUtilMax) }
        }
    }
    catch {}

    $lines += "> Rough guidance: SSD often yields 3–10x responsiveness on HDD systems; RAM to 8 GB reduces paging."
    try {
        $dir = Split-Path -Parent $SummaryPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $SummaryPath -Value ($lines -join "`r`n") -Encoding UTF8
        Write-Host ("Summary saved to: {0}" -f $SummaryPath) -ForegroundColor Cyan
    }
    catch {
        Write-Host "Failed to write summary file." -ForegroundColor Yellow
    }
}

$osf = Get-OSFlavor
$recs = Get-Recommendations -AvgCpu $avgCpu -MinMemMB $minMemMB -AvgQlen $avgQlen -AvgDiskSec $avgDisk -RamTotalGB ($sys.RAM_GB | % { [double]$_ }) -OsFlavor $osf -DisksText $sys.Disks -AvgDpc $avgDpc -AvgIsr $avgIsr
Write-CustomerSummary -SummaryPath $SummaryPath -Sys $sys -OsFlavor $osf -AvgCpu $avgCpu -MinMemMB $minMemMB -AvgQlen $avgQlen -AvgDiskSec $avgDisk -Recs $recs -Probe $probeType -ProbeSeconds $sampleSeconds -AvgDpc $avgDpc -MaxDpc $maxDpc -AvgIsr $avgIsr -MaxIsr $maxIsr -Reliability $reliability -NetTest $netSelfTest -Therm $therm -NetPerf $netPerf

# Optional: HTML report with scoring
function Get-HealthScore {
    param([double]$AvgCpu, [double]$MinMemMB, [double]$AvgQ, [double]$AvgLatency, [double]$AvgDpc, [double]$AvgIsr, [object]$DiskHealth, [object]$EventSum, [object]$Therm, [object]$Reliability)
    $score = 100
    if ($AvgCpu -gt 85) { $score -= 10 }
    if ($MinMemMB -lt 800) { $score -= 15 }
    if ($MinMemMB -lt 400) { $score -= 10 }
    if ($AvgQ -gt 2) { $score -= 15 }
    if ($AvgQ -gt 4) { $score -= 10 }
    if ($AvgLatency -gt 0.05) { $score -= 10 }
    if ($AvgLatency -gt 0.1) { $score -= 10 }
    if ($AvgDpc -gt 5) { $score -= 10 }
    if ($AvgIsr -gt 3) { $score -= 5 }
    try { if ($DiskHealth -and $DiskHealth.SmartAvailable -and $DiskHealth.AnyPredictFailure) { $score -= 50 } } catch {}
    try {
        if ($EventSum) {
            $errs = [int]$EventSum.System.Error + [int]$EventSum.Application.Error + [int]$EventSum.System.Critical + [int]$EventSum.Application.Critical
            if ($errs -gt 0) { $score -= [math]::Min(20, [math]::Ceiling([math]::Log10([double]$errs + 1) * 10)) }
        }
    }
    catch {}
    try {
        if ($Reliability -and $Reliability.RecentFailures -gt 0) { $score -= [math]::Min(10, $Reliability.RecentFailures) }
    }
    catch {}
    try {
        if ($Therm -and $Therm.Zones -and $Therm.Zones.Count -gt 0) {
            $maxC = ($Therm.Zones | Measure-Object -Property TempC -Maximum).Maximum
            if ($maxC -gt 80) { $score -= 15 }
            if ($maxC -gt 90) { $score -= 15 }
        }
        if ($Therm -and $Therm.CpuPercentMaxFreq -ne $null -and $Therm.CpuPercentMaxFreq -lt 90 -and $AvgCpu -gt 50) { $score -= 10 }
    }
    catch {}
    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }
    return [int][math]::Round($score)
}

function Write-HtmlReport {
    param(
        $Path, $Sys, $Score, $SummaryPath, $Probe, $ProbeSeconds,
        [double]$AvgCpu, [double]$MinMemMB, [double]$AvgQlen, [double]$AvgDiskSec, [double]$AvgDpc, [double]$MaxDpc, [double]$AvgIsr, [double]$MaxIsr,
        $Recs, $ProcSample, $DiskHealth, $EventSummary, $Therm, [int]$StartupCount, $Tasks, $Reliability, $NetTest, $NetPerf
    )
    if (-not $Path) { return }
    $color = if ($Score -ge 80) { '#2e7d32' } elseif ($Score -ge 60) { '#f9a825' } else { '#c62828' }
    # Risk classes for key metrics (treat unavailable as 'warn')
    $cpuCls = if ($AvgCpu -eq $null) { 'warn' } elseif ($AvgCpu -gt 85) { 'bad' } elseif ($AvgCpu -gt 60) { 'warn' } else { 'ok' }
    $memCls = if ($MinMemMB -eq $null) { 'warn' } elseif ($MinMemMB -lt 400) { 'bad' } elseif ($MinMemMB -lt 800) { 'warn' } else { 'ok' }
    $qCls = if ($AvgQlen -eq $null) { 'warn' } elseif ($AvgQlen -gt 4) { 'bad' } elseif ($AvgQlen -gt 2) { 'warn' } else { 'ok' }
    $latMs = if ($AvgDiskSec -ne $null) { [double]($AvgDiskSec * 1000) } else { $null }
    $latCls = if ($latMs -eq $null) { 'warn' } elseif ($latMs -gt 100) { 'bad' } elseif ($latMs -gt 50) { 'warn' } else { 'ok' }
    $cpuDisp = if ($AvgCpu -ne $null) { ('{0:N1}%' -f $AvgCpu) } else { 'n/a' }
    $memDisp = if ($MinMemMB -ne $null) { ('{0:N0} MB' -f $MinMemMB) } else { 'n/a' }
    $qDisp = if ($AvgQlen -ne $null) { ('{0:N2}' -f $AvgQlen) } else { 'n/a' }
    $latDisp = if ($latMs -ne $null) { ('{0:N0} ms' -f $latMs) } else { 'n/a' }
    $html = @()
    $html += '<!doctype html><html><head><meta charset="utf-8"><title>Desktop Diagnostic Report</title>'
    $html += '<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#222} .score{font-size:48px;font-weight:700} .card{border:1px solid #eee;border-radius:8px;padding:16px;margin:12px 0} h2{margin:8px 0} h3{margin:6px 0} code{background:#f5f5f5;padding:2px 6px;border-radius:4px} ul{margin:6px 0 0 18px} .metric{display:inline-block;margin-right:16px} .ok{color:#2e7d32}.warn{color:#f9a825}.bad{color:#c62828} table{border-collapse:collapse} td,th{border:1px solid #eee;padding:6px 8px}</style>'
    $html += '</head><body>'
    $html += ('<h1>Desktop Diagnostic Report</h1>')
    $html += ('<div class="card"><div class="score" style="color:{0}">{1}</div><div>Health Score</div></div>' -f $color, $Score)
    $html += ('<div class="card"><h2>System</h2><div>Computer: {0}</div><div>OS: {1}</div><div>CPU: {2} | Cores/Threads: {3}/{4}</div><div>RAM: {5} GB</div><div>Disks: {6}</div><div>Probe: {7} ({8}s)</div></div>' -f [System.Web.HttpUtility]::HtmlEncode($Sys.ComputerName), [System.Web.HttpUtility]::HtmlEncode($Sys.OS), [System.Web.HttpUtility]::HtmlEncode($Sys.CPU), $Sys.Cores, $Sys.Threads, $Sys.RAM_GB, [System.Web.HttpUtility]::HtmlEncode($Sys.Disks), [System.Web.HttpUtility]::HtmlEncode($Probe), $ProbeSeconds)

    $html += ('<div class="card"><h2>Key Metrics</h2><div class="metric">CPU avg: <b class="{0}">{1}</b></div><div class="metric">Min avail mem: <b class="{2}">{3}</b></div><div class="metric">Disk queue avg: <b class="{4}">{5}</b></div><div class="metric">Disk latency avg: <b class="{6}">{7}</b></div></div>' -f $cpuCls, $cpuDisp, $memCls, $memDisp, $qCls, $qDisp, $latCls, $latDisp)

    $dpcDisp = if ($AvgDpc -ne $null) { ('{0:N2}% (max {1:N2}%)' -f $AvgDpc, $MaxDpc) } else { 'n/a' }
    $isrDisp = if ($AvgIsr -ne $null) { ('{0:N2}% (max {1:N2}%)' -f $AvgIsr, $MaxIsr) } else { 'n/a' }
    $html += ('<div class="card"><h2>Kernel latency (DPC/ISR)</h2><div>DPC time: <b>{0}</b></div><div>ISR time: <b>{1}</b></div></div>' -f $dpcDisp, $isrDisp)

    $html += '<div class="card"><h2>Findings & Actions</h2>'
    if ($Recs -and $Recs.Findings) {
        $html += '<h3>Findings</h3><ul>'
        foreach ($f in $Recs.Findings) { $html += ('<li>{0}</li>' -f [System.Web.HttpUtility]::HtmlEncode($f)) }
        $html += '</ul>'
    }
    if ($Recs -and $Recs.Actions) {
        $html += '<h3>Do These First (No/Low Cost)</h3><ul>'
        foreach ($a in $Recs.Actions) { $html += ('<li>{0}</li>' -f [System.Web.HttpUtility]::HtmlEncode($a)) }
        $html += '</ul>'
    }
    if ($Recs -and $Recs.Upgrades) {
        $html += '<h3>High-ROI Upgrades</h3><ul>'
        if ($Recs.Upgrades.Count -gt 0) { foreach ($u in $Recs.Upgrades) { $html += ('<li>{0}</li>' -f [System.Web.HttpUtility]::HtmlEncode($u)) } } else { $html += '<li>None suggested from this run.</li>' }
        $html += '</ul>'
    }
    $html += '</div>'

    $html += '<div class="card"><h2>Top Offenders (short window)</h2>'
    if ($ProcSample -and $ProcSample.TopCPU) {
        $html += '<h3>Top CPU</h3><table><tr><th>Process</th><th>PID</th><th>Avg CPU %</th></tr>'
        foreach ($c in $ProcSample.TopCPU) { $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($c.Name), $c.PID, $c.AvgCPU) }
        $html += '</table>'
    }
    if ($ProcSample -and $ProcSample.TopIO) {
        $html += '<h3>Top I/O</h3><table><tr><th>Process</th><th>Bytes/sec</th></tr>'
        foreach ($io in $ProcSample.TopIO) { $html += ('<tr><td>{0}</td><td>{1}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($io.Name), $io.AvgBps) }
        $html += '</table><div style="font-size:12px;color:#666;margin-top:8px">Note: I/O data may be from perf counters if per-process tracking is unavailable</div>'
    }
    else {
        $html += '<div style="font-size:12px;color:#999">Top I/O: Process I/O tracking limited on this system</div>'
    }
    $html += '</div>'

    $html += '<div class="card"><h2>Disk Health</h2>'
    if ($DiskHealth) {
        if ($DiskHealth.SmartAvailable) {
            $status = if ($DiskHealth.AnyPredictFailure) { "FAILURE PREDICTED ($($DiskHealth.PredictFailureCount) drive(s))" } else { 'OK (no imminent failure reported)' }
            $sCls = if ($DiskHealth.AnyPredictFailure) { 'bad' } else { 'ok' }
            $html += ('<div>SMART status: <b class="{0}">{1}</b></div>' -f $sCls, [System.Web.HttpUtility]::HtmlEncode($status))
        }
        else { $html += '<div>SMART status: <b>Not available</b></div>' }
        if ($DiskHealth.Notes) { foreach ($n in $DiskHealth.Notes) { $html += ('<div>{0}</div>' -f [System.Web.HttpUtility]::HtmlEncode($n)) } }
        # NVMe drives table
        if ($DiskHealth.NVMEDrives -and $DiskHealth.NVMEDrives.Count -gt 0) {
            $html += '<h3>NVMe Drives</h3><table><tr><th>Model</th><th>Size GB</th><th>Health</th><th>Wear %</th><th>Hours</th><th>Data Written GB</th></tr>'
            foreach ($d in $DiskHealth.NVMEDrives) { $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($d.Model), $d.Size_GB, [System.Web.HttpUtility]::HtmlEncode($d.Health), $d.Wear_Percent, $d.PowerOnHours, $d.DataWritten_GB) }
            $html += '</table>'
        }
        # SATA/SAS drives table
        if ($DiskHealth.DriveInfo -and $DiskHealth.DriveInfo.Count -gt 0) {
            $html += '<h3>SATA/SAS Drives</h3><table><tr><th>Model</th><th>Size GB</th><th>Health</th></tr>'
            foreach ($d in $DiskHealth.DriveInfo) { $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($d.Model), $d.Size_GB, [System.Web.HttpUtility]::HtmlEncode($d.Health)) }
            $html += '</table>'
        }
        # Key SMART attributes table
        if ($DiskHealth.KeyAttributes -and $DiskHealth.KeyAttributes.Count -gt 0) {
            $html += '<h3>Key SMART Attributes</h3><table><tr><th>Attribute</th><th>ID</th><th>Current</th><th>Worst</th><th>Threshold</th><th>Raw Value</th></tr>'
            foreach ($a in ($DiskHealth.KeyAttributes | Select-Object -First 12)) {
                $thrTxt = if ($a.Threshold -ne $null) { $a.Threshold } else { 'n/a' }
                $rawTxt = if ($a.Raw -ne $null) { $a.Raw } else { 'n/a' }
                $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($a.Name), $a.Id, $a.Current, $a.Worst, $thrTxt, $rawTxt)
            }
            $html += '</table>'
        }
    }
    else { $html += '<div>Unavailable</div>' }
    $html += '</div>'

    $html += '<div class="card"><h2>Event Logs (last 7 days)</h2>'
    if ($EventSummary) {
        foreach ($ln in 'System', 'Application') {
            $x = $EventSummary.$ln
            if ($x) {
                $errTotal = ([int]$x.Critical + [int]$x.Error)
                $eCls = if ($errTotal -gt 0) { 'warn' } else { 'ok' }
                $html += ('<div><b>{0}</b>: <span class="{1}">Critical={2} Error={3}</span></div>' -f $ln, $eCls, $x.Critical, $x.Error)
                if ($x.TopProviders) {
                    $html += '<table><tr><th>Provider</th><th>Count</th><th>Sample</th></tr>'
                    foreach ($p in $x.TopProviders) { $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($p.Provider), $p.Count, [System.Web.HttpUtility]::HtmlEncode($p.Sample)) }
                    $html += '</table>'
                }
            }
        }
    }
    else { $html += '<div>Unavailable</div>' }
    $html += '</div>'

    $html += '<div class="card"><h2>Reliability</h2>'
    if ($Reliability) {
        if ($Reliability.StabilityIndex -ne $null) { $html += ('<div>Stability Index: <b>{0}</b></div>' -f $Reliability.StabilityIndex) }
        $html += ('<div>Recent failures (7d): {0}</div>' -f $Reliability.RecentFailures)
        if ($Reliability.TopIssues) {
            $html += '<table><tr><th>Source</th><th>Count</th><th>Sample</th></tr>'
            foreach ($i in $Reliability.TopIssues) { $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($i.Source), $i.Count, [System.Web.HttpUtility]::HtmlEncode($i.Sample)) }
            $html += '</table>'
        }
    }
    else { $html += '<div>Unavailable</div>' }
    $html += '</div>'

    $html += '<div class="card"><h2>Startup & Tasks</h2>'
    $html += ('<div>Startup items: {0}</div>' -f $StartupCount)
    if ($Tasks) {
        $html += ('<div>Scheduled tasks: total={0}, running={1}, failed(last)={2}</div>' -f $Tasks.Total, $Tasks.Running, $Tasks.Failed)
        if ($Tasks.TopFailures) {
            $html += '<table><tr><th>Task</th><th>Last Run</th><th>Result</th></tr>'
            foreach ($t in $Tasks.TopFailures) { $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($t.TaskName), [System.Web.HttpUtility]::HtmlEncode($t.LastRunTime), [System.Web.HttpUtility]::HtmlEncode($t.LastResult)) }
            $html += '</table>'
        }
    }
    $html += '</div>'

    $html += '<div class="card"><h2>Network self-test</h2>'
    if ($NetTest) {
        $html += '<table><tr><th>Target</th><th>Avg ms</th><th>Min</th><th>Max</th><th>Loss %</th><th>TCP 443</th></tr>'
        foreach ($t in $NetTest) { $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($t.Target), $t.AvgMs, $t.MinMs, $t.MaxMs, $t.LossPct, $(if ($t.Tcp443 -eq $true) { 'reachable' } elseif ($t.Tcp443 -eq $false) { 'blocked' } else { '' })) }
        $html += '</table>'
    }
    else { $html += '<div>Unavailable</div>' }
    $html += '</div>'

    # Network throughput/jitter card
    $html += '<div class="card"><h2>Network throughput/jitter</h2>'
    if ($NetPerf) {
        if ($NetPerf.Tcp) {
            $html += '<h3>TCP 443 connect jitter</h3><table><tr><th>Target</th><th>Avg ms</th><th>Min</th><th>Max</th><th>Jitter std ms</th><th>Success</th></tr>'
            foreach ($t in $NetPerf.Tcp) { $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}/{6}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($t.Target), $t.AvgMs, $t.MinMs, $t.MaxMs, $t.JitterStdMs, $t.Successes, $t.Attempts) }
            $html += '</table>'
        }
        if ($NetPerf.Http) {
            $html += '<h3>HTTP download throughput</h3><table><tr><th>URL</th><th>MB</th><th>ms</th><th>Mbps</th><th>KB/s</th><th>Status</th></tr>'
            foreach ($h in $NetPerf.Http) { $status = if ($h.Success) { 'OK' } else { 'Fail' }; $html += ('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($h.Url), ([math]::Round([double]$h.Bytes / 1MB, 2)), $h.DurationMs, $h.Mbps, $h.KBps, $status) }
            $html += '</table>'
        }
    }
    else { $html += '<div>Unavailable</div>' }
    $html += '</div>'

    $html += '<div class="card"><h2>Thermals & Throttling</h2>'
    if ($Therm) {
        if ($Therm.Zones -and $Therm.Zones.Count -gt 0) { foreach ($z in $Therm.Zones) { $html += ('<div>{0}: <b>{1}°C</b></div>' -f [System.Web.HttpUtility]::HtmlEncode($z.Name), $z.TempC) } } else { $html += '<div>No thermal zones detected</div>' }
        if ($Therm.CpuPercentMaxFreq -ne $null) { $html += ('<div>CPU % of max frequency: <b>{0}%</b></div>' -f $Therm.CpuPercentMaxFreq) } else { $html += '<div>CPU throttle counter unavailable</div>' }
        if ($Therm.GpuUtilMax -ne $null) { $html += ('<div>GPU utilization peak: <b>{0}%</b></div>' -f $Therm.GpuUtilMax) }
    }
    else { $html += '<div>Unavailable</div>' }
    $html += '</div>'

    $html += ('<div class="card"><h2>Summary File</h2><div>Markdown summary: <code>{0}</code></div></div>' -f [System.Web.HttpUtility]::HtmlEncode($SummaryPath))
    $html += '</body></html>'
    try { Set-Content -Path $Path -Value ($html -join "") -Encoding UTF8 } catch {}
}

if ($Html) {
    try {
        $score = Get-HealthScore -AvgCpu ($avgCpu | % { [double]$_ }) -MinMemMB ($minMemMB | % { [double]$_ }) -AvgQ ($avgQlen | % { [double]$_ }) -AvgLatency ($avgDisk | % { [double]$_ }) -AvgDpc ($avgDpc | % { [double]$_ }) -AvgIsr ($avgIsr | % { [double]$_ }) -DiskHealth $diskHealth -EventSum $eventSummary -Therm $therm -Reliability $reliability
        $base = [System.IO.Path]::GetFileNameWithoutExtension($SummaryPath)
        $htmlOut = Join-Path (Split-Path -Parent $SummaryPath) ($base + '.html')
        Write-HtmlReport -Path $htmlOut -Sys $sys -Score $score -SummaryPath $SummaryPath -Probe $probeType -ProbeSeconds $sampleSeconds -AvgCpu ($avgCpu | % { [double]$_ }) -MinMemMB ($minMemMB | % { [double]$_ }) -AvgQlen ($avgQlen | % { [double]$_ }) -AvgDiskSec ($avgDisk | % { [double]$_ }) -AvgDpc ($avgDpc | % { [double]$_ }) -MaxDpc ($maxDpc | % { [double]$_ }) -AvgIsr ($avgIsr | % { [double]$_ }) -MaxIsr ($maxIsr | % { [double]$_ }) -Recs $recs -ProcSample $procSample -DiskHealth $diskHealth -EventSummary $eventSummary -Therm $therm -StartupCount (($startup | Measure-Object).Count) -Tasks $tasks -Reliability $reliability -NetTest $netSelfTest -NetPerf $netPerf
        Write-Host ("HTML report: {0}" -f $htmlOut) -ForegroundColor Cyan
        try { Start-Process $htmlOut } catch {}
    }
    catch {
        Write-Host "Failed to write HTML report" -ForegroundColor Yellow
    }
}

Write-Host ""; Write-Host "Log saved to: $LogPath" -ForegroundColor Cyan
if ($SummaryPath) { Write-Host "Summary: $SummaryPath" -ForegroundColor Cyan }
Stop-Transcript
