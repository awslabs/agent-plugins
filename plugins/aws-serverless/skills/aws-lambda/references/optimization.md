# Optimization Guide

## Memory and CPU Right-Sizing

Lambda allocates CPU proportionally to memory. The goal is to find the configuration where cost-per-invocation is minimized while meeting latency requirements.

**Strategy:**

1. Use `get_metrics` to measure current duration, memory utilization, and invocation count
2. Test with different memory settings using AWS Lambda Power Tuning
3. Choose the memory level where cost (duration x memory price) is lowest

**General guidelines:**

- 128 MB: Lightweight tasks (routing, simple transformations)
- 512 MB: Standard API handlers, moderate data processing
- 1024 MB: Compute-intensive tasks, image processing
- 3008+ MB: ML inference, large data processing

**CPU scaling:** Lambda allocates CPU proportionally to memory. At **1,769 MB** a function has the equivalent of one full vCPU. Functions below this threshold share a single vCPU. If your function is CPU-bound, the optimal memory setting is often 1,769 MB or higher.

**arm64 (Graviton) savings:** arm64 is approximately **20% cheaper per GB-second** than x86_64 and typically provides equal or faster performance. This is the single easiest cost optimization for most functions. Use x86_64 only when you depend on x86-only native binaries — older Python C extension wheels (NumPy, Pandas pre-built for x86), Node.js native addons compiled for x86, or vendor-provided Lambda layers that ship only x86 binaries. Most pure-Python, pure-Node.js, and Java/Go/.NET workloads run on arm64 without changes.

### AWS Lambda Power Tuning

