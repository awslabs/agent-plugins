# AWS Step Functions

Step Functions provides visual workflow orchestration with native integrations to 9,000+ API actions across 200+ AWS services. Define workflows as state machines in Amazon States Language (ASL).

## Standard vs Express Workflows

|                                   | Standard                             | Express                                     |
| --------------------------------- | ------------------------------------ | ------------------------------------------- |
| **Max duration**                  | 1 year                               | 5 minutes                                   |
| **Execution semantics**           | Exactly-once                         | At-least-once (async) / At-most-once (sync) |
| **Execution history**             | Retained 90 days, queryable via API  | CloudWatch Logs only                        |
| **Max throughput**                | 2,000 exec/sec                       | 100,000 exec/sec                            |
| **Pricing model**                 | Per state transition                 | Per execution count + duration              |
| **`.sync` / `.waitForTaskToken`** | Supported                            | Not supported                               |
| **Best for**                      | Auditable, non-idempotent operations | High-volume, idempotent event processing    |

**Choose Standard** for: payment processing, order fulfillment, compliance workflows, anything that must never execute twice.

**Choose Express** for: IoT data ingestion, streaming transformations, mobile backends, high-throughput short-lived processing.

## Key State Types

| State              | Purpose                                                                              |
| ------------------ | ------------------------------------------------------------------------------------ |
| `Task`             | Execute work — invoke Lambda, call any AWS service via SDK integration               |
| `Choice`           | Branch based on input data conditions (no `Next` required on branches)               |
| `Parallel`         | Execute multiple branches concurrently; waits for all branches to complete           |
| `Map`              | Iterate over an array; use Distributed Map mode for up to 10M items from S3/DynamoDB |
| `Wait`             | Pause for a fixed duration or until a specific timestamp                             |
| `Pass`             | Pass input to output, optionally injecting or transforming data                      |
| `Succeed` / `Fail` | End execution successfully or with an error and cause                                |

## SAM Template

```yaml
Resources:
  MyWorkflow:
    Type: AWS::Serverless::StateMachine
    Properties:
      DefinitionUri: statemachine/my_workflow.asl.json
      Type: STANDARD                          # or EXPRESS
      DefinitionSubstitutions:
        ProcessFunctionArn: !GetAtt ProcessFunction.Arn
        ResultsTable: !Ref ResultsTable
      Policies:
        - LambdaInvokePolicy:
            FunctionName: !Ref ProcessFunction
        - DynamoDBWritePolicy:
            TableName: !Ref ResultsTable
      Tracing:
        Enabled: true
      Logging:
        Destinations:
          - CloudWatchLogsLogGroup:
              LogGroupArn: !GetAtt WorkflowLogGroup.Arn
        IncludeExecutionData: true
        Level: ERROR                          # Use ALL for debugging, ERROR in production

  WorkflowLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      RetentionInDays: 30
```

## State Machine Definition (ASL)

Use `DefinitionSubstitutions` to inject ARNs — never hardcode them:

```json
{
  "Comment": "Order processing workflow",
  "QueryLanguage": "JSONata",
  "StartAt": "ProcessOrder",
  "States": {
    "ProcessOrder": {
      "Type": "Task",
      "Resource": "${ProcessFunctionArn}",
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [{ "ErrorEquals": ["States.ALL"], "Next": "HandleError" }],
      "Next": "SaveResult"
    },
    "SaveResult": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:putItem",
      "Arguments": {
        "TableName": "${ResultsTable}",
        "Item": {
          "id": { "S": "{% $states.input.orderId %}" },
          "status": { "S": "completed" }
        }
      },
      "End": true
    },
    "HandleError": {
      "Type": "Fail",
      "Error": "OrderProcessingFailed"
    }
  }
}
```

## JSONata — Recommended Query Language

JSONata is the modern, preferred way to reference and transform data in ASL. It replaces the five JSONPath I/O fields (`InputPath`, `Parameters`, `ResultSelector`, `ResultPath`, `OutputPath`) with just two: `Arguments` (inputs) and `Output` (result shape).

**Enable at the top level** to apply to all states:

