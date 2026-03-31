# Error Handling and Retry Strategies

Comprehensive error handling patterns for durable functions.

## Retry Strategies

### Exponential Backoff (Recommended)

Configure with max attempts, initial/max delay, backoff rate, and jitter. Use `FULL` jitter to avoid thundering herd problems.

### Fixed Delay

Set `backoffRate: 1` for constant delay between retries.

### Custom Retry Logic

Implement a function receiving error and attempt count, returning a retry decision. Use to skip retries for specific error types (e.g., client errors, validation errors).

### Retryable Error Types

Filter retries to specific error types only (e.g., `NetworkError`, `TimeoutError`). Non-matching errors fail immediately.

## Error Classification

### Retryable Errors

| Language | Exception Type | Description |
|---|---|---|
| TypeScript | `StepError` | Step failed, may be retried |
| Python | `InvocationError` | Transient infrastructure issue |
| Java | `StepInterruptedException` | Transient/interrupted, may retry at invocation level |

### Non-Retryable Errors

| Language | Exception Type | Description |
|---|---|---|
| TypeScript | `UnrecoverableInvocationError` | Stops execution immediately |
| Python | `ExecutionError` | Permanent business logic failure |
| Java | `StepFailedException` | All retries exhausted, permanent failure |
| Java | `CallbackFailedException` | Callback reported failure |
| Java | `CallbackTimeoutException` | Callback timed out |

### Preventing Retry

| Language | Mechanism |
|---|---|
| TypeScript | Throw `UnrecoverableInvocationError` |
| Python | Raise `ExecutionError` |
| Java | Throw any unchecked exception from step |

## Saga Pattern

Implement compensating transactions for distributed workflows:

1. Track compensations as each step succeeds
2. On failure, execute compensations in reverse order
3. Log compensation failures but continue with remaining compensations
4. Re-throw the original error after all compensations complete

## Circuit Breaker Pattern

Wrap external service calls in a circuit breaker that tracks failures and opens after a threshold. After a timeout period, allow a single test request (half-open state).

## Partial Failure Handling

Use completion policies in map operations to tolerate a percentage of failures. Inspect batch results for failed items and store them for later retry.

## Error Determinism

Ensure errors are deterministic across replays. Use custom error classes with stable properties (code, message) rather than runtime-dependent values.

## Best Practices

1. **Use exponential backoff** with jitter for most retry scenarios
2. **Classify errors correctly** — distinguish retryable from non-retryable
3. **Implement compensating transactions** for distributed workflows
4. **Make errors deterministic** — same input produces same error
5. **Use unrecoverable errors** to stop execution early when appropriate
6. **Log errors with context** using the SDK logger
7. **Handle partial failures** gracefully in batch operations
8. **Implement circuit breakers** for external service calls
9. **Test error scenarios** thoroughly with test runners

## Code Examples

- [TypeScript](snippets/error-handling-typescript.md)
- [Python](snippets/error-handling-python.md)
- [Java](snippets/error-handling-java.md)
