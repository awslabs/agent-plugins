# Step Functions Service Integrations and Data Flow

## Direct Service Integrations

Step Functions can call 200+ AWS services directly. Prefer direct integrations over Lambda wrappers for simple API calls.

### DynamoDB PutItem

```json
{
  "PutItem": {
    "Type": "Task",
    "Resource": "arn:aws:states:::dynamodb:putItem",
    "Parameters": {
      "TableName": "Orders",
      "Item": {
        "orderId": {"S.$": "$.orderId"},
        "status": {"S": "PENDING"},
        "createdAt": {"S.$": "$$.State.EnteredTime"}
      }
    },
    "Next": "NotifyCustomer"
  }
}
```

### DynamoDB GetItem

```json
{
  "GetItem": {
    "Type": "Task",
    "Resource": "arn:aws:states:::dynamodb:getItem",
    "Parameters": {
      "TableName": "Orders",
      "Key": {
        "orderId": {"S.$": "$.orderId"}
      }
    },
    "ResultSelector": {
      "orderId.$": "$.Item.orderId.S",
      "status.$": "$.Item.status.S"
    },
    "ResultPath": "$.orderData",
    "Next": "ProcessOrder"
  }
}
```

### SQS SendMessage

```json
{
  "SendMessage": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sqs:sendMessage",
    "Parameters": {
      "QueueUrl": "https://sqs.us-east-1.amazonaws.com/123456789/my-queue",
      "MessageBody": {
        "orderId.$": "$.orderId",
        "action": "process"
      }
    },
    "Next": "Done"
  }
}
```

### SNS Publish

```json
{
  "NotifyCustomer": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sns:publish",
    "Parameters": {
      "TopicArn": "arn:aws:sns:us-east-1:123456789:order-notifications",
      "Message": {
        "orderId.$": "$.orderId",
        "status": "Order confirmed"
      }
    },
    "Next": "Done"
  }
}
```

### EventBridge PutEvents

```json
{
  "EmitEvent": {
    "Type": "Task",
    "Resource": "arn:aws:states:::events:putEvents",
    "Parameters": {
      "Entries": [
        {
          "Source": "order-service",
          "DetailType": "OrderCompleted",
          "Detail": {
            "orderId.$": "$.orderId",
            "amount.$": "$.amount"
          }
        }
      ]
    },
    "Next": "Done"
  }
}
```

### ECS/Fargate RunTask

```json
{
  "RunFargateTask": {
    "Type": "Task",
    "Resource": "arn:aws:states:::ecs:runTask.sync",
    "Parameters": {
      "LaunchType": "FARGATE",
      "Cluster": "arn:aws:ecs:us-east-1:123456789:cluster/my-cluster",
      "TaskDefinition": "arn:aws:ecs:us-east-1:123456789:task-definition/my-task:1",
      "NetworkConfiguration": {
        "AwsvpcConfiguration": {
          "Subnets": ["subnet-abc123"],
          "SecurityGroups": ["sg-abc123"],
          "AssignPublicIp": "DISABLED"
        }
      },
      "Overrides": {
        "ContainerOverrides": [
          {
            "Name": "my-container",
            "Environment": [
              { "Name": "ORDER_ID", "Value.$": "$.orderId" }
            ]
          }
        ]
      }
    },
    "Next": "Done"
  }
}
```

### Bedrock InvokeModel

```json
{
  "InvokeModel": {
    "Type": "Task",
    "Resource": "arn:aws:states:::bedrock:invokeModel",
    "Parameters": {
      "ModelId": "anthropic.claude-3-sonnet-20240229-v1:0",
      "Body": {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1024,
        "messages": [
          {
            "role": "user",
            "content.$": "$.prompt"
          }
        ]
      },
      "ContentType": "application/json",
      "Accept": "application/json"
    },
    "ResultSelector": {
      "response.$": "$.Body.content[0].text"
    },
    "ResultPath": "$.modelResult",
    "Next": "Done"
  }
}
```

## Common Direct Integrations Reference

| Service | Actions | Use Instead of Lambda When... |
|---------|---------|-------------------------------|
| **DynamoDB** | GetItem, PutItem, UpdateItem, DeleteItem, Query | Simple CRUD operations |
| **SQS** | SendMessage | Enqueuing messages |
| **SNS** | Publish | Sending notifications |
| **EventBridge** | PutEvents | Emitting domain events |
| **ECS/Fargate** | RunTask | Long-running container tasks |
| **Glue** | StartJobRun | ETL jobs |
| **SageMaker** | CreateTransformJob, CreateTrainingJob | ML pipeline steps |
| **Bedrock** | InvokeModel | LLM inference calls |
| **S3** | GetObject, PutObject, CopyObject | File operations |
| **Lambda** | Invoke | Complex business logic that needs code |

