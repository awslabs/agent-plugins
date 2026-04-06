# Step Functions Patterns

## Saga Pattern (Compensating Transactions)

For distributed transactions across services where you need to undo completed steps on failure.

### Flow

```
StartOrder -> ChargeCard -> ReserveInventory -> ShipOrder -> Done
                |               |                  |
                v               v                  v
           RefundCard    ReleaseInventory     CancelShipment
                |               |                  |
                +--------> OrderFailed <-----------+
```

### Key Principles

1. Each step has a compensating action
2. Compensations run in reverse order
3. Compensations must be idempotent
4. Store step results for compensation context

### Full ASL Example

```json
{
  "Comment": "Order saga with compensating transactions",
  "StartAt": "ChargeCard",
  "States": {
    "ChargeCard": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789:function:charge-card",
      "ResultPath": "$.chargeResult",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "OrderFailed",
          "ResultPath": "$.error"
        }
      ],
      "Next": "ReserveInventory"
    },
    "ReserveInventory": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789:function:reserve-inventory",
      "ResultPath": "$.inventoryResult",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "RefundCard",
          "ResultPath": "$.error"
        }
      ],
      "Next": "ShipOrder"
    },
    "ShipOrder": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789:function:ship-order",
      "ResultPath": "$.shipResult",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ReleaseInventory",
          "ResultPath": "$.error"
        }
      ],
      "Next": "Done"
    },
    "RefundCard": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789:function:refund-card",
      "ResultPath": "$.refundResult",
      "Next": "OrderFailed"
    },
    "ReleaseInventory": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789:function:release-inventory",
      "ResultPath": "$.releaseResult",
      "Next": "RefundCard"
    },
    "CancelShipment": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:us-east-1:123456789:function:cancel-shipment",
      "ResultPath": "$.cancelResult",
      "Next": "ReleaseInventory"
    },
    "Done": {
      "Type": "Succeed"
    },
    "OrderFailed": {
      "Type": "Fail",
      "Error": "OrderFailed",
      "Cause": "One or more steps failed and compensations have been applied"
    }
  }
}
```

## Human Approval / Callback Pattern

Use `.waitForTaskToken` to pause execution until an external system sends a callback. Common for human approval flows, external system integrations, and async processing.

### ASL Example

```json
{
  "WaitForApproval": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
    "Parameters": {
      "QueueUrl": "https://sqs.us-east-1.amazonaws.com/123456789/approval-queue",
      "MessageBody": {
        "taskToken.$": "$$.Task.Token",
        "orderId.$": "$.orderId",
        "amount.$": "$.amount"
      }
    },
    "TimeoutSeconds": 86400,
    "Next": "ProcessApproval"
  }
}
```

### Callback Commands

The external system calls back with:

```bash
aws stepfunctions send-task-success \
  --task-token "TOKEN" \
  --task-output '{"approved": true}'

# Or on rejection:
aws stepfunctions send-task-failure \
  --task-token "TOKEN" \
  --error "Rejected" \
  --cause "Manager declined the order"
```

**Always set `TimeoutSeconds` on callback tasks.** Without it, the execution waits forever (up to 1 year for Standard).

## Distributed Map Pattern

For large-scale processing of millions of items from S3. Unlike Inline Map, Distributed Map launches child executions (Express) for massive parallelism.

### ASL Example

```json
{
  "ProcessLargeDataset": {
    "Type": "Map",
    "ItemProcessor": {
      "ProcessorConfig": {
        "Mode": "DISTRIBUTED",
        "ExecutionType": "EXPRESS"
      },
      "StartAt": "ProcessBatch",
      "States": {
        "ProcessBatch": { "Type": "Task", "Resource": "...", "End": true }
      }
    },
    "ItemReader": {
      "Resource": "arn:aws:states:::s3:getObject",
      "ReaderConfig": {
        "InputType": "CSV",
        "CSVHeaderLocation": "FIRST_ROW"
      },
      "Parameters": {
        "Bucket": "my-bucket",
        "Key": "data.csv"
      }
    },
    "MaxConcurrency": 1000,
    "Next": "Done"
  }
}
```

### When to Use Distributed Map

- Processing millions of items from S3 (CSV, JSON, manifest)
- Need concurrency beyond what Inline Map offers
- Each item requires non-trivial processing
- Want to leverage Express workflow pricing for child executions
