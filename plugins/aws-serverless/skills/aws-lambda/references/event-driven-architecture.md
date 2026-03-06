# Event-Driven Architecture Guide

## Choreography vs Orchestration

The most important architectural decision in an event-driven system is whether services coordinate through choreography or orchestration.

|                      | Choreography                                             | Orchestration                                                                           |
| -------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| **How it works**     | Services emit events; other services react independently | A central coordinator (Step Functions, Durable Functions) directs each step             |
| **Coupling**         | Loose — publisher doesn't know about consumers           | Tighter — coordinator knows about each step                                             |
| **Visibility**       | Distributed; hard to see the full flow                   | Centralized; execution history in one place                                             |
| **Failure handling** | Each service handles its own failures                    | Central error handling and retry logic                                                  |
| **Best for**         | Independent services reacting to facts about the world   | Business-critical workflows requiring audit trails, visibility, and reliable sequencing |

**Use choreography (EventBridge + Lambda)** when services are genuinely independent and don't need to know the outcome of each other's processing.

**Use orchestration (Step Functions / Lambda durable functions)** when you need reliable sequencing, compensating transactions, human approval steps, or the ability to visualize and debug the full workflow.

In practice, most systems use both: orchestration within a bounded context, choreography between bounded contexts.

---

## EventBridge Concepts

### Event Bus Types

| Type            | Use Case                                                                       |
| --------------- | ------------------------------------------------------------------------------ |
| **Default bus** | Receives AWS service events (EC2 state changes, S3 events, CodePipeline, etc.) |
| **Custom bus**  | Your application events; recommended for all custom event routing              |
| **Partner bus** | Receives events from SaaS partners (Datadog, Zendesk, Stripe, etc.)            |

Always use a **custom event bus** for application events — keeps your events separate from AWS service noise and simplifies IAM and monitoring.

### Standard EventBridge Event Structure

Every event on the bus has this envelope (added automatically by EventBridge):

```json
{
  "version": "0",
  "id": "12345678-1234-1234-1234-123456789012",
  "source": "com.mycompany.orders",
  "detail-type": "OrderPlaced",
  "account": "123456789012",
  "time": "2025-01-15T10:30:00Z",
  "region": "us-east-1",
  "resources": [],
  "detail": {
    "orderId": "ord-987",
    "userId": "usr-123",
    "total": 49.99
  }
}
```

- `source` — identifies the publishing service (`com.mycompany.orders`)
- `detail-type` — identifies the event type (`OrderPlaced`)
- `detail` — your business payload (up to 1 MB per event entry)

### SAM Configuration

**Custom event bus:**

```yaml
OrderEventBus:
  Type: AWS::Events::EventBus
  Properties:
    Name: order-events

OrderEventBusArn:
  Type: AWS::SSM::Parameter
  Properties:
    Name: /myapp/order-event-bus-arn
    Value: !GetAtt OrderEventBus.Arn
    Type: String
```

**Lambda publishing events:**

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    Policies:
      - Statement:
          - Effect: Allow
            Action: events:PutEvents
            Resource: !GetAtt OrderEventBus.Arn
    Environment:
      Variables:
        EVENT_BUS_ARN: !GetAtt OrderEventBus.Arn
```

**Lambda subscribing via rule:**

```yaml
ProcessOrderFunction:
  Type: AWS::Serverless::Function
  Properties:
    Events:
      OrderPlaced:
        Type: EventBridgeRule
        Properties:
          EventBusName: !Ref OrderEventBus
          Pattern:
            source:
              - com.mycompany.orders
            detail-type:
              - OrderPlaced
          RetryPolicy:
            MaximumRetryAttempts: 3
            MaximumEventAgeInSeconds: 3600
          DeadLetterConfig:
            Type: SQS
            QueueLogicalId: ProcessOrderDLQ

ProcessOrderDLQ:
  Type: AWS::SQS::Queue
  Properties:
    MessageRetentionPeriod: 1209600  # 14 days
```

### Publishing Events from Lambda

**Python:**

```python
import json
import os
from datetime import datetime, timezone
import uuid
import boto3
from aws_lambda_powertools import Logger

logger = Logger()
events_client = boto3.client("events")
event_bus_arn = os.environ["EVENT_BUS_ARN"]

def publish_order_placed(order: dict):
    events_client.put_events(
        Entries=[{
            "EventBusName": event_bus_arn,
            "Source": "com.mycompany.orders",
            "DetailType": "OrderPlaced",
            "Detail": json.dumps({
                "metadata": {
                    "id": str(uuid.uuid4()),
                    "version": "1",
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "correlationId": logger.get_correlation_id(),
                    "service": "order-service",
                },
                "data": order,
            }),
        }]
    )
