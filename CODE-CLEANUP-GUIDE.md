# CODE CLEANUP GUIDE - DESKTOP

## 🎯 Mission: Consolidate 24 modules → 18 focused ones

**Start on desktop NOW. Will take ~2 hours.**

---

## Step 1: Create Release Branch

```powershell
cd c:\Users\mrred\git\Bottleneck
git checkout -b release/v1.0
git push -u origin release/v1.0
```

---

## Step 2: Consolidate Baseline.ps1 → Profiles.ps1

**Why**: Baseline is 76 lines, Profiles is 125. Both deal with configuration/personas.

### What to do:

1. **Copy Baseline functions** into Profiles.ps1 (near top, after imports)
   ```powershell
   # In Bottleneck.Profiles.ps1, add after Get-BottleneckProfile:
   
   # Baseline functions (moved from Bottleneck.Baseline.ps1)
   function Save-BottleneckBaseline { ... }
   function Compare-ToBaseline { ... }
   function Get-AnomalyScore { ... }
   ```

2. **Update Bottleneck.psm1** — remove the Baseline import:
   ```powershell
   # REMOVE THIS LINE:
   Import-ModuleFile 'Bottleneck.Baseline.ps1'
   
   # ADD THIS LINE (if not already there):
   . (Join-Path $PSScriptRoot 'Bottleneck.Profiles.ps1')
   ```

3. **Delete the old file**:
   ```powershell
   Remove-Item src\ps\Bottleneck.Baseline.ps1
   ```

4. **Test it**:
   ```powershell
   pwsh -NoLogo -NoProfile
   cd c:\Users\mrred\git\Bottleneck
   Import-Module .\src\ps\Bottleneck.psm1 -Force
   
   # Should work:
   Get-BottleneckProfile
   Save-BottleneckBaseline -Metrics @{CPU=50; Memory=60}
   ```

---

## Step 3: Consolidate WindowsFeatures.ps1 → Checks.ps1

**Why**: WindowsFeatures has 82 lines (2 functions), Checks is 412 lines. Both are check functions.

### What to do:

1. **Read WindowsFeatures.ps1** completely:
   ```powershell
   cat src\ps\Bottleneck.WindowsFeatures.ps1
   ```
   (Functions: `Test-BottleneckWindowsFeatures`, `Test-BottleneckGroupPolicy`)

2. **Add to Checks.ps1** at the END of the file:
   ```powershell
   # Windows Features and Group Policy checks (moved from Bottleneck.WindowsFeatures.ps1)
   function Test-BottleneckWindowsFeatures { ... }
   function Test-BottleneckGroupPolicy { ... }
   ```

3. **Update Bottleneck.psm1**:
   ```powershell
   # CHANGE THIS:
   Import-ModuleFile 'Bottleneck.Checks.ps1'
   
   # TO THIS (dot-source so functions are available):
   . (Join-Path $PSScriptRoot 'Bottleneck.Checks.ps1')
   
   # REMOVE THIS LINE:
   . (Join-Path $PSScriptRoot 'Bottleneck.WindowsFeatures.ps1')
   ```

4. **Delete old file**:
   ```powershell
   Remove-Item src\ps\Bottleneck.WindowsFeatures.ps1
   ```

5. **Test it**:
   ```powershell
   Import-Module .\src\ps\Bottleneck.psm1 -Force
   Test-BottleneckWindowsFeatures
   Test-BottleneckGroupPolicy
   ```

---

## Step 4: Consolidate Entry Scripts

**Why**: 10 scripts do essentially the same thing. Reduce to 1 `run.ps1`.

### Current scripts (MOST WILL BE DELETED):
- `run-quick.ps1` → Merge into run.ps1
- `run-standard.ps1` → Merge into run.ps1
- `run-deep.ps1` → Merge into run.ps1
- `run-desktop-diagnostic.ps1` → Already merged? Check...
- `run-deep-logged.ps1` → Logging option in run.ps1
- `run-computer-scan.ps1` → Alias for run.ps1
- `monitor-network-drops.ps1` → Keep (specific tool)
- `remediate-wifi-issues.ps1` → Keep (specific tool)
- `install.ps1` → Keep (installer)

### What to do:

