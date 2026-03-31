# Concurrent Operations - TypeScript

## Map with Completion Config

```typescript
const results = await context.map(
  'process-items', items,
  async (ctx, item, index) => {
    return await ctx.step(`process-${index}`, async () => processItem(item));
  },
  { maxConcurrency: 3, completionConfig: { minSuccessful: 4, toleratedFailureCount: 1 } }
);
results.throwIfError();
const allResults = results.getResults();
```

## Parallel Operations

```typescript
const results = await context.parallel(
  'parallel-ops',
  [
    { name: 'fetch-user', func: async (ctx) => ctx.step(async () => fetchUser(userId)) },
    { name: 'fetch-orders', func: async (ctx) => ctx.step(async () => fetchOrders(userId)) },
    { name: 'fetch-prefs', func: async (ctx) => ctx.step(async () => fetchPreferences(userId)) }
  ],
  { maxConcurrency: 3 }
);
const [user, orders, preferences] = results.getResults();
```

## Completion Policies

```typescript
await context.map('batch', items, processFunc, {
  completionConfig: { minSuccessful: 8 }           // Require minimum successes
});
await context.map('batch', items, processFunc, {
  completionConfig: { toleratedFailureCount: 2 }    // Allow up to N failures
});
await context.map('batch', items, processFunc, {
  completionConfig: { toleratedFailurePercentage: 10 }  // Allow up to N% failures
});
// Early termination: stop after first success
await context.map('find-match', candidates,
  async (ctx, c) => ctx.step(async () => checkMatch(c)),
  { completionConfig: { minSuccessful: 1 } }
);
```

## Batch Result Handling

```typescript
const results = await context.map('process', items, processFunc);
console.log(results.status, results.successCount, results.failureCount, results.hasFailure());
const successful = results.succeeded.map(item => item.result);
if (results.hasFailure()) {
  const failedItems = results.failed.map(f => items[f.index]);
  await context.map('retry-failed', failedItems, processFunc);
}
```

## Concurrency Control

```typescript
await context.map('process', items, processFunc, { maxConcurrency: 5 });
// Dynamic: adjust processing based on item characteristics
await context.map('process', items, async (ctx, item, index) => {
  if (item.size > 1000) return await ctx.step(`heavy-${index}`, async () => processHeavy(item));
  return await ctx.step(`light-${index}`, async () => processLight(item));
}, { maxConcurrency: 10 });
```

## Advanced Map Patterns

```typescript
// Map with callbacks
await context.map('with-approval', items, async (ctx, item, index) => {
  const processed = await ctx.step('process', async () => process(item));
  const approved = await ctx.waitForCallback('approval',
    async (callbackId) => sendApproval(item, callbackId), { timeout: { hours: 24 } });
  return { processed, approved };
}, { maxConcurrency: 3 });

// Nested map operations
await context.map('batches', batches, async (ctx, batch, batchIndex) => {
  return await ctx.map(`batch-${batchIndex}`, batch.items,
    async (itemCtx, item) => itemCtx.step(async () => process(item)));
});

// Map with child contexts
await context.map('complex', items, async (ctx, item, index) => {
  return await ctx.runInChildContext(`item-${index}`, async (childCtx) => {
    const validated = await childCtx.step('validate', async () => validate(item));
    await childCtx.wait({ seconds: 1 });
    return await childCtx.step('process', async () => process(validated));
  });
}, { maxConcurrency: 5 });
```
