# Error Handling and Retry Strategies

Comprehensive error handling patterns for durable functions.

**TypeScript:**

```typescript
import { createRetryStrategy, JitterStrategy } from '@aws/durable-execution-sdk-js';

// Exponential backoff with jitter
const result = await context.step(
  'api-call',
  async () => callAPI(),
  {
    retryStrategy: createRetryStrategy({
      maxAttempts: 5,
      initialDelay: { seconds: 1 },
      maxDelay: { seconds: 60 },
      backoffRate: 2.0,
      jitter: JitterStrategy.FULL
    })
  }
);

// Fixed delay
const result = await context.step(
  'simple-retry',
  async () => operation(),
  {
    retryStrategy: createRetryStrategy({
      maxAttempts: 3,
      delay: { seconds: 5 },
      backoffRate: 1
    })
  }
);
```

**Python:**

```python
from aws_durable_execution_sdk_python.retries import RetryStrategyConfig, create_retry_strategy, JitterStrategy

retry_config = RetryStrategyConfig(
    max_attempts=5,
    initial_delay=Duration.from_seconds(1),
    max_delay=Duration.from_seconds(60),
    backoff_rate=2.0,
    jitter_strategy=JitterStrategy.FULL
)

result = context.step(
    func=api_call(),
    config=StepConfig(retry_strategy=create_retry_strategy(retry_config))
)
```

**Java:**

```java
import java.time.Duration;
import software.amazon.lambda.durable.config.StepConfig;
import software.amazon.lambda.durable.retry.RetryStrategies;
import software.amazon.lambda.durable.retry.JitterStrategy;

// Exponential backoff with jitter
var result = ctx.step("api-call", ApiResponse.class, stepCtx -> callAPI(),
    StepConfig.builder()
        .retryStrategy(RetryStrategies.exponentialBackoff(
            5,                       // maxAttempts (including initial attempt)
            Duration.ofSeconds(1),   // initialDelay
            Duration.ofSeconds(60),  // maxDelay
            2.0,                     // backoffRate
            JitterStrategy.FULL))
        .build());

// Fixed delay
var simpleResult = ctx.step("simple-retry", Result.class, stepCtx -> operation(),
    StepConfig.builder()
        .retryStrategy(RetryStrategies.fixedDelay(3, Duration.ofSeconds(5)))
        .build());
```

## Custom Retry Logic

**TypeScript:**

```typescript
const result = await context.step(
  'custom-retry',
  async () => riskyOperation(),
  {
    retryStrategy: (error, attemptCount) => {
      // Don't retry client errors
      if (error.statusCode >= 400 && error.statusCode < 500) {
        return { shouldRetry: false };
      }
      
      // Retry server errors with exponential backoff
      if (attemptCount < 5) {
        return {
          shouldRetry: true,
          delay: { seconds: Math.pow(2, attemptCount) }
        };
      }
      
      return { shouldRetry: false };
    }
  }
);
```

**Python:**

```python
def custom_retry(error: Exception, attempt: int) -> RetryDecision:
    if hasattr(error, 'status_code') and 400 <= error.status_code < 500:
        return RetryDecision(should_retry=False)
    
    if attempt < 5:
        return RetryDecision(
            should_retry=True,
            delay=Duration.from_seconds(2 ** attempt)
        )
    
    return RetryDecision(should_retry=False)
```

**Java:**

```java
import software.amazon.lambda.durable.retry.RetryDecision;

var result = ctx.step("custom-retry", Result.class, stepCtx -> riskyOperation(),
    StepConfig.builder()
        .retryStrategy((error, attemptCount) -> {
            // Don't retry client errors (4xx)
            if (error instanceof HttpException he
                    && he.getStatusCode() >= 400 && he.getStatusCode() < 500) {
                return RetryDecision.fail();
            }
            // Retry server errors with exponential backoff
            if (attemptCount < 5) {
                return RetryDecision.retry(Duration.ofSeconds((long) Math.pow(2, attemptCount)));
            }
            return RetryDecision.fail();
        })
        .build());
```

## Error Classification

### Retryable vs Non-Retryable

**TypeScript:**

```typescript
class ValidationError extends Error {
  name = 'ValidationError';
}

class NetworkError extends Error {
  name = 'NetworkError';
}

const result = await context.step(
  'selective-retry',
  async () => operation(),
  {
    retryStrategy: createRetryStrategy({
      maxAttempts: 3,
      retryableErrorTypes: ['NetworkError', 'TimeoutError'],
      // ValidationError won't be retried
    })
  }
);
```

