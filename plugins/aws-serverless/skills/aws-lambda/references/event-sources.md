# Lambda Event Sources Guide

## Overview

This guide covers the most common Lambda event sources — both polling-based (Event Source Mappings) and push-based (S3 notifications, SNS subscriptions). Use `esm_guidance` for polling source setup recommendations and `esm_optimize` for performance tuning.

**Delivery guarantee:** All Lambda event sources deliver events **at least once**. Your function must be idempotent — the same record may be processed more than once. Use the AWS Lambda Powertools Idempotency utility (backed by DynamoDB) to handle duplicates safely.

## Polling-Based Event Sources (ESM)

Event Source Mappings use a Lambda-managed poller that reads from the source, batches records, and invokes your function. You control throughput via batch size, concurrency, and parallelization.

### DynamoDB Streams

**Use case:** React to data changes in DynamoDB tables

**Key configuration:**

- `StartingPosition`: `LATEST` for new records only, `TRIM_HORIZON` for all
- `BatchSize`: 1-10000 (default 100)
- `ParallelizationFactor`: 1-10 (default 1, increase for throughput)
- `BisectBatchOnFunctionError`: Enable to isolate poison records
- `MaximumRetryAttempts`: Set to prevent infinite retries (default unlimited)
- `MaximumBatchingWindowInSeconds`: Buffer time before invoking (0-300)

**Best practices:**

- Enable `BisectBatchOnFunctionError` and set `MaximumRetryAttempts` to 3
- Configure a dead-letter queue for records that exhaust retries
- Use `ParallelizationFactor` > 1 when processing can't keep up

### Kinesis Streams

**Use case:** Process real-time streaming data

**Key configuration:**

- `BatchSize`: 1-10000 (default 100)
- `ParallelizationFactor`: 1-10 (should not exceed shard count)
- `MaximumBatchingWindowInSeconds`: Buffer time (0-300)
- `TumblingWindowInSeconds`: For aggregation scenarios (0-900)
- `StartingPosition`: `LATEST` or `TRIM_HORIZON`

**Best practices:**

- Higher batch sizes reduce invocation costs but increase timeout risk
- Use tumbling windows for time-based aggregation (counts, sums, averages)
- Enable enhanced fan-out when multiple consumers read from the same stream

### SQS Queues

**Use case:** Decouple components with reliable messaging

**Key configuration:**

- `BatchSize`: 1-10000 (default 10)
- `MaximumBatchingWindowInSeconds`: Buffer time (0-300)
- `MaximumConcurrency`: Limit concurrent Lambda invocations
- `FunctionResponseTypes`: Set to `["ReportBatchItemFailures"]` to avoid reprocessing successful messages

**FIFO queue considerations:**

- Use `BatchSize: 1` for strict ordering
- Limit `MaximumConcurrency` to prevent out-of-order processing
- Use message group IDs for parallel processing within groups

**Python SQS batch processor with partial failure reporting:**

```python
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.batch import (
    BatchProcessor, EventType, process_partial_response,
)
from aws_lambda_powertools.utilities.data_classes.sqs_event import SQSRecord

logger = Logger()
processor = BatchProcessor(event_type=EventType.SQS)

def process_record(record: SQSRecord):
    body = record.json_body
    logger.info("Processing order", order_id=body["orderId"])
    # Business logic here — raise to mark this record as failed
    return {"orderId": body["orderId"], "status": "processed"}

@logger.inject_lambda_context
def handler(event, context):
    return process_partial_response(
        event=event, record_handler=process_record, processor=processor, context=context,
    )
```

**TypeScript SQS batch processor:**

```typescript
import {
  BatchProcessor,
  EventType,
  processPartialResponse,
} from '@aws-lambda-powertools/batch';
import { Logger } from '@aws-lambda-powertools/logger';
import type { SQSHandler, SQSRecord } from 'aws-lambda';

const processor = new BatchProcessor(EventType.SQS);
const logger = new Logger();

const recordHandler = async (record: SQSRecord): Promise<void> => {
  const body = JSON.parse(record.body);
  logger.info('Processing order', { orderId: body.orderId });
};

export const handler: SQSHandler = async (event, context) =>
  processPartialResponse(event, recordHandler, processor, { context });
```

