# AWS Lambda Powertools

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

## Deep Dives

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
from pydantic import BaseModel, field_validator
from aws_lambda_powertools.utilities.parser import event_parser
from aws_lambda_powertools.utilities.parser.envelopes import ApiGatewayEnvelope

class OrderRequest(BaseModel):
    order_id: str
    amount: float
    currency: str = "USD"

    @field_validator("amount")
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