**Python:**

```python
retry_config = RetryStrategyConfig(
    max_attempts=3,
    retryable_error_types=[NetworkError, TimeoutError]
)
```

**Java:**

```java
import software.amazon.lambda.durable.retry.RetryDecision;

// The Java SDK's built-in strategies have no "retryable types" option;
// inspect the error type inside a custom strategy instead.
var result = ctx.step("selective-retry", Result.class, stepCtx -> operation(),
    StepConfig.builder()
        .retryStrategy((error, attemptCount) -> {
            boolean retryable = error instanceof NetworkException
                || error instanceof TimeoutException;
            if (retryable && attemptCount < 3) {
                return RetryDecision.retry(Duration.ofSeconds((long) Math.pow(2, attemptCount)));
            }
            // ValidationException (and any non-listed type) won't be retried
            return RetryDecision.fail();
        })
        .build());
```

## Saga Pattern

Implement compensating transactions for distributed workflows:

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const compensations: Array<{
    name: string;
    fn: () => Promise<void>;
  }> = [];

  try {
    // Step 1: Reserve inventory
    const reservation = await context.step('reserve-inventory', async () =>
      inventoryService.reserve(event.items)
    );
    compensations.push({
      name: 'cancel-reservation',
      fn: () => inventoryService.cancelReservation(reservation.id)
    });

    // Step 2: Charge payment
    const payment = await context.step('charge-payment', async () =>
      paymentService.charge(event.paymentMethod, event.amount)
    );
    compensations.push({
      name: 'refund-payment',
      fn: () => paymentService.refund(payment.id)
    });

    // Step 3: Create shipment
    const shipment = await context.step('create-shipment', async () =>
      shippingService.createShipment(event.address, event.items)
    );
    compensations.push({
      name: 'cancel-shipment',
      fn: () => shippingService.cancelShipment(shipment.id)
    });

    return { success: true, orderId: shipment.orderId };

  } catch (error) {
    context.logger.error('Order failed, executing compensations', error);
    
    // Execute compensations in reverse order
    for (const comp of compensations.reverse()) {
      try {
        await context.step(comp.name, async () => comp.fn());
      } catch (compError) {
        context.logger.error(`Compensation ${comp.name} failed`, compError);
        // Continue with other compensations
      }
    }
    
    throw error;
  }
});
```

**Python:**

```python
# Note: All service methods are decorated with @durable_step
@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    compensations = []

    try:
        # Step 1: Reserve inventory
        reservation = context.step(reserve_inventory(event['items']))
        compensations.append(('cancel-reservation', cancel_reservation, reservation['id']))

        # Step 2: Charge payment
        payment = context.step(charge_payment(event['payment_method'], event['amount']))
        compensations.append(('refund-payment', refund_payment, payment['id']))

        # Step 3: Create shipment
        shipment = context.step(create_shipment(event['address'], event['items']))

        return {'success': True, 'order_id': shipment['order_id']}

    except Exception as error:
        context.logger.error('Order failed, executing compensations', error)
        
        for name, comp_step, resource_id in reversed(compensations):
            try:
                context.step(comp_step(resource_id))
            except Exception as comp_error:
                context.logger.error(f'Compensation {name} failed', comp_error)
        
        raise error
```

**Java:**

```java
import software.amazon.lambda.durable.exception.DurableExecutionException;

