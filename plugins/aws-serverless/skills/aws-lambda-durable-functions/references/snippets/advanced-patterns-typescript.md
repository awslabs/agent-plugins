# Advanced Patterns - TypeScript

## GenAI Agent with Reasoning

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  context.logger.info('Starting AI agent', { prompt: event.prompt });
  const messages = [{ role: 'user', content: event.prompt }];
  while (true) {
    const { response, reasoning, tool } = await context.step(
      'invoke-model', async (stepCtx) => {
        stepCtx.logger.info('Invoking AI model', { messageCount: messages.length });
        return await invokeAIModel(messages);
      });
    if (reasoning) context.logger.debug('AI reasoning', { reasoning });
    if (tool == null) return response;
    const toolResult = await context.step(
      `execute-tool-${tool.name}`, async (stepCtx) => {
        stepCtx.logger.info('Executing tool', { toolName: tool.name });
        return await executeTool(tool, response);
      });
    messages.push({ role: 'assistant', content: toolResult });
  }
});
```

## Step Semantics

```typescript
import { StepSemantics } from '@aws/durable-execution-sdk-js';

// AtMostOncePerRetry (DEFAULT) - idempotent operations
await context.step('update-database', async () => updateUserRecord(userId, data),
  { semantics: StepSemantics.AtMostOncePerRetry });

// AtLeastOncePerRetry - external deduplication exists
await context.step('send-notification', async () => sendEmail(email, message),
  { semantics: StepSemantics.AtLeastOncePerRetry });
```

## Completion Policy Combinations

```typescript
const results = await context.map('process-items', items, processFunc, {
  completionConfig: {
    minSuccessful: 8,              // Need at least 8 successes
    toleratedFailureCount: 2,       // OR tolerate 2 failures
    toleratedFailurePercentage: 20, // OR tolerate 20% failures
  }
});
// Stops when ANY constraint is met first
```

## Early Termination

```typescript
const results = await context.map('find-match', candidates,
  async (ctx, candidate) => ctx.step(async () => checkMatch(candidate)),
  { completionConfig: { minSuccessful: 1 } });
if (results.successCount > 0) {
  const match = results.getSucceeded()[0];
  context.logger.info('Found match', { match });
}
```

## Custom Serialization

```typescript
import { createClassSerdesWithDates, createClassSerdes } from '@aws/durable-execution-sdk-js';

class User {
  constructor(public name: string, public email: string,
    public createdAt: Date, public updatedAt: Date) {}
}
await context.step('create-user',
  async () => new User('Alice', 'alice@example.com', new Date(), new Date()),
  { serdes: createClassSerdesWithDates(User, ['createdAt', 'updatedAt']) });
// For complex object graphs, use createClassSerdes(Order)
await context.step('process-order', async () => buildOrder(),
  { serdes: createClassSerdes(Order) });
```

## Nested Parent-Child Workflows

```typescript
export const orchestrator = withDurableExecution(async (event, context: DurableContext) => {
  const childArn = process.env.CHILD_FUNCTION_ARN!;
  return (await context.parallel('process-batches', [
    { name: 'batch-1', func: async (ctx) =>
      ctx.invoke('process-batch-1', childArn, { batch: event.batches[0] }) },
    { name: 'batch-2', func: async (ctx) =>
      ctx.invoke('process-batch-2', childArn, { batch: event.batches[1] }) }
  ])).getResults();
});

export const worker = withDurableExecution(async (event, context: DurableContext) => {
  return (await context.map('process-items', event.batch.items,
    async (ctx, item) => ctx.step(async () => processItem(item)))).getResults();
});
```
