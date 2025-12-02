# Bottleneck Check Matrix

| Tier     | Storage | Power | Startup | Network | RAM | CPU | Update | Driver | Browser | Disk SMART | OS Age | GPU | AV  | Tasks | Deep Diagnostics |
| -------- | ------- | ----- | ------- | ------- | --- | --- | ------ | ------ | ------- | ---------- | ------ | --- | --- | ----- | ---------------- |
| Quick    | ✔       | ✔     | ✔       | ✔       | ✔   | ✔   |        |        |         |            |        |     |     |       |                  |
| Standard | ✔       | ✔     | ✔       | ✔       | ✔   | ✔   | ✔      | ✔      | ✔       | ✔          | ✔      | ✔   | ✔   | ✔     |                  |
| Deep     | ✔       | ✔     | ✔       | ✔       | ✔   | ✔   | ✔      | ✔      | ✔       | ✔          | ✔      | ✔   | ✔   | ✔     | ✔                |

## Network Fused Alert (Phase 6)

- Inputs: `LatencySpikes`, `LossBursts`, `JitterVolatility`
- Sources:
	- Latency spikes: minutes where avg latency ≥ P95 (from monitor CSV or probes)
	- Loss bursts: failure clusters with ≥3 failures within a minute
	- Jitter volatility: per-minute jitter standard deviation ≥ 15 ms
- Scoring (initial weights):
	- Latency spikes: weight 2 per event
	- Loss bursts: weight 3 per cluster
	- Jitter volatility: weight 1 per minute
- Levels:
	- Score ≥ 12 → Critical
	- Score ≥ 7  → High
	- Score ≥ 3  → Moderate
	- Score ≥ 1  → Low
	- Otherwise   → None

Notes:
- Thresholds are subject to tuning with more datasets.
- Fused level is surfaced in RCA, CSV diagnostics, and the HTML report when a recent monitor CSV is present.