```json
{ "QueryLanguage": "JSONata", "StartAt": "...", "States": {...} }
```

**Or per-state** to migrate incrementally:

```json
{ "Type": "Task", "QueryLanguage": "JSONata", ... }
```

**Expression syntax** — wrap expressions in `{% %}`:

```json
"Arguments": {
  "userId": "{% $states.input.user.id %}",
  "greeting": "{% 'Hello, ' & $states.input.user.name %}",
  "total": "{% $sum($states.input.items.price) %}"
}
```

**Built-in Step Functions JSONata functions:**

- `$uuid()` — generate a v4 UUID
- `$parse(str)` — deserialize a JSON string to an object
- `$partition(array, size)` — split array into chunks
- `$range(start, end, step)` — generate a number array
- `$hash(value, algorithm)` — compute MD5/SHA-256/etc. hash

**JSONPath is still supported** and is the default if `QueryLanguage` is omitted — existing state machines do not need to be migrated.

## Integration Patterns

| Pattern               | ARN suffix          | Behaviour                                                             |
| --------------------- | ------------------- | --------------------------------------------------------------------- |
| **Request Response**  | _(none)_            | Call service, proceed after HTTP 200                                  |
| **Run a Job**         | `.sync`             | Call service, wait for job completion                                 |
| **Wait for Callback** | `.waitForTaskToken` | Pass `$$.Task.Token`, pause until `SendTaskSuccess`/`SendTaskFailure` |

**Wait for Callback** is the human-in-the-loop pattern: pass the task token to an external system (email, Slack, ticketing), call `sfn:SendTaskSuccess` with the token when approved.

## SDK Integrations — Avoid Lambda for Simple AWS Calls

Step Functions can call any AWS service API directly without a Lambda intermediary. This saves both cost and latency for simple operations:

```json
"SaveToDynamoDB": {
  "Type": "Task",
  "Resource": "arn:aws:states:::dynamodb:putItem",
  "Arguments": {
    "TableName": "my-table",
    "Item": { "id": { "S": "{% $states.input.id %}" } }
  },
  "End": true
}
```

```json
"PublishEvent": {
  "Type": "Task",
  "Resource": "arn:aws:states:::events:putEvents",
  "Arguments": {
    "Entries": [{
      "EventBusName": "my-bus",
      "Source": "my.service",
      "DetailType": "OrderPlaced",
      "Detail": "{% $states.input %}"
    }]
  },
  "End": true
}
```

Avoiding Lambda intermediaries for simple DynamoDB reads/writes, SNS publishes, SQS sends, and EventBridge puts eliminates invocation latency and cost.

## Distributed Map — Large-Scale Processing

`Map` state with `Mode: DISTRIBUTED` processes up to 10 million items from S3, DynamoDB, or inline arrays, with each item running as an independent child workflow:

```json
"ProcessFiles": {
  "Type": "Map",
  "ItemProcessor": {
    "ProcessorConfig": { "Mode": "DISTRIBUTED", "ExecutionType": "EXPRESS" },
    "StartAt": "ProcessSingleFile",
    "States": { "ProcessSingleFile": { "Type": "Task", "Resource": "${ProcessFunctionArn}", "End": true } }
  },
  "MaxConcurrency": 100,
  "ItemReader": {
    "Resource": "arn:aws:states:::s3:listObjectsV2",
    "Parameters": { "Bucket.$": "$.bucket", "Prefix.$": "$.prefix" }
  },
  "End": true
}
```

## Local Testing

**Recommended: TestState API** — test individual states against real AWS without deploying the full state machine:

```bash
aws stepfunctions test-state \
  --definition '{"Type":"Task","Resource":"${FunctionArn}","End":true}' \
  --role-arn arn:aws:iam::123456789012:role/MyRole \
  --input '{"key":"value"}'
```

**Step Functions Local (Docker)** — run a local emulator for integration testing. Note it is unsupported and does not have full feature parity:

