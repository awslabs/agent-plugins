# Advanced Error Handling

Advanced error handling patterns for durable functions, including timeout handling, circuit breakers, and conditional retry strategies.

**API Reference Conventions:**

- TypeScript/Python: Method names reference the `context` object (e.g., `waitForCallback` means `context.waitForCallback`)
- Java: Full reference with `ctx` prefix (e.g., `ctx.waitForCallback`) since Java uses `ctx` as the conventional variable name

## Timeout Handling with Callbacks

**Pattern:** Wait for an external callback with a timeout, and implement fallback logic if the timeout is reached.

**Implementation approach:**

1. Use `waitForCallback` (TypeScript), `wait_for_callback` (Python), or `ctx.waitForCallback` (Java) with a timeout configuration set in the config argument
2. Wrap in try-catch to handle timeout errors
3. Check if the error is a timeout
4. Implement fallback logic in a step (e.g., escalate to manager, use default value, retry with different parameters)
5. Return appropriate status indicating timeout occurred

**Key considerations:**

- Timeout errors are thrown when the callback doesn't complete within the specified duration
- Fallback logic should be in a step to ensure it's checkpointed
- Log timeout events for monitoring and debugging

## Local Timeout with Promise.race in Typescript SDK

**Pattern:** Implement a timeout for a step operation within a single Lambda invocation.

**Implementation approach:**

1. Use `Promise.race()` to race the step operation against a timeout promise
2. The timeout promise rejects after the specified duration
3. Catch the timeout error and implement fallback logic
4. Execute fallback operation in a separate step

**Important limitation:**
In TypeScript, native setTimeout (and patterns like Promise.race using it) will fail during execution replays. To create a reliable timeout that persists across execution (expands over multi invocations), always use the timeout parameter provided by waitForCallback or waitForCondition.

**Java equivalent - DurableFuture.anyOf:**
Java provides `DurableFuture.anyOf()` for racing multiple async operations, similar to `Promise.race()` in TypeScript:

```java
// Race multiple async operations - first to complete wins
var f1 = ctx.stepAsync("primary-api", Result.class, s -> callPrimaryAPI());
var f2 = ctx.stepAsync("backup-api", Result.class, s -> callBackupAPI());

// Wait for first to complete
DurableFuture.anyOf(f1, f2);

// Check which completed first
Result result;
try {
    result = f1.get();
    ctx.getLogger().info("Primary API completed first");
} catch (Exception e) {
    result = f2.get();
    ctx.getLogger().info("Backup API completed first");
}
```

For reliable cross-invocation timeouts that persist across replays, always use the timeout configuration in `WaitForCallbackConfig` or `WaitForConditionConfig`.

## Conditional Retry Based on Error Type

**Pattern:** Retry operations selectively based on the type of error encountered.

**Implementation approach:**

1. Define a custom retry strategy function that examines the error
2. For client errors (4xx): Don't retry - these are permanent failures
3. For server errors (5xx): Retry with exponential backoff
4. For network errors: Retry with fixed delay
5. For unknown errors: Don't retry by default

**Key considerations:**

- Client errors (400-499) typically indicate bad input and shouldn't be retried
- Server errors (500-599) are often transient and benefit from retry
- Network errors (connection refused, timeout) should retry with reasonable limits
- Use exponential backoff for server errors to avoid overwhelming the service
- Set maximum retry attempts to prevent infinite loops

## Circuit Breaker Pattern

**Pattern:** Temporarily stop making requests to a failing external service to prevent cascading failures.

**Implementation approach:**

1. Track failure count and last failure time (note: these reset on replay due to closure mutations)
2. Check if circuit is "open" (too many recent failures)
3. If open, throw a circuit breaker error and wait before retrying
4. If closed, attempt the operation
5. On success, reset failure count
6. On failure, increment failure count and record timestamp
7. Configure retry strategy to wait longer when circuit is open

**Important caveat:** The example implementations use closure variables (`failureCount`, `lastFailureTime`) which reset on replay. For production use, store circuit breaker state in:

- A step return value that persists across replays
- An external store like DynamoDB
- A durable variable pattern

**Key considerations:**

