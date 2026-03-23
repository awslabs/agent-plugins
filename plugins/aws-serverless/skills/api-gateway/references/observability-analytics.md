# Observability: Analytics and Operations

## CloudWatch Logs Insights Queries

### Find 5xx Errors

```
fields @timestamp, status, requestId, ip, resourcePath, integrationLatency
| filter status >= 500
| sort @timestamp desc
| limit 100
```

### Latency Analysis

```
fields @timestamp, responseLatency, integrationLatency, resourcePath
| stats avg(responseLatency) as avgLatency, max(responseLatency) as maxLatency,
        avg(integrationLatency) as avgIntegration by resourcePath
| sort avgLatency desc
```

### Top Talkers

```
fields ip
| stats count(*) as requestCount by ip
| sort requestCount desc
| limit 20
```

### Per-Domain Analytics

```
filter domainName like /(?i)(api.example.com)/
| stats count(*) as requests, avg(responseLatency) as avgLatency by resourcePath
| sort requests desc
```

### Diagnose 403 Errors by Phase

```
fields @timestamp, requestId, ip, resourcePath
| filter status = 403
| stats count(*) as cnt
    by coalesce(`waf-status`, "-") as waf,
       coalesce(`authenticate-status`, "-") as authn,
       coalesce(`authorizer-status`, "-") as authzr,
       coalesce(`authorize-status`, "-") as authz
| sort cnt desc
```

### Find Specific Gateway Response Types

```
fields @timestamp, requestId, `error-responseType`, `error-message`, status
| filter ispresent(`error-responseType`)
| stats count(*) as cnt by `error-responseType`
| sort cnt desc
```

## Additional Monitoring Tools

- **CloudWatch Synthetics**: Canaries for synthetic monitoring of endpoints on schedule
- **CloudWatch Application Insights**: Automated dashboards for problem detection
- **CloudWatch Contributor Insights**: Find top talkers and contributors; pre-built sample rules for API Gateway
- **CloudWatch Dashboards**: Include dashboard definitions in IaC templates
- **CloudWatch ServiceLens**: Integrates traces, metrics, logs, alarms, resource health

## CloudWatch Embedded Metrics Format

- Include metric data in structured logs sent to CloudWatch Logs
- CloudWatch extracts metrics automatically (**cheaper than PutMetricData API**)
- Use for custom business metrics (e.g., orders per minute, revenue per endpoint)
- Include dashboard definitions in IaC templates with both operational and business metrics

## AI-Assisted Operations

- **CloudWatch AI Operations**: Specify a time window, it correlates logs across services and generates root cause hypothesis
- **Amazon Q CLI**: Natural language troubleshooting ("Why do I see increased 500 errors from API Gateway in this stack?")
- **CloudWatch Logs Insights**: Supports natural language to query translation and auto-generated pattern summaries

## API Analytics Pipeline

For deep analytics beyond CloudWatch dashboards:

1. Stream access logs via Amazon Data Firehose
2. Enrich with Lambda transformation (add business context, geo-IP lookup)
3. Store in S3 (partitioned by date/API/stage)
4. Query with Amazon Athena
5. Visualize with Amazon QuickSight

**Cost tip**: Firehose-to-S3 ingestion (~$0.029/GB) is significantly cheaper than CloudWatch Logs ingestion (~$0.50/GB). For high-volume APIs, stream access logs to Firehose instead of CloudWatch Logs and query with Athena. Use CloudWatch Logs for execution logs (lower volume) and real-time Logs Insights queries.

## Cross-Account and Centralized Logging

For multi-account AWS Organizations setups:

1. **CloudWatch cross-account observability**: Use Observability Access Manager (OAM) to share metrics, logs, and traces from source accounts to a central monitoring account. Enables unified dashboards and alarms across all API Gateways
2. **Subscription filters**: Stream access logs from each account to a central Kinesis Data Stream or Firehose in the monitoring account for aggregated analysis
3. **Consistent log group naming**: Use a standard naming convention across accounts (e.g., `/aws/apigateway/<account-alias>/<api-name>/access-logs`) to simplify cross-account queries and cost attribution

## CloudTrail

- Captures all API Gateway management calls as control plane events
- Does NOT log data plane events (actual API requests); use access logs for that
- Determines: request made, IP address, who made it, when
- Use for audit and compliance, not operational monitoring
- **Do not forget CloudTrail for control plane audit**: who changed API configuration and when
