# Step Operations

Steps are atomic operations with automatic retry and state persistence.

## Basic Step Patterns

### Named Steps (Recommended)

**TypeScript:**

```typescript
const result = await context.step('fetch-user', async () => {
  return await fetchUserFromAPI(userId);
});
```

**Python:**

```python
@durable_step
def fetch_user(step_ctx: StepContext, user_id: str):
    return fetch_user_from_api(user_id)

result = context.step(fetch_user(user_id))
```

### Anonymous Steps

**TypeScript:**

```typescript
const result = await context.step(async () => processData());
```

**Python:**

```python
result = context.step(lambda _: process_data(), name='process')
```

**Best Practice:** Always name steps for easier debugging and testing.

## Retry Configuration

### Exponential Backoff

**TypeScript:**

```typescript
import { RetryPresets } from '@aws/durable-execution-sdk-js';

const result = await context.step(
  'api-call',
  async () => callExternalAPI(),
  {
    retryStrategy: RetryPresets.exponentialBackoff({
      maxAttempts: 5,
      initialDelay: { seconds: 1 },
      maxDelay: { seconds: 60 },
      backoffRate: 2.0,
      jitter: 'full'
    })
  }
);
```

**Python:**

```python
from aws_durable_execution_sdk_python.config import StepConfig, Duration
from aws_durable_execution_sdk_python.retries import RetryStrategyConfig, create_retry_strategy

retry_config = RetryStrategyConfig(
    max_attempts=5,
    initial_delay=Duration.from_seconds(5),
    max_delay=Duration.from_seconds(60),
    backoff_rate=2.0,
    jitter='full'
)

result = context.step(
    api_call(),
    config=StepConfig(retry_strategy=create_retry_strategy(retry_config))
)
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

### Retryable Error Types

**TypeScript:**

```typescript
const result = await context.step(
  'selective-retry',
  async () => operation(),
  {
    retryStrategy: RetryPresets.exponentialBackoff({
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
    retryable_error_types=['NetworkError', 'TimeoutError']
)
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
    config=StepConfig(semantics=StepSemantics.AT_MOST_ONCE)
)
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
from aws_durable_execution_sdk_python.errors import StepError

try:
    result = context.step(risky_operation(), name='risky')
except StepError as error:
    context.logger.error('Step failed', error.cause)
    # Handle or rethrow
```

## Best Practices

1. **Always name steps** for debugging and testing
2. **Keep steps atomic** - one logical operation per step
3. **Make steps idempotent** when possible
4. **Use appropriate retry strategies** based on operation type
5. **Handle errors explicitly** - don't let them propagate unexpectedly
6. **Use custom serialization** for complex types
7. **Choose correct semantics** (AT_LEAST_ONCE vs AT_MOST_ONCE)
