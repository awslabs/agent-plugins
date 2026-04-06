# Messaging Integration Patterns

Architectural patterns for event-driven systems on AWS, with service mappings and implementation guidance.

## Fan-Out with Filtering

Deliver one event to multiple consumers, each receiving only the subset they care about.

```
                          ┌─ [Filter: premium] ──> SQS Queue A ──> Premium Processor
                          │
Producer ──> SNS Topic ───┼─ [Filter: standard] ──> SQS Queue B ──> Standard Processor
                          │
                          └─ [Filter: all]       ──> Lambda       ──> Analytics Pipeline
```

**When to use:** One event type needs different processing paths based on attributes (order type, priority, region).

**AWS services:** SNS + SQS (high throughput), or EventBridge rules (complex routing, <10K events/sec).

**Implementation notes:**
- Apply SNS filter policies on each subscription to avoid delivering irrelevant messages
- Each SQS queue scales independently and processes at its own pace
- Add a DLQ to every queue
- For EventBridge: use one rule per consumer with the event pattern as the filter

**SNS filter policy example:**
```json
{
  "order_type": ["premium"],
  "amount": [{"numeric": [">", 100]}]
}
```

## Saga Pattern (Choreography)

Coordinate a multi-step business process where each service publishes events and reacts to events. No central coordinator.

```
Order Service                   Payment Service                 Shipping Service
     │                                │                               │
     ├── OrderPlaced ──>              │                               │
     │              EventBridge       │                               │
     │                   ├──────────> ├── PaymentProcessed ──>        │
     │                   │            │                  EventBridge   │
     │                   │            │                       ├─────> ├── ShipmentCreated
     │                   │            │                       │       │
     │ <── ShipmentFailed ──────────────────────────────────────────  │ (compensating event)
     ├── OrderCancelled (compensation)│                               │
```

**When to use:** Multi-service transaction that must eventually reach a consistent state but does not require strong (ACID) consistency across services.

**AWS services:** EventBridge as the event bus. Each service publishes events to EventBridge and subscribes to events it cares about.

**Implementation notes:**
- Every service must handle compensating actions (rollback) when a downstream step fails
- Add a DLQ on every consumer for unprocessable events
- Use correlation IDs (e.g., `orderId`) across all events to trace the saga
- Choreography works for 3-5 services. Beyond that, consider orchestration with Step Functions.
- Set up a "saga monitor" that subscribes to all events and tracks saga state for observability

**Failure handling:**
- Service B fails: publishes a failure event. Service A reacts with compensation.
- Service B is down: EventBridge retries. DLQ catches persistent failures. Alarm on DLQ depth.
- Duplicate events: every service must be idempotent. Use `orderId` + `eventType` as deduplication key.

## Saga Pattern (Orchestration)

A central coordinator (Step Functions) manages the workflow and handles retries and compensation.

```
                     Step Functions (Orchestrator)
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼              ▼
          Order Service  Payment Service  Shipping Service
                              │
                        (on failure)
                              ▼
                     Compensation Steps
                     (reverse previous)
```

**When to use:** Complex workflows with many steps, conditional logic, or when you need centralized visibility and error handling.

**AWS services:** Step Functions as orchestrator, invoking Lambda/ECS/SQS/other services as task states.

**When to prefer orchestration over choreography:**
- More than 5 services in the saga
- Complex conditional branching
- Need centralized monitoring of all saga instances
- Compensation logic is complex and must execute in a specific order

## Queue-Based Load Leveling

Absorb traffic spikes with a queue so the consumer processes at a controlled, sustainable rate.

```
API Gateway ──> SQS Queue ──> Lambda (reserved concurrency = 10)
                   │
                   └──> DLQ (alarm on depth > 0)
```

**When to use:** Bursty or unpredictable traffic hitting a rate-limited backend (database writes, third-party API calls, batch processing).

**AWS services:** SQS (Standard or FIFO) + Lambda event source mapping, or SQS + ECS consumer.

**Implementation notes:**
- Set Lambda reserved concurrency to limit downstream pressure (e.g., database connection pool size)
- Configure Lambda event source mapping batch size (1-10,000) and batch window (0-300s) for throughput tuning
- Use SQS `ApproximateAgeOfOldestMessage` alarm to detect when the queue cannot keep up
- Visibility timeout = 6x average processing time
- Always configure a DLQ with `maxReceiveCount` of 3-5

