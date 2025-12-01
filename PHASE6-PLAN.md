# Phase 6 Plan: Advanced Alert Fusion

Objectives:
- Fuse latency spikes, loss bursts, and jitter volatility into a single alert severity.
- Add badges to HTML dashboards.
- Prepare health checks (DNS, gateway, MTU) for preflight.

Deliverables:
- Get-FusedAlertLevel in Alerts module.
- Dashboard badge rendering stub.
- Follow-up expanding anomaly pipeline and notifications.

## PR Summary (Ready to Merge)
- **Title:** Phase 6: Advanced Alert Fusion, Unified CLI, AI Triage, and Profiles
- **Overview:** Unified CLI (`scripts/run.ps1`) with auto-elevation and profiles, Advanced Alert Fusion in network RCA/diagnostics/report, optional AI triage in report, streamlined log collection.
- **Key Changes:**
	- `scripts/run.ps1`: `-Computer`, `-Network`, `-Minutes`, `-Profile`, `-AI`, `-CollectLogs`; elevation; fresh module import; RCA/diagnostics; opens latest report; optional bundling.
	- `config/scan-profiles.json`: quick/standard/deep presets; CLI reads Minutes+AI.
	- Fused alerts: RCA/diagnostics compute `FusedAlertLevel`; surfaced in CLI and report.
	- AI triage: Enabled via `Global:Bottleneck_EnableAI` set by CLI.
	- Tasks pruned; log collector improved.
- **Usage:**
	- `./scripts/run.ps1 -Computer -Profile standard -AI`
	- `./scripts/run.ps1 -Network -Profile quick`
	- `./scripts/run.ps1 -Computer -Network -Minutes 15 -AI -CollectLogs`
- **Artifacts:** Reports in `Reports`, Documents, and OneDrive (if present); network monitor CSV/HTML/OUT; logs zip via collector.
- **Testing:** Pester passes from `bottleneck/tests`; manual smoke validated under PowerShell 7.5.4.
- **Follow-ups:** Event log guard sweep; README/QUICKSTART refresh; optional CI.
