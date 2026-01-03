# Bottleneck v1.0 Release Plan

**Goal**: Ship a clean, tested, production-ready v1.0 release by end of week

---

## 📊 Current State Audit

### What's Working ✅
- **24 PowerShell modules** (303.7 KB) with 8,654 lines of code
- **Core diagnostics**: Quick/Standard/Deep scans with 46+ checks
- **AI integration**: ChatGPT/Copilot/Gemini context injection
- **Reporting**: HTML with color-coded severity, trending, Grafana exports
- **Fixes**: 10 remediation functions with rollback capability
- **Parallel execution**: Phase 10 infrastructure (Bottleneck.Parallel.ps1) in place
- **10 entry point scripts** covering all major workflows

### What Needs Cleanup 🧹
- **Redundant scripts**: Some overlap between run-quick/run-standard/run-deep/run.ps1
- **Test coverage**: Only 1 basic Pester file, no comprehensive test suite
- **Documentation**: PHASE plans scattered; no unified "how to use v1.0"
- **Module debt**: Some small modules could be consolidated (Baseline.ps1 is 76 lines)
- **Error handling**: Event log resilience from Phase 10 not fully integrated
- **Release artifacts**: No version file, no changelog for v1.0

---

## 🎯 Release Checklist

### Phase 1: Code Cleanup (2 days)
- [ ] Consolidate redundant entry scripts → single `run.ps1` with all modes
- [ ] Merge small modules (< 100 lines) into logical units
  - Baseline.ps1 (76 lines) → merge into Profiles
  - WindowsFeatures.ps1 (82 lines) → merge into Checks
  - Logging.ps1 (97 lines) → keep separate (core utility)
  - Performance.ps1 (89 lines) → keep separate (caching engine)
- [ ] Audit all imports/requires; remove unused dependencies
- [ ] Remove any debug/testing code from Phase 7-9 iteration

### Phase 2: Phase 10 Completion (3 days)
- [ ] Finalize event log hardening (null StartTime, AccessDenied fallback)
- [ ] Wire all Standard/Deep checks to use parallel path
- [ ] Add comprehensive error handling + graceful degradation
- [ ] Implement performance telemetry + timing budgets (Phase 10 Section 5)
- [ ] Create perf baseline on reference machine

### Phase 3: Testing & Validation (3 days)
- [ ] Build stress test suite (CPU burn, memory, disk, network throttle)
- [ ] Create Pester tests for:
  - Each major check function
  - Parallel execution logic
  - Error handling (null logs, access denied)
  - Report generation
  - AI context injection
- [ ] Run full suite in CI/CD (GitHub Actions)
- [ ] Manual smoke tests on Windows 10/11

### Phase 4: Documentation & Release (2 days)
- [ ] Update README.md with v1.0 feature list
- [ ] Create CHANGELOG.md with v1.0 summary
- [ ] Add version file: `Version.txt` = "1.0.0"
- [ ] Create `INSTALL.md` (winget, manual, git clone)
- [ ] Create `QUICKSTART.md` for different personas
- [ ] Tag release in git: `git tag -a v1.0.0 -m "Bottleneck v1.0"`

---

## 📂 File Organization (Post-Cleanup)

```
src/ps/
  ├── Bottleneck.psm1                 (main loader)
  ├── Bottleneck.Logging.ps1          (logging + observability)
  ├── Bottleneck.Performance.ps1      (CIM caching + perf utils)
  ├── Bottleneck.Utils.ps1            (constants + helpers)
  ├── Bottleneck.Parallel.ps1         (job orchestration)
  ├── Bottleneck.Checks.ps1           (all check dispatch logic)
  ├── Bottleneck.Hardware.ps1         (CPU/Memory/Disk/Thermal)
  ├── Bottleneck.Network.ps1          (network diagnostics)
  ├── Bottleneck.Security.ps1         (security baseline)
  ├── Bottleneck.UserExperience.ps1   (boot/launch/UI perf)
  ├── Bottleneck.SystemPerformance.ps1(processes/services/logs)
  ├── Bottleneck.DeepScan.ps1         (deep analysis, ETW)
  ├── Bottleneck.Profiles.ps1         (predefined profiles)
  ├── Bottleneck.Wireshark.ps1        (network packet analysis)
  ├── Bottleneck.Report.ps1           (HTML/PDF generation)
  ├── Bottleneck.Remediation.ps1      (fixes + rollback)
  ├── Bottleneck.Analytics.ps1        (trend analysis + Grafana)
  ├── Bottleneck.EnhancedReport.ps1   (report enrichment)
  ├── Bottleneck.HealthCheck.ps1      (sanity checks)
  └── Bottleneck.Debug.ps1            (troubleshooting)

scripts/
  ├── run.ps1                         (MAIN: all modes, replaces 9 others)
  └── install.ps1                     (standalone installer)

tests/
  ├── unit-tests.ps1                  (Pester: function logic)
  ├── integration-tests.ps1           (Pester: full workflows)
  ├── stress-scenarios.ps1            (stress test definitions)
  └── ci-runner.ps1                   (GitHub Actions entry point)
```

---

## 🚀 Entry Points (Unified)

All modes accessible via `run.ps1`:

```powershell
# Quick scan
./run.ps1 -Quick

# Standard scan (with parallel by default)
./run.ps1 -Standard

# Deep scan
./run.ps1 -Deep

# Profile-based
./run.ps1 -Profile RemoteWorker

# With network analysis
./run.ps1 -Standard -WiresharkPath C:\captures\latest.pcapng

# Desktop diagnostic
./run.ps1 -Desktop -Html

# Network monitor
./run.ps1 -Network -DurationMinutes 30

# AI help
./run.ps1 -Standard -AI
```

---

## ✅ Success Criteria

- [ ] All 10 scripts consolidated → `run.ps1` only
- [ ] Parallel execution tested with stress scenarios
- [ ] 40+ Pester tests passing
- [ ] GitHub Actions CI/CD pipeline working
- [ ] v1.0.0 tag created and released
- [ ] README documents all features
- [ ] Zero known critical bugs (known issues documented)

---

## 📅 Timeline

| Task | Duration | Days |
|------|----------|------|
| Code cleanup + module consolidation | 2 days | Mon-Tue |
| Phase 10 hardening | 3 days | Wed-Fri |
| Test suite + CI/CD | 3 days | Sat-Mon |
| Documentation + release | 2 days | Tue-Wed |
| **TOTAL** | | **10 days** |

---

## 🎬 Starting Now

1. Create feature branch: `git checkout -b release/v1.0`
2. Start with module consolidation (Phase 1)
3. Complete Phase 10 hardening in parallel
4. Build tests as you go (TDD mindset)
5. Final PR review before merge to `main`

