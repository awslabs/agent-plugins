# Replay Model Rules - TypeScript

## Wrong - Non-Deterministic Outside Steps

```typescript
const id = uuid.v4();                    // Different UUID each time
const timestamp = Date.now();            // Different timestamp each time
const random = Math.random();            // Different random number
await context.step('save', async () => saveData({ id, timestamp }));
```

## Correct - Non-Deterministic Inside Steps

```typescript
const id = await context.step('generate-id', async () => uuid.v4());
const timestamp = await context.step('get-time', async () => Date.now());
const random = await context.step('random', async () => Math.random());
await context.step('save', async () => saveData({ id, timestamp }));
```

## Wrong - Nested Operations

```typescript
await context.step('process', async () => {
  await context.wait({ seconds: 1 });      // ERROR!
  await context.step(async () => ...);     // ERROR!
  return result;
});
```

## Correct - Child Context

```typescript
await context.runInChildContext('process', async (childCtx) => {
  await childCtx.wait({ seconds: 1 });
  const step1 = await childCtx.step('validate', async () => validate());
  const step2 = await childCtx.step('process', async () => process(step1));
  return step2;
});
```

## Wrong - Closure Mutations

```typescript
let counter = 0;
await context.step('increment', async () => {
  counter++;  // This mutation is lost on replay!
});
console.log(counter);  // Always 0 on replay!
```

## Correct - Return Values

```typescript
let counter = 0;
counter = await context.step('increment', async () => counter + 1);
console.log(counter);  // Correct value
```

## Wrong - Side Effects Outside Steps

```typescript
console.log('Starting process');     // Logs multiple times!
await sendEmail(user.email);         // Sends multiple emails!
await context.step('process', async () => process());
```

## Correct - Side Effects In Steps

```typescript
context.logger.info('Starting process');  // Deduplicated automatically
await context.step('send-email', async () => sendEmail(user.email));
await context.step('process', async () => process());
```

## Common Pitfalls

```typescript
// ❌ WRONG - env vars can change across replays
const apiKey = process.env.API_KEY;
// ✅ CORRECT
const apiKey = await context.step('get-key', async () => process.env.API_KEY);

// ❌ WRONG - array mutation lost on replay
const items = [];
await context.step('add-item', async () => { items.push(newItem); });
// ✅ CORRECT
let items = [];
items = await context.step('add-item', async () => [...items, newItem]);

// ❌ WRONG - conditional on non-deterministic value
if (Math.random() > 0.5) {
  await context.step('path-a', async () => ...);
}
// ✅ CORRECT
const takePathA = await context.step('decide', async () => Math.random() > 0.5);
if (takePathA) {
  await context.step('path-a', async () => ...);
}
```
