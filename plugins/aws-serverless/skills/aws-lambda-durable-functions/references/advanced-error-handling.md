# Advanced Error Handling

Advanced error handling patterns for durable functions, including timeout handling, circuit breakers, and conditional retry strategies.

## Timeout Handling with waitForCallback

Handle callback timeouts with fallback logic:

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context) => {
  try {
    // Wait for external approval with timeout
    const approval = await context.waitForCallback(
      'wait-for-approval',
      async (callbackId, ctx) => {
        ctx.logger.info('Sending approval request', { callbackId });
        await sendApprovalEmail(event.approverEmail, callbackId);
      },
      { timeout: { hours: 24 } }
    );

    context.logger.info('Approval received', { approval });
    return { status: 'approved', approval };

  } catch (error: any) {
    // Check for callback timeout
    if (error.name === 'CallbackTimeoutError' ||
        error.message?.includes('timeout')) {

      context.logger.warn('Approval timed out after 24 hours', {
        approverEmail: event.approverEmail,
        error: error.message,
      });

      // Implement fallback: auto-escalate
      await context.step('handle-timeout', async (stepCtx) => {
        stepCtx.logger.info('Escalating to manager due to timeout');
        await escalateToManager(event);
      });

      return { status: 'timeout', escalated: true };
    }

    // Re-throw other errors
    throw error;
  }
});
```

**Python:**

```python
@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    try:
        # Wait for approval
        def submit_callback(callback_id: str):
            send_approval_email(event['approver_email'], callback_id)

        approval = context.wait_for_callback(
            submitter=submit_callback,
            config=WaitForCallbackConfig(timeout=Duration.from_hours(24)),
            name='wait-for-approval'
        )

        return {'status': 'approved', 'approval': approval}

    except Exception as error:
        # Check for timeout
        if 'timeout' in str(error).lower():
            context.logger.warning('Approval timed out')

            # Escalate
            context.step(
                lambda _: escalate_to_manager(event),
                name='handle-timeout'
            )

            return {'status': 'timeout', 'escalated': True}

        raise
```

## Local Timeout with Promise.race

For step-level timeouts within a single invocation:

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context) => {
  try {
    // Operation with local timeout
    const result = await Promise.race([
      context.step('long-operation', async () => longRunningTask()),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Operation timeout')), 30000)
      ),
    ]);

    return result;
  } catch (error: any) {
    if (error.message === 'Operation timeout') {
      context.logger.warn('Operation timed out, implementing fallback');
      return await context.step('fallback', async () => fallbackOperation());
    }
    throw error;
  }
});
```

**Note:** Promise.race only works within a single Lambda invocation. For timeouts across replays, use `timeout` option on `waitForCallback` or `waitForCondition`.

## Conditional Retry Based on Error Type

**TypeScript:**

```typescript
import { createRetryStrategy } from '@aws/durable-execution-sdk-js';

const result = await context.step(
  'api-call',
  async () => callExternalAPI(),
  {
    retryStrategy: (error, attemptCount) => {
      // Don't retry client errors (4xx)
      if (error.statusCode >= 400 && error.statusCode < 500) {
        return { shouldRetry: false };
      }

      // Retry server errors (5xx) with exponential backoff
      if (error.statusCode >= 500) {
        return {
          shouldRetry: attemptCount < 5,
          delay: { seconds: Math.pow(2, attemptCount) }
        };
      }

      // Retry network errors with fixed delay
      if (error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
        return {
          shouldRetry: attemptCount < 10,
          delay: { seconds: 5 }
        };
      }

      // Don't retry unknown errors
      return { shouldRetry: false };
    }
  }
);
```

**Python:**

```python
def custom_retry_strategy(error: Exception, attempt_count: int) -> RetryDecision:
    # Don't retry client errors
    if hasattr(error, 'status_code'):
        if 400 <= error.status_code < 500:
            return RetryDecision(should_retry=False)
        
        # Retry server errors with exponential backoff
        if error.status_code >= 500:
            return RetryDecision(
                should_retry=attempt_count < 5,
                delay=Duration.from_seconds(2 ** attempt_count)
            )
    
    # Retry network errors
    if isinstance(error, (ConnectionError, TimeoutError)):
        return RetryDecision(
            should_retry=attempt_count < 10,
            delay=Duration.from_seconds(5)
        )
    
    # Don't retry unknown errors
    return RetryDecision(should_retry=False)

result = context.step(
    lambda _: call_external_api(),
    name='api-call',
    retry_strategy=custom_retry_strategy
)
```

## Circuit Breaker Pattern

Protect against cascading failures by temporarily stopping requests to failing services:

**TypeScript:**

```typescript
let failureCount = 0;
let lastFailureTime = 0;
const CIRCUIT_OPEN_DURATION = 60000; // 1 minute

const result = await context.step(
  'call-with-circuit-breaker',
  async () => {
    const now = Date.now();

    // Check if circuit is open
    if (failureCount >= 5 && (now - lastFailureTime) < CIRCUIT_OPEN_DURATION) {
      throw new Error('Circuit breaker is open');
    }

    try {
      const result = await callExternalService();
      failureCount = 0; // Reset on success
      return result;
    } catch (error) {
      failureCount++;
      lastFailureTime = now;
      throw error;
    }
  },
  {
    retryStrategy: (error, attemptCount) => {
      if (error.message === 'Circuit breaker is open') {
        return {
          shouldRetry: true,
          delay: { seconds: 60 } // Wait before checking circuit again
        };
      }

      return {
        shouldRetry: attemptCount < 3,
        delay: { seconds: 2 }
      };
    }
  }
);
```

**Python:**

```python
failure_count = 0
last_failure_time = 0
CIRCUIT_OPEN_DURATION = 60  # seconds

def call_with_circuit_breaker():
    global failure_count, last_failure_time
    now = time.time()
    
    # Check if circuit is open
    if failure_count >= 5 and (now - last_failure_time) < CIRCUIT_OPEN_DURATION:
        raise Exception('Circuit breaker is open')
    
    try:
        result = call_external_service()
        failure_count = 0  # Reset on success
        return result
    except Exception as error:
        failure_count += 1
        last_failure_time = now
        raise

def circuit_breaker_retry(error: Exception, attempt_count: int) -> RetryDecision:
    if 'Circuit breaker is open' in str(error):
        return RetryDecision(
            should_retry=True,
            delay=Duration.from_seconds(60)
        )
    
    return RetryDecision(
        should_retry=attempt_count < 3,
        delay=Duration.from_seconds(2)
    )

result = context.step(
    lambda _: call_with_circuit_breaker(),
    name='call-with-circuit-breaker',
    retry_strategy=circuit_breaker_retry
)
```

## Error Handling Best Practices

1. **Timeout Handling**: Always implement fallback logic for callback timeouts
2. **Conditional Retries**: Retry based on error type (don't retry client errors)
3. **Circuit Breakers**: Protect against cascading failures to external services
4. **Structured Logging**: Log error context for debugging
5. **Graceful Degradation**: Return partial results when possible
6. **Error Classification**: Distinguish between transient and permanent failures

## Common Error Patterns

### Transient Errors (Should Retry)

- Network timeouts
- Service unavailable (503)
- Rate limiting (429)
- Database connection failures

### Permanent Errors (Should Not Retry)

- Invalid input (400)
- Authentication failures (401, 403)
- Resource not found (404)
- Business logic violations

### Timeout Errors (Need Fallback)

- Callback timeouts
- External system delays
- Long-running operations