Both examples require `FunctionResponseTypes: ["ReportBatchItemFailures"]` in the ESM configuration.

**Best practices:**

- Always enable `ReportBatchItemFailures` for partial failure handling
- Set queue `VisibilityTimeout` >= Lambda function timeout
- Configure a DLQ with `maxReceiveCount` of 3-5

### MSK/Kafka

**Use case:** Process high-throughput streaming data from Kafka

**Key configuration:**

- `Topics`: List of Kafka topics to consume
- `BatchSize`: 1-10000 (default 100)
- `MaximumBatchingWindowInSeconds`: Buffer time (0-300)
- `StartingPosition`: `LATEST` or `TRIM_HORIZON`
- `ConsumerGroupId`: Consumer group identifier

**Network requirements:**

- Lambda must have VPC access to the MSK cluster
- Security groups must allow traffic on ports 9092 (plaintext) or 9094 (TLS)
- Use IAM authentication or SASL/SCRAM for authentication

**Best practices:**

- Use `esm_kafka_troubleshoot` for connectivity issues
- Generate IAM policies with `secure_esm_msk_policy`

**Powertools Kafka Consumer:** For Kafka events with Avro, Protobuf, or JSON Schema payloads, use the Kafka Consumer utility to deserialize records automatically instead of manually parsing byte arrays:

```python
from aws_lambda_powertools.utilities.kafka import KafkaConsumer, SchemaConfig

schema_config = SchemaConfig(schema_type="AVRO", schema_registry_url="https://my-registry.example.com")
consumer = KafkaConsumer(schema_config=schema_config)

@consumer.handler
def handler(event, context):
    for record in consumer.records:
        # record.value is already deserialized from Avro
        order = record.value
        print(f"Order: {order['orderId']}")
```

Available for Python, TypeScript, Java, and .NET. Supports Avro, Protobuf, and JSON Schema with both AWS Glue Schema Registry and Confluent Schema Registry.

### Amazon MQ

**Use case:** Process messages from ActiveMQ or RabbitMQ brokers

Lambda connects to Amazon MQ using a VPC-attached ESM. Configure the broker in a private subnet and ensure Lambda's security group can reach the broker port (61614 for ActiveMQ over STOMP/TLS, 5671 for RabbitMQ over AMQP/TLS).

### Self-Managed Kafka

**Use case:** Process messages from a Kafka cluster you operate (not MSK)

Use a self-managed Kafka ESM when your cluster is not AWS-managed. Lambda connects via the network configuration you provide. Supports SASL/PLAIN, SASL/SCRAM, mTLS, and VPC connectivity.

### Amazon DocumentDB (with change streams)

**Use case:** React to changes in DocumentDB collections

Similar to DynamoDB Streams — Lambda polls the DocumentDB change stream. Requires DocumentDB change streams to be enabled on the collection and Lambda to have VPC access to the cluster.

## Push-Based Event Sources

These sources invoke Lambda directly via asynchronous invocation — no ESM poller involved. Lower latency than polling sources, but less control over throughput and concurrency.

### S3 Event Notifications

**Use case:** React to object uploads, deletions, or modifications — image processing, file validation, data import, thumbnail generation

**SAM template:**

```yaml
ImageProcessor:
  Type: AWS::Serverless::Function
  Properties:
    Handler: src/handlers/process_image.handler
    Runtime: python3.12
    Architectures: [arm64]
    Policies:
      - S3ReadPolicy:
          BucketName: !Ref UploadBucket
    Events:
      ImageUploaded:
        Type: S3
        Properties:
          Bucket: !Ref UploadBucket
          Events: s3:ObjectCreated:*
          Filter:
            S3Key:
              Rules:
                - Name: prefix
                  Value: uploads/
                - Name: suffix
                  Value: .jpg

UploadBucket:
  Type: AWS::S3::Bucket
```

**Key configuration:**

