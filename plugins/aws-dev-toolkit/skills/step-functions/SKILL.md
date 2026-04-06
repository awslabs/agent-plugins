---
name: step-functions
description: Design and build AWS Step Functions workflows. Use when orchestrating multi-step processes, implementing saga patterns, coordinating parallel tasks, handling retries and error recovery, or choosing between Standard and Express workflows.
---

You are a Step Functions specialist. Help teams design reliable, cost-effective state machine workflows.

## Decision Framework: Standard vs Express

| Feature | Standard | Express |
|---|---|---|
| Max duration | 1 year | 5 minutes |
| Execution model | Exactly-once | At-least-once (async) / At-most-once (sync) |
| Pricing | Per state transition ($0.025/1000) | Per request + duration |
| History | Full execution history in console | CloudWatch Logs only |
| Step limit | 25,000 events per execution | Unlimited |
| Max concurrency | Default ~1M (soft limit) | Default ~1,000 (soft limit) |
| Ideal for | Long-running, business-critical workflows | High-volume, short, event processing |

**Opinionated recommendation**:
- **Default to Standard** for business workflows, orchestration, and anything requiring auditability.
- **Use Express** for high-volume event processing (>100K executions/day), data transforms, and ETL microbatches where duration is under 5 minutes.
- **Express is cheaper at scale** but loses execution history -- you must configure CloudWatch Logs.

## State Types

### Task State (does work)

**Opinionated**: Always add Retry and Catch to every Task state. Without Retry, a transient failure (Lambda throttle, DynamoDB ProvisionedThroughputExceededException, network timeout) fails the entire execution immediately — even though a retry 2 seconds later would succeed. Without Catch, a permanent failure (invalid input, missing resource) causes an unhandled error that terminates the workflow with no way to log the failure, notify anyone, or run compensating actions. The cost of adding Retry+Catch is a few lines of ASL; the cost of omitting them is silent failures in production.

### Direct Service Integrations (prefer over Lambda wrappers)

Step Functions can call 200+ AWS services directly. Do NOT wrap simple API calls in Lambda. Common direct integrations to use instead of Lambda:
- **DynamoDB**: GetItem, PutItem, UpdateItem, DeleteItem, Query
- **SQS**: SendMessage
- **SNS**: Publish
- **EventBridge**: PutEvents
- **ECS/Fargate**: RunTask (for long-running containers)
- **Glue**: StartJobRun
- **SageMaker**: CreateTransformJob, CreateTrainingJob
- **Bedrock**: InvokeModel

See `references/integrations.md` for ASL examples of each integration, plus Choice, Parallel, Map, and Wait state examples.

### Other State Types

- **Choice**: Branch based on input values (string, numeric, boolean comparisons)
- **Parallel**: Run multiple branches concurrently, Catch on any branch failure
- **Map (Inline)**: Iterate over a collection with configurable MaxConcurrency
- **Map (Distributed)**: Process millions of items from S3 with Express child executions
- **Wait**: Pause for a duration or until a timestamp

## Error Handling: Retry and Catch

### Retry Strategy
```json
"Retry": [
  {
    "ErrorEquals": ["States.Timeout"],
    "IntervalSeconds": 5,
    "MaxAttempts": 2,
    "BackoffRate": 2.0
  },
  {
    "ErrorEquals": ["TransientError", "Lambda.ServiceException"],
    "IntervalSeconds": 1,
    "MaxAttempts": 5,
    "BackoffRate": 2.0,
    "JitterStrategy": "FULL"
  },
  {
    "ErrorEquals": ["States.ALL"],
    "MaxAttempts": 0
  }
]
```

**Opinionated**: Order retries from specific to general. Use `JitterStrategy: FULL` to prevent thundering herd. Put `States.ALL` with `MaxAttempts: 0` last to explicitly catch-and-fail on unexpected errors rather than retrying them.

### Catch and Error Recovery
```json
"Catch": [
  {
    "ErrorEquals": ["PaymentDeclined"],
    "Next": "NotifyCustomerPaymentFailed",
    "ResultPath": "$.error"
  },
  {
    "ErrorEquals": ["States.ALL"],
    "Next": "GenericErrorHandler",
    "ResultPath": "$.error"
  }
]
```

**Always use `ResultPath` in Catch** to preserve the original input alongside the error. Without it, the error replaces your entire state input.

## Pattern: Saga (Compensating Transactions)

For distributed transactions across services where you need to undo completed steps on failure. Each step has a compensating action, compensations run in reverse order, and compensations must be idempotent. See `references/patterns.md` for the full ASL example with compensating transaction flow.

## Pattern: Human Approval (Callback)

Use `.waitForTaskToken` to pause execution until an external system sends a callback via `send-task-success` or `send-task-failure`. **Always set `TimeoutSeconds` on callback tasks.** Without it, the execution waits forever (up to 1 year for Standard). See `references/patterns.md` for the full ASL and CLI examples.

## Pattern: Distributed Map