## Input/Output Processing Pipeline

Step Functions processes data through a pipeline at each state:

```
InputPath -> Parameters -> Task -> ResultSelector -> ResultPath -> OutputPath
```

### InputPath

Filters what the state sees from the input. Default: `$` (everything).

```json
{
  "ProcessOrder": {
    "Type": "Task",
    "InputPath": "$.orderDetails",
    "Resource": "...",
    "Next": "Done"
  }
}
```

### Parameters

Constructs the payload sent to the task. Use `.$` suffix for JSONPath references.

```json
{
  "ProcessOrder": {
    "Type": "Task",
    "Parameters": {
      "orderId.$": "$.orderId",
      "timestamp.$": "$$.State.EnteredTime",
      "staticValue": "PROCESSING"
    },
    "Resource": "...",
    "Next": "Done"
  }
}
```

### ResultSelector

Reshapes the task result before merging back. Use to trim large API responses.

```json
{
  "GetOrder": {
    "Type": "Task",
    "Resource": "arn:aws:states:::dynamodb:getItem",
    "Parameters": {
      "TableName": "Orders",
      "Key": { "orderId": {"S.$": "$.orderId"} }
    },
    "ResultSelector": {
      "orderId.$": "$.Item.orderId.S",
      "status.$": "$.Item.status.S",
      "amount.$": "$.Item.amount.N"
    },
    "ResultPath": "$.orderData",
    "Next": "ProcessOrder"
  }
}
```

### ResultPath

Where to place the result in the original input. Use `$.taskResult` to preserve original input alongside the result.

```json
{
  "ChargeCard": {
    "Type": "Task",
    "Resource": "...",
    "ResultPath": "$.chargeResult",
    "Next": "ReserveInventory"
  }
}
```

Without `ResultPath`, the task result **replaces** the entire state input. With `ResultPath: "$.chargeResult"`, the result is merged into the input at that path.

### OutputPath

Filters what gets passed to the next state.

```json
{
  "GetOrder": {
    "Type": "Task",
    "Resource": "...",
    "ResultPath": "$.orderData",
    "OutputPath": "$.orderData",
    "Next": "ProcessOrder"
  }
}
```

### Best Practices

- Use `ResultPath` generously to accumulate data through states
- Use `ResultSelector` to trim large API responses (saves state size and cost on Standard workflows)
- The `.$` suffix in Parameters is how you reference JSONPath values vs static strings
- `$$.` prefix accesses the context object (execution ARN, state name, entered time, task token)

## State Type Examples

### Choice State (Branching)

```json
{
  "CheckOrderType": {
    "Type": "Choice",
    "Choices": [
      {
        "Variable": "$.orderType",
        "StringEquals": "express",
        "Next": "ExpressShipping"
      },
      {
        "Variable": "$.amount",
        "NumericGreaterThan": 1000,
        "Next": "RequireApproval"
      }
    ],
    "Default": "StandardShipping"
  }
}
```

### Parallel State (Concurrent Branches)

```json
{
  "ProcessInParallel": {
    "Type": "Parallel",
    "Branches": [
      {
        "StartAt": "ChargeCard",
        "States": {
          "ChargeCard": { "Type": "Task", "Resource": "...", "End": true }
        }
      },
      {
        "StartAt": "ReserveInventory",
        "States": {
          "ReserveInventory": { "Type": "Task", "Resource": "...", "End": true }
        }
      }
    ],
    "Catch": [{"ErrorEquals": ["States.ALL"], "Next": "RollbackAll"}],
    "Next": "ConfirmOrder"
  }
}
```

### Inline Map State (Iterate Over Collections)

```json
{
  "ProcessItems": {
    "Type": "Map",
    "ItemsPath": "$.items",
    "MaxConcurrency": 10,
    "ItemProcessor": {
      "ProcessorConfig": {
        "Mode": "INLINE"
      },
      "StartAt": "ProcessItem",
      "States": {
        "ProcessItem": { "Type": "Task", "Resource": "...", "End": true }
      }
    },
    "Next": "Done"
  }
}
```

### Wait State

```json
{
  "WaitForApproval": {
    "Type": "Wait",
    "Seconds": 3600,
    "Next": "CheckApproval"
  }
}
```

Wait until a specific timestamp:

```json
{
  "WaitUntilDelivery": {
    "Type": "Wait",
    "TimestampPath": "$.deliveryTime",
    "Next": "Deliver"
  }
}
```
