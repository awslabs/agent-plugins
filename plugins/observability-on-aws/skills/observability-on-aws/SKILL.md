---
name: observability-on-aws
description: "Comprehensive AWS observability platform combining CloudWatch Logs, Metrics, Alarms, Application Signals (APM), CloudTrail security auditing, Billing & Cost Management, and automated codebase observability gap analysis. Triggers on phrases like: CloudWatch logs, metrics, alarms, monitoring, observability, application signals, APM, distributed tracing, performance, latency, errors, troubleshooting, root cause analysis, security audit, CloudTrail, log analysis, alerting, SLO, incident response, observability gaps, missing instrumentation, AWS costs, billing, cost anomaly."
---

# AWS Observability

Requires AWS CLI credentials. All stdio MCP servers use `AWS_PROFILE` and `AWS_REGION` from their env config (defaults: `default` profile, `us-east-1`).

## Capabilities

| Capability                  | MCP Server                                         | Use When                                                 |
| --------------------------- | -------------------------------------------------- | -------------------------------------------------------- |
| CloudWatch Logs             | `awslabs.cloudwatch-mcp-server`                    | Log queries, pattern detection, anomaly analysis         |
| Metrics & Alarms            | `awslabs.cloudwatch-mcp-server`                    | Metric data, alarm recommendations, trend analysis       |
| Application Signals (APM)   | `awslabs.cloudwatch-applicationsignals-mcp-server` | Service health, SLOs, distributed tracing, error budgets |
| CloudTrail Security         | `awslabs.cloudtrail-mcp-server`                    | IAM changes, resource deletions, compliance audits       |
| Billing & Cost Management   | `awslabs.billing-cost-management-mcp-server`       | Cost analysis, forecasting, Compute Optimizer, budgets   |
| AWS Documentation           | `awsknowledge` (HTTP)                              | Troubleshooting, best practices, API references          |
| Codebase Observability Gaps | _(file analysis, no MCP)_                          | Identify missing logging, metrics, tracing in code       |

## Workflow Decision Tree

**User reports an incident or error?**
-> Load [Incident Response](references/incident-response.md). Start with `audit_services` wildcard, then correlate alarms + logs + traces + CloudTrail changes.

**User asks about logs or wants to query logs?**
-> Load [Log Analysis](references/log-analysis.md). Use `execute_log_insights_query`. Always include `| limit` in queries.

**User wants to set up or tune alarms?**
-> Load [Alerting Setup](references/alerting-setup.md). Use `get_recommended_metric_alarms` for best-practice thresholds.

**User asks about service performance, latency, or SLOs?**
-> Load [Performance Monitoring](references/performance-monitoring.md). Start with `audit_services`, then `search_transaction_spans` for 100% trace visibility.

**User needs security audit or compliance review?**
-> Load [Security Auditing](references/security-auditing.md). Follow data source priority: CloudTrail Lake > CloudWatch Logs > Lookup Events API.

**User wants to assess codebase observability?**
-> Load [Observability Gap Analysis](references/observability-gap-analysis.md). Analyze logging, metrics, tracing, error handling, health checks.

**User setting up Application Signals for the first time?**
-> Load [Application Signals Setup](references/application-signals-setup.md). Start with `get_enablement_guide`.

**Need prerequisites or configuration help?**
-> Load [Prerequisites and Configuration](references/prerequisites.md) for IAM permissions, MCP server setup, and AWS credential configuration.

## Essential Log Query Patterns

### Error Search

```
fields @timestamp, @message, @logStream, level
| filter level = "ERROR"
| sort @timestamp desc
| limit 100
```

### Performance Analysis

```
stats count() as requestCount,
      avg(duration) as avgDuration,
      pct(duration, 95) as p95Duration,
      pct(duration, 99) as p99Duration
by endpoint
| filter requestCount > 10
| sort p95Duration desc
| limit 100
```

### Error Rate Over Time

```
stats count() as total,
      sum(statusCode >= 500) as errors,
      (sum(statusCode >= 500) / count()) * 100 as errorRate
by bin(5m) as timeWindow
| sort timeWindow
```

## Key Tool Entry Points

- **Application Signals**: Start with `audit_services` using `[{"Type":"service","Data":{"Service":{"Type":"Service","Name":"*"}}}]` for wildcard discovery
- **Logs**: Use `describe_log_groups` to discover groups, then `execute_log_insights_query`
- **Metrics**: Use Sum for count metrics, Average for utilization, percentiles for latency
- **CloudTrail**: Check Lake first (`list_event_data_stores`), fall back to CloudWatch Logs, then `lookup_events`
- **Costs**: Use `cost-explorer` tool for spend analysis, `compute-optimizer` for right-sizing