Process millions of items from S3 using Express child executions for massive parallelism. See `references/patterns.md` for the ASL example with S3 CSV reader configuration.

## Common CLI Commands

```bash
# Create state machine
aws stepfunctions create-state-machine \
  --name my-workflow \
  --definition file://definition.json \
  --role-arn arn:aws:iam::123456789:role/step-functions-role

# Start execution
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-1:123456789:stateMachine:my-workflow \
  --input '{"orderId": "12345"}'

# List executions
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:us-east-1:123456789:stateMachine:my-workflow \
  --status-filter FAILED

# Get execution details
aws stepfunctions describe-execution \
  --execution-arn arn:aws:states:us-east-1:123456789:execution:my-workflow:exec-123

# Get execution history (debug step-by-step)
aws stepfunctions get-execution-history \
  --execution-arn arn:aws:states:us-east-1:123456789:execution:my-workflow:exec-123 \
  --query 'events[?type==`TaskFailed` || type==`ExecutionFailed`]'

# Update state machine
aws stepfunctions update-state-machine \
  --state-machine-arn arn:aws:states:us-east-1:123456789:stateMachine:my-workflow \
  --definition file://definition.json

# Test a state (local testing)
aws stepfunctions test-state \
  --definition '{"Type":"Task","Resource":"arn:aws:states:::dynamodb:getItem","Parameters":{"TableName":"Orders","Key":{"orderId":{"S":"123"}}}}' \
  --role-arn arn:aws:iam::123456789:role/step-functions-role \
  --input '{"orderId": "123"}'
```

## Workflow Studio

Use Workflow Studio in the AWS Console for:
- Visual design and prototyping (drag-and-drop states)
- Understanding existing workflows
- Quick iteration on state machine logic

**Opinionated**: Start in Workflow Studio for prototyping, then export to ASL (Amazon States Language) JSON and manage in version control. Never rely solely on the console for production workflows.

## Input/Output Processing

Data flows through each state as: `InputPath -> Parameters -> Task -> ResultSelector -> ResultPath -> OutputPath`

**Opinionated**: Use `ResultPath` generously to accumulate data through states. Use `ResultSelector` to trim large API responses down to only what you need (saves state size and cost on Standard workflows). See `references/integrations.md` for detailed examples of each processing stage.

## Anti-Patterns

1. **Lambda wrappers for AWS API calls**: Step Functions integrates directly with 200+ services. Don't write a Lambda just to call DynamoDB PutItem or SQS SendMessage.
2. **No error handling on Task states**: Every Task state should have Retry (for transient errors) and Catch (for permanent failures). No exceptions.
3. **Ignoring state payload limits**: Standard workflows have a 256 KB payload limit per state. Store large data in S3 and pass references.
4. **Using Standard for high-volume short tasks**: If you're running >100K executions/day with <5 min duration, Express workflows are dramatically cheaper.
5. **Missing TimeoutSeconds on callback tasks**: Without a timeout, `.waitForTaskToken` tasks will hang for up to 1 year if the callback never arrives.
6. **Not using Distributed Map for large datasets**: Inline Map processes items sequentially or with limited concurrency within one execution. Distributed Map scales to millions of items.
7. **Putting business logic in the state machine**: ASL is for orchestration, not computation. Complex data transforms and business rules belong in Lambda functions.
8. **Not enabling logging for Express workflows**: Express workflows have no built-in execution history. You MUST configure CloudWatch Logs or you'll have zero visibility.
9. **Monolith state machines**: A 50-state workflow is hard to understand and test. Break large workflows into nested state machines using `arn:aws:states:::states:startExecution.sync:2`.
10. **Not using `JitterStrategy` on retries**: Without jitter, retried tasks create thundering herd effects that amplify the original failure.

## Cost Optimization

- **Standard**: $0.025 per 1,000 state transitions. Minimize states. Use direct integrations to avoid Lambda invocation costs on top of transition costs.
- **Express**: Priced by number of requests and duration. Cheaper for high-volume, short workflows.
- **Pass states are not free** in Standard (they count as transitions). Eliminate unnecessary Pass states.
- **Combine simple sequential tasks** where possible to reduce transition count.
- Use `ResultSelector` to trim response payloads -- smaller payloads mean faster processing.

## Reference Files

- **references/patterns.md** -- Saga, callback, and Distributed Map patterns with full ASL examples
- **references/integrations.md** -- Direct service integration examples (DynamoDB, SQS, SNS, EventBridge, ECS, Bedrock), state type ASL, and input/output processing pipeline details

## Related Skills

- `aws-plan` -- Architecture planning that may include Step Functions workflows
- `lambda` -- Lambda functions used as Task state targets
- `api-gateway` -- API Gateway to Step Functions direct integrations (StartExecution, StartSyncExecution)
- `observability` -- CloudWatch Logs, X-Ray tracing, and monitoring for Step Functions
- `aws-debug` -- Debugging failed Step Functions executions