public class OrderHandler extends DurableHandler<OrderRequest, OrderResult> {
    @Override
    public OrderResult handleRequest(OrderRequest event, DurableContext ctx) {
        var compensations = new ArrayList<Runnable>();
        try {
            // Step 1: Reserve inventory
            var reservation = ctx.step("reserve-inventory", Reservation.class,
                s -> inventoryService.reserve(event.getItems()));
            compensations.add(() -> ctx.step("cancel-reservation", Void.class,
                s -> { inventoryService.cancelReservation(reservation.getId()); return null; }));

            // Step 2: Charge payment
            var payment = ctx.step("charge-payment", Payment.class,
                s -> paymentService.charge(event.getPaymentMethod(), event.getAmount()));
            compensations.add(() -> ctx.step("refund-payment", Void.class,
                s -> { paymentService.refund(payment.getId()); return null; }));

            // Step 3: Create shipment
            var shipment = ctx.step("create-shipment", Shipment.class,
                s -> shippingService.createShipment(event.getAddress(), event.getItems()));

            return new OrderResult(true, shipment.getOrderId());
        } catch (DurableExecutionException e) {
            ctx.getLogger().error("Order failed, executing compensations: {}", e.getMessage());
            // Execute compensations in reverse order
            Collections.reverse(compensations);
            for (var comp : compensations) {
                try {
                    comp.run();
                } catch (DurableExecutionException ce) {
                    ctx.getLogger().error("Compensation failed: {}", ce.getMessage());
                    // Continue with other compensations
                }
            }
            throw e;
        }
    }
}
```

## Unrecoverable Errors

Mark errors as unrecoverable to stop execution immediately:

**TypeScript:**

```typescript
import { UnrecoverableInvocationError } from '@aws/durable-execution-sdk-js';

export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const user = await context.step('fetch-user', async () => {
    const user = await fetchUser(event.userId);
    
    if (!user) {
      // Stop execution immediately - no retry
      throw new UnrecoverableInvocationError('User not found');
    }
    
    return user;
  });
  
  // Continue processing...
});
```

**Python:**

```python
from aws_durable_execution_sdk_python.exceptions import ExecutionError

@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    @durable_step
    def fetch_user_step(step_ctx: StepContext):
        user = fetch_user(event['user_id'])
        if not user:
            # Stop execution immediately — permanent failure, no retry
            raise ExecutionError('User not found')
        return user
    
    user = context.step(fetch_user_step())
    # Continue processing...
```

**Java:**

```java
import software.amazon.lambda.durable.exception.UnrecoverableDurableExecutionException;
import software.amazon.awssdk.services.lambda.model.ErrorObject;

public class MyHandler extends DurableHandler<MyInput, MyOutput> {
    @Override
    public MyOutput handleRequest(MyInput event, DurableContext ctx) {
        var user = ctx.step("fetch-user", User.class, stepCtx -> {
            var u = fetchUser(event.getUserId());
            if (u == null) {
                // Terminate execution immediately - no retry.
                // A plain RuntimeException would be retried by the step's retry
                // strategy; UnrecoverableDurableExecutionException is not.
                throw new UnrecoverableDurableExecutionException(
                    ErrorObject.builder()
                        .errorType("UserNotFound")
                        .errorMessage("User not found")
                        .build());
            }
            return u;
        });
        // Continue processing...
    }
}
```

The SDK provides these exception types for different failure scenarios:

| Exception                | Retryable       | Use case                                                    |
| ------------------------ | --------------- | ----------------------------------------------------------- |
| `ExecutionError`         | No              | Permanent business logic failures (returns FAILED status)   |
| `InvocationError`        | Yes (by Lambda) | Transient infrastructure issues (Lambda retries invocation) |
| `CallbackError`          | No              | Callback handling failures                                  |
| `DurableExecutionsError` | —               | Base class for all SDK exceptions                           |

**Java** SDK exception types:

| Exception                              | Retryable | Use case                                                |
| -------------------------------------- | --------- | ------------------------------------------------------- |
| `StepFailedException`                  | No        | Step execution failed (business logic error)            |
| `StepInterruptedException`             | Yes       | Step with AT_MOST_ONCE_PER_RETRY interrupted before completion |
| `CallbackTimeoutException`             | No        | Callback didn't complete within timeout                 |
| `CallbackFailedException`              | No        | Callback failed or was explicitly rejected              |
| `WaitForConditionFailedException`      | No        | Condition check failed or max polling attempts exceeded |
| `InvokeFailedException`                | No        | Lambda invocation failed                                |
| `InvokeTimedOutException`              | No        | Lambda invocation timed out                             |
| `UnrecoverableDurableExecutionException` | No      | Terminate execution immediately, no retry               |
| `DurableExecutionException`            | —         | Base class for all SDK exceptions                       |

## Error Determinism

Ensure errors are deterministic across replays:

**TypeScript:**

```typescript
class CustomBusinessError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly details: any
  ) {
    super(message);
    this.name = 'CustomBusinessError';
  }
}

