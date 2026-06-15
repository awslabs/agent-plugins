# Step Operations

Steps are atomic operations with automatic retry and state persistence.

## Basic Step Patterns

### Python: Two Ways to Define Steps

**Recommended: `@durable_step` Decorator**

```python
from aws_durable_execution_sdk_python import durable_step, StepContext

@durable_step
def fetch_user(step_ctx: StepContext, user_id: str):
    """Fetch user from database - reusable step function."""
    return fetch_user_from_api(user_id)

# Call it - name is automatically inferred from function name
result = context.step(fetch_user(user_id))
```

Alternative: **Inline Lambda**

```python
# For simple one-off operations
result = context.step(
    func=lambda step_ctx: fetch_user_from_api(user_id),
    name='fetch-user'
)
```

**Use `@durable_step` for:**

- Reusable step functions
- Complex logic
- Better readability and testing

**Use lambda for:**

- Simple inline operations
- One-off transformations

### TypeScript: Named Steps

**TypeScript:**

```typescript
const result = await context.step('fetch-user', async () => {
  return await fetchUserFromAPI(userId);
});
```

**Best Practice:** Always name steps for easier debugging and testing.

### Java: Typed Steps

**Java:**

```java
import software.amazon.lambda.durable.StepContext;

// Java always requires a name and the result type (Class or TypeToken)
var result = ctx.step("fetch-user", User.class,
    (StepContext stepCtx) -> fetchUserFromAPI(userId));

// Use TypeToken for generic result types like List<T>
var users = ctx.step("fetch-users", new TypeToken<List<User>>() {},
    stepCtx -> fetchAllUsers());
```

**Best Practice:** Always name steps for easier debugging and testing.

## Retry Configuration

### Exponential Backoff

**TypeScript:**

```typescript
import { createRetryStrategy, JitterStrategy } from '@aws/durable-execution-sdk-js';

const result = await context.step(
  'api-call',
  async () => callExternalAPI(),
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
```

**Python:**

```python
# Note: api_call is decorated with @durable_step
from aws_durable_execution_sdk_python.config import StepConfig, Duration
from aws_durable_execution_sdk_python.retries import RetryStrategyConfig, create_retry_strategy, JitterStrategy

retry_config = RetryStrategyConfig(
    max_attempts=5,
    initial_delay=Duration.from_seconds(5),
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

var result = ctx.step("api-call", ApiResponse.class, stepCtx -> callExternalAPI(),
    StepConfig.builder()
        .retryStrategy(RetryStrategies.exponentialBackoff(
            5,                       // maxAttempts (including initial attempt)
            Duration.ofSeconds(1),   // initialDelay
            Duration.ofSeconds(60),  // maxDelay
            2.0,                     // backoffRate
            JitterStrategy.FULL))
        .build());
```

### Custom Retry Strategy

**TypeScript:**

```typescript
const result = await context.step(
  'custom-retry',
  async () => riskyOperation(),
  {
    retryStrategy: (error, attemptCount) => {
      // Don't retry validation errors
      if (error.name === 'ValidationError') {
        return { shouldRetry: false };
      }
      
      // Retry up to 3 times with exponential backoff
      if (attemptCount < 3) {
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
from aws_durable_execution_sdk_python.retries import RetryDecision

def custom_retry(error: Exception, attempt: int) -> RetryDecision:
    if isinstance(error, ValidationError):
        return RetryDecision(should_retry=False)
    
    if attempt < 3:
        return RetryDecision(
            should_retry=True,
            delay=Duration.from_seconds(2 ** attempt)
        )
    
    return RetryDecision(should_retry=False)

result = context.step(
    risky_operation(),
    config=StepConfig(retry_strategy=custom_retry)
)
```

**Java:**

```java
import software.amazon.lambda.durable.retry.RetryDecision;

var result = ctx.step("custom-retry", Result.class, stepCtx -> riskyOperation(),
    StepConfig.builder()
        .retryStrategy((error, attemptCount) -> {
            // Don't retry validation errors
            if (error instanceof ValidationException) {
                return RetryDecision.fail();
            }
            // Retry up to 3 times with exponential backoff
            if (attemptCount < 3) {
                return RetryDecision.retry(Duration.ofSeconds((long) Math.pow(2, attemptCount)));
            }
            return RetryDecision.fail();
        })
        .build());
```

### Retryable Error Types

**TypeScript:**

```typescript
const result = await context.step(
  'selective-retry',
  async () => operation(),
  {
    retryStrategy: createRetryStrategy({
      maxAttempts: 3,
      retryableErrorTypes: ['NetworkError', 'TimeoutError']
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

// The Java SDK has no "retryable types" option on the built-in strategy;
// inspect the error type inside a custom strategy instead.
var result = ctx.step("selective-retry", Result.class, stepCtx -> operation(),
    StepConfig.builder()
        .retryStrategy((error, attemptCount) -> {
            boolean retryable = error instanceof NetworkException
                || error instanceof TimeoutException;
            if (retryable && attemptCount < 3) {
                return RetryDecision.retry(Duration.ofSeconds((long) Math.pow(2, attemptCount)));
            }
            return RetryDecision.fail();
        })
        .build());
```

## Step Semantics

### AT_LEAST_ONCE (Default)

Step executes at least once, may execute multiple times on failure/retry.

**TypeScript:**

```typescript
const result = await context.step(
  'idempotent-operation',
  async () => idempotentAPI(),
  { semantics: 'AT_LEAST_ONCE' }
);
```

### AT_MOST_ONCE

Step executes at most once, never retries. Use for non-idempotent operations.

**TypeScript:**

```typescript
const result = await context.step(
  'charge-payment',
  async () => chargeCard(amount),
  { semantics: 'AT_MOST_ONCE' }
);
```

