# Application Signals Performance Monitoring

## Purpose

Guidance for using AWS CloudWatch Application Signals to monitor application performance, health, and dependencies. For trace analysis and query patterns, see `performance-traces.md`. For SLO configuration and troubleshooting, see `performance-slos.md`.

## Application Signals Overview

Application Signals provides automatic instrumentation with service-level metrics (latency, error rate, volume), distributed tracing via X-Ray, service maps, SLOs, and automatic discovery requiring no code changes.

## Core Concepts

- **Services**: Logical components (microservices, Lambda functions, API endpoints, DB connections)
- **Operations**: Actions within a service (API endpoints, DB queries, external calls, queue ops)
- **SLOs**: Expected performance targets (availability %, latency thresholds, custom metrics)
- **Traces**: End-to-end request flows with trace IDs, spans, annotations, and subsegments

## Common Monitoring Tasks

1. **View Service Health**: List services by time range/status; check request count, error rate, P99 latency
2. **Analyze Dependencies**: Get service map over 24h; look for downstream/upstream bottlenecks
3. **Investigate Issues**: Compare current vs baseline latency, filter slow traces, check dependencies
4. **Set Up SLOs**: Define availability (99.9% over 30d) and latency targets (95% under 500ms over 7d)

## Application Signals MCP Server Tools

**Primary Audit Tools**: `audit_services` (service health with wildcards), `audit_slos` (SLO compliance), `audit_service_operations` (operation-level analysis)

**Service Discovery**: `list_monitored_services`, `get_service_detail`, `list_service_operations` (max 24h lookback)

**SLO Management**: `list_slos`, `get_slo`, `list_slis` (legacy SLI breach summary)

**Metrics**: `query_service_metrics` (Latency, Error, Fault for a service)

**Trace & Log Analysis**: `search_transaction_spans` (100% sampled, Logs Insights), `query_sampled_traces` (5% sampled, X-Ray filters)

**Canary, Change Events & Enablement**: `analyze_canary_failures`, `list_change_events` (`comprehensive_history=True` for ListEntityEvents API or `False` for ListServiceStates), `get_enablement_guide`

## Target Format Reference

**All services:**

```json
[{ "Type": "service", "Data": { "Service": { "Type": "Service", "Name": "*" } } }]
```

**Wildcard pattern:**

```json
[{ "Type": "service", "Data": { "Service": { "Type": "Service", "Name": "*payment*" } } }]
```

**Specific service:**

```json
[{
  "Type": "service",
  "Data": {
    "Service": { "Type": "Service", "Name": "checkout-service", "Environment": "eks:prod-cluster" }
  }
}]
```

**All SLOs:**

```json
[{ "Type": "slo", "Data": { "Slo": { "SloName": "*" } } }]
```

**Operation targets:**

```json
[{
  "Type": "service_operation",
  "Data": {
    "ServiceOperation": {
      "Service": { "Type": "Service", "Name": "*payment*" },
      "Operation": "*GET*",
      "MetricType": "Latency"
    }
  }
}]
```

MetricType options: `Latency`, `Availability`, `Fault`, `Error`

## Auditor Selection Guide

| Scenario                 | Auditors                           |
| ------------------------ | ---------------------------------- |
| Quick health check       | Default (omit parameter)           |
| Root cause analysis      | `all`                              |
| SLO breach investigation | `all`                              |
| Error investigation      | `log,trace`                        |
| Dependency issues        | `dependency_metric,trace`          |
| Find outlier hosts       | `top_contributor,operation_metric` |
| Quota monitoring         | `service_quota,operation_metric`   |

The 7 auditor types: `slo`, `operation_metric`, `trace`, `log`, `dependency_metric`, `top_contributor`, `service_quota`
