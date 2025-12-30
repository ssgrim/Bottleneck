# Desktop Diagnostic (Win7-safe)

This utility runs a short, safe diagnostic to identify CPU, memory, and disk bottlenecks on older systems (including Windows 7) without modifying the machine.

What it does

- Collects OS/CPU/RAM and disk capacity info
- Lists top processes (CPU and memory) for quick visibility
- Samples key performance counters once per second
- Optionally applies a light CPU load to observe behavior under stress
- Safe heavy probe (-HeavyLoad): 30s cap, uses CPU (leaves one core free) and disk I/O with throttling to avoid lockups
- Writes a transcript to `Reports/desktop-diagnostic-<timestamp>.log`
- Detects OS (Win7/8/8.1/10/11) and prints OS-aware focus suggestions
- Adds SMART/disk health, event log summaries, startup/tasks, process activity sampler, and thermal/throttle signals
- Optional HTML report with health score (`-Html`)

Quick start

```pwsh
# From the repo root
pwsh -ExecutionPolicy Bypass -File scripts/run-desktop-diagnostic.ps1

# Passive (no synthetic load)
pwsh -ExecutionPolicy Bypass -File scripts/run-desktop-diagnostic.ps1 -NoLoad

# Shorter window (e.g., 15 seconds)
pwsh -ExecutionPolicy Bypass -File scripts/run-desktop-diagnostic.ps1 -DurationSeconds 15

# Safe heavy probe (capped at 30s)
pwsh -ExecutionPolicy Bypass -File scripts/run-desktop-diagnostic.ps1 -HeavyLoad -DurationSeconds 30

# Generate HTML report with score
pwsh -ExecutionPolicy Bypass -File scripts/run-desktop-diagnostic.ps1 -Html -DurationSeconds 15
```

Interpreting results

- CPU avg > ~85% under light load: background apps or CPU limited
- Min Available Memory < ~800 MB: memory pressure; close apps or add RAM
- Disk Queue > ~2: storage bottleneck or heavy I/O
- Disk sec/transfer > ~0.05s: slow storage device
- System drive < 10% free: free up space

Notes

- No admin required. If a counter is unavailable, it logs `null` and continues.
- Synthetic load uses at most half of logical CPUs for the specified duration.
- Output is human-readable and safe to share; sensitive process names may appear.