**Scaling knobs:**
| Parameter | Effect |
|---|---|
| Lambda reserved concurrency | Max parallel consumers |
| Batch size | Messages per Lambda invocation |
| Batch window | Max wait before invoking (fills partial batches) |
| Visibility timeout | How long a message is hidden while being processed |

## CQRS (Command Query Responsibility Segregation)

Separate write and read models. Writes go to a primary store; reads come from a purpose-built view.

```
Write Path:                              Read Path:

API ──> Lambda ──> DynamoDB (commands)   API ──> Lambda ──> ElastiCache / OpenSearch
                       │                                        ▲
                       └── DynamoDB Streams ──> Lambda ──> Update read model
```

**When to use:** Read and write patterns have fundamentally different requirements (e.g., writes are simple key-value, reads need full-text search or complex aggregations).

**AWS services:**
- Write side: DynamoDB or RDS
- Change capture: DynamoDB Streams or RDS event notifications
- Read side: ElastiCache (Redis) for key lookups, OpenSearch for full-text search, another DynamoDB table for pre-computed views

**Implementation notes:**
- The read model is eventually consistent with the write model (seconds, not minutes)
- Use DynamoDB Streams + Lambda to project changes to the read store
- Idempotent projections: processing the same stream record twice must produce the same result
- Monitor stream iterator age to detect lag in read model updates

## Event Sourcing

Store every state change as an immutable event. Reconstruct current state by replaying events.

```
Command ──> Lambda ──> Append to event store (DynamoDB)
                              │
                              └── DynamoDB Streams ──> Lambda ──> Update materialized views
                                                              ──> EventBridge (notify other services)
```

**When to use:** Audit trail is a first-class requirement, or you need to reconstruct historical state at any point in time.

**AWS services:** DynamoDB as event store (partition key = entity ID, sort key = version/timestamp), DynamoDB Streams for projections.

**Implementation notes:**
- Events are immutable and append-only. Never update or delete an event.
- DynamoDB conditional writes (`attribute_not_exists` or version check) prevent conflicting appends
- Keep events small. Store only what changed, not the full entity state.
- Materialized views are read-optimized projections of the event stream
- Snapshotting: periodically save the current state to avoid replaying the full event history

## Claim-Check Pattern

For messages that exceed size limits, store the payload externally and pass a reference through the messaging system.

```
Producer ──> Store payload in S3 ──> Send S3 key via SQS ──> Consumer fetches from S3
```

**When to use:** Payloads exceed 256 KB (SQS/SNS limit) or you want to reduce messaging costs for large payloads.

**AWS services:** S3 for payload storage, SQS/SNS for the reference message. The SQS Extended Client Library automates this pattern.

## Competing Consumers

Multiple consumers read from the same queue, each processing different messages in parallel.

```
                    ┌──> Consumer A (Lambda invocation 1)
SQS Queue ──────────┼──> Consumer B (Lambda invocation 2)
                    └──> Consumer C (Lambda invocation 3)
```

**When to use:** High message volume where a single consumer cannot keep up.

**AWS services:** SQS + Lambda (auto-scales consumers), or SQS + ECS service (manual scaling).

**Implementation notes:**
- SQS Standard: messages may be delivered out of order and duplicated. Consumers must be idempotent.
- SQS FIFO with message groups: messages within the same group are processed in order by one consumer. Different groups are processed in parallel.
- Lambda automatically scales to match queue depth (up to 1,000 concurrent for Standard, limited for FIFO).

## Pattern Selection Guide

| Scenario | Pattern | Primary Services |
|---|---|---|
| One event, many consumers | Fan-out | SNS + SQS or EventBridge |
| Multi-service transaction (simple) | Saga (choreography) | EventBridge |
| Multi-service transaction (complex) | Saga (orchestration) | Step Functions |
| Bursty traffic, rate-limited backend | Queue-based load leveling | SQS + Lambda |
| Different read/write requirements | CQRS | DynamoDB Streams + read store |
| Full audit trail required | Event sourcing | DynamoDB + Streams |
| Large payloads through messaging | Claim-check | S3 + SQS |
| High-throughput parallel processing | Competing consumers | SQS + Lambda/ECS |
