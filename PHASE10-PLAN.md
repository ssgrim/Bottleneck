# Phase 10: Parallel Execution & Resilience

**Status**: Planning  
**Priority**: Critical  
**Target**: Q1 2026

---

## 🎯 Vision

Cut scan times by 60–70% while making diagnostics resilient to flaky event logs and invalid inputs. Phase 10 focuses on **parallel execution**, **event log hardening**, **input validation**, and **module load efficiency** so users get faster, more reliable results.

**Core Principle**: _"Fast, Fault-Tolerant, and Safe by Default"_

---

## 📋 Objectives

1. **Parallel Execution**: Run checks concurrently with safe runspace/job orchestration
2. **Event Log Resilience**: Never fail scans due to missing/null event data or access errors
3. **Input & Parameter Validation**: Prevent bad inputs before runtime; clear user errors
4. **Module Consolidation**: Reduce dot-sourcing overhead; faster load and fewer files
5. **Performance Observability**: Measure and enforce budgets per tier

---

## 🔧 Core Workstreams

### 1) Parallel Execution Architecture
- **Goal**: 60–70% faster Standard/Deep scans
- **Approach**:
  - Introduce a **Job Controller** that schedules check groups by category (CPU/Memory/Disk/Network/Security)
  - Use `Start-ThreadJob` (or `Start-Job` fallback) with **module import bootstrap** per job
  - **Concurrency budget** per tier: Quick=2, Standard=4, Deep=6 (tunable)
  - **Shared context**: pass immutable scan config and paths; collect results via `Receive-Job`
  - **Timeouts**: per-job default 120s; tier max cap to prevent runaways
  - **Cancellation**: allow early abort if critical error occurs
- **Deliverables**:
  - `Bottleneck.Parallel.ps1` (controller + helpers)
  - Refactor core checks to expose a **job-friendly entrypoint** (no reliance on global state)
  - Update `Bottleneck.psm1` to wire parallel path by tier flag (default ON for Standard/Deep)

### 2) Event Log Hardening
- Handle **null StartTime** in `Get-WinEvent` filter hashtables
- Graceful **AccessDenied** fallback: degrade to summary counts via `wevtutil` or skip with warning
- **Time-bounded queries**: enforce 10–15s per log with cancellation
- Add **retry with smaller window** if initial query fails
- Log **explicit reason** into report ("Event logs partially collected: AccessDenied")

### 3) Input & Parameter Validation
- Add `[ValidateNotNullOrEmpty()]` to file paths and identifiers
- Validate **timeouts** (5–300s), **tiers** (Quick|Standard|Deep), and **profile names** (from scan-profiles.json)
- Normalize paths (resolve relative to repo root when possible)
- User-friendly error messages bubbled to HTML/PDF

### 4) Module Consolidation & Load Optimization
- Merge micro-modules (<50 lines) into logical units to cut dot-sourcing overhead
- Lazy-load heavyweight pieces only when the feature is invoked (e.g., PDF/export, Wireshark helpers)
- Ensure `Bottleneck.psm1` export list stays stable; document any renamed functions

### 5) Performance Observability & Budgeting
- Add timing telemetry per check and per category (write to logs + report footer)
- Define **performance budgets** per tier: Quick <30s, Standard <45s, Deep <75s on reference hardware
- Detect and flag outliers: if any check exceeds 2x median, surface in report with suggestion

### 6) Reporting Enhancements (Optional but Valuable)
- Surface parallel execution stats in HTML (total time, longest checks)
- Add small Sparkline/Chart.js for per-category timing (if data available)

---

## 🧪 Testing & Validation
- **Unit**: Pester for new parallel controller and validation helpers
- **Integration**: Run Standard/Deep scans in parallel mode; verify no missing outputs
- **Resilience**: Simulate event log access denied/null StartTime; ensure graceful fallback
- **Performance**: Benchmark before/after on sample machine; document timing deltas

---

## 🚀 Milestones
- **Week 1**: Spike parallel controller + job bootstrap; add validation helpers
- **Week 2**: Wire key check groups to parallel path; implement event log hardening
- **Week 3**: Consolidate modules; add performance telemetry; initial benchmarks
- **Week 4**: Stabilization, Pester coverage, docs/report updates; release

---

## ⚠️ Risks & Mitigations
- **Runspace isolation**: Functions not visible in jobs → include bootstrap that dot-sources required modules
- **Race conditions**: Shared files/logs → write per-job temp artifacts, merge at end
- **Timeout tuning**: Too aggressive → tier-based defaults with overrides in config
- **Behavior regressions**: Guard with feature flag `-Parallel` (on by default for Standard/Deep, off for Quick)

---

## ✅ Success Criteria
- Standard scan time reduced by **≥60%** vs current baseline
- Deep scan time reduced by **≥50%** vs current baseline
- Zero hard failures from event log collection (all fallbacks logged, not fatal)
- All public entrypoints guarded by validation attributes and friendly errors
- No loss of diagnostic coverage compared to pre-parallel runs
