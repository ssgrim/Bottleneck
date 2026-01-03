# 🎯 LAPTOP WORK QUICK START - PHASE 10

**Everything you need for laptop Phase 10 completion work**

---

## 📋 Quick Reference

**Full details**: See [PHASE10-COMPLETION-PROMPT.md](PHASE10-COMPLETION-PROMPT.md)

**Duration**: 2-3 hours total
**Deadline**: Tomorrow EOD
**Push to**: `release/v1.0` branch

---

## ⚡ The 3 Tasks

### Task 1: Event Log Hardening (1-2 hours)
**File**: `src/ps/Bottleneck.DeepScan.ps1`

**Problem**: Event logs crash on null StartTime or AccessDenied

**Solution**: Create `Get-EventLogSafeQuery` function:
```powershell
function Get-EventLogSafeQuery {
    param([string]$LogName, [datetime]$StartTime, [datetime]$EndTime)
    
    try {
        # Handle null StartTime
        $filter = @{ LogName = $LogName }
        if ($StartTime) { $filter['StartTime'] = $StartTime }
        if ($EndTime) { $filter['EndTime'] = $EndTime }
        
        # 10s timeout per log
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
        # Graceful fallback: count via wevtutil
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

**Checklist**:
- [ ] Add function to DeepScan.ps1
- [ ] Find all `Get-WinEvent` calls and replace with wrapper
- [ ] Test: System log (should work)
- [ ] Test: Security log (should fallback gracefully)

---

### Task 2: Wire to Parallel Path (30-45 mins)
**Files**: `src/ps/Bottleneck.Parallel.ps1` + `scripts/run.ps1`

**Current**: Sequential checks (slow, 120+ seconds)
**Target**: Parallel jobs (fast, ~45 seconds on Standard)

**Key changes**:
1. Open `Bottleneck.Parallel.ps1` — examine `Invoke-BottleneckParallel`
2. Find `Invoke-BottleneckScan` in `run.ps1`
3. Add logic:
   ```powershell
   if ($Tier -in @('Standard', 'Deep')) {
       # Use parallel with job concurrency
       $results = Invoke-BottleneckParallel -Tier $Tier -Concurrency @{
           Standard = 4
           Deep = 6
       }[$Tier]
   }
   ```

**Concurrency defaults**:
- Quick: 2 jobs
- Standard: 4 jobs
- Deep: 6 jobs

**Checklist**:
- [ ] Understand Parallel.ps1 structure
- [ ] Wire Standard scans to parallel
- [ ] Wire Deep scans to parallel
- [ ] Quick stays sequential (fast anyway)
- [ ] Test: `./run.ps1 -Standard` (should be <45s)

---

### Task 3: Performance Budgeting (30-45 mins)
**File**: `src/ps/Bottleneck.Performance.ps1`

**Add this function**:
```powershell
function Test-PerformanceBudget {
    param(
        [string]$CheckName,
        [timespan]$ElapsedTime,
        [string]$Tier = 'Standard'
    )
    
    $budgets = @{
        'Quick'     = 30
        'Standard'  = 45
        'Deep'      = 75
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
- [ ] Add function to Performance.ps1
- [ ] Call after each parallel job
- [ ] Log slow checks to HTML report
- [ ] Add telemetry footer to report

---

## 🧪 Testing Before Commit

```powershell
# 1. Test event log function
cd c:\users\[you]\git\Bottleneck
pwsh -NoLogo -NoProfile
. .\src\ps\Bottleneck.DeepScan.ps1
$result = Get-EventLogSafeQuery -LogName 'Security'
$result  # Should show AccessDenied, not crash

# 2. Test parallel execution
Measure-Command { ./scripts/run.ps1 -Standard }
# Should be <45 seconds (was 120+)

# 3. Test performance warning
./scripts/run.ps1 -Deep
# Check report for slow check warnings
```

---

## 💾 Commit When Done

```powershell
git checkout release/v1.0
git pull origin release/v1.0  # Get desktop changes
git add -A
git commit -m "Phase 10: Event log hardening + parallel execution

- Implement Get-EventLogSafeQuery for null/AccessDenied handling
- Wire Standard/Deep scans to parallel path (4-6 concurrent jobs)
- Add performance budgeting and telemetry
- Tested on System and Security logs"

git push origin release/v1.0
```

---

## ⚠️ Common Issues

| Problem | Fix |
|---------|-----|
| "Null StartTime" error | Wrap in `if ($null -ne $StartTime)` guard |
| Parallel job no data | Check module bootstrap in Parallel.ps1 |
| Timeout on logs | Reduce timeout to 5s, use `-ErrorAction SilentlyContinue` |
| Report not showing telemetry | Verify Report.ps1 calls budget function |
| Security log AccessDenied | This is EXPECTED — test that fallback works |

---

## 🚀 Success Criteria

- [x] Desktop cleanup done (pushed to `release/v1.0`)
- [ ] Event log hardening complete
- [ ] Parallel path wired for Standard/Deep
- [ ] Performance budgeting implemented
- [ ] Tested and working locally
- [ ] Committed and pushed to `release/v1.0`

---

## 📞 Need Help?

Message me if:
- Event log functions aren't working
- Parallel jobs not returning data
- Report telemetry not showing
- Performance targets way off

**I'm on desktop ready to pull your work and build tests on top!** 🚀

---

**Start with Task 1 (event log hardening). It's the foundation for everything else.**
