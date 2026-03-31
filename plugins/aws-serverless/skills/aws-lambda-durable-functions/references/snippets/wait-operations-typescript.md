# Wait Operations - TypeScript

## Simple Waits

```typescript
await context.wait({ seconds: 30 });
await context.wait({ minutes: 5 });
await context.wait({ hours: 1, minutes: 30 });
await context.wait({ days: 7 });

// Named wait (recommended)
await context.wait('rate-limit-delay', { seconds: 60 });
```

## Wait for Callback

```typescript
const result = await context.waitForCallback(
  'wait-for-approval',
  async (callbackId, ctx) => {
    await sendApprovalEmail(approverEmail, callbackId);
  },
  { timeout: { hours: 24 }, heartbeatTimeout: { minutes: 5 } }
);
```

## Callback Success (SDK)

```typescript
import { LambdaClient, SendDurableExecutionCallbackSuccessCommand } from '@aws-sdk/client-lambda';

const client = new LambdaClient({});
await client.send(new SendDurableExecutionCallbackSuccessCommand({
  CallbackId: callbackId,
  Payload: JSON.stringify({ status: 'approved' })
}));
```

## Wait for Condition

```typescript
const finalState = await context.waitForCondition(
  'wait-for-job',
  async (currentState, ctx) => {
    const status = await checkJobStatus(currentState.jobId);
    return { ...currentState, status };
  },
  {
    initialState: { jobId: 'job-123', status: 'pending' },
    waitStrategy: createWaitStrategy({
      maxAttempts: 60, initialDelaySeconds: 5, maxDelaySeconds: 30,
      backoffRate: 1.5, shouldContinuePolling: (result) => result.status !== "completed"
    }),
    timeout: { hours: 1 }
  }
);
```

## Custom Wait Strategy

```typescript
const result = await context.waitForCondition(
  'custom-poll',
  async (state) => {
    const data = await fetchData();
    return { ...state, data, attempts: state.attempts + 1 };
  },
  {
    initialState: { attempts: 0 },
    waitStrategy: (state, attempt) => {
      if (state.attempts >= 10) return { shouldContinue: false };
      return {
        shouldContinue: !state.data?.ready,
        delay: { seconds: Math.min(Math.pow(2, attempt), 60) }
      };
    }
  }
);
```

## Error Handling

```typescript
try {
  const result = await context.waitForCallback(
    'wait-approval',
    async (callbackId) => sendApproval(callbackId),
    { timeout: { hours: 24 } }
  );
} catch (error) {
  if (error instanceof CallbackError) {
    if (error.errorType === 'Timeout') {
      context.logger.warn('Approval timed out');
    } else {
      context.logger.error('Callback failed', error);
    }
  }
}
```