1. **Check what run-quick.ps1 does**:
   ```powershell
   cat scripts\run-quick.ps1 | Select-Object -First 20
   ```

2. **Check current run.ps1 parameters** (already has them?):
   ```powershell
   cat scripts\run.ps1 | Select-Object -First 30
   # Look for -Quick, -Standard, -Deep flags
   ```

3. **If run.ps1 already supports all tiers**, DELETE redundant scripts:
   ```powershell
   Remove-Item scripts\run-quick.ps1
   Remove-Item scripts\run-standard.ps1
   Remove-Item scripts\run-deep.ps1
   Remove-Item scripts\run-computer-scan.ps1
   Remove-Item scripts\run-deep-logged.ps1
   ```

4. **Keep these** (they're special):
   ```powershell
   scripts\run.ps1                    (MAIN - all modes)
   scripts\install.ps1                (installer)
   scripts\monitor-network-drops.ps1  (WiFi diagnostics)
   scripts\remediate-wifi-issues.ps1  (WiFi fixes)
   ```

---

## Step 5: Update Documentation

### Update README.md:

Find this section:
```markdown
## Usage

### With Wireshark Analysis
```

Replace with:
```markdown
## Usage

All operations use the **single entry point**: `./scripts/run.ps1`

### Quick Scan (5 checks, <30s)
```powershell
./run.ps1 -Quick
```

### Standard Scan (46 checks, <45s, with parallel execution)
```powershell
./run.ps1 -Standard
```

### Deep Scan (52 checks, <75s, parallel + ETW)
```powershell
./run.ps1 -Deep
```

### Profile-Based Scan
```powershell
./run.ps1 -Profile RemoteWorker
./run.ps1 -Profile DesktopGamer
```

### Desktop Diagnostic (Windows 7+ compatible)
```powershell
./run.ps1 -Desktop -Html -Duration 60
```

### Network Monitor (WiFi drops, latency)
```powershell
./run.ps1 -Network -Minutes 30
```

### With Wireshark Analysis
```powershell
./run.ps1 -Standard -WiresharkPath C:\captures\latest.pcapng
```
```

---

## Step 6: Create Version File

```powershell
"1.0.0" | Set-Content -Path version.txt
git add version.txt
```

---

## Step 7: Verify Everything Works

```powershell
# Test Quick scan
./scripts/run.ps1 -Quick
# Should complete in <30 seconds

# Test import
Import-Module .\src\ps\Bottleneck.psm1 -Force
Get-BottleneckProfile
Save-BottleneckBaseline -Metrics @{Test=1}
Test-BottleneckWindowsFeatures
```

---

## Step 8: Commit Your Work

```powershell
git status  # Review what changed
git add -A
git commit -m "Code cleanup: Consolidate modules and entry scripts

- Merge Bottleneck.Baseline.ps1 into Bottleneck.Profiles.ps1
- Merge Bottleneck.WindowsFeatures.ps1 into Bottleneck.Checks.ps1
- Delete 5 redundant entry scripts (run-quick, run-standard, etc)
- Single entry point: ./scripts/run.ps1 with all modes
- Add version.txt (1.0.0)
- Update README with unified usage examples"

git push origin release/v1.0
```

---

## ⚠️ Gotchas to Watch

| Issue | Solution |
|-------|----------|
| "Function already exists" | Make sure you're not loading the file twice in psm1 |
| Quick scan fails | Check that -Quick parameter is handled in run.ps1 |
| Functions not found | Verify you're dot-sourcing (`.`) not importing (`Import-Module`) |
| Can't delete files | Make sure PowerShell ISE/editor isn't holding a lock |

---

## 📊 Before & After

### Before
- 24 PS files (303.7 KB)
- 10 entry scripts
- Module loading mixed (Import-ModuleFile + dot-source)
- Confusing which script to run

### After
- 22 PS files (295 KB) — 8.7 KB saved
- 1 main entry script + 3 specialized tools
- Consistent dot-source pattern
- Clear: `./run.ps1 -Standard` is the way

---

**Timeline**: 2 hours
**Difficulty**: Medium (mostly copy/paste + deletions)
**Risk**: Low (well-tested functions, simple consolidation)

**When done, message me and we'll sync with laptop Phase 10 work!** 🚀