- `Events`: Event types to trigger on — `s3:ObjectCreated:*`, `s3:ObjectRemoved:*`, `s3:ObjectCreated:Put`, etc.
- `Filter.S3Key.Rules`: Prefix and/or suffix filters to limit which objects trigger the function
- `Bucket`: Must reference an `AWS::S3::Bucket` declared in the same SAM template

**Best practices:**

- Avoid recursive triggers — if your function writes back to the same bucket that triggers it, Lambda will loop infinitely. Use a separate output bucket or a different prefix
- S3 delivers events at least once and NOT in order — write idempotent handlers and don't depend on event sequencing
- URL-decode the object key (`urllib.parse.unquote_plus` in Python, `decodeURIComponent` in JS) — S3 URL-encodes special characters in keys
- Use prefix/suffix filters to limit invocations to relevant objects
- For complex routing (multiple consumers, content-based filtering, cross-account), use S3 → EventBridge instead — enable EventBridge notifications on the bucket and create rules

**Python S3 event handler:**

```python
import json
import urllib.parse
import boto3
from aws_lambda_powertools import Logger

logger = Logger()
s3 = boto3.client('s3')

@logger.inject_lambda_context
def handler(event, context):
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        size = record['s3']['object']['size']
        logger.info("Processing object", bucket=bucket, key=key, size=size)

        response = s3.get_object(Bucket=bucket, Key=key)
        # Process the object content
```

**TypeScript S3 event handler:**

```typescript
import { Logger } from '@aws-lambda-powertools/logger';
import { Tracer } from '@aws-lambda-powertools/tracer';
import type { S3Event, Context } from 'aws-lambda';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';

const logger = new Logger();
const tracer = new Tracer();
const s3 = tracer.captureAWSv3Client(new S3Client({}));

export const handler = async (event: S3Event, context: Context): Promise<void> => {
  logger.addContext(context);
  for (const record of event.Records) {
    const bucket = record.s3.bucket.name;
    const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));
    const size = record.s3.object.size;
    logger.info('Processing object', { bucket, key, size });

    const response = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    // Process the object content
  }
};
```

### SNS Subscriptions

**Use case:** Fan-out processing — one published message triggers multiple independent Lambda consumers

**SAM template:**

```yaml
OrderNotifier:
  Type: AWS::Serverless::Function
  Properties:
    Handler: src/handlers/notify.handler
    Runtime: python3.12
    Architectures: [arm64]
    Events:
      OrderEvent:
        Type: SNS
        Properties:
          Topic: !Ref OrderTopic
          FilterPolicy:
            event_type:
              - order_placed
              - order_shipped
          FilterPolicyScope: MessageAttributes
          RedrivePolicy:
            deadLetterTargetArn: !GetAtt OrderDLQ.Arn

OrderTopic:
  Type: AWS::SNS::Topic

OrderDLQ:
  Type: AWS::SQS::Queue
  Properties:
    MessageRetentionPeriod: 1209600  # 14 days
```

**Key configuration:**

- `Topic`: ARN or reference to the SNS topic
- `FilterPolicy`: JSON filter to receive only matching messages — reduces invocations and cost
- `FilterPolicyScope`: `MessageAttributes` (default) or `MessageBody`
- `RedrivePolicy`: DLQ ARN for messages that fail delivery — configured at the subscription level, not the topic

**Best practices:**

- Use filter policies to reduce invocations — filter at the subscription level, not in handler code
- Configure a redrive policy (DLQ) on every subscription — SNS retries server-side errors up to 100,015 times over 23 days; client-side errors (deleted function) go directly to DLQ
- Set DLQ `MessageRetentionPeriod` to 14 days (maximum) for investigation time
- SNS delivers at least once; write idempotent handlers
- FIFO SNS topics do NOT support Lambda subscriptions — use standard topics only
- For simple point-to-point delivery, prefer SQS → Lambda (ESM) over SNS → Lambda
- For complex event routing with pattern matching, prefer EventBridge over SNS

**Python SNS event handler:**