[Lambda Power Tuning](https://github.com/alexcasalboni/aws-lambda-power-tuning) is an open-source Step Functions state machine that automates memory/cost optimization. It invokes your function at multiple memory settings, measures duration and cost, and recommends the optimal configuration.

**How it works:**

1. Deploy the state machine into your AWS account (one-time setup)
2. Execute it with your function ARN and the memory values to test
3. It invokes your function N times at each memory setting, collects metrics
4. Returns the optimal memory size plus a visualization URL showing the cost/performance curve

**Deploy via SAR (simplest):**

```bash
aws serverlessrepo create-cloud-formation-change-set \
  --application-id arn:aws:serverlessrepo:us-east-1:451282441545:applications/aws-lambda-power-tuning \
  --stack-name lambda-power-tuning \
  --capabilities CAPABILITY_IAM
```

Or deploy via SAM CLI:

```bash
sam init --location https://github.com/alexcasalboni/aws-lambda-power-tuning
sam deploy --guided
```

**Run the state machine:**

```json
{
  "lambdaARN": "arn:aws:lambda:us-east-1:123456789012:function:my-function",
  "powerValues": [128, 256, 512, 1024, 1769, 3008],
  "num": 50,
  "payload": {}
}
```

| Parameter     | Description                                                |
| ------------- | ---------------------------------------------------------- |
| `lambdaARN`   | ARN of the function to tune                                |
| `powerValues` | Memory sizes (MB) to test — include 1769 (1 vCPU boundary) |
| `num`         | Invocations per memory setting (50-100 for stable results) |
| `payload`     | Event payload to pass to each invocation                   |

**Output:** The state machine returns the cheapest and fastest configurations with exact cost-per-invocation at each memory level. It also generates a visualization URL (data encoded client-side, nothing sent to external servers) showing the cost/performance tradeoff curve.

**When to use:**

- Before launching a new function to production — right-size from the start
- When `get_metrics` shows memory utilization is consistently very low or very high
- After significant code changes that affect compute profile
- Periodically (quarterly) for long-running production functions

## Cold Start Optimization

Cold starts affect latency on the first invocation after idle time or scaling events.

**Checklist:**

- [ ] Initialize SDK clients and database connections outside the handler function
- [ ] Use `lru_cache` or module-level variables for configuration that doesn't change
- [ ] Minimize deployment package size (exclude dev dependencies, use layers for shared code)
- [ ] Choose a fast-starting runtime (Python, Node.js) for latency-sensitive paths
- [ ] Consider `arm64` architecture for faster cold starts
- [ ] Use provisioned concurrency only for consistently latency-sensitive endpoints

**When to use provisioned concurrency:**

- API endpoints with strict latency SLAs
- Functions called synchronously where cold starts are user-visible
- Not recommended for asynchronous or batch processing workloads

## Lambda SnapStart

SnapStart reduces cold start latency by taking a snapshot of the initialized execution environment, then resuming from that snapshot on subsequent invocations. This provides sub-second startup performance with minimal code changes.

**Supported runtimes:** Java 11+, Python 3.12+, .NET 8+
**Not supported with:** provisioned concurrency, EFS, ephemeral storage > 512 MB, container images

**Enable in SAM template:**

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    Runtime: python3.12
    SnapStart:
      ApplyOn: PublishedVersions
```

SnapStart only works on **published versions**, not `$LATEST`. Always use an alias pointing to a published version.

**Critical — handle uniqueness correctly:**

```python
# WRONG: unique value captured in snapshot, reused across invocations
import uuid
CORRELATION_ID = str(uuid.uuid4())

# CORRECT: generate unique values inside the handler
def handler(event, context):
    correlation_id = str(uuid.uuid4())
```

**Re-establish connections on restore:** Use `lambda_runtime_api_prepare_to_invoke.py` (Python) runtime hooks to reconnect databases or refresh credentials after snapshot restoration — connection state is not guaranteed.

**When to use SnapStart vs provisioned concurrency:**

| Scenario                                   | Recommendation          |
| ------------------------------------------ | ----------------------- |
| Tolerate ~100–200 ms restore time          | SnapStart               |
| Require < 10 ms latency                    | Provisioned concurrency |
| Java/Python/.NET with heavy initialization | SnapStart               |
| Infrequently invoked functions             | Neither                 |

**Pricing:** Free for Java. Python and .NET incur a caching charge (minimum 3 hours) plus a restoration charge.

## Lambda Managed Instances

Lambda Managed Instances run your function on dedicated EC2 instances from your own account, while AWS still manages OS patching, load balancing, and auto-scaling. Unlike regular Lambda, each instance handles **multiple concurrent requests**, so your code must be thread-safe.

**When to use:**

- Consistent high-throughput workloads (hundreds to thousands of requests per second)
- Workloads that benefit from warm connection pools shared across concurrent requests
- Scenarios where cold starts must be eliminated at lower cost than provisioned concurrency

**When NOT to use:**

- Bursty or unpredictable traffic — instances take tens of seconds to launch (vs. seconds for regular Lambda)
- Low-volume applications
- Any code that is not thread-safe (module-level mutable state, non-reentrant libraries)

**Cost model:** EC2 instance cost + 15% premium + $0.20 per million requests. Compatible with existing EC2 Savings Plans. GPU instances are not supported.

**Configure via AWS CLI** (SAM template support may vary — check latest CloudFormation docs):

```bash
aws lambda create-function \
  --function-name my-function \
  --runtime python3.12 \
  --handler app.handler \
  --role arn:aws:iam::123456789012:role/my-role \
  --code S3Bucket=my-bucket,S3Key=my-code.zip \
  --compute-config '{"Mode": "ManagedInstances"}'
```

**Thread safety requirement:** Because multiple requests execute concurrently in the same environment, any module-level state must be read-only after initialization. Use connection pools designed for concurrent access (e.g., psycopg3 AsyncConnectionPool, SQLAlchemy async pools).

## Cost Optimization

### Decision Framework

| Scenario                 | Recommendation                                             |
| ------------------------ | ---------------------------------------------------------- |
| Unpredictable traffic    | On-demand billing, no provisioned concurrency              |
| Steady baseline + spikes | Provisioned concurrency for baseline, on-demand for spikes |
| Batch processing         | Maximize batch size, optimize memory for cost              |
| Infrequently called      | Minimize memory, accept cold starts                        |

### Key Cost Levers

- **Memory**: Lower memory is cheaper per-ms, but if it makes duration longer, net cost may increase
- **Timeout**: Set to actual max expected duration + buffer, not the maximum 900s
- **Reserved concurrency**: Caps maximum concurrent executions to prevent runaway costs
- **Storage**: Use S3 lifecycle policies to transition objects to cheaper tiers
- **Logs**: Set CloudWatch log retention to the minimum needed (7-30 days for dev, longer for prod/compliance)

## API Gateway Optimization

- Enable caching for read-heavy GET endpoints (0.5 GB cache is the minimum size)
- Use request validation at the gateway level to reject bad requests before invoking Lambda
- Use HTTP APIs (v2) instead of REST APIs when you don't need REST API-specific features (cheaper, lower latency)

## Response Streaming

Response streaming sends data to the client incrementally rather than buffering the complete response. This dramatically reduces time-to-first-byte (TTFB) for workloads where output is generated progressively.

### When to Use Streaming

| Scenario                               | Benefit                                                       |
| -------------------------------------- | ------------------------------------------------------------- |
| LLM/Bedrock responses                  | Users see tokens appear in real time instead of waiting       |
| Responses > 6 MB                       | Streaming bypasses the 6 MB sync payload limit (up to 200 MB) |
| Long-running operations (up to 15 min) | Keeps the HTTP connection alive and sends progress            |
| Large file/dataset delivery            | Stream directly without S3 pre-signed URL workarounds         |

### Lambda Side — `streamifyResponse`

Wrap your handler with `awslambda.streamifyResponse()` (Node.js runtime). Use `HttpResponseStream.from()` to attach HTTP metadata before writing to the stream.

```typescript
const streamingHandler = async (event: any, responseStream: NodeJS.WritableStream) => {
  const httpStream = awslambda.HttpResponseStream.from(responseStream, {
    statusCode: 200,
    headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' },
  });

  // Write tokens in Server-Sent Events format
  for await (const chunk of someStream) {
    httpStream.write(`data: ${JSON.stringify({ token: chunk })}\n\n`);
  }
  httpStream.write('data: [DONE]\n\n');
  httpStream.end();
};

export const handler = awslambda.streamifyResponse(streamingHandler);
```

**Runtime support:** Node.js only for `streamifyResponse`. Python and other runtimes can stream via Lambda Function URLs using a different mechanism.

### API Gateway REST API — Enable Streaming

API Gateway REST API response streaming requires two changes in your OpenAPI definition:

1. Use the `/response-streaming-invocations` Lambda ARN path (not `/invocations`)
2. Set `responseTransferMode: STREAM` on the integration

```yaml
# openapi.yaml
x-amazon-apigateway-integration:
  type: AWS_PROXY
  httpMethod: POST
  uri:
    Fn::Sub: "arn:aws:apigateway:${AWS::Region}:lambda:path/2021-11-15/functions/${MyFunction.Arn}/response-streaming-invocations"
  responseTransferMode: STREAM
  passthroughBehavior: when_no_match
```

Compare to the standard (non-streaming) path:

```yaml
# Standard (buffered) integration
uri:
  Fn::Sub: "arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${MyFunction.Arn}/invocations"
```

This feature is available on all endpoint types — regional, private, and edge-optimized.

### Lambda Function URLs — Enable Streaming

Function URLs also support streaming without API Gateway:

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    FunctionUrlConfig:
      AuthType: AWS_IAM
      InvokeMode: RESPONSE_STREAM   # default is BUFFERED
```

### Server-Sent Events (SSE) Pattern

For LLM and AI streaming, use SSE format — it's natively supported by browsers and easy to consume:

```text
data: {"token":"Hello"}\n\n
data: {"token":" world"}\n\n
data: [DONE]\n\n
```

Client-side consumption (JavaScript):

```javascript
const es = new EventSource('/streaming');
es.onmessage = (e) => {
  if (e.data === '[DONE]') { es.close(); return; }
  appendToken(JSON.parse(e.data).token);
};
```

### Key Limits

| Resource                               | Limit      |
| -------------------------------------- | ---------- |
| Max streamed response size             | 200 MB     |
| Standard (buffered) sync response      | 6 MB       |
| Max integration timeout with streaming | 15 minutes |

## DynamoDB Optimization

- Use single-table design with composite keys (PK/SK) for efficient access patterns
- Use `Query` instead of `Scan` wherever possible
- Project only needed attributes to reduce read capacity usage
- Use ON_DEMAND billing for unpredictable workloads, PROVISIONED with auto-scaling for steady workloads
- Use GSIs with KEYS_ONLY projection when you only need to look up primary keys

## Event Source Mapping Tuning

Use `esm_optimize` to get source-specific recommendations. General guidelines:

| Source           | Key Tuning Parameters                                                            |
| ---------------- | -------------------------------------------------------------------------------- |
| DynamoDB Streams | `BatchSize` (1-10000), `ParallelizationFactor` (1-10)                            |
| Kinesis          | `BatchSize` (1-10000), `ParallelizationFactor` (1-10), `TumblingWindowInSeconds` |
| SQS              | `BatchSize` (1-10000), `MaximumConcurrency`, `MaximumBatchingWindowInSeconds`    |
| Kafka/MSK        | `BatchSize` (1-10000), `MaximumBatchingWindowInSeconds`                          |

## Monitoring

For Lambda metrics, event source metrics, EventBridge metrics, alarm configuration, and dashboard setup, see [observability.md](observability.md). Use `get_metrics` to retrieve current values.

## AWS Lambda Powertools

Lambda Powertools is the recommended library for implementing observability and reliability patterns with minimal boilerplate. It is available for Python, TypeScript, Java, and .NET.

**Install:**

| Runtime    | Command                                                                                                     |
| ---------- | ----------------------------------------------------------------------------------------------------------- |
| Python     | `pip install aws-lambda-powertools`                                                                         |
| TypeScript | `npm i @aws-lambda-powertools/logger @aws-lambda-powertools/tracer @aws-lambda-powertools/metrics`          |
| Java       | Add `software.amazon.lambda:powertools-tracing`, `powertools-logging`, `powertools-metrics` to Maven/Gradle |
| .NET       | `dotnet add package AWS.Lambda.Powertools.Logging` (plus `.Tracing`, `.Metrics`)                            |

**SAM init templates:**

- Python: `sam init --app-template hello-world-powertools-python`
- TypeScript: `sam init --app-template hello-world-powertools-typescript`

**Core utilities:**

| Utility                       | What it does                                                                                                   |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **Logger**                    | Structured JSON logging with Lambda context automatically injected                                             |
| **Tracer**                    | X-Ray tracing with decorators; traces handler + downstream calls                                               |
| **Metrics**                   | Custom CloudWatch metrics via Embedded Metric Format (EMF) — async, no API call overhead                       |
| **Idempotency**               | Prevent duplicate execution using DynamoDB as idempotency store                                                |
| **Batch**                     | Partial batch failure handling for SQS, Kinesis, DynamoDB Streams                                              |
| **Parameters**                | Cached retrieval from SSM Parameter Store, Secrets Manager, AppConfig                                          |
| **Parser**                    | Event validation with typed models — Python uses Pydantic, TypeScript uses Zod                                 |
| **Feature Flags**             | Rule-based feature toggles backed by AppConfig                                                                 |
| **Event Handler**             | Route REST/HTTP API, GraphQL, and Bedrock Agent events with decorators (Python, TS, Java, .NET)                |
| **Kafka Consumer**            | Deserialize Kafka events (Avro, Protobuf, JSON Schema) for MSK and self-managed Kafka (Python, TS, Java, .NET) |
| **Data Masking**              | Redact or encrypt sensitive fields for compliance (Python, TS)                                                 |
| **Event Source Data Classes** | Typed data classes for all Lambda event sources (Python)                                                       |

**Use Embedded Metric Format (EMF) for custom metrics** — zero latency overhead and no extra API cost. See [observability.md](observability.md) for setup and code examples.

**Parameters caching** reduces cold start impact from secrets retrieval. The Parameters utility caches values for a configurable TTL (default 5 seconds), avoiding an API call on every invocation.

**Key environment variables:**

| Variable                        | Purpose                                                  |
| ------------------------------- | -------------------------------------------------------- |
| `POWERTOOLS_PARAMETERS_MAX_AGE` | Cache TTL in seconds for Parameters utility (default: 5) |

For observability environment variables (`POWERTOOLS_SERVICE_NAME`, `POWERTOOLS_LOG_LEVEL`, `POWERTOOLS_METRICS_NAMESPACE`, `POWERTOOLS_DEV`), see [observability.md](observability.md).

**Parser validation:** Python uses Pydantic models; TypeScript uses Zod schemas. Both provide compile-time type safety and runtime validation for Lambda event payloads.

## Structured Logging

For structured logging best practices, Logger setup (Python and TypeScript), log level strategy, and Logs Insights queries, see [observability.md](observability.md).

## Powertools Deep Dives

### Feature Flags

Use Feature Flags for runtime configuration changes without redeployment — percentage rollouts, user-targeted flags, and kill switches. The backend is AWS AppConfig, which supports deployment strategies (linear, canary, all-at-once) with automatic rollback.

**Python:**

```python
from aws_lambda_powertools.utilities.feature_flags import AppConfigStore, FeatureFlags

app_config = AppConfigStore(environment="prod", application="my-app", name="features")
feature_flags = FeatureFlags(store=app_config)

def handler(event, context):
    # Boolean flag with default
    dark_mode = feature_flags.evaluate(name="dark_mode", default=False)

    # Rules-based flag (percentage rollout, user targeting)
    new_checkout = feature_flags.evaluate(
        name="new_checkout",
        context={"username": event["requestContext"]["authorizer"]["claims"]["sub"]},
        default=False,
    )
```

**TypeScript:**

```typescript
import { AppConfigProvider } from '@aws-lambda-powertools/parameters/appconfig';
import { FeatureFlags } from '@aws-lambda-powertools/parameters/feature-flags';

const provider = new AppConfigProvider({
  environment: 'prod',
  application: 'my-app',
  name: 'features',
});
const featureFlags = new FeatureFlags({ provider });

export const handler = async (event: any) => {
  const darkMode = await featureFlags.evaluate('dark_mode', false);
  const newCheckout = await featureFlags.evaluate('new_checkout', false, {
    username: event.requestContext.authorizer.claims.sub,
  });
};
```

### Parameters

The Parameters utility provides cached retrieval from SSM Parameter Store, Secrets Manager, and AppConfig with a configurable TTL.

**Default TTL:** 5 seconds. Override globally with the `POWERTOOLS_PARAMETERS_MAX_AGE` environment variable (in seconds) or per-call with `max_age`.

**Python:**

```python
from aws_lambda_powertools.utilities.parameters import get_parameter, get_secret

# Cached for 300 seconds
db_host = get_parameter("/my-app/prod/db-host", max_age=300)

# Secrets Manager — decrypted and cached
db_password = get_secret("my-app/prod/db-password", max_age=300)
```

**TypeScript:**

```typescript
import { getParameter } from '@aws-lambda-powertools/parameters/ssm';
import { getSecret } from '@aws-lambda-powertools/parameters/secrets';

const dbHost = await getParameter('/my-app/prod/db-host', { maxAge: 300 });
const dbPassword = await getSecret('my-app/prod/db-password', { maxAge: 300 });
```

### Parser (Input Validation)

Validate event payloads at the system boundary using typed schemas. Catches malformed input before your business logic runs.

**Python (Pydantic):**

```python
from pydantic import BaseModel, validator
from aws_lambda_powertools.utilities.parser import event_parser
from aws_lambda_powertools.utilities.parser.envelopes import ApiGatewayEnvelope

class OrderRequest(BaseModel):
    order_id: str
    amount: float
    currency: str = "USD"

    @validator("amount")
    def amount_must_be_positive(cls, v):
        if v <= 0:
            raise ValueError("amount must be positive")
        return v

@event_parser(model=OrderRequest, envelope=ApiGatewayEnvelope)
def handler(event: OrderRequest, context):
    # event is already validated and typed
    return {"statusCode": 200, "body": f"Order {event.order_id}: {event.amount} {event.currency}"}
```

**TypeScript (Zod):**

```typescript
import { z } from 'zod';
import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';

const OrderRequest = z.object({
  orderId: z.string(),
  amount: z.number().positive(),
  currency: z.string().default('USD'),
});

type OrderRequest = z.infer<typeof OrderRequest>;

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  const parsed = OrderRequest.safeParse(JSON.parse(event.body ?? '{}'));
  if (!parsed.success) {
    return { statusCode: 400, body: JSON.stringify({ errors: parsed.error.issues }) };
  }
  const order = parsed.data;
  return { statusCode: 200, body: JSON.stringify({ orderId: order.orderId }) };
};
```

### Environment Variable Validation

Validate required environment variables at module load time (outside the handler) so misconfigured functions fail immediately on cold start rather than producing cryptic errors mid-invocation.

**Python (Pydantic):**

```python
import os
from pydantic import BaseModel

class Config(BaseModel):
    table_name: str
    event_bus_arn: str
    log_level: str = "INFO"

# Validated once at module load — fails fast if TABLE_NAME or EVENT_BUS_ARN is missing
config = Config(
    table_name=os.environ["TABLE_NAME"],
    event_bus_arn=os.environ["EVENT_BUS_ARN"],
    log_level=os.environ.get("LOG_LEVEL", "INFO"),
)
```

**TypeScript (Zod):**

```typescript
import { z } from 'zod';

const Config = z.object({
  TABLE_NAME: z.string(),
  EVENT_BUS_ARN: z.string(),
  LOG_LEVEL: z.string().default('INFO'),
});

// Validated once at module load
const config = Config.parse(process.env);
```

This pattern catches missing or malformed configuration at deploy time (via smoke tests) or immediately on first invocation, rather than on the specific code path that uses the variable.

### Streaming (Python)

For processing S3 objects larger than available Lambda memory, use the Powertools Streaming utility. It provides a stream-like interface that reads data in chunks without loading the entire object into memory.

```python
from aws_lambda_powertools.utilities.streaming import S3Object

def handler(event, context):
    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    key = event["Records"][0]["s3"]["object"]["key"]

    s3_object = S3Object(bucket=bucket, key=key)
    for line in s3_object:
        process_line(line)
```

This is particularly useful for CSV/JSON-lines processing, log analysis, and any workload where the input file exceeds the function's memory allocation.
