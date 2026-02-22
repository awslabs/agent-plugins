# Testing Patterns

Test durable functions locally and in the cloud with comprehensive test runners.

## Critical Testing Patterns

**ALWAYS follow these patterns to avoid flaky tests:**

### DO:

- ✅ Use `runner.getOperation("name")` to find operations by name
- ✅ Use `WaitingOperationStatus.STARTED` when waiting for callback operations
- ✅ JSON.stringify callback parameters: `sendCallbackSuccess(JSON.stringify(data))`
- ✅ Parse callback results: `JSON.parse(result.value)`
- ✅ Name all operations for test reliability
- ✅ Use `skipTime: true` in setupTestEnvironment for fast tests
- ✅ Wrap event data in `payload` object: `runner.run({ payload: { ... } })`
- ✅ Cast `getResult()` to appropriate type: `execution.getResult() as ResultType`

### DON'T:

- ❌ Use `getOperationByIndex()` unless absolutely necessary
- ❌ Assume operation indices are stable (parallel creates nested operations)
- ❌ Send objects to sendCallbackSuccess - stringify first!
- ❌ Forget that callback results are JSON strings - parse them
- ❌ Use incorrect enum values (check @aws-sdk/client-lambda for current OperationType)
- ❌ Test callbacks without proper synchronization (leads to race conditions)

## Local Testing Setup

**TypeScript:**

```typescript
import {
  LocalDurableTestRunner,
  OperationType,
  OperationStatus
} from '@aws/durable-execution-sdk-js-testing';

describe('My Durable Function', () => {
  beforeAll(() => 
    LocalDurableTestRunner.setupTestEnvironment({ skipTime: true })
  );
  
  afterAll(() => 
    LocalDurableTestRunner.teardownTestEnvironment()
  );

  it('should execute workflow', async () => {
    const runner = new LocalDurableTestRunner({ 
      handlerFunction: handler 
    });
    
    const execution = await runner.run({ 
      payload: { userId: '123' } 
    });

    expect(execution.getStatus()).toBe('SUCCEEDED');
    expect(execution.getResult()).toEqual({ success: true });
  });
});
```

**Python:**

```python
import pytest
from aws_durable_execution_sdk_python_testing import InvocationStatus
from my_module import handler

@pytest.mark.durable_execution(
    handler=handler,
    lambda_function_name='my_function'
)
def test_workflow(durable_runner):
    with durable_runner:
        result = durable_runner.run(input={'user_id': '123'}, timeout=10)

    assert result.status is InvocationStatus.SUCCEEDED
    assert result.result == {'success': True}
```

## Getting Operations

**CRITICAL: Always get operations by NAME, not by index.**

**TypeScript:**

```typescript
it('should execute steps in order', async () => {
  const runner = new LocalDurableTestRunner({ handlerFunction: handler });
  await runner.run({ payload: { test: true } });

  // ✅ CORRECT: Get by name
  const fetchStep = runner.getOperation('fetch-user');
  expect(fetchStep.getType()).toBe(OperationType.STEP);
  expect(fetchStep.getStatus()).toBe(OperationStatus.SUCCEEDED);

  const processStep = runner.getOperation('process-data');
  expect(processStep.getStatus()).toBe(OperationStatus.SUCCEEDED);

  // ❌ WRONG: Get by index (brittle, breaks easily)
  // const step1 = runner.getOperationByIndex(0);
});
```

**Python:**

```python
def test_steps_execute(durable_runner):
    with durable_runner:
        result = durable_runner.run(input={'test': True})

    # ✅ CORRECT: Get by name
    fetch_step = result.get_step('fetch-user')
    assert fetch_step.status is InvocationStatus.SUCCEEDED

    process_step = result.get_step('process-data')
    assert process_step.status is InvocationStatus.SUCCEEDED
```

## Testing Replay Behavior

**TypeScript:**

