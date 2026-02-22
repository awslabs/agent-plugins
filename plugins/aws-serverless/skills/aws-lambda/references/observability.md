# Observability Guide

## Strategy

Serverless observability relies on three pillars — logs, metrics, and traces — but the approach differs from traditional infrastructure. There are no servers to SSH into, functions are distributed by nature, and cold starts create visibility gaps. Every function should emit structured logs, publish custom metrics, and participate in distributed traces from day one.

Use AWS Lambda Powertools as the consistent instrumentation layer across all functions. It handles Logger, Tracer, and Metrics with minimal boilerplate. For installation and the full utilities reference, see [optimization.md](optimization.md).

### Decorator Stacking Order

When combining multiple Powertools decorators on a single handler, order matters. Decorators execute outer-to-inner on invocation, inner-to-outer on return. Stack them in this order so that logging context is available first, metrics flush after business logic, and tracing wraps the entire execution:

**Python:**

```python
from aws_lambda_powertools import Logger, Metrics, Tracer

logger = Logger()
metrics = Metrics()
tracer = Tracer()

@logger.inject_lambda_context(correlation_id_path="requestContext.requestId")
@metrics.log_metrics(capture_cold_start_metric=True)
@tracer.capture_lambda_handler
def handler(event, context):
    # Logger context available first (outermost)
    # Tracer captures the full handler execution (innermost)
    # Metrics flush after handler returns (middle, on exit)
    ...
```

**TypeScript (middy middleware):**

```typescript
import { Logger, injectLambdaContext } from '@aws-lambda-powertools/logger';
import { Metrics, logMetrics } from '@aws-lambda-powertools/metrics';
import { Tracer, captureLambdaHandler } from '@aws-lambda-powertools/tracer';
import middy from '@middy/core';

const logger = new Logger();
const metrics = new Metrics();
const tracer = new Tracer();

const lambdaHandler = async (event: any, context: any) => {
  // Business logic
};

export const handler = middy(lambdaHandler)
  .use(injectLambdaContext(logger))
  .use(logMetrics(metrics))
  .use(captureLambdaHandler(tracer));
```

Middy middleware executes in registration order (top-to-bottom on request, bottom-to-top on response), achieving the same effect as the Python decorator stack.

## Structured Logging

Use structured JSON logging so CloudWatch Logs Insights can query across fields rather than parsing free-text messages.

**Required fields in every log entry:**

- `request_id` — Lambda request ID for correlating logs to a single invocation
- `function_name` — identifies which function emitted the log
- `level` — DEBUG, INFO, WARN, ERROR
- Business context (user ID, order ID, operation type) as fields, not embedded in message strings

**Python:**

```python
from aws_lambda_powertools import Logger

logger = Logger()  # Reads POWERTOOLS_SERVICE_NAME from env

@logger.inject_lambda_context(correlation_id_path="requestContext.requestId")
def handler(event, context):
    logger.info("Processing order", order_id=event["orderId"], amount=event["total"])
    # Output: {"level":"INFO","message":"Processing order","order_id":"ord-123",
    #          "amount":49.99,"request_id":"...","function_name":"...","correlation_id":"..."}
```

**TypeScript:**

```typescript
import { Logger } from '@aws-lambda-powertools/logger';
import type { Context } from 'aws-lambda';

const logger = new Logger();

export const handler = async (event: any, context: Context) => {
  logger.addContext(context);
  logger.info('Processing order', { orderId: event.orderId, amount: event.total });
};
```

**Log level strategy:**

| Environment | Level | Rationale                                                 |
| ----------- | ----- | --------------------------------------------------------- |
| Development | DEBUG | Full visibility during development                        |
| Staging     | INFO  | Verify behavior without noise                             |
| Production  | WARN  | Minimize log volume and cost; drop to INFO when debugging |

Set `LOG_LEVEL` or `POWERTOOLS_LOG_LEVEL` via environment variable — no code changes needed to adjust per environment.

Enable `POWERTOOLS_LOG_DEDUPLICATION_DISABLED=true` in test environments to prevent log deduplication issues with test frameworks.

## Distributed Tracing

X-Ray traces the execution path through your Lambda function and all downstream AWS SDK calls. Enable it globally in your SAM template:

```yaml
Globals:
  Function:
    Tracing: Active
```

**Python:**

