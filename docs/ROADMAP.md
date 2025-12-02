# Bottleneck Roadmap

- Deep scan: ETW, SMART, SFC/DISM
- More checks: RAM, CPU, GPU
- GUI: Tauri/React
- Hardware upgrade links
- Rollback/restore UI
- Cloud sync

## Phase 6: Advanced Alert Fusion
- Implement fused alert level from latency spikes, loss bursts, and jitter volatility.
- Wire fused level into RCA, CSV diagnostics, and HTML report.
- Tune weights/thresholds with real datasets; add config overrides.
- Display fused level in console outputs for quick triage.

## Phase 7: Full Network Scan Integration
- Persist probe/minute-level events needed for fusion in monitor outputs.
- Add summary export (CSV/JSON) including fused alert level.
- Optional: real-time fused alert during long-running monitors.
