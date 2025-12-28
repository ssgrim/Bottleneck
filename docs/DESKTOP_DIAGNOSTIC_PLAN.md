# Desktop Diagnostic Plan (Win7-safe)

Goal: Provide a safe, production-friendly diagnostic for an older Windows 7 desktop that identifies CPU, memory, and disk bottlenecks and stability risks without changing system state or impacting installed software.

Scope

- Collection-only: No registry edits, driver changes, or software installs.
- Duration: ~30 seconds active sampling, optional light synthetic CPU load.
- Output: Transcript log in `Reports/` with human-readable summary and recommendations.

Checks & Signals

- System Info: OS, version, uptime, CPU model/cores/threads, RAM size, per-drive capacity and free.
- Baseline Processes: Top 5 by CPU and working set.
- Performance Counters (1 Hz during window):
  - `Processor(_Total)\% Processor Time`
  - `Memory\Available MBytes`
  - `PhysicalDisk(_Total)\Avg. Disk Queue Length`
  - `PhysicalDisk(_Total)\Avg. Disk sec/Transfer`
  - `LogicalDisk(_Total)\% Free Space` (sampling reference)
- Synthetic Load (optional): Light CPU spin using background jobs for `$DurationSeconds`.
- Disk Free Space: System drive percent free thresholding.

Heuristics & Thresholds

- CPU Saturation: Avg CPU > 85% under light load ⇒ close background apps or consider CPU upgrade.
- Memory Pressure: Min available < 800 MB ⇒ add RAM or close apps.
- Disk Queue: Avg queue length > 2 ⇒ storage is bottleneck; consider SSD or reduce I/O.
- Disk Latency: Avg disk sec/transfer > 0.05s (50ms) ⇒ storage is slow.
- System Drive Free Space: < 10% free ⇒ clean up space.

Safety Considerations

- Uses WMI and Get-Counter only; no writes.
- Synthetic load bounded by `$DurationSeconds`; number of workers ≤ half logical CPUs.
- Works without admin; if counters are unavailable, values are logged as null without failing.

Runbook

- Default: `pwsh -ExecutionPolicy Bypass -File scripts/run-desktop-diagnostic.ps1`
- Passive: `... -NoLoad`
- Short probe: `... -DurationSeconds 15`
- Deliverable: Send `Reports/desktop-diagnostic-*.log` to reviewer.

Future Enhancements (still Win7-safe)

- S.M.A.R.T. snapshot (WMI/MSFT Storage where available) – read-only.
- Temperature (WMI/ACPI if exposed) – read-only.
- Select Windows Event Log summaries (Application/System critical and error counts).
- Startup impact: enumerate Run keys and Startup Folder entries (list only).