```python
from aws_lambda_powertools import Tracer

tracer = Tracer()

@tracer.capture_lambda_handler
def handler(event, context):
    order = get_order(event["orderId"])
    return order

@tracer.capture_method
def get_order(order_id: str):
    tracer.put_annotation(key="orderId", value=order_id)
    tracer.put_metadata(key="orderSource", value="dynamodb")
    # Annotations are indexed and searchable in X-Ray console
    # Metadata is attached but not indexed
    return table.get_item(Key={"orderId": order_id})["Item"]
```

**TypeScript:**

```typescript
import { Tracer } from '@aws-lambda-powertools/tracer';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';

const tracer = new Tracer();
const client = tracer.captureAWSv3Client(
  DynamoDBDocumentClient.from(new DynamoDBClient({}))
);

export const handler = async (event: any, context: any) => {
  tracer.putAnnotation('orderId', event.orderId);

  const subsegment = tracer.getSegment()!.addNewSubsegment('processOrder');
  try {
    // Custom logic traced as a subsegment
  } finally {
    subsegment.close();
  }
};
```

**Key concepts:**

- **Annotations** — indexed key-value pairs you can filter on in the X-Ray console (e.g., find all traces for `orderId=ord-123`)
- **Metadata** — non-indexed data attached to a segment for debugging context
- **`captureAWSv3Client`** — automatically traces all AWS SDK calls (DynamoDB, S3, SQS, etc.) without manual subsegments
- **Subsegments** — wrap custom logic blocks to measure their duration separately
- **Cold start annotation** — add `ColdStart: true/false` as an annotation so you can filter X-Ray traces by cold start status and measure cold start impact on latency separately from warm invocations. Use the `capture_cold_start_metric=True` option on `@metrics.log_metrics` to track cold starts automatically via EMF metrics.

**Sampling rules:** X-Ray defaults to 1 request/second reservoir + 5% of additional requests. For high-throughput functions, this is usually sufficient. Lower the percentage if tracing costs are a concern. Configure custom rules via the X-Ray console or API.

**Limitation:** X-Ray trace context does **not** propagate across EventBridge, SQS, or SNS. The publisher and consumer appear as separate traces. Use correlation IDs (see below) to reconstruct cross-service request chains in logs.

## CloudWatch Application Signals

Application Signals provides APM-style capabilities on top of X-Ray, giving you service-level visibility without building custom dashboards or alarms from scratch. It uses the AWS Distro for OpenTelemetry (ADOT) Lambda layer to auto-instrument your functions.

**What it provides:**

- **Service dependency map** — visual topology showing how your Lambda functions connect to downstream services (DynamoDB, S3, SQS, other Lambda functions, external APIs)
- **Pre-built service dashboards** — per-service latency (p50, p90, p99), error rate, throughput, and fault breakdown without manual widget configuration
- **SLO tracking** — define Service Level Objectives (latency p99 < 500ms, availability > 99.9%) and monitor compliance over rolling windows
- **Anomaly detection** — automatic alerting when a service deviates from its learned baseline

**Enable via SAM template:**

```yaml
Globals:
  Function:
    Tracing: Active
    Layers:
      - !Sub arn:aws:lambda:${AWS::Region}:901920570463:layer:aws-otel-python-amd64-ver-1-25-0:1
    Environment:
      Variables:
        AWS_LAMBDA_EXEC_WRAPPER: /opt/otel-instrument
        OTEL_AWS_APPLICATION_SIGNALS_ENABLED: "true"
        OTEL_METRICS_EXPORTER: none
        OTEL_TRACES_SAMPLER: xray
```