```python
import json
from aws_lambda_powertools import Logger

logger = Logger()

@logger.inject_lambda_context
def handler(event, context):
    for record in event['Records']:
        message = json.loads(record['Sns']['Message'])
        subject = record['Sns'].get('Subject', '')
        message_id = record['Sns']['MessageId']
        logger.info("Processing SNS message", message_id=message_id, subject=subject)

        # Process the message
```

**TypeScript SNS event handler:**

```typescript
import { Logger } from '@aws-lambda-powertools/logger';
import type { SNSEvent, Context } from 'aws-lambda';

const logger = new Logger();

export const handler = async (event: SNSEvent, context: Context): Promise<void> => {
  logger.addContext(context);
  for (const record of event.Records) {
    const message = JSON.parse(record.Sns.Message);
    const subject = record.Sns.Subject ?? '';
    const messageId = record.Sns.MessageId;
    logger.info('Processing SNS message', { messageId, subject });

    // Process the message
  }
};
```

## Event Filtering

### ESM Filtering (Polling Sources)

ESM event filtering lets Lambda evaluate filter criteria **before invoking your function**, reducing unnecessary invocations and costs.

**Add filters in SAM template:**

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Events:
    MySQSEvent:
      Type: SQS
      Properties:
        Queue: !GetAtt MyQueue.Arn
        FilterCriteria:
          Filters:
            - Pattern: '{"body": {"eventType": ["ORDER_CREATED"]}}'
```

**Filter pattern syntax** matches against the event structure:

- Exact match: `{"body": {"status": ["ACTIVE"]}}`
- Prefix match: `{"body": {"id": [{"prefix": "order-"}]}}`
- Numeric range: `{"body": {"amount": [{"numeric": [">", 100]}]}}`
- Exists check: `{"body": {"metadata": [{"exists": true}]}}`

Filtering is supported for SQS, Kinesis, DynamoDB Streams, MSK, self-managed Kafka, and MQ. Records that don't match filters are dropped before Lambda is invoked — SQS messages are deleted, stream records are skipped.

### Push Source Filtering

Push-based sources use their own filtering mechanisms (not ESM FilterCriteria):

- **S3**: Prefix/suffix filters on the object key via `Filter.S3Key.Rules` in the SAM template
- **SNS**: Subscription filter policies via `FilterPolicy` — supports matching on `MessageAttributes` (default) or `MessageBody`

## ESM Provisioned Mode

For high-throughput Kafka (MSK or self-managed) and SQS workloads, provisioned mode provides:

- **3x faster autoscaling** compared to default mode
- **16x higher maximum capacity**
- Manual control over minimum and maximum event pollers

Enable in SAM template:

```yaml
MySQSEvent:
  Type: SQS
  Properties:
    Queue: !GetAtt MyQueue.Arn
    ProvisionedPollerConfig:
      MinimumPollers: 2
      MaximumPollers: 20
```

Use provisioned mode when default autoscaling is too slow to absorb traffic spikes without message backlog.

## Batch Size Guidelines

| Priority         | Small (1-10)              | Medium (10-100) | Large (100-1000+)                       |
| ---------------- | ------------------------- | --------------- | --------------------------------------- |
| **Latency**      | Lowest                    | Moderate        | Higher                                  |
| **Cost**         | Higher (more invocations) | Balanced        | Lower (fewer invocations)               |
| **Timeout risk** | Low                       | Low             | Higher (more processing per invocation) |

## Error Handling

- **Stream sources** (DynamoDB, Kinesis): Records retry until success, expiry, or max retries. Enable `BisectBatchOnFunctionError` and set `MaximumRetryAttempts`.
- **SQS**: Failed messages return to the queue after visibility timeout. Use `ReportBatchItemFailures` for partial batch success.
- **Kafka**: Similar to stream sources. Failed batches retry based on ESM configuration.

Always configure a dead-letter queue or on-failure destination to capture records that cannot be processed.

## Monitoring

For event source metrics to alarm on (IteratorAge, Errors, Throttles, DLQ depth), alarm thresholds, and dashboard setup, see [observability.md](observability.md).

## Schema Integration

For type-safe event processing with EventBridge:

1. Use `search_schema` to find event schemas
2. Use `describe_schema` to get the full definition
3. Generate typed handlers based on the schema
