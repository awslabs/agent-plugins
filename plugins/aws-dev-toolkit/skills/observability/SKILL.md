---
name: observability
description: Design and implement AWS observability solutions. Use when configuring CloudWatch metrics, logs, alarms, dashboards, Logs Insights queries, X-Ray tracing, anomaly detection, or debugging monitoring gaps.
allowed-tools: Read, Grep, Glob, Bash(aws *), mcp__plugin_aws-dev-toolkit_aws-docs__read_documentation, mcp__plugin_aws-dev-toolkit_aws-docs__search_documentation, mcp__plugin_aws-dev-toolkit_aws-docs__read_sections, mcp__plugin_aws-dev-toolkit_aws-docs__recommend
---

You are an AWS observability specialist. Design monitoring, logging, and tracing solutions using CloudWatch and X-Ray.

## CloudWatch Metrics

### Key Concepts
- **Namespace**: Grouping for metrics (e.g., `AWS/EC2`, `AWS/Lambda`, custom)
- **Metric**: Time-ordered set of data points (e.g., `CPUUtilization`)
- **Dimension**: Key-value pair that identifies a metric (e.g., `InstanceId=i-xxx`)
- **Period**: Aggregation interval (60s, 300s, etc.)
- **Statistic**: Aggregation function (Average, Sum, Min, Max, p99, etc.)

### Critical Metrics by Service

| Service | Metric | Alarm Threshold | Notes |
|---|---|---|---|
| Lambda | Errors | > 0 for 1 min | Also alarm on Throttles and Duration p99 |
| Lambda | ConcurrentExecutions | > 80% of account limit | Prevent throttling |
| ALB | HTTPCode_Target_5XX_Count | > 0 for 5 min | Backend errors |
| ALB | TargetResponseTime p99 | > your SLA | Latency SLO |
| ALB | UnHealthyHostCount | > 0 | Failing targets |
| RDS | CPUUtilization | > 80% for 5 min | Sustained high CPU |
| RDS | FreeStorageSpace | < 20% of total | Prevent disk full |
| RDS | DatabaseConnections | > 80% of max | Connection exhaustion |
| DynamoDB | ThrottledRequests | > 0 | Capacity issues |
| SQS | ApproximateAgeOfOldestMessage | > your processing SLA | Queue backlog |
| ECS | CPUUtilization / MemoryUtilization | > 80% for 5 min | Scaling trigger |

### Custom Metrics
- Use `PutMetricData` API or the CloudWatch Agent
- Embedded Metric Format (EMF) for Lambda: log structured JSON that CloudWatch automatically extracts as metrics. Zero API calls, no cost per PutMetricData.
- High-resolution metrics (1-second) cost more — use only when sub-minute granularity matters
- Metric math: combine metrics without publishing new ones (e.g., error rate = Errors / Invocations * 100)

## CloudWatch Logs

### Log Groups and Retention
- Set retention on every log group. The default is **never expire** — this gets expensive fast.
- Recommended: 30 days for dev, 90 days for production, archive to S3 for long-term
- Use subscription filters to stream logs to Lambda, Kinesis, or OpenSearch

### Structured Logging
Always log in JSON format. This enables Logs Insights queries on fields.

```json
{"level": "ERROR", "message": "Payment failed", "orderId": "123", "errorCode": "DECLINED", "duration_ms": 45}
```

### CloudWatch Logs Insights Queries

```
# Find errors in Lambda functions
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

# P99 latency from structured logs
fields @timestamp, duration_ms
| stats percentile(duration_ms, 99) as p99, avg(duration_ms) as avg_ms by bin(5m)

# Top 10 most frequent errors
fields @timestamp, errorCode, @message
| filter level = "ERROR"
| stats count(*) as error_count by errorCode
| sort error_count desc
| limit 10

# Request rate over time
fields @timestamp
| stats count(*) as requests by bin(1m)
| sort @timestamp desc

# Find slow requests
fields @timestamp, @duration, @requestId
| filter @duration > 5000
| sort @duration desc
| limit 20

# Cold starts in Lambda
filter @type = "REPORT"
| fields @requestId, @duration, @initDuration
| filter ispresent(@initDuration)
| stats count(*) as cold_starts, avg(@initDuration) as avg_init by bin(1h)

# API Gateway latency breakdown
fields @timestamp
| filter @message like /API Gateway/
| stats avg(integrationLatency) as backend_ms, avg(latency) as total_ms by bin(5m)
```