```

**TypeScript:**

```typescript
import { EventBridgeClient, PutEventsCommand } from '@aws-sdk/client-eventbridge';
import { randomUUID } from 'crypto';

const client = new EventBridgeClient({});
const eventBusArn = process.env.EVENT_BUS_ARN!;

async function publishOrderPlaced(order: Record<string, unknown>): Promise<void> {
  await client.send(new PutEventsCommand({
    Entries: [{
      EventBusName: eventBusArn,
      Source: 'com.mycompany.orders',
      DetailType: 'OrderPlaced',
      Detail: JSON.stringify({
        metadata: {
          id: randomUUID(),
          version: '1',
          timestamp: new Date().toISOString(),
          service: 'order-service',
        },
        data: order,
      }),
    }],
  }));
}
```

---

## Event Patterns (Content-Based Routing)

EventBridge rules use **event patterns** to filter which events reach a target. Patterns match against the standard envelope fields and anything inside `detail`.

**All values are arrays** — a field matches if the event value equals any element in the array:

```json
{
  "source": ["com.mycompany.orders"],
  "detail-type": ["OrderPlaced", "OrderUpdated"],
  "detail": {
    "status": ["CONFIRMED"],
    "total": [{ "numeric": [">", 100] }]
  }
}
```

**Common pattern operators:**

| Operator        | Example                                         | Matches                   |
| --------------- | ----------------------------------------------- | ------------------------- |
| Exact match     | `"status": ["ACTIVE"]`                          | status equals "ACTIVE"    |
| Multiple values | `"status": ["ACTIVE", "PENDING"]`               | status is either          |
| Prefix          | `"id": [{"prefix": "ord-"}]`                    | id starts with "ord-"     |
| Anything-but    | `"status": [{"anything-but": ["CANCELLED"]}]`   | status is not "CANCELLED" |
| Exists          | `"refundId": [{"exists": true}]`                | refundId field is present |
| Numeric range   | `"amount": [{"numeric": [">=", 0, "<", 1000]}]` | 0 ≤ amount < 1000         |
| Null            | `"coupon": [null]`                              | coupon field is null      |

**Up to 5 targets per rule.** If you need to fan out to more consumers, route to an SNS topic or use the rule to fan out via SQS.

---

## Event Design

### Event Envelopes

Wrap your business payload in a custom metadata layer inside `detail`. This provides consistent fields for filtering, deduplication, and observability across all events regardless of the transport (EventBridge, SNS, SQS, Kinesis):

```json
{
  "metadata": {
    "id": "01HXHMF28A94NS7NSHC5GM80F4",
    "version": "1",
    "timestamp": "2025-01-15T10:30:00Z",
    "domain": "orders",
    "service": "order-service",
    "correlationId": "req-abc123"
  },
  "data": {
    "orderId": "ord-987",
    "userId": "usr-123",
    "total": 49.99
  }
}
```

**Key metadata fields:**

- `id` — unique event identifier; use for idempotency deduplication
- `version` — schema version of the `data` payload
- `timestamp` — when the event occurred (not when it was received)
- `correlationId` — trace ID that flows through the entire request chain
- `domain` / `service` — for filtering and observability

### Light Events vs Rich Events

**Light events** carry only IDs and directly relevant fields. Consumers fetch additional data they need.

**Rich events** include expanded entities — the complete state of the object at the time of the event.

|                           | Light events                              | Rich events                           |
| ------------------------- | ----------------------------------------- | ------------------------------------- |
| **Payload size**          | Small                                     | Large                                 |
| **Subscriber complexity** | Higher (must hydrate)                     | Lower (self-contained)                |
| **Race conditions**       | Risk between event publish and data fetch | None                                  |
| **Coupling**              | Consumer coupled to publisher's API       | Consumer coupled to event schema only |

**Guidance:**

- **Within a bounded context** (same team, same domain): light events are fine — you control both sides
- **Across bounded contexts** (different teams, different domains): prefer rich events — unknown consumers shouldn't need to call back into your service to understand what happened

### Event Versioning

Prefer the **no-breaking-changes policy**: always add new fields, never remove or rename existing fields, never change a field's type. Consumers that ignore unknown fields continue working without any changes.

When a breaking change is unavoidable, the cleanest approach is versioning in the `detail-type`:

```text
OrderPlaced.v1   →   OrderPlaced.v2
```

Consumers subscribe to specific versions. The publisher emits both versions during the migration window, then retires `v1` once all consumers have migrated.

**Avoid:** using Lambda versions/aliases or API Gateway stages to version event-driven integrations — IAM roles don't version alongside function versions, which creates subtle permission bugs.

---

## Retry Policy and Dead-Letter Queues

EventBridge retries failed Lambda invocations with exponential backoff. Configure both `RetryPolicy` and a DLQ on every rule target that processes important events:

```yaml
Events:
  OrderEvent:
    Type: EventBridgeRule
    Properties:
      Pattern:
        source: [com.mycompany.orders]
      RetryPolicy:
        MaximumRetryAttempts: 3         # 0–185; default 185
        MaximumEventAgeInSeconds: 3600  # 60–86400; default 86400 (24h)
      DeadLetterConfig:
        Type: SQS
        QueueLogicalId: MyDLQ
