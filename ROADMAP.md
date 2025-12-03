# Bottleneck – Roadmap

This roadmap outlines the planned evolution of **Bottleneck** from a powerful single-host diagnostic script into a more capable, integratable diagnostic **platform**—while staying true to its core principles:

- **Single binary / zero-install** (PowerShell-first)
- **Unified network + system diagnostics**
- **Readable, beautiful reports**
- **Free, open-source, no telemetry**

Status and priorities may change as issues are filed and community feedback comes in. This document is a _directional_ guide, not a strict contract.

---

## Versioning & Milestones

Bottleneck uses **semantic-ish versions**:

- **v1.x** – Single-host diagnostics & reporting (current)
- **v2.x** – Continuous/agent mode + integrations
- **v3.x** – Advanced analytics, ETW, and "pro" scenarios

Each milestone below groups features by **priority** and assigns them to a **version target** (subject to change).

---

## Milestone v1.1 – Quality & Convenience

**Goal:** Polish the v1 experience, reduce friction, and prepare the codebase for bigger features.

**Focus Areas:**

- Usability
- Configuration
- Documentation

### Features

- [ ] **Predefined Scan Profiles**

  - Add named profiles for common personas:
    - `DesktopGamer`
    - `RemoteWorker`
    - `DeveloperLaptop`
    - `ServerDefault`
  - Each profile:
    - Selects a subset of checks
    - Tunes thresholds where appropriate
    - Modifies report emphasis (e.g., network vs thermal vs disk)

- [ ] **Profile Discovery & Help**

  - `Get-BottleneckProfile` command to list available profiles and included checks.
  - Update `QUICKSTART.md` with examples:
    - `.\run.ps1 -Computer -Profile RemoteWorker -Network -Minutes 20`

- [ ] **Config File Support**

  - Optional `bottleneck.config.json` to define:
    - Default profile
    - Default network targets
    - Report output paths
  - CLI flags always override config file.

- [ ] **Report Usability Improvements**
  - Add "Jump to Section" table of contents at top of HTML report.
  - Add "Copy diagnostics summary to clipboard" block (pure text) for ticketing systems.
  - Improve "Story Mode" phrasing for non-technical users.

---

## Milestone v1.2 – Network Quality Scoring

**Goal:** Match and exceed common network diagnostics norms (PingPlotter-style) for remote work, gaming, and VoIP.

**Focus Areas:**

- Latency
- Jitter
- Quality scoring

### Features

- [ ] **Jitter Metrics**

  - Compute jitter per session:
    - Per-probe difference from previous probe
    - Session-level metrics: avg jitter, max jitter
  - Add jitter column to CSV/JSON network logs.

- [ ] **Connection Quality Score**

  - Derive a single **Connection Quality Index** (0–100) per session based on:
    - Packet loss
    - Latency (avg/P95)
    - Jitter
  - Classify into tiers:
    - 90–100: Excellent
    - 70–89: Good
    - 40–69: Degraded
    - 0–39: Poor

- [ ] **Report Enhancements for Quality**
  - Add Connection Quality Score to:
    - Executive Summary
    - Story Mode narrative
  - Introduce a dedicated "Network Quality" visualization:
    - Gauge / bar indicator
    - Color-coded explanation (good for screenshots and stakeholder sharing)

---

## Milestone v1.3 – Synthetic Stress & Load-aware Diagnostics

**Goal:** Let Bottleneck not only _observe_ problems but also help _reproduce_ them under controlled load.

**Focus Areas:**

- Stress harness
- Load-aware analysis

### Features

- [ ] **CPU & Memory Stress Mode (Lightweight)**

  - `-StressCpu` option:
    - Spin up configurable CPU load for a short duration using PowerShell loops / tasks.
  - `-StressMemory` option:
    - Allocate, touch, and release memory in a controlled way for basic stress.

- [ ] **Disk I/O Stress Option**

  - Generate sequential and/or random I/O against a temporary file to test disk performance under load.
  - Automatically clean up test files.

- [ ] **Load-aware Diagnostics**

  - Capture pre-, during-, and post-stress metrics to:
    - Detect thermal throttling
    - Identify instability (e.g., major performance degradation during stress)
  - Add a "Stress Summary" section to the HTML report:
    - Before vs during vs after metrics
    - High-level conclusion (e.g., "System remains stable under moderate CPU stress")

- [ ] **Safety & Guardrails**
  - Clear warnings before starting stress tests.
  - Hard limits on duration and intensity to prevent accidental system abuse.

---

## Milestone v2.0 – Agent Mode & Alerting

**Goal:** Evolve Bottleneck from a one-shot diagnostic tool into a **lightweight monitoring agent** for single hosts.

**Focus Areas:**

- Background operation
- Notifications
- Integrations

### Features

- [ ] **Agent / Service Mode**

  - `-AgentMode` or `Start-BottleneckAgent`:
    - Runs periodic network and system checks in the background.
    - Uses a simple schedule (e.g., every 5 minutes) configurable via JSON or CLI.
  - Support for:
    - Windows Scheduled Task wrapper
    - Optional Windows service wrapper (documented)

- [ ] **Rolling Metrics Storage**

  - Maintain a local lightweight history:
    - e.g., `Reports\Metrics\bottleneck-metrics-YYYYMMDD.jsonl`
  - Store key metrics only:
    - Health score
    - Connection quality score
    - Packet loss / latency
    - CPU / memory / disk key metrics