```typescript
it('should handle replay correctly', async () => {
  const runner = new LocalDurableTestRunner({ handlerFunction: handler });
  
  // First execution
  const execution1 = await runner.run({ payload: { value: 42 } });
  expect(execution1.getStatus()).toBe('SUCCEEDED');

  // Simulate replay
  const execution2 = await runner.run({ payload: { value: 42 } });
  expect(execution2.getStatus()).toBe('SUCCEEDED');
  
  // Results should be identical
  expect(execution1.getResult()).toEqual(execution2.getResult());
});
```

## Testing with Fake Clock

**TypeScript:**

```typescript
it('should wait for specified duration', async () => {
  const runner = new LocalDurableTestRunner({ 
    handlerFunction: handler 
  });

  const executionPromise = runner.run({ payload: {} });

  // Advance time by 60 seconds
  await runner.skipTime({ seconds: 60 });

  const execution = await executionPromise;
  expect(execution.getStatus()).toBe('SUCCEEDED');

  const waitOp = runner.getOperation('delay');
  expect(waitOp.getType()).toBe(OperationType.WAIT);
  expect(waitOp.getWaitDetails()?.waitSeconds).toBe(60);
});
```

## Test Runner API Patterns

**CRITICAL:** Always wrap event data in `payload` and cast results appropriately.

**TypeScript:**

```typescript
it('should use correct test runner API', async () => {
  const runner = new LocalDurableTestRunner({
    handlerFunction: handler,
  });

  // ✅ CORRECT: Wrap event in payload
  const execution = await runner.run({
    payload: { name: 'Alice', userId: '123' }
  });

  // ✅ CORRECT: Type cast result
  const result = execution.getResult() as {
    greeting: string;
    message: string;
  };

  expect(result.greeting).toBe('Hello, Alice!');

  // ✅ CORRECT: Get operations by name
  const greetingStep = runner.getOperation('generate-greeting');
  expect(greetingStep.getStepDetails()?.result).toBe('Hello, Alice!');
});

// ❌ WRONG: Missing payload wrapper and type casting
it('incorrect api usage', async () => {
  const runner = new LocalDurableTestRunner({ handlerFunction: handler });

  // ❌ Missing payload wrapper
  const execution = await runner.run({ name: 'Alice' });

  // ❌ No type casting - result is 'unknown'
  const result = execution.getResult();
  // expect(result.greeting).toBe('...'); // Type error!
});
```

## Testing Callbacks

**CRITICAL:** Use `waitForData()` with `WaitingOperationStatus.STARTED` to avoid flaky tests caused by promise races.

**TypeScript:**

```typescript
import { WaitingOperationStatus } from '@aws/durable-execution-sdk-js-testing';

it('should handle callback success', async () => {
  const runner = new LocalDurableTestRunner({ handlerFunction: handler });

  // Start execution (will pause at callback)
  const executionPromise = runner.run({
    payload: { approver: 'alice@example.com' }
  });

  // ✅ CRITICAL: Get operation by NAME
  const callbackOp = runner.getOperation('wait-for-approval');

  // ✅ CRITICAL: Wait for operation to reach STARTED status
  await callbackOp.waitForData(WaitingOperationStatus.STARTED);

  // ✅ CRITICAL: Must JSON.stringify callback data!
  await callbackOp.sendCallbackSuccess(
    JSON.stringify({ approved: true, comments: 'Looks good' })
  );

  const execution = await executionPromise;
  expect(execution.getStatus()).toBe('SUCCEEDED');

  // ✅ CRITICAL: Parse JSON string result
  const result: any = execution.getResult();
  const approval = typeof result.approval === 'string'
    ? JSON.parse(result.approval)
    : result.approval;

  expect(approval.approved).toBe(true);
  expect(approval.comments).toBe('Looks good');
});

it('should handle callback failure', async () => {
  const runner = new LocalDurableTestRunner({ handlerFunction: handler });

  const executionPromise = runner.run({ payload: {} });

  await new Promise(resolve => setTimeout(resolve, 100));

  const callbackOp = runner.getOperation('wait-for-approval');
  
  // Send callback failure
  await callbackOp.sendCallbackFailure(
    'ApprovalDenied',
    'Request was rejected'
  );

  const execution = await executionPromise;
  expect(execution.getStatus()).toBe('FAILED');
});
```

