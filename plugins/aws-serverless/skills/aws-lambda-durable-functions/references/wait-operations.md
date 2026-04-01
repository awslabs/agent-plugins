# Wait Operations

Suspend execution without compute charges for delays, external callbacks, and polling.

## Simple Waits

Pause execution for a duration with no compute charges. Always name waits for debugging.

**Max wait duration:** Up to 1 year.

| Language   | Sync Wait                                         | Async Wait                                     |
| ---------- | ------------------------------------------------- | ---------------------------------------------- |
| TypeScript | `context.wait('name', { seconds: N })`            | N/A (all waits are async)                      |
| Python     | `context.wait(duration=Duration.from_seconds(N))` | N/A                                            |
| Java       | `ctx.wait("name", Duration.ofSeconds(N))`         | `ctx.waitAsync("name", Duration.ofSeconds(N))` |

## Wait for Callback

Wait for external systems to respond (human approval, webhook, async job). The SDK generates a callback ID passed to a submitter function, then suspends until the external system calls back.

### Callback Commands

Success:

```bash
aws lambda send-durable-execution-callback-success \
  --callback-id <callbackId> \
  --payload '{"status": "approved", "comments": "Looks good"}'
```

Failure:

```bash
aws lambda send-durable-execution-callback-failure \
  --callback-id <callbackId> \
  --error-type "ApprovalDenied" \
  --error-message "Request denied by approver"
```

Heartbeat (keep callback alive during long-running external processes):

```bash
aws lambda send-durable-execution-callback-heartbeat \
  --callback-id <callbackId>
```

### Callback Configuration

Always set a timeout. Use heartbeat timeout for long-running external processes that should send periodic heartbeats to prevent early timeout.

## Wait for Condition

Poll until a condition is met (job completion, resource availability). Provide a check function, initial state, and a wait strategy controlling polling intervals.

### Wait Strategies

- **Exponential backoff** (recommended): Configure max attempts, initial/max delay, and backoff rate
- **Custom strategy**: Implement a function receiving current state and attempt count, return continue/stop with delay

## Callback Patterns

Common patterns using callbacks:

- **Human approval**: Send callback ID in approval email, wait for approve/reject response
- **Webhook integration**: Pass callback ID as webhook URL parameter, wait for payment/event notification
- **Async job polling**: Start a batch job, use `waitForCondition` to poll until completion

## Best Practices

1. **Always name wait operations** for debugging
2. **Set appropriate timeouts** to prevent indefinite waits
3. **Use heartbeats** for long-running external processes
4. **Handle callback failures** explicitly
5. **Implement exponential backoff** for polling
6. **Keep check functions lightweight** in waitForCondition
7. **Store callback IDs securely** when sending to external systems
8. **Validate callback payloads** before processing

## Error Handling

| Language   | Timeout Exception                       | Failure Exception         | Condition Exception               |
| ---------- | --------------------------------------- | ------------------------- | --------------------------------- |
| TypeScript | `CallbackError` (errorType: 'Timeout')  | `CallbackError`           | N/A                               |
| Python     | `CallbackError` (error_type: 'Timeout') | `CallbackError`           | N/A                               |
| Java       | `CallbackTimeoutException`              | `CallbackFailedException` | `WaitForConditionFailedException` |

## Code Examples

- [TypeScript](snippets/wait-operations-typescript.md)
- [Python](snippets/wait-operations-python.md)
- [Java](snippets/wait-operations-java.md)
