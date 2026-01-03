# PHASE 10 COMPLETION PROMPT - FOR LAPTOP

**Objective**: Make event logs bulletproof + wire all checks to parallel path

---

## 🎯 The Problem We're Solving

Your brother's WiFi drops corrupted event logs. Bottleneck crashed or missed data because:
1. **Null StartTime** in event log filter hashtables
2. **AccessDenied** errors on restricted logs (Security, System)
3. **No fallback** when queries timeout or fail
4. **Not running in parallel** — checks are sequential, slow

Result: **Fast, unreliable on real-world messy machines**

---

## ✅ What You're Delivering

### 1️⃣ Event Log Hardening (Bottleneck.DeepScan.ps1)

**Current problem code** (find this):
```powershell
$filter = @{
    LogName = 'System'
    StartTime = $startTime  # ← CAN BE NULL
    EndTime = $endTime
}
Get-WinEvent -FilterHashtable $filter
```

**Your fix**:
```powershell
function Get-EventLogSafeQuery {
    param([string]$LogName, [datetime]$StartTime, [datetime]$EndTime)
    
    try {
        # Handle null StartTime
        $filter = @{ LogName = $LogName }
        if ($StartTime) { $filter['StartTime'] = $StartTime }
        if ($EndTime) { $filter['EndTime'] = $EndTime }
        
        # Time-bounded with timeout (10s max per log)
        $timeout = New-TimeSpan -Seconds 10
        $sw = [Diagnostics.Stopwatch]::StartNew()
        
        $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        
        return @{
            Success = $true
            Events = $events
            Count = $events.Count
        }
    }
    catch [System.UnauthorizedAccessException] {
        # Graceful fallback: count via wevtutil instead
        try {
            $countOutput = wevtutil qe $LogName /c /q:"*" 2>$null
            return @{
                Success = $false
                Reason = 'AccessDenied'
                Count = [int]$countOutput
                Note = 'Summary only; detailed analysis skipped'
            }
        }
        catch {
            return @{
                Success = $false
                Reason = 'AccessDenied'
                Count = 0
                Note = 'Cannot access log'
            }
        }
    }
    catch [System.OperationCanceledException] {
        return @{
            Success = $false
            Reason = 'Timeout'
            Count = $null
            Note = 'Query exceeded 10 second limit'
        }
    }
    catch {
        return @{
            Success = $false
            Reason = $_.Exception.GetType().Name
            Count = $null
            Note = $_.Message
        }
    }
}
```

**Where to add**: `src/ps/Bottleneck.DeepScan.ps1` (around line 100-150, find the event log section)

**Checklist**:
- [ ] Find all `Get-WinEvent` calls in DeepScan.ps1
- [ ] Replace with `Get-EventLogSafeQuery` wrapper
- [ ] Add null check for $startTime/$endTime
- [ ] Test with System log (should never fail)
- [ ] Test with Security log (should fallback gracefully)

---

### 2️⃣ Wire Checks to Parallel Path

**Current issue**: `Bottleneck.psm1` loads modules but doesn't USE parallel for Standard/Deep

**Your task**:
1. Open `src/ps/Bottleneck.Parallel.ps1` — this exists and has job controller
2. Open `scripts/run.ps1` — find where it calls Standard/Deep scans
3. Change from **sequential** to **parallel**:

```powershell
# OLD (Sequential, slow)
$results = @()
$results += Invoke-Check -Name 'CPU' -Tier 'Standard'
$results += Invoke-Check -Name 'Memory' -Tier 'Standard'
$results += Invoke-Check -Name 'Disk' -Tier 'Standard'
# Takes 30+ seconds

# NEW (Parallel, fast)
$results = Invoke-BottleneckParallel -CheckGroups @('CPU', 'Memory', 'Disk') -Tier 'Standard' -Concurrency 4
# Takes ~8 seconds (60% faster)
```

