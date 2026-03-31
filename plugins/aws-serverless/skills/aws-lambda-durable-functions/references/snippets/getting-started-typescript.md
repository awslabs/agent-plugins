# Getting Started - TypeScript

## Basic Handler

```typescript
import { withDurableExecution, DurableContext } from '@aws/durable-execution-sdk-js';

export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const userData = await context.step('fetch-user', async () => fetchUserFromDB(event.userId));
  await context.wait({ seconds: 5 });
  const result = await context.step('process', async () => processUser(userData));
  return { success: true, data: result };
});
```

## Multi-Step Workflow

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const validated = await context.step('validate', async () => validateInput(event));
  const processed = await context.step('process', async () => processData(validated));
  await context.wait('cooldown', { seconds: 30 });
  await context.step('notify', async () => sendNotification(processed));
  return { success: true };
});
```

## GenAI Agent (Agentic Loop)

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const messages = [{ role: 'user', content: event.prompt }];
  while (true) {
    const { response, tool } = await context.step('invoke-model', async () =>
      invokeAIModel(messages)
    );
    if (tool == null) return response;
    const toolResult = await context.step(`tool-${tool.name}`, async () =>
      executeTool(tool, response)
    );
    messages.push({ role: 'assistant', content: toolResult });
  }
});
```

## Human-in-the-Loop Approval

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const plan = await context.step('generate-plan', async () => generatePlan(event));
  const answer = await context.waitForCallback(
    'wait-for-approval',
    async (callbackId) => sendApprovalEmail(event.approverEmail, plan, callbackId),
    { timeout: { hours: 24 } }
  );
  if (answer === 'APPROVED') {
    await context.step('execute', async () => performAction(plan));
    return { status: 'completed' };
  }
  return { status: 'rejected' };
});
```

## Saga Pattern

```typescript
export const handler = withDurableExecution(async (event, ctx: DurableContext) => {
  const compensations: Array<{ name: string; fn: () => Promise<void> }> = [];
  try {
    await ctx.step('book-flight', async () => flightClient.book(event));
    compensations.push({ name: 'cancel-flight', fn: () => flightClient.cancel(event) });
    await ctx.step('book-hotel', async () => hotelClient.book(event));
    compensations.push({ name: 'cancel-hotel', fn: () => hotelClient.cancel(event) });
    return { success: true };
  } catch (error) {
    for (const c of compensations.reverse()) await ctx.step(c.name, async () => c.fn());
    throw error;
  }
});
```

## ESLint Setup

```bash
npm install --save-dev @aws/durable-execution-sdk-js-eslint-plugin
```

```javascript
import durableExecutionPlugin from '@aws/durable-execution-sdk-js-eslint-plugin';
export default [durableExecutionPlugin.configs.recommended];
```

## Jest Config

```javascript
module.exports = {
  preset: 'ts-jest', testEnvironment: 'node',
  testMatch: ['**/*.test.ts'], transform: { '^.+\\.ts$': 'ts-jest' },
};
```
