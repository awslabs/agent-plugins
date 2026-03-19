# Application Signals Trace Analysis

## Purpose

Transaction search patterns, X-Ray filter expressions, and distributed tracing analysis for Application Signals performance monitoring.

## Transaction Search Query Patterns

Use with `search_transaction_spans` (100% sampled, queries `aws/spans` log group):

**Error analysis:**

```
FILTER attributes.aws.local.service = "service-name"
  and attributes.http.status_code >= 400
| STATS count() as error_count by attributes.aws.local.operation
| SORT error_count DESC
| LIMIT 20
```

**Latency analysis:**

```
FILTER attributes.aws.local.service = "service-name"
| STATS avg(duration) as avg_latency, pct(duration, 99) as p99_latency
  by attributes.aws.local.operation
| SORT p99_latency DESC
| LIMIT 20
```

**Dependency calls:**

```
FILTER attributes.aws.local.service = "service-name"
| STATS count() as call_count, avg(duration) as avg_latency
  by attributes.aws.remote.service, attributes.aws.remote.operation
| SORT call_count DESC
| LIMIT 20
```

**GenAI token usage:**

```
FILTER attributes.aws.local.service = "service-name"
  and attributes.aws.remote.operation = "InvokeModel"
| STATS sum(attributes.gen_ai.usage.output_tokens) as total_tokens
  by attributes.gen_ai.request.model, bin(1h)
```

## X-Ray Filter Expressions

Use with `query_sampled_traces` (5% sampled):

```
service("service-name"){fault = true}
service("service-name") AND duration > 5
annotation[aws.local.operation]="GET /api/orders"
http.status = 500
service("api"){fault = true} AND annotation[aws.local.operation]="POST /checkout"
```

## Pagination (`next_token`) Guidance

Wildcard patterns process services/SLOs in batches (default: 5 per call). First call returns findings + `next_token` if more results exist. Continue with same parameters + `next_token` until no token is returned.

## Tool Usage Patterns

| Pattern               | Steps                                                                                                                                                      |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Health Check          | `audit_services(...)` with `Name: "*"` then add `auditors="all"` for issues                                                                                |
| Latency Investigation | `audit_service_operations(...)` with `MetricType: Latency` then `query_service_metrics(...)` then `search_transaction_spans(...)` with latency query above |
| Dependency Analysis   | `audit_services(..., auditors="dependency_metric,trace")` then `query_service_metrics(...)` per dependency                                                 |
| SLO Monitoring        | `audit_slos(...)` with `SloName: "*"` then `get_slo(...)` then `audit_slos(..., auditors="all")` for breaches                                              |

## Distributed Tracing Analysis

**What to look for**: Long spans (disproportionate time), sequential calls (parallelize), repeated operations (cache), external dependency latency, error spans (failed operations/exceptions).

**Common patterns**: N+1 queries (fix: batch/cache), sequential external calls (fix: parallelize), long cold starts > 1s (fix: provisioned concurrency), downstream timeouts (fix: circuit breaker/timeout tuning).

## Integration with CloudWatch Logs

Correlate Application Signals metrics with logs using Logs Insights:

```
fields @timestamp, @message, requestId, traceId, duration, level
| filter duration > 1000
| sort duration desc
| limit 100
```

## Integration with CloudTrail

Follow CloudTrail data source priority (see `cloudtrail-data-source-selection.md`): Lake event data stores (preferred), CloudWatch Logs integration, or Lookup Events API (fallback).
