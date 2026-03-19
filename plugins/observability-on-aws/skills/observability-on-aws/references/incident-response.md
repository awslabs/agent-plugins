# Incident Response and Troubleshooting

## Purpose

Guidance for responding to incidents using the full AWS observability stack. For common incident patterns, see `incident-patterns.md`. For root cause analysis and postmortem templates, see `incident-postmortem.md`.

## Incident Response Framework

### Phase 1: Detection and Triage

**Severity Classification**:

- **SEV1 (Critical)**: Complete service outage, data loss, security breach
- **SEV2 (High)**: Major functionality impaired, significant user impact
- **SEV3 (Medium)**: Partial functionality impaired, workaround available
- **SEV4 (Low)**: Minor issue, minimal user impact
- **SEV5 (Informational)**: No immediate impact, cosmetic or non-urgent

**Actions**:

1. **Check Active Alarms** - Query CloudWatch for alarms in ALARM state, review alarm history and timing
2. **Review Application Signals** - Check service health, SLO status, error rates, and service maps
3. **Assess Impact** - Query logs for error volume, check request counts and success rates

### Phase 2: Investigation

**Data Collection Sources**:

1. **CloudWatch Logs Insights** - See `log-analysis.md` for detailed query patterns. Key query for incident context:

   ```
   # Quick error snapshot for incident timeframe
   fields @timestamp, @logStream, @message, level, errorType, requestId
   | filter level = "ERROR"
   | sort @timestamp asc
   | limit 100
   ```

2. **Application Signals Traces** - Search for failed traces, analyze timelines for bottlenecks, examine error spans
3. **CloudWatch Metrics** - Compare affected resource metrics with baseline, check for resource exhaustion
4. **CloudTrail Events** - See `security-auditing.md` for detailed patterns. Follow data source priority from `cloudtrail-data-source-selection.md`. Query for recent configuration changes and deployments.

### Phase 3: Mitigation

**Common Mitigation Strategies**:

1. **Rollback Deployment** - Check CloudTrail for recent deployments, rollback to previous stable version
2. **Scale Resources** - Increase capacity (EC2, Lambda concurrency), add read replicas, enable auto-scaling
3. **Circuit Breaker** - Route traffic away from failing dependency, enable degraded mode
4. **Rate Limiting** - Implement rate limiting at API Gateway, block malicious IPs, enable WAF rules
5. **Database Optimization** - Identify slow queries, add indexes, scale database resources

### Phase 4: Recovery Verification

**Verification Steps**:

1. **Check Alarms** - Verify alarms returned to OK state, monitor for flapping
2. **Validate Application Signals** - Confirm error rates normalized and latency within SLO targets
3. **Query Logs**:

   ```
   # Verify error rate has decreased
   fields @timestamp, level
   | stats count(*) as totalLogs,
          sum(level = "ERROR") as errorCount
     by bin(1m)
   | sort @timestamp asc
   | limit 60
   ```

4. **Monitor Metrics** - Verify CPU, memory, network, request rates, and latencies

## Complete Investigation Workflow

1. Detection (CloudWatch Alarms)
2. Service Health (Application Signals)
3. Error Analysis (CloudWatch Logs Insights)
4. Trace Analysis (Application Signals Traces)
5. Metric Correlation (CloudWatch Metrics)
6. Change Detection (CloudTrail)
7. Cost Impact (Billing & Cost Management MCP server)
8. Documentation (AWS Documentation)

For detailed patterns on individual tools, see `log-analysis.md`, `performance-monitoring.md`, and `security-auditing.md`.

## Quick Reference: Incident Checklist

- [ ] Check active alarms
- [ ] Review Application Signals service health
- [ ] Query logs for errors
- [ ] Analyze traces for failures
- [ ] Check metrics for anomalies
- [ ] Review CloudTrail for changes
- [ ] Assess cost impact
- [ ] Document timeline
- [ ] Implement mitigation
- [ ] Verify recovery
- [ ] Conduct root cause analysis (see `incident-postmortem.md`)
- [ ] Write postmortem (see `incident-postmortem.md`)
- [ ] Implement preventive measures
