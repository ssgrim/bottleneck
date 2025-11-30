# Phase 2 Plan (Draft)

Focus Areas:
1. Adaptive Analysis Engine
2. Smart Target Selection & Reliability Scoring
3. Anomaly Detection & Trend Modeling
4. Interactive Report Visualizations (Chart.js)
5. Enhanced Alert Intelligence (correlation & suppression)

## 1. Adaptive Analysis Engine
- Maintain rolling 30-day history: scan-history.json (system + network summary per run)
- Baseline drift detection:
  - SuccessRate drop > 1.5% week-over-week
  - P95 latency increase > 20% compared to 14-day moving average
- Recurring issue identification:
  - Same likely cause appears in >40% of daily monitors
  - Path hop with sustained loss > 2% in 5+ distinct monitors
- Functions:
  - Update-BottleneckHistory
  - Get-BottleneckDriftReport
  - Get-BottleneckRecurringIssues
  - Get-BottleneckAdaptiveRecommendations

## 2. Smart Target Selection
- Discover local gateway (ipconfig /all parsing) and add dynamic gateway probe
- Query system DNS settings (Get-DnsClientServerAddress)
- Expand public targets list with CDN endpoints (Cloudflare, Akamai, AWS CloudFront)
- Reliability scoring formula:
  Score = (WeightSuccess * SuccessRate) - (WeightLatency * Normalize(P95Latency)) - (WeightJitter * Normalize(Jitter)) - (WeightLoss * LossPercent)
- Maintain target performance cache target-performance.json
- Functions:
  - Get-BottleneckBaseTargets
  - Measure-TargetPerformanceBatch
  - Get-RecommendedTargets
  - Rotate-AdaptiveTargets

## 3. Anomaly Detection
- Short-term z-score deviations for latency (|z| > 3 triggers anomaly event)
- EWMA (Exponentially Weighted Moving Average) for smoothing jitter trends
- Burst loss detection using sliding window (loss > 5% over 60s)
- Functions:
  - Get-LatencyAnomalies
  - Get-LossBursts
  - Get-JitterVolatility
  - Write-AnomalyEvents (log file anomalies.log)

## 4. Interactive Report Visualizations
- Integrate Chart.js via CDN in HTML reports
- Charts:
  - Latency Time Series (line)
  - Success Rate Gauge (doughnut)
  - Speedtest Trend (bar or line with moving average)
  - Path Hop Heatmap (custom gradient table)
- Add toggle for raw data vs summarized view
- Functions / Enhancements:
  - Get-ChartDataObjects
  - Add-InteractiveScriptsToReport

## 5. Enhanced Alert Intelligence
- Correlate alerts (e.g., high latency + path hop loss -> single root cause grouping)
- Suppress duplicate alerts within 15-minute window
- Escalation logic: repeated critical alerts (>=3/hour) -> Escalated severity
- Functions:
  - Group-AlertEvents
  - Should-SuppressAlert
  - Get-AlertEscalationLevel

## Data Files (New)
- scan-history.json
- target-performance.json
- anomalies.log
- alert-events.json (structured alert events with correlation IDs)

## Implementation Order
1. History persistence & drift detection
2. Smart targets & reliability scoring
3. Anomaly detection layer
4. Interactive charts integration
5. Alert correlation & suppression

## Acceptance Criteria
- History file persists after each scan/monitor end
- Drift report lists deviations with context metrics
- Recommended targets adjust after 3 monitoring sessions
- At least one anomaly type surfaced in report when triggered
- Report renders charts without breaking existing layout
- Alert log groups related events reducing noise

## Stretch Goals
- Simple REST endpoint to serve metrics (Start-BottleneckApiServer)
- Export scan-history trends to CSV/Excel
- Path quality geographic inference (optional)

## Version Target
- Phase 2 release tag: v1.1.0-phase2