## CloudWatch Alarms

### Alarm Types
- **Static threshold**: Fixed value (e.g., CPU > 80%)
- **Anomaly detection**: ML-based band. Good for metrics with patterns (traffic, latency).
- **Composite alarm**: Combine multiple alarms with AND/OR logic. Reduces noise.

### Alarm Best Practices
- Use **3 out of 5 datapoints** evaluation to avoid flapping on transient spikes
- Set `TreatMissingData` to `notBreaching` for low-traffic services (avoids false alarms when no data)
- Set `TreatMissingData` to `breaching` for critical health checks (missing data = something is down)
- Use composite alarms to create "alarm hierarchies": a top-level alarm that fires only when multiple sub-alarms are in ALARM state
- Always send alarms to SNS. Connect SNS to PagerDuty, Slack, or email.

### Anomaly Detection
- Trains on 2 weeks of data. Do not enable during a known-bad period.
- Adjust the band width (number of standard deviations). Start with 2, widen if too noisy.
- Best for: request count, latency, error rate — metrics with daily/weekly patterns.
- Not good for: binary metrics, metrics that are normally zero.

## CloudWatch Dashboards

### Dashboard Design
- One dashboard per service or domain (not one giant dashboard)
- Top row: key business metrics (request rate, error rate, latency p99)
- Second row: infrastructure health (CPU, memory, connections)
- Third row: dependencies (downstream API latency, queue depth)
- Use metric math to show rates and percentages, not raw counts
- Add text widgets to document what each section monitors and what to do when values are abnormal

### Automatic Dashboards
- CloudWatch provides automatic dashboards per service — start there before building custom
- ServiceLens provides an application-centric view combining metrics, logs, and traces

## X-Ray Tracing

### When to Use X-Ray
- Distributed applications with multiple services
- Debugging latency issues across service boundaries
- Understanding request flow and dependencies

### Instrumentation
- AWS SDK automatically instruments calls to AWS services
- Use X-Ray SDK or OpenTelemetry to instrument your application code
- Set sampling rules to control trace volume (default: 1 req/sec + 5% of additional)

### Key X-Ray Concepts
- **Trace**: End-to-end request path
- **Segment**: A single service's processing of the request
- **Subsegment**: Detailed breakdown within a segment (DB call, HTTP call)
- **Service Map**: Visual representation of your architecture based on trace data
- **Annotations**: Indexed key-value pairs for filtering traces (e.g., `customerId=123`)
- **Metadata**: Non-indexed data attached to segments

### X-Ray Best Practices
- Add annotations for business-relevant fields (user ID, order ID) so you can filter traces
- Use groups to define filter expressions for specific trace sets
- Active tracing on API Gateway and Lambda captures the full request lifecycle
- X-Ray daemon runs as a sidecar in ECS or as a DaemonSet in EKS

## Contributor Insights

- Identifies top contributors to a metric (e.g., top IPs, top API callers)
- Define rules in JSON that specify log group + fields to analyze
- Good for: identifying noisy neighbors, DDoS sources, hot partition keys in DynamoDB

## Common CLI Commands

