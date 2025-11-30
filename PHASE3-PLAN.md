# Phase 3 Plan

## Objectives

- Dashboards: Alert badges, severity timelines, trend deltas.
- Path visuals: Traceroute hop timelines with RTT/loss overlays and changes.
- Scheduling + Trends: Weekly baselines; aggregate JSON for trend reporting.
- Notifications: Email/Webhook on High/Critical — gated by config.

## Deliverables

- `scripts/generate-dashboards.ps1`: Produces HTML dashboards from Reports JSON/CSV.
- `scripts/summarize-trends.ps1`: Builds weekly/monthly aggregates (avg/95th, anomalies).
- `src/ps/Bottleneck.TracerouteViz.ps1`: Hop timeline and diff utilities.
- `src/ps/Bottleneck.Scheduler.ps1`: Weekly baseline runner with retention.
- `config/bottleneck.profiles.json`: Config profiles for different environments.

## Milestones

1. Data schemas
   - Define `trend-week.json`, `trend-month.json`, and run manifest format.
   - Add integrity markers (hash + timestamps).
2. Traceroute visualization
   - Parse snapshots; compute hop deltas; render compact hop timeline.
   - Integrate into HTML report and new dashboards page.
3. Dashboards
   - Severity badges; anomaly fusion line; per-target summaries.
   - Printable `--compact` layout option.
4. Scheduling
   - Weekly baseline task script; retention (last N runs).
   - Optional notifications on High/Critical during scheduled runs.

## Initial Tasks

- Implement `summarize-trends.ps1` with schemas and aggregation.
- Implement `TracerouteViz` functions (parse/diff/render data for charts).
- Update HTML generator to include badges + trend deltas.
- Add config profiles and simple loader.

## Try It

```pwsh
# Aggregate recent data for dashboards
pwsh -NoProfile -File .\scripts\summarize-trends.ps1 -Window "7d" -Out "Reports\trend-week.json"

# Generate dashboards
pwsh -NoProfile -File .\scripts\generate-dashboards.ps1 -PageSize Letter
```

## Notes

- Keep outputs aligned with existing `Reports` structure.
- Maintain single-page printable option where feasible.
- Prefer minimal changes to public APIs; add new functions/modules for Phase 3.
