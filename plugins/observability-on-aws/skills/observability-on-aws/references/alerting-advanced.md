# Advanced Alerting

## Purpose

Advanced alerting patterns including composite alarms, anomaly detection, SLO-based alerting, and alarm tuning. For basic alarm setup and configuration patterns, see `alerting-setup.md`.

## Composite Alarms

**Service Health** - combine metrics to determine overall health:

```
Composite Alarm: "api-service-unhealthy"
Logic: (high-error-rate OR high-latency) AND low-success-rate
Components: Errors > 5%, p99 Latency > 2000ms, Success rate < 95%
```

**Dependency Failure** - detect cascading failures:

```
Composite Alarm: "service-and-dependency-down"
Logic: service-errors AND (database-errors OR cache-errors)
Components: Lambda Errors > 10, RDS CPU > 90%, ElastiCache Evictions > 1000
```

## Anomaly Detection Alarms

**When to Use**: Metrics with predictable patterns (daily/weekly cycles), metrics where absolute thresholds are hard to define, or detecting unusual behavior vs normal patterns.

```
Metric: AWS/ApiGateway - Count | Anomaly Detection: Enabled
Threshold: 2 standard deviations | Evaluation Period: 10 min
Rationale: Learns normal request patterns, adapts to traffic growth over time
```

## SLO-Based Alerting

Use SLO error budget consumption to drive alerting thresholds:

```
SLO: 99.9% availability (30-day window)
Error Budget: 0.1% = 43.2 minutes downtime/month
  Warning (50% consumed, 21.6 min): Notify team, review recent changes
  Critical (80% consumed, 34.6 min): Page on-call, implement feature freeze
  Emergency (100% consumed, 43.2 min): All hands, immediate mitigation
```

**Implementation**: Set up SLO in Application Signals, create CloudWatch alarm on error budget metric, configure multi-level thresholds, link to incident response procedures.

## Alarm Actions

- **Critical**: Page on-call (PagerDuty/Opsgenie), post to critical alerts channel, create high-priority ticket
- **Warning**: Post to team channel, create normal-priority ticket, email team distribution list
- **Info**: Log to monitoring system, email individual owner, no immediate action required

## Alarm Tuning and Maintenance

### Reducing False Positives

When alarms trigger frequently without real issues (alarm fatigue):

1. **Adjust Thresholds**: Review alarm history, analyze patterns, increase threshold if too sensitive, use percentiles instead of max/min
2. **Increase Datapoints to Alarm**: Change from 1/1 to 2/3 to require sustained breach
3. **Use Composite Alarms**: Combine multiple signals for more accurate detection
4. **Implement Maintenance Windows**: Suppress alarms during deployments using CloudWatch alarm actions

### Handling Alarm Flapping

When an alarm rapidly switches between OK and ALARM:

1. **Increase Evaluation Period**: Longer time windows smooth oscillations
2. **Add Hysteresis**: Different thresholds for alarm and recovery (e.g., alarm at 80%, recover at 70%)
3. **Use Anomaly Detection**: Adapts to patterns, less sensitive to threshold proximity

## Alarm Testing

**Test Checklist**: Alarm triggers on breach, recovers on return to normal, actions execute correctly, description is actionable, runbook link works, on-call receives notification within SLA.

**Testing Approaches**:

1. **Synthetic Testing**: Inject errors or load, verify alarm triggers, confirm notifications
2. **Historical Analysis**: Review past incidents, check if alarm would have triggered, adjust as needed
3. **Chaos Engineering**: Deliberately cause failures, validate detection and incident response

## Integration with Incident Response

**Alarm-Triggered Investigation**: Alarm triggers notification, on-call checks details, query CloudWatch Logs for errors, analyze Application Signals traces, check CloudTrail for recent changes (use data source priority), implement mitigation, update alarm if needed.

**Proactive Monitoring**: Review alarm history daily, identify patterns and trends, tune thresholds before issues occur, add missing alarms for coverage gaps, document learnings in runbooks.
