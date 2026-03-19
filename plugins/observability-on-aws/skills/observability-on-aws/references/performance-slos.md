# Application Signals SLOs & Troubleshooting

## Purpose

SLO configuration, performance metrics, alerting, and troubleshooting workflows for Application Signals.

## Performance Metrics Reference

- **Request**: RequestCount, SuccessCount (< 400), FaultCount (>= 500), ErrorCount (400-499)
- **Latency**: Duration, P50, P90, P95, P99, P99.9
- **Rate**: ErrorRate = (ErrorCount / RequestCount) * 100, FaultRate, SuccessRate
- **Throughput**: RequestsPerSecond = RequestCount / time_window, BytesIn, BytesOut

## SLO Configuration Best Practices

**Availability**: High-availability = 99.95% over 30 days (alert when error budget < 20%). Standard = 99.9% over 7 days.

**Latency**: User-facing API = 95% of requests < 500ms over 7 days (P95). Background processing = 99% of jobs < 30s over 30 days (P99).

### Custom SLOs

**Data freshness**: 99% of updates < 5 minutes old over 24h, custom metric (data_age).

## Performance Troubleshooting Workflows

### Workflow 1: High Error Rate

1. Identify service with high error rate and get error breakdown by operation
2. Sample error traces; analyze patterns: 4xx = input/auth issues, 5xx = bugs/dependency failures
3. Check dependencies, recent deployments, and CloudWatch Logs

```
fields @timestamp, endpoint, statusCode, errorType
| filter statusCode >= 400
| stats count(*) as errorCount by endpoint, statusCode
| sort errorCount desc
| limit 20
```

### Workflow 2: Increased Latency

1. Compare current P95/P99 vs baseline; identify slow operations
2. Analyze slow traces (which spans, downstream services, DB queries)
3. Check for increased load, code changes, dependency issues, resource constraints

```
fields @timestamp, endpoint, duration
| filter ispresent(duration)
| stats count(*) as requestCount,
        avg(duration) as avgDuration,
        pct(duration, 95) as p95,
        pct(duration, 99) as p99,
        max(duration) as maxDuration
  by endpoint
| sort p95 desc
| limit 20
```

### Workflow 3: SLO Breach Investigation

1. Identify which SLO was breached and when
2. Get metrics during breach period (error rate spike, latency increase, traffic surge)
3. Check correlated events: deployments (CloudTrail), infrastructure changes, dependency failures
4. Review traces from breach period, document root cause, update runbooks

## Alerting Configuration

**Critical**: ErrorRate > 5% (5 min, 3/5 datapoints, page on-call) | P99 > 2000ms (10 min, 2/2, notify team) | Error budget < 20% (1 hour, notify + feature freeze)

**Warning**: ErrorRate > 1% (15 min, notify channel) | P95 > 1000ms (15 min, log to monitoring)

## Best Practices

- **Instrumentation**: X-Ray SDK for custom instrumentation; environment in service names; consistent naming
- **SLO Management**: Start realistic (99% before 99.99%); align with business needs; review quarterly
- **Trace Sampling**: Adaptive for high-volume; always capture errors; 100% during incidents
- **Metric Collection**: Monitor P50/P95/P99; track 4xx vs 5xx; measure volume trends
- **Baselines**: Establish normal latency baselines; document expected error rates; track seasonal patterns

## Common Performance Patterns

| Pattern               | Symptom                     | Solution                               |
| --------------------- | --------------------------- | -------------------------------------- |
| Cold Start Impact     | High P99, large P50-P99 gap | Provisioned concurrency, keep-alive    |
| DB Connection Pooling | Latency increases with load | Connection pooling, query optimization |
| Cascading Failures    | Multiple services erroring  | Circuit breakers, timeouts, bulkheads  |
| Cache Invalidation    | Periodic latency spikes     | Optimize cache strategy, cache warming |
| Traffic Bursts        | Error rate up during peaks  | Auto-scaling, rate limiting, queues    |

## Quick Reference Commands

- **Service health**: `audit_services(...)` with `Name: "*"`
- **Slow request**: `search_transaction_spans(...)` with `FILTER ... and duration > 5000 | LIMIT 20`
- **Dependencies**: `audit_services(..., auditors="dependency_metric,trace")`
- **SLO monitor**: `audit_slos(...)` then `get_slo(...)` then if breached: add `auditors="all"`
