# Phase 5 Plan

## Objectives
- Notifications: Email/Webhook on High/Critical alerts
- Advanced alert fusion: Real-time anomaly detection with badge computation
- Notification templates and opt-in consent
- Integration with monitor post-run hooks

## Deliverables
- `src/ps/Bottleneck.Notifications.ps1`: Email/Webhook notification module
- `config/notifications.json`: Notification config (SMTP/webhook endpoints, opt-in flags)
- Enhanced dashboard badges using full anomaly pipeline
- Notification templates for alert summaries

## Milestones
1. Notification module
   - SMTP email via secure credential storage
   - Webhook POST with JSON payload (alert level, targets, correlation context)
   - Template engine for alert messages
2. Advanced alert fusion
   - Wire `Get-LatencyAnomalies`, `Get-LossBursts`, `Get-JitterVolatility` into dashboard
   - Compute real-time alert level from anomaly counts
   - Dynamic badge rendering based on fusion results
3. Integration
   - Monitor post-run hook calls notification module on High/Critical
   - Consent gates and opt-in config validation
4. Testing
   - Test notifications with mock SMTP/webhook
   - Validate alert level computation accuracy

## Try It
```pwsh
# Configure notifications (opt-in)
pwsh -NoProfile -File .\scripts\configure-notifications.ps1 -Email "alerts@company.com" -SmtpServer "smtp.gmail.com" -Port 587

# Enable webhook
pwsh -NoProfile -File .\scripts\configure-notifications.ps1 -WebhookUrl "https://hooks.slack.com/services/YOUR/WEBHOOK"

# Test notification
pwsh -NoProfile -File .\scripts\test-notification.ps1 -Level Critical -Message "Test alert"
```

## Notes
- All notifications opt-in; no default endpoints
- Credentials stored securely (Windows Credential Manager or encrypted config)
- Rate limiting to avoid spam (max 1 per hour per alert type)
- Privacy: redact IPs/hostnames option in templates