Layer ARNs vary by runtime and architecture. Check the [ADOT Lambda layer documentation](https://aws-otel.github.io/docs/getting-started/lambda) for the correct ARN for your runtime (Python, Node.js, Java, .NET) and architecture (amd64, arm64).

**SLO configuration** happens in the CloudWatch console or via API after deployment — define SLIs (latency percentile, error rate, availability) and set objectives with burn rate alerting.

**When to use Application Signals vs plain X-Ray:**

| Scenario                               | Recommendation                                                 |
| -------------------------------------- | -------------------------------------------------------------- |
| Single function, basic tracing         | X-Ray with Powertools Tracer                                   |
| Multi-service system, need service map | Application Signals                                            |
| SLO tracking and compliance reporting  | Application Signals                                            |
| Custom trace annotations and filtering | X-Ray with Powertools Tracer (complements Application Signals) |

Application Signals and Powertools Tracer are complementary — ADOT handles auto-instrumentation and service-level metrics, while Powertools adds custom annotations, metadata, and fine-grained subsegments. Use both together for full coverage.

**Pricing:** Application Signals charges per service signal ingested. For low-traffic services the cost is negligible; for high-throughput services, review the [Application Signals pricing page](https://aws.amazon.com/cloudwatch/pricing/) and use X-Ray sampling rules to control trace volume.

## Custom Metrics

**Use Embedded Metric Format (EMF)** instead of calling `cloudwatch:PutMetricData`. EMF writes metrics as structured log entries that CloudWatch parses asynchronously — zero latency overhead and no extra API cost.

**Python:**

```python
from aws_lambda_powertools import Metrics
from aws_lambda_powertools.metrics import MetricUnit

metrics = Metrics()  # Reads POWERTOOLS_METRICS_NAMESPACE from env

@metrics.log_metrics(capture_cold_start_metric=True)
def handler(event, context):
    metrics.add_dimension(name="environment", value="prod")
    metrics.add_metric(name="OrdersProcessed", unit=MetricUnit.Count, value=1)
    metrics.add_metric(name="OrderTotal", unit=MetricUnit.Count, value=event["total"])
```

**TypeScript:**

```typescript
import { Metrics, MetricUnit } from '@aws-lambda-powertools/metrics';

const metrics = new Metrics();

export const handler = async (event: any) => {
  metrics.addDimension('environment', 'prod');
  metrics.addMetric('OrdersProcessed', MetricUnit.Count, 1);
  metrics.addMetric('OrderTotal', MetricUnit.Count, event.total);
  metrics.publishStoredMetrics();
};
```

**Dimensions:** Standard dimensions should include service name and environment. Avoid high-cardinality dimensions (user IDs, request IDs) — each unique combination creates a separate CloudWatch metric and incurs cost.

**Resolution:** Standard resolution (60-second aggregation) is appropriate for most use cases. Use high resolution (1-second) only for latency-sensitive SLAs where you need sub-minute granularity.

`capture_cold_start_metric=True` (Python) automatically publishes a `ColdStart` metric so you can track cold start frequency without manual instrumentation.

### Technical Metrics vs Business KPIs

Distinguish between **technical metrics** (errors, duration, throttles) and **business KPI metrics** (orders processed, revenue, user signups). Both are emitted via EMF, but they serve different audiences and alarm strategies.

**Technical metrics** are infrastructure-facing — they tell you whether the system is healthy. AWS provides most of these automatically; you supplement with custom metrics for gaps (e.g., cold start count).

**Business KPI metrics** are product-facing — they tell you whether the system is doing its job. These must be explicitly instrumented:

```python
# Technical metric — system health
metrics.add_metric(name="OrderProcessingErrors", unit=MetricUnit.Count, value=1)

# Business KPI metric — product health
metrics.add_metric(name="OrdersPlaced", unit=MetricUnit.Count, value=1)
metrics.add_metric(name="OrderRevenue", unit=MetricUnit.Count, value=order["total"])
```

**Alarm differently:** Technical metric alarms page the on-call engineer. Business KPI alarms (e.g., orders drop to zero) should notify the product team and may indicate a business issue rather than an infrastructure failure.

**Metric aggregation limit:** CloudWatch EMF supports up to 100 metrics per log entry. If a single invocation emits more than 100 metrics, split them across multiple EMF blobs by calling `metrics.publish_stored_metrics()` (Python) or `metrics.publishStoredMetrics()` (TypeScript) mid-handler, then continuing to add metrics.

## CloudWatch Alarms

### Lambda Metrics

| Metric                 | What it means                      | Recommended alarm          |
| ---------------------- | ---------------------------------- | -------------------------- |
| `Errors`               | Invocations that returned an error | Error rate > 1% over 5 min |
| `Duration` (p90)       | Latency affecting most users       | p90 > 1.5x your baseline   |
| `Duration` (p99)       | Latency outliers                   | p99 > 3x your baseline     |
| `Throttles`            | Rejected due to concurrency limits | > 0                        |
| `ConcurrentExecutions` | Current concurrent invocations     | > 80% of account limit     |

Use **p90 for early warning** (catches widespread degradation) and **p99 for tail latency** (catches outlier slowness). Alert on p90 first — if p90 is breaching, most users are affected.

### Event Source Metrics

| Metric                                   | What it means                                | Alarm |
| ---------------------------------------- | -------------------------------------------- | ----- |
| `IteratorAge` (streams)                  | Lag between record production and processing | > 60s |
| DLQ `ApproximateNumberOfMessagesVisible` | Messages that exhausted retries              | > 0   |

### EventBridge Metrics

| Metric                  | What it means                                | Alarm             |
| ----------------------- | -------------------------------------------- | ----------------- |
| `FailedInvocations`     | Target invocations that failed after retries | > 0               |
| `ThrottledRules`        | Rules throttled due to target limits         | > 0               |
| `DeadLetterInvocations` | Events sent to DLQ                           | > 0               |
| `MatchedEvents`         | Events that matched a rule                   | Anomaly detection |

### Alarm Best Practices

- Use **anomaly detection** for functions with variable traffic instead of static thresholds — CloudWatch learns the expected pattern and alerts on deviations
- Use **composite alarms** to reduce alert fatigue — combine multiple signals (e.g., error rate AND duration spike) before paging
- Set alarm actions to SNS for notifications; chain SNS → Lambda for auto-remediation (e.g., increase reserved concurrency on throttle alarm)
- Use `get_metrics` to retrieve current values before setting thresholds — base alarms on observed behavior, not guesses

## CloudWatch Logs Insights

Useful queries for serverless debugging and analysis.

**Trace a correlation ID across services:**

```text
fields @timestamp, @message
| filter @message like /corr-id-value/
| sort @timestamp asc
```

Run this query across multiple log groups simultaneously to follow a request through the entire service chain.

**Cold start frequency:**

```text
filter @message like /REPORT/ and @message like /Init Duration/
| stats count() as coldStarts, avg(@initDuration) as avgInitMs by bin(1h)
```

**Error patterns:**

```text
filter @message like /ERROR/
| stats count() as errors by @message
| sort errors desc
| limit 20
```

**Duration percentiles over time:**

```text
filter @type = "REPORT"
| stats avg(@duration) as avgMs, pct(@duration, 99) as p99Ms by bin(5m)
```

**Slowest invocations:**

```text
filter @type = "REPORT"
| sort @duration desc
| limit 10
```

## Lambda Insights

Lambda Insights provides enhanced monitoring with per-function CPU utilization, memory usage, network throughput, and disk I/O — metrics that standard Lambda monitoring does not expose.

**Enable via SAM template:**

```yaml
Globals:
  Function:
    Layers:
      - !Sub arn:aws:lambda:${AWS::Region}:580247275435:layer:LambdaInsightsExtension:53
    Policies:
      - CloudWatchLambdaInsightsExecutionRolePolicy
```

**When to use:**

- Diagnosing memory leaks (memory usage grows across invocations)
- Identifying CPU-bound functions that need more memory (and thus more CPU)
- Network bottlenecks from slow downstream calls
- Understanding disk I/O patterns for `/tmp`-heavy workloads

**Pricing:** Lambda Insights writes performance log events to CloudWatch Logs and publishes enhanced metrics — you pay standard CloudWatch Logs ingestion and metrics pricing based on invocation volume. Enable selectively for functions you are actively troubleshooting, not across all functions by default.

## Dashboards

### Two-Tier Dashboard Strategy

Build two dashboards per service, each serving a different audience:

**High-level dashboard** (for SREs, managers, stakeholders):

- Overall error rate and availability (SLO compliance)
- Business KPI trends (orders placed, revenue, active users)
- Cross-service health summary (one row per service: green/yellow/red)
- Time range: 24 hours or 7 days

**Low-level dashboard** (for developers debugging issues):

- Per-function: Errors, Duration p90/p99, ConcurrentExecutions, Throttles, ColdStarts
- Per-API: 4xx rate, 5xx rate, Latency p99, Request count
- Per-table: ThrottledReadRequests, ThrottledWriteRequests, ConsumedReadCapacityUnits
- Per-stream: IteratorAge, GetRecords.IteratorAgeMilliseconds
- Time range: 1 hour or 3 hours

The high-level dashboard answers "is the system healthy?" The low-level dashboard answers "why is the system unhealthy?"

### Dashboard as Code

**SAM template:**

```yaml
ServerlessDashboard:
  Type: AWS::CloudWatch::Dashboard
  Properties:
    DashboardName: !Sub "${AWS::StackName}-health"
    DashboardBody: !Sub |
      {
        "widgets": [
          {
            "type": "metric",
            "properties": {
              "metrics": [
                ["AWS/Lambda", "Errors", "FunctionName", "${MyFunction}", {"stat": "Sum"}],
                ["AWS/Lambda", "Duration", "FunctionName", "${MyFunction}", {"stat": "p99"}],
                ["AWS/Lambda", "Throttles", "FunctionName", "${MyFunction}", {"stat": "Sum"}]
              ],
              "period": 300,
              "region": "${AWS::Region}",
              "title": "Lambda Health"
            }
          }
        ]
      }
```

## Correlation ID Propagation

X-Ray traces break at async boundaries (EventBridge, SQS, SNS). Propagate a `correlationId` through event metadata to reconstruct the full request chain in logs.

**Pattern:** The producing function generates or forwards a correlation ID. The consuming function extracts it and injects it into Logger. All log entries from both functions share the same correlation ID, queryable via Logs Insights.

**Producer (Python):**

```python
import json
import boto3
from aws_lambda_powertools import Logger

logger = Logger()
events_client = boto3.client("events")

@logger.inject_lambda_context
def handler(event, context):
    events_client.put_events(Entries=[{
        "Source": "orders.service",
        "DetailType": "OrderPlaced",
        "EventBusName": "my-app-bus",
        "Detail": json.dumps({
            "metadata": {
                "correlationId": logger.get_correlation_id() or context.aws_request_id,
            },
            "data": {"orderId": "ord-123", "total": 49.99},
        }),
    }])
```

**Consumer (Python):**

```python
from aws_lambda_powertools import Logger

logger = Logger()

@logger.inject_lambda_context(correlation_id_path="detail.metadata.correlationId")
def handler(event, context):
    logger.info("Processing event")
    # Every log entry now includes correlation_id from the producer
```

This pattern works identically for SQS (inject in message attributes) and SNS (inject in message attributes). The key is consistency: always inject `correlationId` in the same location so consumers can extract it with a predictable path.

For the event envelope structure (including `correlationId`, `domain`, `service` fields), see the Event Envelopes section in [event-driven-architecture.md](event-driven-architecture.md).

## Environment Variables

| Variable                       | Purpose                                     |
| ------------------------------ | ------------------------------------------- |
| `POWERTOOLS_SERVICE_NAME`      | Service name for Logger, Tracer, Metrics    |
| `POWERTOOLS_LOG_LEVEL`         | Log level (DEBUG, INFO, WARN, ERROR)        |
| `POWERTOOLS_METRICS_NAMESPACE` | CloudWatch Metrics namespace                |
| `POWERTOOLS_DEV`               | Enable verbose output for local development |

Set these in the `Globals.Function.Environment.Variables` section of your SAM template. `POWERTOOLS_SERVICE_NAME` and `POWERTOOLS_METRICS_NAMESPACE` are required for Metrics; Logger and Tracer will use `POWERTOOLS_SERVICE_NAME` but fall back to the function name if unset.

## Cost Management

Observability has a cost. Manage it deliberately.

**Log retention:** Set CloudWatch log retention per environment — don't pay to store debug logs forever.

| Environment | Retention | Rationale                     |
| ----------- | --------- | ----------------------------- |
| Development | 7 days    | Short-lived debugging         |
| Staging     | 30 days   | Enough for release validation |
| Production  | 90 days   | Incident investigation window |
| Compliance  | 365+ days | Regulatory requirements       |

```yaml
MyFunctionLogGroup:
  Type: AWS::Logs::LogGroup
  Properties:
    LogGroupName: !Sub "/aws/lambda/${MyFunction}"
    RetentionInDays: 90
```

**X-Ray sampling:** The default (1 req/sec + 5%) is fine for most workloads. For functions processing thousands of requests per second, the 5% creates significant trace volume. Create a custom sampling rule with a lower fixed rate.

**Metrics cardinality:** Every unique combination of dimensions creates a separate CloudWatch metric. A dimension with 10,000 unique values (like `userId`) creates 10,000 metrics. Use annotations in X-Ray traces for high-cardinality identifiers, not metric dimensions.

**Lambda Insights:** Adds CloudWatch Logs ingestion and metrics costs per enabled function. The cost scales with invocation volume, so high-throughput functions cost more. Enable for functions you're actively investigating, disable when done.
