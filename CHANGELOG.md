# Changelog

## [1.0.0-phase1] - 2025-11-30
### Added
- Unified computer scan (`Invoke-BottleneckComputerScan`) with elevation logic.
- Long-running network monitor (`Invoke-BottleneckNetworkMonitor`) with duration presets and graceful Ctrl+C shutdown.
- MTR-lite path quality analysis (per-hop latency & loss, JSON persistence, report integration).
- Speedtest integration (`Invoke-BottleneckSpeedtest`) with multi-provider support (HTTP, Ookla, Fast) and historical trend tracking.
- Per-process network traffic snapshot (`Get-BottleneckNetworkTrafficSnapshot`) including bandwidth delta & risky port detection.
- Metrics export (`Export-BottleneckMetrics`) supporting JSON and Prometheus formats.
- Threshold alerting (`Test-BottleneckThresholds`) with configurable JSON, toast notifications, and logging.
- Task scheduling (`Register-BottleneckScheduledScan`, etc.) for automated Computer/Network/Speedtest scans.
- New version metadata module (`Get-BottleneckVersion`).
- Comprehensive documentation: README, QUICKSTART, DESIGN, ROADMAP, PHASE1-SUMMARY.

### Changed
- Module export list updated to include new Phase 1 functions.
- `.gitignore` refined to exclude transient Reports and reference repos.

### Removed
- Excluded large reference repositories under `Other Ideas/` from tracked history.

### Security
- No known security issues introduced; network operations limited to standard diagnostic endpoints.

---