- Circuit breaker prevents cascading failures to downstream services
- The "open" duration should be long enough for the service to recover
- Reset the circuit on successful operations
- Log circuit state changes for monitoring

## Error Handling Best Practices

1. **Timeout Handling**: Always implement fallback logic for callback timeouts - don't let executions fail silently
2. **Conditional Retries**: Classify errors as transient vs permanent, only retry transient errors
3. **Circuit Breakers**: Protect against cascading failures to external services, especially for high-volume operations
4. **Structured Logging**: Log error context (error type, attempt count, operation name) for debugging
5. **Graceful Degradation**: Return partial results when possible rather than failing completely
6. **Error Classification**: Distinguish between client errors (don't retry), server errors (retry with backoff), and network errors (retry with fixed delay)

## Common Error Patterns

### Transient Errors (Should Retry)

- Network timeouts
- Service unavailable (503)
- Rate limiting (429)
- Database connection failures
- Temporary infrastructure issues

### Permanent Errors (Should Not Retry)

- Invalid input (400)
- Authentication failures (401, 403)
- Resource not found (404)
- Business logic violations
- Validation errors

### Timeout Errors (Need Fallback)

- Callback timeouts - external system didn't respond in time
- External system delays - service is slow or unresponsive
- Long-running operations - operation exceeded expected duration

## Exception Type Reference

Complete exception types by category and language:

### TypeScript SDK Exceptions

| Exception Type                 | Category         | Retryable | Use Case                                          |
| ------------------------------ | ---------------- | --------- | ------------------------------------------------- |
| `UnrecoverableInvocationError` | Permanent        | No        | Business logic failures (validation, not found)   |
| `InvocationError`              | Transient        | Yes       | Infrastructure issues (Lambda retries invocation) |
| `CallbackTimeoutError`         | Timeout          | No        | Callback didn't complete within timeout duration  |
| `CallbackError`                | Callback Failure | No        | Callback failed or was explicitly rejected        |
| `WaitForConditionTimeoutError` | Timeout          | No        | Condition polling exceeded timeout                |
| `DurableExecutionsError`       | Base             | —         | Base class for all SDK exceptions                 |

### Python SDK Exceptions

| Exception Type           | Category         | Retryable | Use Case                                          |
| ------------------------ | ---------------- | --------- | ------------------------------------------------- |
| `ExecutionError`         | Permanent        | No        | Business logic failures (returns FAILED status)   |
| `InvocationError`        | Transient        | Yes       | Infrastructure issues (Lambda retries invocation) |
| `CallbackError`          | Callback Failure | No        | Callback handling failures                        |
| `DurableExecutionsError` | Base             | —         | Base class for all SDK exceptions                 |

### Java SDK Exceptions

| Exception Type                    | Category          | Retryable | Use Case                                                |
| --------------------------------- | ----------------- | --------- | ------------------------------------------------------- |
| `StepFailedException`             | Permanent         | No        | Step execution failed (business logic error)            |
| `StepInterruptedException`        | Transient         | Yes       | Step was interrupted (can retry)                        |
| `CallbackTimeoutException`        | Timeout           | No        | Callback didn't complete within timeout duration        |
| `CallbackFailedException`         | Callback Failure  | No        | Callback failed or was explicitly rejected              |
| `WaitForConditionFailedException` | Condition Failure | No        | Condition check failed or max polling attempts exceeded |
| `InvokeFailedException`           | Invoke Failure    | No        | Lambda invocation failed                                |
| `InvokeTimedOutException`         | Timeout           | No        | Lambda invocation timed out                             |
| `DurableExecutionException`       | Base              | —         | Base class for all SDK exceptions                       |

### Usage Guidelines

**Permanent failures** - Stop execution immediately, no retry:

- Validation errors
- Resource not found
- Authentication failures
- Business rule violations

**Transient failures** - Retry with backoff:

- Network timeouts
- Service unavailable (503)
- Rate limiting (429)
- Database connection failures

**Timeout failures** - Implement fallback logic:

- Callback timeouts → escalate to manager, use default value
- Condition timeouts → return partial results, notify operators
- Wait timeouts → trigger alternative workflow