```bash
docker run -p 8083:8083 amazon/aws-stepfunctions-local

# Run alongside sam local start-lambda for Lambda-integrated tests
sam local start-lambda &
docker run -p 8083:8083 \
  -e LAMBDA_ENDPOINT=http://host.docker.internal:3001 \
  amazon/aws-stepfunctions-local
```

Then use the AWS CLI with `--endpoint-url http://localhost:8083` to create and execute state machines locally.

## Anti-Polling Pattern

The typical polling loop — `Wait → Check Status → Choice → loop` — is an expensive anti-pattern in Standard workflows because every state transition is billed. Replace it with the **callback + event-driven** approach:

1. Lambda starts the long-running task and receives a task token (`$$.Task.Token`)
2. Store the task token alongside the job ID in DynamoDB
3. Use `.waitForTaskToken` to pause the state machine at zero cost
4. When the job completes, an EventBridge rule triggers a Lambda that looks up the token and calls `sfn:SendTaskSuccess`

```json
"StartJob": {
  "Type": "Task",
  "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
  "Arguments": {
    "FunctionName": "${StartJobFunctionArn}",
    "Payload": {
      "taskToken": "{% $$.Task.Token %}",
      "input": "{% $states.input %}"
    }
  },
  "HeartbeatSeconds": 3600,
  "Next": "ProcessResult"
}
```

For third-party APIs that don't emit events, pass a callback URL to the external service so it can POST back to your endpoint when done, which then calls `SendTaskSuccess`.

**Lambda durable functions alternative:** `context.wait_for_callback()` / `context.waitForCallback()` implements the same pattern without manual token management.

## Fan-Out / Fan-In

| Scale                             | Recommended approach                                                        |
| --------------------------------- | --------------------------------------------------------------------------- |
| Up to 40 items                    | Step Functions `Map` state (Inline mode)                                    |
| Up to 10 million items            | Step Functions `Map` state (Distributed mode, child Express workflows)      |
| Millions of items, cost-sensitive | Custom: S3 → Lambda fan-out → SQS workers → DynamoDB tracking → aggregation |

For most teams, Step Functions Distributed Map is the right trade-off between cost and operational simplicity. A custom S3+SQS+DynamoDB solution is meaningfully cheaper at very high item counts but carries significant implementation overhead.

## Timeout Handling

Always set **both** `TimeoutSeconds` and `HeartbeatSeconds` on Task states. Without them, a hung downstream call can hold the execution open indefinitely:

```json
"CallExternalAPI": {
  "Type": "Task",
  "Resource": "${FunctionArn}",
  "TimeoutSeconds": 300,
  "HeartbeatSeconds": 60,
  "Retry": [...]
}
```

- `TimeoutSeconds` — maximum total time for the state (including retries)
- `HeartbeatSeconds` — maximum time between heartbeat signals; fails faster when a worker disappears silently

**Handling Express workflow timeouts:** Express workflows do not publish `TIMED_OUT` events to EventBridge. Wrap Express workflows inside a parent Standard workflow — the Standard workflow can catch the timeout and trigger remediation.

## Best Practices

- **Always add `Retry` on Task states** — Lambda returns transient errors (`Lambda.ServiceException`, `Lambda.AWSLambdaException`, `Lambda.TooManyRequestsException`) under load; without retry, these fail the execution
- **Use `Catch` for error routing** — route failures to a dedicated error-handling state rather than letting the execution fail silently
- **Use `DefinitionSubstitutions`** — never hardcode ARNs or table names in `.asl.json` files
- **Use JSONata for new workflows** — it produces simpler, more readable definitions than JSONPath
- **Use SDK integrations directly** — call DynamoDB, SNS, SQS, EventBridge, etc. without a Lambda wrapper for simple operations
- **Enable X-Ray tracing** (`Tracing.Enabled: true`) for end-to-end visibility across Step Functions and Lambda spans
- **Set logging to `Level: ERROR` in production** and `Level: ALL` when debugging; `IncludeExecutionData: true` is required to see input/output in logs
- **Standard workflows**: prefer for non-idempotent operations — exactly-once semantics prevent accidental double-charges or duplicate records
- **Express workflows**: ensure downstream operations are idempotent — at-least-once delivery means tasks may run more than once