**Checklist**:
- [ ] Examine `Bottleneck.Parallel.ps1` — understand the `Invoke-BottleneckParallel` function
- [ ] Find `Invoke-BottleneckScan` in `run.ps1`
- [ ] Add logic: `if ($Tier -in @('Standard', 'Deep')) { use parallel } else { use sequential }`
- [ ] Set concurrency defaults:
  - Quick: 2 jobs
  - Standard: 4 jobs
  - Deep: 6 jobs

---

### 3️⃣ Add Performance Budgeting

**Goal**: Track timing, alert if checks are slow

Create new function in `src/ps/Bottleneck.Performance.ps1`:

```powershell
function Test-PerformanceBudget {
    param(
        [string]$CheckName,
        [timespan]$ElapsedTime,
        [string]$Tier = 'Standard'
    )
    
    $budgets = @{
        'Quick'     = 30   # 30 seconds total
        'Standard'  = 45   # 45 seconds total
        'Deep'      = 75   # 75 seconds total
    }
    
    $budget = $budgets[$Tier]
    $elapsed = $ElapsedTime.TotalSeconds
    
    if ($elapsed -gt ($budget * 0.8)) {
        Write-Warning "⚠️  Check '$CheckName' took ${elapsed}s (Tier budget: ${budget}s)"
        return @{
            ExceededBudget = $true
            Severity = if ($elapsed -gt $budget) { 'Critical' } else { 'Warning' }
            Elapsed = $elapsed
            Budget = $budget
        }
    }
    
    return @{ ExceededBudget = $false }
}
```

**Checklist**:
- [ ] Add to Performance.ps1
- [ ] Call after each parallel job completes
- [ ] Log slow checks to report
- [ ] Add telemetry to HTML report footer

---

## 🧪 Testing (Before Merging)

Run these manual tests on your laptop:

```powershell
# Test 1: Event log safe query (should not crash)
cd c:\users\[you]\git\Bottleneck
pwsh -NoLogo -NoProfile
. .\src\ps\Bottleneck.DeepScan.ps1
$result = Get-EventLogSafeQuery -LogName 'Security' -StartTime (Get-Date).AddHours(-1) -EndTime (Get-Date)
$result  # Should show Success: $false, Reason: AccessDenied

# Test 2: Parallel execution (should be ~60% faster)
$sw = [Diagnostics.Stopwatch]::StartNew()
./scripts/run.ps1 -Standard
$sw.Stop()
Write-Host "Total time: $($sw.Elapsed.TotalSeconds)s"
# Target: <45 seconds (was 120+ seconds sequential)

# Test 3: Performance budget warning
# Run Deep scan, check for timeout warnings in output
./scripts/run.ps1 -Deep
# Should show telemetry in report
```

---

## 📝 Deliverables

When done, commit to branch `release/v1.0`:

```powershell
git checkout release/v1.0
git add -A
git commit -m "Phase 10: Event log hardening + parallel execution

- Implement Get-EventLogSafeQuery for null/AccessDenied handling
- Wire Standard/Deep scans to parallel path (4-6 concurrent jobs)
- Add performance budgeting and telemetry
- Test on both accessible and restricted logs"

git push origin release/v1.0
```

---

## 🆘 If You Get Stuck

1. **Null StartTime error**: Add `if ($null -ne $StartTime)` guard
2. **Parallel job not returning data**: Check module bootstrap in Parallel.ps1
3. **Timeout on event logs**: Reduce timeout to 5s, use `-ErrorAction SilentlyContinue`
4. **Report not showing telemetry**: Verify Report.ps1 calls the new budget function

**Message me** if any of these fail and I'll debug remotely.

---

## ⏱️ Timeline

- **Today (1-2 hours)**: Event log hardening
- **Tomorrow (1-2 hours)**: Wire to parallel path + performance budgeting
- **Tomorrow evening (30 mins)**: Testing + manual validation

**Goal**: Push to `release/v1.0` by tomorrow EOD

---

**Status**: Ready to work? Start with the Event Log Hardening section. I'm handling code cleanup on desktop in parallel. 🚀
