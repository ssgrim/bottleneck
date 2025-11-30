# Enhancements Backlog (Phase 2 → Future Phases)

This captures ideas that surfaced during Phase 2 to inform Phase 3 and beyond (up to Phase 10+). Prioritize as needed.

## Monitoring & Analysis

- Adaptive intervals: Dynamically adjust `PingIntervalSeconds` based on recent jitter/latency volatility.
- Weighted target scoring: Blend reliability, geographic diversity, ASN mix, and historical availability.
- Multi-path traceroute deltas: Compare successive traceroutes, highlight hop changes and RTT shifts.
- Cross-signal anomaly fusion: Combine latency z-score, loss bursts, and jitter volatility into a single confidence metric.
- Stateful anomaly suppression: Per-target cooldown windows to reduce noise.
- Auto-baselining windows: Detect quiet periods to refresh baselines automatically.

## Reporting & UX

- Path summary visualization: Sankey-style or layered hop view with RTT and loss overlays.
- Alert badges and severity timeline: Top-of-report badges, color-coded severity bands.
- Compact mobile view: Responsive layout with collapsible sections.
- Export presets: `--compact`, `--full`, `--ops` controlling chart density and detail.
- PDF export: Headless conversion and automatic file naming with run metadata.

## Data & Persistence

- Trend JSON schemas: Weekly and monthly aggregates (avg/95th, anomaly counts, availability by target).
- History compaction: Roll-up older raw samples to reduce storage growth.
- Integrity markers: Hashes + run manifest for reproducibility.
- Config profiles: JSON/YAML profiles for corporate/home/lab networks.

## Automation & Ops

- Scheduler: Weekly baseline runs with retention policies.
- Notifications: Email/Webhook on High/Critical alerts with correlation context.
- Health checks: Pre-flight tests (DNS resolution, gateway reachability, MTU).
- Self-test: Synthetic short run to verify environment/capabilities before long monitoring.
- Prometheus/Grafana: Optional export + dashboards using ideas from `mtr-exporter`.

## Performance & Robustness

- Async ping/traceroute pool: Increase throughput while limiting resource usage.
- Resilience on sleeps/hibernation: Detect clock jumps; mark samples invalid and resume cleanly.
- Fallback speedtests: Multiple providers/endpoints with timeout logic.
- NIC tuning: Leverage L2 performance ideas (RSS, interrupt affinity, offloads) from `l2perf`.

## Security & Privacy

- Redaction: Strip hostnames/IPs in reports for sharing.
- Consent gates: Ask before uploading or sharing diagnostics.

## Developer Experience

- Module diagnostics: Verbose traces gated by `-Debug`/`-Verbose`.
- Test harness: Mini datasets and golden outputs for CI.
- Lint configuration: Standardized rules to avoid unapproved verb warnings.

## Integrations (Other Ideas)

- Sniffnet-inspired per-process insights: Optional lightweight per-process traffic metrics and top talkers.
- Speedtest multi-provider: Integrate a CLI that chooses between multiple endpoints/providers; retry & backoff.
- MTR exporter bridge: Produce Prometheus metrics for path quality; sample jobs for common targets.
- MimicNet-inspired ML: Explore ML models for predicting congestion/anomalies; synthetic traffic generation for training.
- Simulation bridge: Optional OMNeT++/MimicNet data ingestion to compare simulated vs real-world runs.

### Project references and actionable items

#### mtr-exporter

- Scripts: `cmd/mtr-exporter`, `helpers/prometheus.yml`, `helpers/run-prometheus.sh`.
- Outputs: Prometheus metrics for MTR path quality, change tracking, VERSIONed releases.
- Visuals: Grafana dashboards consuming Prometheus (to design in Bottleneck).
- Actions: Implement a Bottleneck Prometheus endpoint for latency/loss/jitter and per-hop RTT; provide sample `prometheus.yml`.

#### sniffnet

- Scripts: Rust binary and services, per-process traffic capture (`src/`), build.rs.
- Outputs: Top talkers, per-protocol/process stats, alerts.
- Visuals: Built-in charts; we can mirror key visuals in HTML.
- Actions: Add optional per-process sampler in Bottleneck using Windows APIs/NetAdapter; render top talkers in report.

#### speedtest (monorepo)

- Scripts: Multiple packages under `packages/`, CLI orchestrated by `lerna`.
- Outputs: Throughput/latency/jitter to multiple providers/endpoints.
- Visuals: Result summaries; we’ll fold metrics into our HTML and trends.
- Actions: Abstract speedtest provider interface; support retries/backoff and failover; tag results in `Reports`.

#### MimicNet

- Scripts: `run_all.sh` pipeline (prepare/train/simulate/evaluate), `evaluate/visualize`, `prepare` feature extraction, `simulate` OMNeT++.
- Outputs: Latency/throughput CDFs, RTT/throughput plots, model artifacts.
- Visuals: Gnuplot templates for latency/throughput; training/eval visuals.
- Actions: Import CDFs into Bottleneck dashboards; optional ML model to predict congestion; compare simulated vs measured.

#### l2perf

- Scripts: Rust `main.rs`; NIC tuning strategies.
- Outputs: Layer-2 performance metrics, recommended NIC settings.
- Actions: Add Windows NIC tuning checks (RSS, interrupt moderation, offload flags) and recommendations module.

---

Notes:

- Keep enhancements modular; avoid breaking public APIs without migration notes.
- Align report outputs with future dashboards to ensure continuity.