const result = await context.step('validate', async () => {
  if (!isValid(data)) {
    // ✅ Deterministic error
    throw new CustomBusinessError(
      'Validation failed',
      'INVALID_DATA',
      { field: 'email', reason: 'invalid format' }
    );
  }
  
  return processData(data);
});
```

**Java:**

```java
// Define a deterministic, serializable business exception
public class CustomBusinessException extends RuntimeException {
    private final String code;
    private final String field;

    public CustomBusinessException(String message, String code, String field) {
        super(message);
        this.code = code;
        this.field = field;
    }

    public String getCode() { return code; }
    public String getField() { return field; }
}

var result = ctx.step("validate", ProcessResult.class, stepCtx -> {
    if (!isValid(data)) {
        // ✅ Deterministic error - same input produces the same failure
        throw new CustomBusinessException("Validation failed", "INVALID_DATA", "email");
    }
    return processData(data);
});
```

## Circuit Breaker Pattern

**TypeScript:**

```typescript
class CircuitBreaker {
  private failures = 0;
  private lastFailureTime = 0;
  private readonly threshold = 5;
  private readonly timeout = 60000; // 1 minute

  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.isOpen()) {
      throw new Error('Circuit breaker is open');
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  private isOpen(): boolean {
    if (this.failures >= this.threshold) {
      const elapsed = Date.now() - this.lastFailureTime;
      return elapsed < this.timeout;
    }
    return false;
  }

  private onSuccess() {
    this.failures = 0;
  }

  private onFailure() {
    this.failures++;
    this.lastFailureTime = Date.now();
  }
}

// Use in handler
const breaker = new CircuitBreaker();

export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const result = await context.step('api-call', async () => {
    return await breaker.execute(() => callExternalAPI());
  });
  
  return result;
});
```

## Partial Failure Handling

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const results = await context.map(
    'process-items',
    event.items,
    async (ctx, item, index) => {
      return await ctx.step(async () => processItem(item));
    },
    {
      completionConfig: {
        toleratedFailurePercentage: 10  // Allow 10% failures
      }
    }
  );

  if (results.hasFailure()) {
    // Log failures but continue
    context.logger.warn('Some items failed', {
      failureCount: results.failureCount,
      failures: results.failed.map(f => ({
        index: f.index,
        error: f.error?.message
      }))
    });

    // Store failed items for later retry
    await context.step('store-failures', async () => {
      const failedItems = results.failed.map(f => event.items[f.index]);
      return await storeFailedItems(failedItems);
    });
  }

  return {
    totalProcessed: results.successCount,
    failed: results.failureCount
  };
});
```

**Java:**

```java
import software.amazon.lambda.durable.config.MapConfig;
import software.amazon.lambda.durable.config.CompletionConfig;
import software.amazon.lambda.durable.model.MapResult.MapResultItem;

public class BatchHandler extends DurableHandler<BatchInput, BatchOutput> {
    @Override
    public BatchOutput handleRequest(BatchInput event, DurableContext ctx) {
        var results = ctx.map("process-items", event.getItems(), Result.class,
            (item, index, childCtx) -> childCtx.step("process-" + index, Result.class,
                s -> processItem(item)),
            MapConfig.builder()
                .completionConfig(CompletionConfig.toleratedFailurePercentage(0.1))  // Allow 10% failures
                .build());

        if (!results.allSucceeded()) {
            // Log failures but continue
            ctx.getLogger().warn("Some items failed. Failure count: {}", results.failed().size());

            // Collect failed items for later retry
            var failedItems = new ArrayList<Item>();
            for (int i = 0; i < results.size(); i++) {
                if (results.getItem(i).status() == MapResultItem.Status.FAILED) {
                    failedItems.add(event.getItems().get(i));
                }
            }

            ctx.step("store-failures", Void.class, s -> { storeFailedItems(failedItems); return null; });
        }

        return new BatchOutput(results.succeeded().size(), results.failed().size());
    }
}
```

## Best Practices

1. **Use appropriate retry strategies** - exponential backoff for most cases
2. **Classify errors correctly** - distinguish retryable from non-retryable
3. **Implement compensating transactions** for distributed workflows
4. **Make errors deterministic** - same input produces same error
5. **Use unrecoverable errors** to stop execution early when appropriate
6. **Log errors with context** using `context.logger`
7. **Handle partial failures** gracefully in batch operations
8. **Implement circuit breakers** for external service calls
9. **Test error scenarios** thoroughly with test runners
10. **Monitor error rates** and adjust retry strategies accordingly
