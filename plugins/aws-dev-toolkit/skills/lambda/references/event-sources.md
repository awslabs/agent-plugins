# Lambda Event Source Patterns

## Event Source Mapping — SQS

```bash
aws lambda create-event-source-mapping \
  --function-name my-function \
  --event-source-arn arn:aws:sqs:us-east-1:123456789:my-queue \
  --batch-size 10 \
  --maximum-batching-window-in-seconds 5 \
  --function-response-types ReportBatchItemFailures
```

**Always enable `ReportBatchItemFailures`** to avoid reprocessing the entire batch on partial failures.

### SQS Partial Batch Failure Handler (Python)

```python
from aws_lambda_powertools.utilities.batch import (
    BatchProcessor, EventType, process_partial_response
)

processor = BatchProcessor(event_type=EventType.SQS)

def record_handler(record):
    payload = record["body"]
    # process each message individually
    return True

def handler(event, context):
    return process_partial_response(
        event=event, record_handler=record_handler,
        processor=processor, context=context
    )
```

## Event Source Mapping — DynamoDB Streams

```bash
aws lambda create-event-source-mapping \
  --function-name my-function \
  --event-source-arn arn:aws:dynamodb:us-east-1:123456789:table/my-table/stream/... \
  --starting-position LATEST \
  --batch-size 100 \
  --maximum-retry-attempts 3 \
  --bisect-batch-on-function-error \
  --destination-config '{"OnFailure":{"Destination":"arn:aws:sqs:us-east-1:123456789:dlq"}}'
```

**Always configure**: `bisect-batch-on-function-error`, `maximum-retry-attempts`, and a DLQ destination.

### SAM Template — DynamoDB Stream

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    Handler: handler.lambda_handler
    Runtime: python3.12
    Events:
      DDBStream:
        Type: DynamoDB
        Properties:
          Stream: !GetAtt MyTable.StreamArn
          StartingPosition: LATEST
          BatchSize: 100
          MaximumRetryAttempts: 3
          BisectBatchOnFunctionError: true
          DestinationConfig:
            OnFailure:
              Destination: !GetAtt DLQ.Arn
```

## Event Source Mapping — Kinesis

```bash
aws lambda create-event-source-mapping \
  --function-name my-function \
  --event-source-arn arn:aws:kinesis:us-east-1:123456789:stream/my-stream \
  --starting-position LATEST \
  --batch-size 100 \
  --parallelization-factor 10 \
  --maximum-retry-attempts 3 \
  --bisect-batch-on-function-error \
  --destination-config '{"OnFailure":{"Destination":"arn:aws:sqs:us-east-1:123456789:dlq"}}'
```

Key settings:
- **`parallelization-factor`** (1-10): Process multiple batches per shard concurrently. Default 1.
- **`bisect-batch-on-function-error`**: Splits failing batch in half to isolate poison records.
- **DLQ destination**: Captures records that exhaust retry attempts.

## API Gateway Integration

### SAM — REST API

```yaml
MyApiFunction:
  Type: AWS::Serverless::Function
  Properties:
    Handler: handler.lambda_handler
    Runtime: python3.12
    Events:
      GetItems:
        Type: Api
        Properties:
          Path: /items
          Method: GET
      CreateItem:
        Type: Api
        Properties:
          Path: /items
          Method: POST
```

### SAM — HTTP API (v2, lower cost)

```yaml
MyApiFunction:
  Type: AWS::Serverless::Function
  Properties:
    Handler: handler.lambda_handler
    Runtime: python3.12
    Events:
      GetItems:
        Type: HttpApi
        Properties:
          Path: /items
          Method: GET
          ApiId: !Ref MyHttpApi

MyHttpApi:
  Type: AWS::Serverless::HttpApi
  Properties:
    StageName: prod
    CorsConfiguration:
      AllowOrigins:
        - "https://example.com"
      AllowMethods:
        - GET
        - POST
```

### CDK — HTTP API

```typescript
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';

const integration = new HttpLambdaIntegration('MyIntegration', fn);

const httpApi = new apigwv2.HttpApi(this, 'MyApi');
httpApi.addRoutes({
  path: '/items',
  methods: [apigwv2.HttpMethod.GET],
  integration,
});
```

## S3 Event Notifications

### SAM Template

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    Handler: handler.lambda_handler
    Runtime: python3.12
    Events:
      S3Upload:
        Type: S3
        Properties:
          Bucket: !Ref MyBucket
          Events: s3:ObjectCreated:*
          Filter:
            S3Key:
              Rules:
                - Name: prefix
                  Value: uploads/
                - Name: suffix
                  Value: .csv
```

### CDK

```typescript
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';

bucket.addEventNotification(
  s3.EventType.OBJECT_CREATED,
  new s3n.LambdaDestination(fn),
  { prefix: 'uploads/', suffix: '.csv' }
);
```

## EventBridge (CloudWatch Events)

### SAM Template

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    Handler: handler.lambda_handler
    Runtime: python3.12
    Events:
      OrderCreated:
        Type: EventBridgeRule
        Properties:
          EventBusName: my-event-bus
          Pattern:
            source:
              - "my-app.orders"
            detail-type:
              - "OrderCreated"
```

### CDK

```typescript
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';

const rule = new events.Rule(this, 'OrderRule', {
  eventBus,
  eventPattern: {
    source: ['my-app.orders'],
    detailType: ['OrderCreated'],
  },
});
rule.addTarget(new targets.LambdaFunction(fn));
```

## Deployment Patterns

### SAM (recommended for Lambda-centric projects)

```bash
sam build
sam deploy --guided  # first time
sam deploy            # subsequent
sam local invoke       # local testing
sam logs --name MyFunction --tail  # tail logs
```

### CDK (recommended for complex infrastructure)

```bash
cdk deploy
cdk diff    # preview changes
cdk synth   # generate CloudFormation
```

### Direct CLI (for quick iterations)

```bash
# Update function code
zip -r function.zip .
aws lambda update-function-code \
  --function-name my-function \
  --zip-file fileb://function.zip

# Update environment variables
aws lambda update-function-configuration \
  --function-name my-function \
  --environment 'Variables={DB_HOST=mydb.example.com,STAGE=prod}'
```

## Event Source Decision Matrix

| Source | Invocation | Retry Behavior | Key Setting |
|---|---|---|---|
| SQS | Poll-based | Visibility timeout, then retry | `ReportBatchItemFailures` |
| DynamoDB Streams | Poll-based | Retries until record expires (24h) | `bisect-batch-on-function-error` |
| Kinesis | Poll-based | Retries until record expires (default 24h) | `parallelization-factor` |
| API Gateway | Synchronous | Client retries | 29s hard timeout limit |
| S3 | Async invocation | 2 retries, then DLQ | Configure on-failure destination |
| EventBridge | Async invocation | Configurable retries | DLQ + retry policy |
| SNS | Async invocation | 3 retries | DLQ on subscription |
| CloudWatch Logs | Async invocation | 2 retries | Subscription filter |
| IoT Rules | Async invocation | Configurable | Error action |