```

- `MaximumRetryAttempts` — how many times EventBridge retries before sending to DLQ
- `MaximumEventAgeInSeconds` — EventBridge stops retrying after this age, even if retries remain
- Without a DLQ, events that exhaust retries are silently dropped

**Process your DLQ actively.** Set a CloudWatch alarm on `ApproximateNumberOfMessagesVisible` and reprocess events by replaying them back to the event bus.

---

## Archive and Replay

EventBridge can archive all events (or a filtered subset) and replay them at any time. This is invaluable for:

- Reprocessing events after deploying a bug fix
- Bootstrapping new consumers with historical events
- Disaster recovery

**Create an archive in SAM:**

```yaml
OrderEventArchive:
  Type: AWS::Events::Archive
  Properties:
    SourceArn: !GetAtt OrderEventBus.Arn
    EventPattern:
      source:
        - com.mycompany.orders
    RetentionDays: 30
```

Replay from the console, CLI, or API by specifying the archive, a time range, and optionally a different target bus.

---

## EventBridge Pipes

Pipes provide **point-to-point** integrations following a Source → Filter → Enrich → Target pattern. Use Pipes when you need to:

- Connect a stream/queue source to a target with enrichment (e.g., add customer data before sending to Step Functions)
- Filter events before they reach the target (you only pay for events that pass the filter)
- Transform payloads without writing a Lambda function

```yaml
OrderPipe:
  Type: AWS::Pipes::Pipe
  Properties:
    Source: !GetAtt OrderQueue.Arn
    SourceParameters:
      SqsQueueParameters:
        BatchSize: 10
    Filter:
      Filters:
        - Pattern: '{"body": {"eventType": ["ORDER_CREATED"]}}'
    Enrichment: !GetAtt EnrichOrderFunction.Arn
    Target: !Ref OrderProcessingStateMachine
    TargetParameters:
      StepFunctionStateMachineParameters:
        InvocationType: FIRE_AND_FORGET
    RoleArn: !GetAtt PipeRole.Arn
```

**Pipes vs Rules:**

- Use **Pipes** for point-to-point (one source → one target) with enrichment or transformation
- Use **Rules** for fan-out (one event → multiple targets) or when the source is the event bus itself

---

## Schema Registry

The EventBridge Schema Registry discovers and stores schemas for events on your bus. Use it to generate typed code bindings and enforce contracts.

**Discover schemas automatically** by enabling schema discovery on your event bus:

```yaml
OrderBusDiscovery:
  Type: AWS::EventSchemas::Discoverer
  Properties:
    SourceArn: !GetAtt OrderEventBus.Arn
```

Once events flow through the bus, schemas appear in the registry. Then use the MCP tools to work with them:

1. `list_registries` — browse available registries
2. `search_schema` with keywords (e.g., `"order"`) — find relevant schemas
3. `describe_schema` — get the full schema definition
4. Download code bindings from the console (Java, Python, TypeScript) — generates typed event classes

**Use schemas as contracts:** consumer teams reference a specific schema version. The publisher must not make breaking changes to a versioned schema without bumping the version.

---

## Push vs Poll

| Pattern  | Services                           | Characteristics                                                                        |
| -------- | ---------------------------------- | -------------------------------------------------------------------------------------- |
| **Push** | EventBridge, SNS                   | Low latency; event delivered as soon as it occurs; minimal compute waste at low volume |
| **Poll** | SQS+ESM, Kinesis, DynamoDB Streams | Full throughput control; ordered processing; higher latency; better for batching       |

Choose **push (EventBridge)** when:

- You need real-time fan-out to multiple independent consumers
- Services are loosely coupled and don't need ordering guarantees
- You want content-based routing without consumer-side filtering code

Choose **poll (SQS/Kinesis)** when:

- You need strict ordering within a partition or message group
- Consumer needs to control throughput (e.g., protect a downstream database)
- You need large batch sizes for cost efficiency (e.g., bulk database writes)

---

## Observability

For EventBridge metrics to alarm on, CloudWatch Logs Insights queries, and correlation ID propagation patterns, see [observability.md](observability.md).

**Key principle:** X-Ray traces Lambda execution but does not automatically connect publisher to consumer across the event bus. Propagate `correlationId` in the event `metadata` envelope (see Event Envelopes above) and use CloudWatch Logs Insights to reconstruct cross-service request chains.
