# Lambda Powertools Patterns

Always use Powertools for AWS Lambda. It provides structured logging, tracing, and metrics with minimal boilerplate.

## Python — Full Example

```python
from aws_lambda_powertools import Logger, Tracer, Metrics
from aws_lambda_powertools.event_handler import APIGatewayRestResolver

logger = Logger()
tracer = Tracer()
metrics = Metrics()
app = APIGatewayRestResolver()

@app.get("/items")
@tracer.capture_method
def get_items():
    logger.info("Fetching items")
    metrics.add_metric(name="ItemsFetched", unit="Count", value=1)
    return {"items": []}

@logger.inject_lambda_context
@tracer.capture_lambda_handler
@metrics.log_metrics
def handler(event, context):
    return app.resolve(event, context)
```

### Key Decorators (Python)

| Decorator | Purpose |
|---|---|
| `@logger.inject_lambda_context` | Auto-adds request_id, function_name to every log line |
| `@tracer.capture_lambda_handler` | Creates X-Ray subsegment for the handler |
| `@tracer.capture_method` | Creates X-Ray subsegment for individual methods |
| `@metrics.log_metrics` | Flushes metrics to CloudWatch at the end of invocation |

### Structured Logging (Python)

```python
from aws_lambda_powertools import Logger

logger = Logger(service="order-service")

# Append persistent keys across all log lines
logger.append_keys(environment="prod")

# Log with structured data
logger.info("Order placed", extra={"order_id": "123", "total": 49.99})

# Inject Lambda context automatically
@logger.inject_lambda_context(log_event=True)  # log_event=True logs the raw event
def handler(event, context):
    logger.info("Processing request")
```

### Tracing (Python)

```python
from aws_lambda_powertools import Tracer

tracer = Tracer(service="order-service")

@tracer.capture_method
def process_order(order_id: str):
    tracer.put_annotation(key="OrderId", value=order_id)
    tracer.put_metadata(key="order_details", value={"id": order_id})
    # ... processing logic
    return {"status": "processed"}

@tracer.capture_lambda_handler
def handler(event, context):
    return process_order(event["order_id"])
```

### Parameters & Secrets (Python)

```python
from aws_lambda_powertools.utilities import parameters

# SSM Parameter Store (cached by default, 5s TTL)
config = parameters.get_parameter("/my-app/config")

# Secrets Manager
secret = parameters.get_secret("my-database-credentials")

# With custom cache TTL
config = parameters.get_parameter("/my-app/config", max_age=300)
```

## Node.js (TypeScript) — Full Example

```typescript
import { Logger } from '@aws-lambda-powertools/logger';
import { Tracer } from '@aws-lambda-powertools/tracer';
import { Metrics, MetricUnit } from '@aws-lambda-powertools/metrics';
import middy from '@middy/core';
import { injectLambdaContext } from '@aws-lambda-powertools/logger/middleware';
import { captureLambdaHandler } from '@aws-lambda-powertools/tracer/middleware';
import { logMetrics } from '@aws-lambda-powertools/metrics/middleware';

const logger = new Logger({ serviceName: 'order-service' });
const tracer = new Tracer({ serviceName: 'order-service' });
const metrics = new Metrics({ serviceName: 'order-service', namespace: 'MyApp' });

const lambdaHandler = async (event: any) => {
  logger.info('Processing order', { orderId: event.orderId });

  const subsegment = tracer.getSegment()?.addNewSubsegment('processOrder');
  tracer.putAnnotation('OrderId', event.orderId);

  metrics.addMetric('OrdersProcessed', MetricUnit.Count, 1);

  subsegment?.close();
  return { statusCode: 200, body: JSON.stringify({ status: 'ok' }) };
};

// Use middy middleware for clean decorator-style usage
export const handler = middy(lambdaHandler)
  .use(injectLambdaContext(logger))
  .use(captureLambdaHandler(tracer))
  .use(logMetrics(metrics));
```

### Structured Logging (Node.js)

```typescript
import { Logger } from '@aws-lambda-powertools/logger';

const logger = new Logger({
  serviceName: 'order-service',
  logLevel: 'INFO',
  persistentLogAttributes: {
    environment: process.env.STAGE,
  },
});

// Append keys for the current invocation
logger.appendKeys({ customerId: '123' });

// Structured log output
logger.info('Order created', { orderId: 'abc-123', total: 49.99 });
```

## SAM Template — Powertools Layer

```yaml
Globals:
  Function:
    Runtime: python3.12
    Architectures:
      - arm64
    Layers:
      - !Sub arn:aws:lambda:${AWS::Region}:017000801446:layer:AWSLambdaPowertoolsPythonV3-python312-arm64:7
    Environment:
      Variables:
        POWERTOOLS_SERVICE_NAME: my-service
        POWERTOOLS_LOG_LEVEL: INFO
        POWERTOOLS_METRICS_NAMESPACE: MyApp
```

## CDK — Powertools Setup

```typescript
import { Tracing } from 'aws-cdk-lib/aws-lambda';

const fn = new lambda.Function(this, 'MyFunction', {
  runtime: lambda.Runtime.PYTHON_3_12,
  architecture: lambda.Architecture.ARM_64,
  tracing: Tracing.ACTIVE,
  environment: {
    POWERTOOLS_SERVICE_NAME: 'my-service',
    POWERTOOLS_LOG_LEVEL: 'INFO',
    POWERTOOLS_METRICS_NAMESPACE: 'MyApp',
  },
});
```

## References

- [Powertools for AWS Lambda (Python)](https://docs.powertools.aws.dev/lambda/python/latest/)
- [Powertools for AWS Lambda (TypeScript)](https://docs.powertools.aws.dev/lambda/typescript/latest/)