**Python:**

```python
def test_callback_success(durable_runner):
    with durable_runner:
        execution_future = durable_runner.run_async(input={'approver': 'alice@example.com'})
        
        # Wait for callback operation
        time.sleep(0.1)
        
        callback_op = durable_runner.get_operation('wait-for-approval')
        callback_op.send_callback_success('{"approved": true}')
        
        result = execution_future.result(timeout=10)
    
    assert result.status is InvocationStatus.SUCCEEDED
    assert result.result['approved'] is True
```

## Testing Callback Heartbeats

**TypeScript:**

```typescript
it('should handle callback heartbeats', async () => {
  const runner = new LocalDurableTestRunner({ handlerFunction: handler });

  const executionPromise = runner.run({ payload: {} });

  await new Promise(resolve => setTimeout(resolve, 100));

  const callbackOp = runner.getOperation('long-running-process');
  
  // Send heartbeats
  await callbackOp.sendCallbackHeartbeat();
  await runner.skipTime({ minutes: 2 });
  await callbackOp.sendCallbackHeartbeat();
  await runner.skipTime({ minutes: 2 });
  
  // Complete callback
  await callbackOp.sendCallbackSuccess(JSON.stringify({ status: 'completed' }));

  const execution = await executionPromise;
  expect(execution.getStatus()).toBe('SUCCEEDED');
});
```

## Testing Error Scenarios

**TypeScript:**

```typescript
it('should retry on failure', async () => {
  let attemptCount = 0;
  
  const testHandler = withDurableExecution(async (event, context: DurableContext) => {
    return await context.step('flaky-operation', async () => {
      attemptCount++;
      if (attemptCount < 3) {
        throw new Error('Temporary failure');
      }
      return { success: true };
    });
  });

  const runner = new LocalDurableTestRunner({ handlerFunction: testHandler });
  const execution = await runner.run({ payload: {} });

  expect(execution.getStatus()).toBe('SUCCEEDED');
  expect(attemptCount).toBe(3);

  const step = runner.getOperation('flaky-operation');
  expect(step.getStatus()).toBe(OperationStatus.SUCCEEDED);
});

it('should fail after max retries', async () => {
  const testHandler = withDurableExecution(async (event, context: DurableContext) => {
    return await context.step(
      'always-fails',
      async () => {
        throw new Error('Permanent failure');
      },
      {
        retryStrategy: RetryPresets.exponentialBackoff({ maxAttempts: 3 })
      }
    );
  });

  const runner = new LocalDurableTestRunner({ handlerFunction: testHandler });
  const execution = await runner.run({ payload: {} });

  expect(execution.getStatus()).toBe('FAILED');
  expect(execution.getError()?.message).toContain('Permanent failure');
});
```

## Testing Concurrent Operations

**TypeScript:**

```typescript
it('should process items concurrently', async () => {
  const runner = new LocalDurableTestRunner({ handlerFunction: handler });
  
  const execution = await runner.run({ 
    payload: { items: [1, 2, 3, 4, 5] } 
  });

  expect(execution.getStatus()).toBe('SUCCEEDED');

  const mapOp = runner.getOperation('process-items');
  expect(mapOp.getType()).toBe(OperationType.MAP);

  // Check individual item operations
  const item0 = runner.getOperation('process-0');
  expect(item0.getStatus()).toBe(OperationStatus.SUCCEEDED);
});
```

## Cloud Testing

For integration tests against real Lambda:

**TypeScript:**

