# Step Operations - TypeScript

## Basic Step

```typescript
const result = await context.step('fetch-user', async () => fetchUserFromAPI(userId));
```

## Retry Configuration

```typescript
import { createRetryStrategy, JitterStrategy } from '@aws/durable-execution-sdk-js';

const result = await context.step('api-call', async () => callExternalAPI(), {
  retryStrategy: createRetryStrategy({
    maxAttempts: 5, initialDelay: { seconds: 1 }, maxDelay: { seconds: 60 },
    backoffRate: 2.0, jitter: JitterStrategy.FULL
  })
});
```

## Custom Retry

```typescript
const result = await context.step('custom-retry', async () => riskyOperation(), {
  retryStrategy: (error, attemptCount) => {
    if (error.name === 'ValidationError') return { shouldRetry: false };
    if (attemptCount < 3) {
      return { shouldRetry: true, delay: { seconds: Math.pow(2, attemptCount) } };
    }
    return { shouldRetry: false };
  }
});
```

## Retryable Error Types

```typescript
const result = await context.step('selective-retry', async () => operation(), {
  retryStrategy: createRetryStrategy({
    maxAttempts: 3, retryableErrorTypes: ['NetworkError', 'TimeoutError']
  })
});
```

## Step Semantics

```typescript
// AT_LEAST_ONCE (default) - may execute multiple times on failure/retry
const result = await context.step('idempotent-op', async () => idempotentAPI(), {
  semantics: 'AT_LEAST_ONCE'
});
// AT_MOST_ONCE - never retries, use for non-idempotent operations
const payment = await context.step('charge-payment', async () => chargeCard(amount), {
  semantics: 'AT_MOST_ONCE'
});
```

## Custom Serialization

```typescript
import { createClassSerdesWithDates } from '@aws/durable-execution-sdk-js';

class User {
  constructor(public id: string, public name: string, public createdAt: Date) {}
}
const userSerdes = createClassSerdesWithDates(User, ['createdAt']);
const user = await context.step('fetch-user', async () => new User('123', 'Alice', new Date()), {
  serdes: userSerdes
});
```

## Child Context

```typescript
await context.runInChildContext('process', async (childCtx) => {
  const data = await childCtx.step('fetch', async () => fetch());
  await childCtx.wait({ seconds: 1 });
  return await childCtx.step('save', async () => save(data));
});
```

## Error Handling

```typescript
try {
  const result = await context.step('risky', async () => riskyOperation());
} catch (error) {
  if (error instanceof StepError) {
    context.logger.error('Step failed', error.cause);
  }
}
```