**Python:**

```python
from aws_durable_execution_sdk_python.config import StepSemantics

result = context.step(
    charge_card(amount),
    config=StepConfig(step_semantics=StepSemantics.AT_MOST_ONCE_PER_RETRY)
)
```

**Java:**

```java
import software.amazon.lambda.durable.config.StepSemantics;

// AT_LEAST_ONCE_PER_RETRY (default) - may execute multiple times on failure/retry
var result = ctx.step("idempotent-op", Result.class, stepCtx -> idempotentAPI());

// AT_MOST_ONCE_PER_RETRY - use for non-idempotent operations.
// semanticsPerRetry(...) retries interrupted steps per the retry strategy.
var payment = ctx.step("charge-payment", PaymentResult.class, stepCtx -> chargeCard(amount),
    StepConfig.builder()
        .semanticsPerRetry(StepSemantics.AT_MOST_ONCE_PER_RETRY)
        .build());
```

## Custom Serialization

For complex types, provide custom serialization:

**TypeScript:**

```typescript
import { createClassSerdesWithDates } from '@aws/durable-execution-sdk-js';

class User {
  constructor(
    public id: string,
    public name: string,
    public createdAt: Date
  ) {}
}

const userSerdes = createClassSerdesWithDates(User, ['createdAt']);

const user = await context.step(
  'fetch-user',
  async () => new User('123', 'Alice', new Date()),
  { serdes: userSerdes }
);
```

**Python:**

```python
from dataclasses import dataclass
from datetime import datetime

@dataclass
class User:
    id: str
    name: str
    created_at: datetime

# Python SDK handles dataclass serialization automatically
user = context.step(
    lambda _: User('123', 'Alice', datetime.now()),
    name='fetch-user'
)
```

**Java:**

```java
import software.amazon.lambda.durable.serde.SerDes;
import software.amazon.lambda.durable.TypeToken;
import com.fasterxml.jackson.databind.ObjectMapper;

// SerDes is a non-generic interface: serialize(Object) and
// deserialize(String, TypeToken<T>)
public class UserSerDes implements SerDes {
    private final ObjectMapper mapper = new ObjectMapper();

    @Override
    public String serialize(Object value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public <T> T deserialize(String data, TypeToken<T> typeToken) {
        try {
            return mapper.readValue(data, mapper.constructType(typeToken.getType()));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}

// Provide the custom SerDes via StepConfig
var user = ctx.step("fetch-user", User.class,
    stepCtx -> new User("123", "Alice", Instant.now()),
    StepConfig.builder().serDes(new UserSerDes()).build());
```

## When to Use Steps vs Child Contexts

### Use Steps For:

- Single atomic operations
- API calls
- Database queries
- Data transformations
- Operations that should retry as a unit

### Use Child Contexts For:

- Grouping multiple durable operations
- Complex workflows with steps, waits, and invokes
- Isolating state tracking
- Organizing related operations

**Example:**

```typescript
// ❌ WRONG: Cannot nest durable operations in step
await context.step('process', async () => {
  await context.wait({ seconds: 1 });  // ERROR!
});

// ✅ CORRECT: Use child context
await context.runInChildContext('process', async (childCtx) => {
  const data = await childCtx.step('fetch', async () => fetch());
  await childCtx.wait({ seconds: 1 });
  return await childCtx.step('save', async () => save(data));
});
```

**Java:**

```java
// ❌ WRONG: Cannot nest durable operations in step
ctx.step("process", Result.class, stepCtx -> {
    ctx.wait("delay", Duration.ofSeconds(1));  // ERROR!
    return result;
});

// ✅ CORRECT: Use child context
var result = ctx.runInChildContext("process", ProcessResult.class, childCtx -> {
    var data = childCtx.step("fetch", Data.class, s -> fetchData());
    childCtx.wait("processing-delay", Duration.ofSeconds(1));
    return childCtx.step("save", SaveResult.class, s -> save(data));
});
```

## Error Handling

Steps throw errors after all retry attempts are exhausted:

**TypeScript:**

```typescript
try {
  const result = await context.step('risky', async () => riskyOperation());
} catch (error) {
  if (error instanceof StepError) {
    context.logger.error('Step failed', error.cause);
    // Handle or rethrow
  }
}
```

**Python:**

```python
try:
    # Note: risky_operation is decorated with @durable_step
    result = context.step(risky_operation())
except Exception as error:
    context.logger.error('Step failed: %s', str(error))
    # Handle or rethrow
```

For SDK-specific exceptions, use the base class or specific types:

```python
from aws_durable_execution_sdk_python import DurableExecutionsError

try:
    result = context.step(risky_operation())
except DurableExecutionsError as error:
    context.logger.error('SDK error: %s', str(error))
except Exception as error:
    context.logger.error('Application error: %s', str(error))
```

**Java:**

```java
import software.amazon.lambda.durable.exception.StepFailedException;
import software.amazon.lambda.durable.exception.StepInterruptedException;

try {
    var result = ctx.step("risky", Result.class, stepCtx -> riskyOperation());
} catch (StepFailedException e) {
    ctx.getLogger().error("Step permanently failed: {}", e.getMessage());
    // Handle or rethrow
} catch (StepInterruptedException e) {
    ctx.getLogger().error("Step interrupted: {}", e.getMessage());
    // Handle or rethrow
}
```

## Best Practices

1. **Always name steps** for debugging and testing
2. **Keep steps atomic** - one logical operation per step
3. **Make steps idempotent** when possible
4. **Use appropriate retry strategies** based on operation type
5. **Handle errors explicitly** - don't let them propagate unexpectedly
6. **Use custom serialization** for complex types
7. **Choose correct semantics** (AT_LEAST_ONCE vs AT_MOST_ONCE)
