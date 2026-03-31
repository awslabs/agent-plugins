# Error Handling - TypeScript

## Retry Strategies

```typescript
import { createRetryStrategy, JitterStrategy } from '@aws/durable-execution-sdk-js';

const result = await context.step('api-call', async () => callAPI(), {
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
    if (error.statusCode >= 400 && error.statusCode < 500) return { shouldRetry: false };
    return attemptCount < 5
      ? { shouldRetry: true, delay: { seconds: Math.pow(2, attemptCount) } }
      : { shouldRetry: false };
  }
});
```

## Error Classification

```typescript
const result = await context.step('selective-retry', async () => operation(), {
  retryStrategy: createRetryStrategy({ maxAttempts: 3, retryableErrorTypes: ['NetworkError'] })
});
```

## Saga Pattern

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const compensations: Array<{ name: string; fn: () => Promise<void> }> = [];
  try {
    const reservation = await context.step('reserve-inventory', async () =>
      inventoryService.reserve(event.items));
    compensations.push({ name: 'cancel-reservation',
      fn: () => inventoryService.cancelReservation(reservation.id) });
    const payment = await context.step('charge-payment', async () =>
      paymentService.charge(event.paymentMethod, event.amount));
    compensations.push({ name: 'refund-payment',
      fn: () => paymentService.refund(payment.id) });
    return { success: true, orderId: payment.orderId };
  } catch (error) {
    for (const comp of compensations.reverse()) {
      try { await context.step(comp.name, async () => comp.fn()); }
      catch (compError) { context.logger.error(`Compensation ${comp.name} failed`, compError); }
    }
    throw error;
  }
});
```

## Unrecoverable Error

```typescript
import { UnrecoverableInvocationError } from '@aws/durable-execution-sdk-js';

const user = await context.step('fetch-user', async () => {
  const user = await fetchUser(event.userId);
  if (!user) throw new UnrecoverableInvocationError('User not found');
  return user;
});
```

## Circuit Breaker

```typescript
class CircuitBreaker {
  private failures = 0;
  private lastFailTime = 0;
  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.failures >= 5 && Date.now() - this.lastFailTime < 60000)
      throw new Error('Circuit breaker is open');
    try { const r = await fn(); this.failures = 0; return r; }
    catch (e) { this.failures++; this.lastFailTime = Date.now(); throw e; }
  }
}
```

## Partial Failure Handling

```typescript
const results = await context.map('process-items', event.items,
  async (ctx, item) => ctx.step(async () => processItem(item)),
  { completionConfig: { toleratedFailurePercentage: 10 } });
if (results.hasFailure()) {
  await context.step('store-failures', async () =>
    storeFailedItems(results.failed.map(f => event.items[f.index])));
}
```
