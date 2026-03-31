# Testing Patterns - TypeScript

## Local Setup

```typescript
import { LocalDurableTestRunner, OperationType, OperationStatus } from '@aws/durable-execution-sdk-js-testing';

beforeAll(() => LocalDurableTestRunner.setupTestEnvironment({ skipTime: true }));
afterAll(() => LocalDurableTestRunner.teardownTestEnvironment());

const runner = new LocalDurableTestRunner({ handlerFunction: handler });
const execution = await runner.run({ payload: { userId: '123' } });
expect(execution.getStatus()).toBe('SUCCEEDED');
```

## Get Operations by Name

```typescript
const fetchStep = runner.getOperation('fetch-user');
expect(fetchStep.getType()).toBe(OperationType.STEP);
expect(fetchStep.getStatus()).toBe(OperationStatus.SUCCEEDED);
// ❌ WRONG: runner.getOperationByIndex(0) — brittle, breaks easily
```

## Replay Testing

```typescript
const execution1 = await runner.run({ payload: { value: 42 } });
const execution2 = await runner.run({ payload: { value: 42 } });
expect(execution1.getResult()).toEqual(execution2.getResult());
```

## Fake Clock

```typescript
const executionPromise = runner.run({ payload: {} });
await runner.skipTime({ seconds: 60 });
const execution = await executionPromise;
const waitOp = runner.getOperation('delay');
expect(waitOp.getType()).toBe(OperationType.WAIT);
```

## Callback Testing

```typescript
import { WaitingOperationStatus } from '@aws/durable-execution-sdk-js-testing';

const executionPromise = runner.run({ payload: { approver: '[email]' } });
const callbackOp = runner.getOperation('wait-for-approval');
await callbackOp.waitForData(WaitingOperationStatus.STARTED);
await callbackOp.sendCallbackSuccess(JSON.stringify({ approved: true }));
const execution = await executionPromise;
// ❌ WRONG: sendCallbackSuccess without waitForData — causes race conditions
```

## Error Scenarios

```typescript
let attemptCount = 0;
const testHandler = withDurableExecution(async (event, ctx: DurableContext) => {
  return await ctx.step('flaky-op', async () => {
    if (++attemptCount < 3) throw new Error('Temporary failure');
    return { success: true };
  });
});
const runner = new LocalDurableTestRunner({ handlerFunction: testHandler });
const execution = await runner.run({ payload: {} });
expect(execution.getStatus()).toBe('SUCCEEDED');
```

## Concurrent Operations

```typescript
const execution = await runner.run({ payload: { items: [1, 2, 3, 4, 5] } });
const mapOp = runner.getOperation('process-items');
expect(mapOp.getType()).toBe(OperationType.MAP);
const item0 = runner.getOperation('process-0');
expect(item0.getStatus()).toBe(OperationStatus.SUCCEEDED);
```

## Cloud Testing

```typescript
import { CloudDurableTestRunner } from '@aws/durable-execution-sdk-js-testing';

const runner = new CloudDurableTestRunner({
  functionName: 'my-durable-function:1', client: new LambdaClient({ region: 'us-east-1' })
});
const execution = await runner.run({ payload: { userId: '123' }, config: { pollInterval: 1000 } });
```

## Jest Config

```javascript
module.exports = {
  preset: 'ts-jest', testEnvironment: 'node',
  roots: ['<rootDir>/src'], testMatch: ['**/*.test.ts'],
  transform: { '^.+\\.ts$': 'ts-jest' },
};
```
