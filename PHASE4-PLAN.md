# Phase 4 Plan

## Objectives
- Scheduler: Automated weekly baseline runs with retention policies
- Config profiles: JSON-based presets for different network environments
- Notifications: Email/Webhook on High/Critical alerts
- Advanced alert fusion: Real-time anomaly detection with badge computation

## Deliverables
- `scripts/schedule-baseline.ps1`: Weekly task runner with cron-like config
- `config/bottleneck.profiles.json`: Network presets (corporate/home/lab)
- `src/ps/Bottleneck.Notifications.ps1`: Email/Webhook hooks
- Enhanced dashboard badges using full anomaly detection pipeline

## Milestones
1. Scheduler implementation
   - Task definition and retention policy
   - Integration with Windows Task Scheduler or portable job runner
2. Config profiles
   - JSON schema for targets, thresholds, intervals
   - Profile loader and validator
3. Notifications
   - Email via SMTP or SendGrid
   - Webhook POST with JSON payload (alert level, targets, correlation)
4. Advanced alert fusion
   - Wire `Get-LatencyAnomalies`, `Get-LossBursts`, `Get-JitterVolatility` into dashboard
   - Real-time badge computation from anomaly counts

## Try It
```pwsh
# Schedule weekly baseline (Windows Task Scheduler)
pwsh -NoProfile -File .\scripts\schedule-baseline.ps1 -Frequency Weekly -DayOfWeek Sunday -Time "02:00"

# Load config profile
pwsh -NoProfile -File .\scripts\run-monitor-with-profile.ps1 -Profile corporate -Duration 30min
```

## Notes
- Keep scheduler portable; avoid tight coupling to Windows Task Scheduler.
- Profiles should override CLI args but allow per-run overrides.
- Notifications must be opt-in with clear consent gates.