```typescript
import { CloudDurableTestRunner } from '@aws/durable-execution-sdk-js-testing';

describe('Integration Tests', () => {
  it('should execute in real Lambda', async () => {
    const runner = new CloudDurableTestRunner({
      functionName: 'my-durable-function:1',  // Qualified ARN required
      client: new LambdaClient({ region: 'us-east-1' })
    });

    const execution = await runner.run({
      payload: { userId: '123' },
      config: { pollInterval: 1000 }
    });

    expect(execution.getStatus()).toBe('SUCCEEDED');
    
    const step = runner.getOperation('fetch-user');
    expect(step.getStatus()).toBe(OperationStatus.SUCCEEDED);
  });
});
```

## Test Assertions

**TypeScript:**

```typescript
it('should validate operation details', async () => {
  const runner = new LocalDurableTestRunner({ handlerFunction: handler });
  await runner.run({ payload: {} });

  const step = runner.getOperation('process-data');
  
  // Check operation type
  expect(step.getType()).toBe(OperationType.STEP);
  
  // Check status
  expect(step.getStatus()).toBe(OperationStatus.SUCCEEDED);
  
  // Check timing
  expect(step.getStartTimestamp()).toBeDefined();
  expect(step.getEndTimestamp()).toBeDefined();
  
  // Check result
  const stepDetails = step.getStepDetails();
  expect(stepDetails?.result).toEqual({ processed: true });
});
```

## Best Practices

1. **Always name operations** for reliable test assertions
2. **Get operations by name**, never by index
3. **Test replay behavior** with multiple invocations
4. **Use fake clock** for time-dependent tests
5. **Test error scenarios** including retries and failures
6. **Test callbacks** with success, failure, and timeout cases
7. **Validate operation details** (type, status, timing, results)
8. **Use cloud tests** for integration testing
9. **Mock external dependencies** in unit tests
10. **Test concurrent operations** individually and as a group

## Common Pitfalls

### ❌ Getting Operations by Index

```typescript
// Brittle - breaks when operations change
const step = runner.getOperationByIndex(0);
```

### ✅ Getting Operations by Name

```typescript
// Robust - works even if operation order changes
const step = runner.getOperation('fetch-user');
```

### ❌ Not Waiting for Callbacks

```typescript
// Race condition - callback might not exist yet
const callbackOp = runner.getOperation('wait-approval');
await callbackOp.sendCallbackSuccess('{}');
```

### ✅ Waiting for Callbacks

```typescript
// Use waitForData with proper status
import { WaitingOperationStatus } from '@aws/durable-execution-sdk-js-testing';

const callbackOp = runner.getOperation('wait-approval');
await callbackOp.waitForData(WaitingOperationStatus.STARTED);
await callbackOp.sendCallbackSuccess(JSON.stringify({}));
```

## Common Testing Errors

| Error                                 | Cause                                 | Solution                                          |
| ------------------------------------- | ------------------------------------- | ------------------------------------------------- |
| `'result' is of type 'unknown'`       | Missing type casting in tests         | Cast result: `as any` or specific type            |
| `'payload' does not exist in type`    | Wrong test runner API                 | Wrap event in `payload: {}` object                |
| `Cannot find operation at index`      | Using index for unstable operations   | Use `getOperation("name")` instead                |
| Flaky callback tests                  | Race condition with callback creation | Use `waitForData(WaitingOperationStatus.STARTED)` |
| `Unexpected token` in callback result | Forgot to JSON.stringify              | Always stringify: `JSON.stringify(data)`          |
| Callback result parsing error         | Result is JSON string                 | Parse result: `JSON.parse(result.value)`          |
| Operation not found by name           | Missing operation name                | Always name operations in handler                 |

## Jest Configuration

**jest.config.js:**

```javascript
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.test.ts'],
  transform: {
    '^.+\\.ts$': 'ts-jest',
  },
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.d.ts',
  ],
};
```

**Key points:**

- `preset: 'ts-jest'` is essential for TypeScript support
- `transform` maps .ts files to ts-jest transformer
- `testMatch` specifies test file patterns
- Use `skipTime: true` in test setup for fast execution
