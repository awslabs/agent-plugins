# IoT Rules Engine Patterns

## Topic Structure Best Practices

### Standard Topic Hierarchy

```
{org}/{env}/{device-type}/{device-id}/{data-category}
```

| Segment | Example | Purpose |
|---|---|---|
| org | `acme` | Multi-tenant isolation |
| env | `prod`, `staging` | Environment separation |
| device-type | `temp-sensor`, `valve` | Type-based rule targeting |
| device-id | `sensor-001` | Per-device access control via policy variables |
| data-category | `telemetry`, `alerts`, `commands`, `status` | Separate data streams for targeted rules |

### Reserved Prefixes

- `$aws/things/{thingName}/shadow/` -- Device Shadow MQTT topics (do not use for custom data)
- `$aws/things/{thingName}/jobs/` -- IoT Jobs MQTT topics
- `$aws/rules/{ruleName}` -- Basic Ingest prefix (bypasses message broker)
- `$aws/events/` -- Lifecycle events (connect, disconnect, subscribe)

## Rule SQL Examples

### Route Telemetry to Timestream

```sql
SELECT
  topic(4) as device_id,
  topic(3) as device_type,
  temperature,
  humidity,
  pressure,
  timestamp() as time
FROM 'acme/prod/+/+/telemetry'
WHERE temperature IS NOT NULL
```

**Timestream action configuration:**
```json
{
  "timestream": {
    "roleArn": "arn:aws:iam::ACCOUNT:role/iot-timestream-role",
    "databaseName": "iot_telemetry",
    "tableName": "sensor_data",
    "dimensions": [
      { "name": "device_id", "value": "${device_id}" },
      { "name": "device_type", "value": "${device_type}" }
    ],
    "timestamp": {
      "value": "${time}",
      "unit": "MILLISECONDS"
    }
  }
}
```

### Route Alerts to Lambda for Enrichment

```sql
SELECT
  topic(4) as device_id,
  *
FROM 'acme/prod/+/+/alerts'
WHERE severity >= 3
```

Use this pattern when alerts need enrichment (look up device owner, location, maintenance history) before sending notifications. The Lambda function queries DynamoDB for device metadata and publishes to SNS.

### Write Latest State to DynamoDB

```sql
SELECT
  topic(4) as device_id,
  state.reported as reported_state,
  timestamp() as last_updated
FROM '$aws/things/+/shadow/update/documents'
```

**DynamoDBv2 action configuration:**
```json
{
  "dynamoDBv2": {
    "roleArn": "arn:aws:iam::ACCOUNT:role/iot-dynamodb-role",
    "putItem": {
      "tableName": "device_state"
    }
  }
}
```

The DynamoDBv2 action writes the entire SQL SELECT result as a DynamoDB item. The `device_id` field becomes the partition key (configure the table with `device_id` as the partition key).

### Buffer High-Volume Data in Kinesis

```sql
SELECT
  topic(4) as device_id,
  *
FROM 'acme/prod/+/+/telemetry'
```

**Kinesis action configuration:**
```json
{
  "kinesis": {
    "roleArn": "arn:aws:iam::ACCOUNT:role/iot-kinesis-role",
    "streamName": "iot-telemetry-stream",
    "partitionKey": "${device_id}"
  }
}
```

Use Kinesis when downstream consumers (Lambda, Kinesis Data Analytics, custom applications) need to process telemetry in real-time with ordering guarantees per device. The partition key ensures all messages from the same device go to the same shard.

### Archive Raw Telemetry to S3

```sql
SELECT * FROM 'acme/prod/+/+/telemetry'
```

**S3 action configuration:**
```json
{
  "s3": {
    "roleArn": "arn:aws:iam::ACCOUNT:role/iot-s3-role",
    "bucketName": "acme-iot-telemetry-archive",
    "key": "year=${parse_time('yyyy', timestamp())}/month=${parse_time('MM', timestamp())}/day=${parse_time('dd', timestamp())}/${topic(4)}/${timestamp()}.json",
    "cannedAcl": "private"
  }
}
```

Partition the S3 key by date and device ID for efficient Athena queries with partition projection.

### Republish Filtered Data to Another Topic

```sql
SELECT
  topic(4) as device_id,
  temperature,
  'HIGH_TEMP' as alert_type
FROM 'acme/prod/temp-sensor/+/telemetry'
WHERE temperature > 100
```

**Republish action configuration:**
```json
{
  "republish": {
    "roleArn": "arn:aws:iam::ACCOUNT:role/iot-republish-role",
    "topic": "acme/prod/temp-sensor/${topic(4)}/alerts",
    "qos": 1
  }
}
```

Use republish to generate derived topics. Downstream applications subscribe to the alert topic without processing raw telemetry.

### Send Notifications via SNS

```sql
SELECT
  topic(4) as device_id,
  concat('Device ', topic(4), ' battery critically low: ', cast(battery_pct as String), '%') as message
FROM 'acme/prod/+/+/telemetry'
WHERE battery_pct < 10
```