```bash
# Query Logs Insights
aws logs start-query --log-group-name /aws/lambda/my-function \
  --start-time $(date -d '1 hour ago' +%s) --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | limit 20'

# Get query results
aws logs get-query-results --query-id "query-id-here"

# Describe alarms in ALARM state
aws cloudwatch describe-alarms --state-value ALARM --query 'MetricAlarms[*].{Name:AlarmName,Metric:MetricName,State:StateValue}'

# Get metric statistics
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Errors \
  --start-time 2024-01-01T00:00:00Z --end-time 2024-01-01T01:00:00Z \
  --period 300 --statistics Sum --dimensions Name=FunctionName,Value=my-function

# Put custom metric
aws cloudwatch put-metric-data --namespace MyApp --metric-name RequestLatency \
  --value 42 --unit Milliseconds --dimensions Name=Environment,Value=prod

# List log groups with retention
aws logs describe-log-groups --query 'logGroups[*].{Name:logGroupName,RetentionDays:retentionInDays,StoredBytes:storedBytes}'

# Set log retention
aws logs put-retention-policy --log-group-name /aws/lambda/my-function --retention-in-days 30

# List X-Ray traces
aws xray get-trace-summaries --start-time $(date -d '1 hour ago' +%s) --end-time $(date +%s)

# Get X-Ray service map
aws xray get-service-graph --start-time $(date -d '1 hour ago' +%s) --end-time $(date +%s)

# List CloudWatch dashboards
aws cloudwatch list-dashboards
```

## Output Format

| Field | Details |
|-------|---------|
| **Metrics** | Critical alarms with thresholds, evaluation periods, and actions |
| **Logs** | Log groups, retention policy, structured format (JSON), subscription filters |
| **Traces** | X-Ray or OpenTelemetry, sampling rules, annotations for filtering |
| **Dashboards** | Dashboard names, key widgets, layout (business/infra/dependencies) |
| **Anomaly detection** | Metrics with anomaly detection bands, standard deviation config |
| **Cost** | Estimated monthly cost for logs ingestion, metrics, dashboards, and traces |

## Reference Files

- `references/logs-insights-queries.md` — Ready-to-use CloudWatch Logs Insights queries organized by service (Lambda, API Gateway, ECS, VPC Flow Logs, CloudFront, structured logs)
- `references/alarm-recipes.md` — Production alarm configurations with thresholds, metric math examples, composite alarm and anomaly detection recipes

## Related Skills

- `lambda` — Lambda metrics, Embedded Metric Format, and X-Ray active tracing
- `ecs` — Container Insights, task-level metrics, and ECS service alarms
- `eks` — Control plane logging, Prometheus, and Container Insights for Kubernetes
- `cloudfront` — CloudFront access logs and cache metrics
- `api-gateway` — API Gateway latency and error monitoring
- `networking` — VPC Flow Logs, Route53 health checks, and Transit Gateway metrics

## Anti-Patterns

- **No log retention policy**: CloudWatch Logs default to never expire. Costs grow silently. Set retention on every log group.
- **Alarming on every metric**: Too many alarms leads to alert fatigue. Alarm on symptoms (error rate, latency), not causes (CPU). Use composite alarms to reduce noise.
- **Average-based latency alarms**: Averages hide tail latency. Use p99 or p95 for latency alarms.
- **Missing structured logging**: Unstructured logs cannot be queried efficiently with Logs Insights. Always log JSON.
- **No tracing in distributed systems**: Without X-Ray or OpenTelemetry, debugging cross-service issues requires correlating timestamps across log groups. Enable tracing.
- **Sampling rate of 100%**: Full tracing in production generates enormous data volume and cost. Use sampling — 1 req/sec + 5% is usually sufficient.
- **Not using Embedded Metric Format in Lambda**: EMF turns log lines into metrics with zero PutMetricData API calls. It's cheaper and simpler than the alternatives.
- **Dashboard without runbook links**: A dashboard that shows a problem without explaining what to do about it is only half useful. Add text widgets with runbook links.
- **Ignoring CloudWatch anomaly detection**: Static thresholds don't work for metrics with daily patterns. Use anomaly detection for request count and latency.
- **CloudWatch Agent not installed on EC2**: Without the agent, you only get basic metrics (CPU, network, disk I/O). Install the agent for memory utilization, disk space, and custom metrics.
