# Root Cause Analysis and Postmortems

## Purpose

Root cause analysis methodology and postmortem templates. For the overall incident response framework, see `incident-response.md`. For common incident patterns, see `incident-patterns.md`.

## Phase 5: Root Cause Analysis

### Timeline Construction

Create a detailed timeline from first anomaly to resolution. Mark key milestones: incident start, detection, mitigation, and resolution.

### Five Whys Analysis

```
Problem: API returned 500 errors
Why? Lambda function timed out
Why? Database queries were slow
Why? Database was under heavy load
Why? New feature caused N+1 query problem
Why? Code review didn't catch the inefficient query pattern
Root Cause: Insufficient code review process for database queries
```

### Contributing Factors

- **Technical**: Code bugs, configuration errors, infrastructure limits
- **Process**: Inadequate testing, missing monitoring, insufficient review
- **Human**: Knowledge gaps, communication issues, alert fatigue

### Evidence Collection

- Log excerpts showing errors (see `log-analysis.md` for query patterns)
- Metric graphs showing anomalies
- Trace examples demonstrating failures (see `performance-monitoring.md`)
- CloudTrail events showing changes (see `security-auditing.md`)
- Cost data showing resource usage

## Phase 6: Postmortem and Prevention

### Postmortem Template

```markdown
# Incident Postmortem: [Incident Title]

## Summary

- **Date**: YYYY-MM-DD
- **Duration**: X hours Y minutes
- **Severity**: SEVX
- **Impact**: Description of user impact
- **Root Cause**: Brief root cause statement

## Timeline

- HH:MM - Incident began
- HH:MM - First alert triggered
- HH:MM - Root cause identified
- HH:MM - Mitigation applied
- HH:MM - Service restored

## What Happened

Detailed description of the incident

## Root Cause

Detailed root cause analysis with evidence

## Resolution

How the incident was resolved

## Impact

- Users affected: X | Requests failed: Y | SLO budget consumed: Z%

## Action Items

1. [ ] Immediate fix (Owner, Due Date)
2. [ ] Monitoring improvement (Owner, Due Date)
3. [ ] Process change (Owner, Due Date)

## Lessons Learned

What went well and what could be improved
```

### Prevention Strategies

- **Monitoring**: Add missing alarms, improve thresholds, create composite alarms, set up SLOs
- **Testing**: Add failure scenario tests, implement chaos engineering, load test for capacity
- **Process**: Update deployment procedures, improve code review checklists, implement gradual rollouts
- **Architecture**: Add redundancy for single points of failure, implement circuit breakers, add caching

## Example: Complete Incident Investigation

**Scenario**: API returning 500 errors

1. **Detect**: CloudWatch alarm "api-error-rate" triggers
2. **Assess**: Application Signals shows 15% error rate on api-service (normal: 0.1%)
3. **Query Logs**: Error logs show database timeout exceptions (see `log-analysis.md`)
4. **Trace**: Application Signals traces show timeout calling database
5. **Metrics**: RDS CPUUtilization at 95%
6. **CloudTrail**: Check for recent changes (see `cloudtrail-data-source-selection.md`)
7. **Analyze Logs**: Slow query analysis reveals N+1 pattern - 10,000+ queries per request
8. **Root Cause**: New deployment introduced N+1 query causing database overload
9. **Mitigate**: Rollback deployment, verify error rate returns to normal, fix N+1 query