**SNS action configuration:**
```json
{
  "sns": {
    "roleArn": "arn:aws:iam::ACCOUNT:role/iot-sns-role",
    "targetArn": "arn:aws:sns:REGION:ACCOUNT:iot-device-alerts",
    "messageFormat": "RAW"
  }
}
```

### Trigger IoT Events Detector

```sql
SELECT
  topic(4) as device_id,
  temperature,
  vibration,
  timestamp() as ts
FROM 'acme/prod/motor/+/telemetry'
```

**IoT Events action configuration:**
```json
{
  "iotEvents": {
    "roleArn": "arn:aws:iam::ACCOUNT:role/iot-events-role",
    "inputName": "motor_telemetry",
    "messageId": "${newuuid()}"
  }
}
```

## Error Action Configuration

### Error Action to S3 (Recommended Default)

Every rule should have an error action. S3 is the cheapest destination for error capture and allows batch reprocessing later.

```json
{
  "errorAction": {
    "s3": {
      "roleArn": "arn:aws:iam::ACCOUNT:role/iot-error-action-role",
      "bucketName": "acme-iot-rule-errors",
      "key": "errors/${ruleName}/${parse_time('yyyy/MM/dd/HH', timestamp())}/${newuuid()}.json",
      "cannedAcl": "private"
    }
  }
}
```

The error payload includes:
- `ruleName`: Which rule failed
- `topic`: The original MQTT topic
- `clientId`: The device that published
- `base64OriginalPayload`: The original message (base64 encoded)
- `failures[]`: Array of failed actions with error messages

### Error Action to SQS (For Automated Reprocessing)

Use SQS when you want a Lambda function to automatically retry failed messages:

```json
{
  "errorAction": {
    "sqs": {
      "roleArn": "arn:aws:iam::ACCOUNT:role/iot-error-sqs-role",
      "queueUrl": "https://sqs.REGION.amazonaws.com/ACCOUNT/iot-rule-errors",
      "useBase64": true
    }
  }
}
```

Wire a Lambda function to the SQS queue to inspect the failure reason, fix the issue (e.g., create a missing DynamoDB table, fix IAM permissions), and republish the original message.

### Error Action to CloudWatch Logs (For Debugging)

Use during development or when you need searchable error logs:

```json
{
  "errorAction": {
    "cloudwatchLogs": {
      "roleArn": "arn:aws:iam::ACCOUNT:role/iot-error-cw-role",
      "logGroupName": "/aws/iot/rules/errors",
      "batchMode": true
    }
  }
}
```

## Basic Ingest Setup

### When to Use Basic Ingest

Use Basic Ingest for telemetry that only needs rules engine processing (not consumed by other MQTT subscribers). It eliminates the message broker publish charge ($1.00 per million messages).

### How It Works

Devices publish to `$aws/rules/<rule-name>/<custom-topic>` instead of the custom topic directly. The message goes straight to the named rule, bypassing the message broker.

### Example

Device publishes to:
```
$aws/rules/telemetry-to-timestream/acme/prod/temp-sensor/sensor-001/telemetry
```

The rule SQL references the custom topic portion:
```sql
SELECT
  topic(4) as device_id,
  temperature,
  humidity
FROM '$aws/rules/telemetry-to-timestream/acme/prod/+/+/telemetry'
```

Note: `topic()` function indexes from the custom topic portion, not from `$aws/rules/rule-name`.

### Basic Ingest Limitations

- Messages are not published to the MQTT broker, so other subscribers cannot receive them
- Cannot use MQTT retained messages with Basic Ingest
- The rule name in the topic must match an existing rule
- Still charges for rule actions (Lambda invocations, Timestream writes, etc.)

## IAM Role for Rules Engine

Every rule action needs an IAM role that grants the rules engine permission to invoke the target service. Use a single role per rule (not per action) with least-privilege permissions.

### Example: Timestream + S3 Error Action Role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "timestream:WriteRecords",
        "timestream:DescribeEndpoints"
      ],
      "Resource": "arn:aws:timestream:REGION:ACCOUNT:database/iot_telemetry/table/sensor_data"
    },
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::acme-iot-rule-errors/*"
    }
  ]
}
```

**Trust policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "iot.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "ACCOUNT_ID"
        }
      }
    }
  ]
}
```

Always include the `aws:SourceAccount` condition to prevent cross-account confused deputy attacks.

## Monitoring Rules

### CloudWatch Metrics to Alarm On

| Metric | Alarm Threshold | Why |
|---|---|---|
| `RuleMessageThrottled` | > 0 for 5 minutes | Messages are being dropped due to account-level throttling |
| `TopicMatch` | Sudden drop > 50% | Devices may have stopped publishing or topic structure changed |
| `Failure` | > 0 for 5 minutes | Rule action is failing (IAM, target service issue) |
| `ErrorActionFailure` | > 0 | Even the error action is failing; data loss is occurring |

Enable IoT Core logging (set to INFO for development, ERROR for production) to get detailed rule execution logs in CloudWatch Logs at `/aws/iot/logs`.