- [ ] **Alerting Engine**

  - Configurable thresholds for:
    - Packet loss %
    - Latency P95
    - Health score
    - Disk free space
    - Temperature
  - When threshold breached:
    - Write alert event into structured logs
    - Optionally trigger notification channels (see next item)

- [ ] **Notification Integrations**

  - **Email (SMTP)**:
    - Simple configuration for SMTP host, from, to, and credentials (with secure storage recommendations).
  - **Webhooks**:
    - Generic webhook target for Slack, Teams, Discord, etc.
    - Document sample JSON payloads.
  - (Optional later) **Local balloon/toast notifications** for interactive sessions.

- [ ] **Alert Summary in HTML Reports**
  - HTML report should summarize:
    - How many alerts fired during the last period
    - Which thresholds were violated
    - Sample notification payload (for debugging)

---

## Milestone v2.1 – SNMP Router/Modem Awareness

**Goal:** Improve root cause analysis by correlating host-side data with **gateway / modem** metrics.

**Focus Areas:**

- SNMP
- Router-side visibility

### Features

- [ ] **Optional SNMP Polling**

  - New module (and feature flag) for SNMP:
    - `-SnmpTarget` for router/modem IP (often default gateway)
    - Support SNMPv2c (v3 optional later)
  - Collect:
    - Interface in/out octets, errors, discards
    - Device uptime
    - Basic CPU and temperature (if available via standard OIDs)

- [ ] **SNMP-Enhanced RCA**

  - When SNMP is enabled:
    - Correlate host-side loss with interface error/discard counters.
    - Augment RCA labels (DNS/router/ISP/target) with SNMP findings.
      - Example: "Router interface shows increasing error counters; likely local link issue."

- [ ] **SNMP Section in HTML Report**
  - Summarized view of SNMP data:
    - Graph of errors/discards over time if multiple samples
    - Current status and any detected anomalies

---

## Milestone v2.2 – Local Web Dashboard

**Goal:** Provide a **live view** of system and network health without requiring a full external monitoring stack.

**Focus Areas:**

- Local HTTP endpoint
- Live charts

### Features

- [ ] **Embedded HTTP Server (Local Only)**

  - Optional mode:
    - `Start-BottleneckDashboard`
  - Serves a small SPA (HTML/JS) via `http://localhost:<port>/`
  - Reads data from:
    - Rolling metrics files
    - Current agent snapshots

- [ ] **Dashboard Widgets**

  - Initial widgets:
    - Overall Health Score (gauge)
    - Connection Quality Score (gauge)
    - Recent packet loss / latency chart (last X minutes)
    - CPU / memory / disk quick view
  - Read-only, uses existing JSON outputs.

- [ ] **Authentication & Security**
  - Default bind to `localhost` only.
  - Optional simple auth (e.g., token in header or querystring) for remote viewing via SSH tunnel or VPN.

---

## Milestone v3.0 – Advanced Analytics & Pro Mode

**Goal:** Add "power-user" capabilities without sacrificing simplicity for casual users.

**Focus Areas:**

- Protocol classification
- ETW integration
- Open APIs

### Features

- [ ] **Basic Protocol Classification**

  - Tag traffic categories using port + heuristics:
    - Web (80/443)
    - Streaming
    - Gaming
    - VPN
    - File sync / backup
  - Show distribution in HTML report:
    - Pie chart by category
    - Tie network issues to dominant categories if possible.

- [ ] **ETW / Kernel Trace Integration (Advanced Mode)**

  - Optional `-AdvancedTracing` mode:
    - Short ETW trace capture around scan window for:
      - Disk I/O
      - CPU scheduling
      - Network stack events
  - Summarize ETW data into:
    - Top wait reasons
    - Obvious chokepoints (e.g., frequent DPC/ISR spikes)

- [ ] **Stable JSON Schema & External API**

  - Document a **versioned JSON schema** for:
    - Network scan outputs
    - System scan outputs
    - Baselines and anomalies
  - Ensure compatibility between versions with a `schemaVersion` field.
  - Provide a `Get-BottleneckStatus -AsJson` helper for scripting.

- [ ] **MSP / Multi-Host Friendly Add-ons**
  - Provide sample scripts for:
    - Running Bottleneck across multiple hosts in a domain.
    - Consolidating JSON outputs into a central CSV or dashboard.
  - Optional "multi-host" HTML summary page generator.

---

## Nice-to-Have / Backlog Ideas

These are intentionally **unscheduled** until there's clear demand:

- [ ] PDF export of HTML reports.
- [ ] Direct integration with:
  - Jira / ServiceNow / GitHub Issues via REST.
- [ ] Import/export of **settings & profiles** for MSPs.
- [ ] Dark/light theme toggle for reports and dashboard.
- [ ] Minimal GUI wrapper for non-PowerShell users.

---

## How to Influence the Roadmap

Contributions and feedback are welcome:

1. **Open a GitHub Issue**

   - Use the "Feature Request" template.
   - Reference the relevant milestone or section from this roadmap.

2. **Upvote / Comment**

   - Add a 👍 reaction to issues you care about.
   - Comment with additional use cases or constraints.

3. **Pull Requests**
   - For new features:
     - Start with a short design comment on an existing issue or open a new one.
     - Keep changes modular and well-documented.
   - Ensure:
     - Pester tests pass
     - PSScriptAnalyzer shows no new warnings

This roadmap will be updated periodically as major features land and priorities shift.

---
