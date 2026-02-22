# Advanced Patterns

Advanced techniques and patterns for sophisticated durable function workflows.

## Advanced GenAI Agent Patterns

### Agent with Reasoning and Dynamic Step Naming

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  context.logger.info('Starting AI agent', { prompt: event.prompt });
  const messages = [{ role: 'user', content: event.prompt }];

  while (true) {
    // Invoke AI model with reasoning
    const { response, reasoning, tool } = await context.step(
      'invoke-model',
      async (stepCtx) => {
        stepCtx.logger.info('Invoking AI model', {
          messageCount: messages.length
        });
        return await invokeAIModel(messages);
      }
    );

    // Log AI's reasoning
    if (reasoning) {
      context.logger.debug('AI reasoning', { reasoning });
    }

    // If no tool needed, return response
    if (tool == null) {
      context.logger.info('AI agent completed - no tool needed');
      return response;
    }

    // Execute tool with dynamic step naming
    const toolResult = await context.step(
      `execute-tool-${tool.name}`,  // Dynamic step name
      async (stepCtx) => {
        stepCtx.logger.info('Executing tool', {
          toolName: tool.name,
          toolParams: tool.parameters
        });
        return await executeTool(tool, response);
      }
    );

    // Add result to conversation
    messages.push({
      role: 'assistant',
      content: toolResult,
    });

    context.logger.debug('Tool result added', {
      toolName: tool.name,
      resultLength: toolResult.length
    });
  }
});
```

**Python:**

```python
@durable_execution
def handler(event: dict, context: DurableContext) -> str:
    context.logger.info('Starting AI agent', extra={'prompt': event['prompt']})
    messages = [{'role': 'user', 'content': event['prompt']}]

    while True:
        # Invoke AI model
        result = context.step(
            lambda _: invoke_ai_model(messages),
            name='invoke-model'
        )

        response = result['response']
        reasoning = result.get('reasoning')
        tool = result.get('tool')

        if reasoning:
            context.logger.debug('AI reasoning', extra={'reasoning': reasoning})

        if tool is None:
            context.logger.info('AI agent completed')
            return response

        # Execute tool with dynamic step naming
        tool_result = context.step(
            lambda _: execute_tool(tool, response),
            name=f"execute-tool-{tool['name']}"
        )

        messages.append({'role': 'assistant', 'content': tool_result})
        context.logger.debug('Tool result added', extra={'tool': tool['name']})
```

## Step Semantics Deep Dive

### AtMostOncePerRetry vs AtLeastOncePerRetry

**TypeScript:**

```typescript
import { StepSemantics } from '@aws/durable-execution-sdk-js';

// AtMostOncePerRetry (DEFAULT) - For idempotent operations
// Step executes at most once per retry attempt
// If step fails partway through, it won't re-execute the same attempt
await context.step(
  'update-database',
  async () => {
    // This is idempotent - safe to retry
    return await updateUserRecord(userId, data);
  },
  { semantics: StepSemantics.AtMostOncePerRetry }
);

// AtLeastOncePerRetry - For operations that can execute multiple times
// Step may execute multiple times per retry attempt
// Use when idempotency is handled externally
await context.step(
  'send-notification',
  async () => {
    // External system handles deduplication
    return await sendEmail(email, message);
  },
  { semantics: StepSemantics.AtLeastOncePerRetry }
);
```

**When to use each:**

| Semantic                | Use When                      | Example Operations                                |
| ----------------------- | ----------------------------- | ------------------------------------------------- |
| **AtMostOncePerRetry**  | Operation is idempotent       | Database updates, API calls with idempotency keys |
| **AtLeastOncePerRetry** | External deduplication exists | Queuing systems, event streams                    |

## Completion Policies - Interaction and Combination

### Combining Multiple Constraints

Completion policies can be combined, and execution **stops when the first constraint is met**:

**TypeScript:**

```typescript
const results = await context.map(
  'process-items',
  items,
  processFunc,
  {
    completionConfig: {
      minSuccessful: 8,              // Need at least 8 successes
      toleratedFailureCount: 2,       // OR can tolerate 2 failures
      toleratedFailurePercentage: 20, // OR can tolerate 20% failures
    }
  }
);

// Execution stops when ANY of these conditions is met:
// 1. 8 successful items (minSuccessful reached)
// 2. 2 failures occur (toleratedFailureCount reached)
// 3. 20% of items fail (toleratedFailurePercentage reached)
```

### Understanding Stop Conditions

**Example with 10 items:**

```typescript
const items = Array.from({ length: 10 }, (_, i) => i);

const results = await context.map(
  'process',
  items,
  processFunc,
  {
    maxConcurrency: 3,
    completionConfig: {
      minSuccessful: 7,
      toleratedFailureCount: 3
    }
  }
);

// Scenario 1: 7 successes, 0 failures
// ✅ Stops after 7th success (minSuccessful reached)
// Remaining 3 items are not processed

// Scenario 2: 5 successes, 3 failures
// ❌ Stops after 3rd failure (toleratedFailureCount reached)
// Remaining 2 items are not processed
// results.throwIfError() will throw because minSuccessful not met

// Scenario 3: 7 successes, 2 failures
// ✅ Stops after 7th success (minSuccessful reached)
// 1 item not processed, but completion policy satisfied
```

### Early Termination Pattern

Use completion policies for early termination when searching:

**TypeScript:**

```typescript
// Stop after finding first match
const results = await context.map(
  'find-match',
  candidates,
  async (ctx, candidate) => {
    return await ctx.step(async () => checkMatch(candidate));
  },
  {
    completionConfig: {
      minSuccessful: 1  // Stop after first success
    }
  }
);

// Only one item processed (assuming first succeeds)
if (results.successCount > 0) {
  const match = results.getSucceeded()[0];
  context.logger.info('Found match', { match });
}
```

## Advanced Error Handling

### Timeout Handling with waitForCallback

Handle callback timeouts with fallback logic:

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context) => {
  try {
    // Wait for external approval with timeout
    const approval = await context.waitForCallback(
      'wait-for-approval',
      async (callbackId, ctx) => {
        ctx.logger.info('Sending approval request', { callbackId });
        await sendApprovalEmail(event.approverEmail, callbackId);
      },
      { timeout: { hours: 24 } }
    );

    context.logger.info('Approval received', { approval });
    return { status: 'approved', approval };

  } catch (error: any) {
    // Check for callback timeout
    if (error.name === 'CallbackTimeoutError' ||
        error.message?.includes('timeout')) {

      context.logger.warn('Approval timed out after 24 hours', {
        approverEmail: event.approverEmail,
        error: error.message,
      });

      // Implement fallback: auto-escalate
      await context.step('handle-timeout', async (stepCtx) => {
        stepCtx.logger.info('Escalating to manager due to timeout');
        await escalateToManager(event);
      });

      return { status: 'timeout', escalated: true };
    }

    // Re-throw other errors
    throw error;
  }
});
```

**Python:**

```python
@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    try:
        # Wait for approval
        def submit_callback(callback_id: str):
            send_approval_email(event['approver_email'], callback_id)

        approval = context.wait_for_callback(
            submitter=submit_callback,
            config=WaitForCallbackConfig(timeout=Duration.from_hours(24)),
            name='wait-for-approval'
        )

        return {'status': 'approved', 'approval': approval}

    except Exception as error:
        # Check for timeout
        if 'timeout' in str(error).lower():
            context.logger.warning('Approval timed out')

            # Escalate
            context.step(
                lambda _: escalate_to_manager(event),
                name='handle-timeout'
            )

            return {'status': 'timeout', 'escalated': True}

        raise
```

### Local Timeout with Promise.race

For step-level timeouts within a single invocation:

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context) => {
  try {
    // Operation with local timeout
    const result = await Promise.race([
      context.step('long-operation', async () => longRunningTask()),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Operation timeout')), 30000)
      ),
    ]);

    return result;
  } catch (error: any) {
    if (error.message === 'Operation timeout') {
      context.logger.warn('Operation timed out, implementing fallback');
      return await context.step('fallback', async () => fallbackOperation());
    }
    throw error;
  }
});
```

**Note:** Promise.race only works within a single Lambda invocation. For timeouts across replays, use `timeout` option on `waitForCallback` or `waitForCondition`.

## Custom Serialization Patterns

### Class with Date Fields

**TypeScript:**

```typescript
import {
  createClassSerdesWithDates
} from '@aws/durable-execution-sdk-js';

class User {
  constructor(
    public name: string,
    public email: string,
    public createdAt: Date,
    public updatedAt: Date
  ) {}
}

const result = await context.step(
  'create-user',
  async () => new User('Alice', 'alice@example.com', new Date(), new Date()),
  {
    serdes: createClassSerdesWithDates(User, ['createdAt', 'updatedAt'])
  }
);

// result is properly deserialized User instance with Date objects
console.log(result.createdAt instanceof Date); // true
```

### Complex Object Graphs

**TypeScript:**

```typescript
import { createClassSerdes } from '@aws/durable-execution-sdk-js';

class Order {
  constructor(
    public id: string,
    public items: OrderItem[],
    public customer: Customer
  ) {}
}

class OrderItem {
  constructor(public sku: string, public quantity: number) {}
}

class Customer {
  constructor(public id: string, public name: string) {}
}

// Create serdes for each class
const orderSerdes = createClassSerdes(Order);
const itemSerdes = createClassSerdes(OrderItem);
const customerSerdes = createClassSerdes(Customer);

const result = await context.step(
  'process-order',
  async () => {
    const customer = new Customer('CUST-123', 'Alice');
    const items = [
      new OrderItem('SKU-001', 2),
      new OrderItem('SKU-002', 1)
    ];
    return new Order('ORD-456', items, customer);
  },
  { serdes: orderSerdes }
);
```

## Advanced Retry Strategies

### Conditional Retry Based on Error Type

**TypeScript:**

```typescript
import { createRetryStrategy } from '@aws/durable-execution-sdk-js';

const result = await context.step(
  'api-call',
  async () => callExternalAPI(),
  {
    retryStrategy: (error, attemptCount) => {
      // Don't retry client errors (4xx)
      if (error.statusCode >= 400 && error.statusCode < 500) {
        return { shouldRetry: false };
      }

      // Retry server errors (5xx) with exponential backoff
      if (error.statusCode >= 500) {
        return {
          shouldRetry: attemptCount < 5,
          delay: { seconds: Math.pow(2, attemptCount) }
        };
      }

      // Retry network errors with fixed delay
      if (error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
        return {
          shouldRetry: attemptCount < 10,
          delay: { seconds: 5 }
        };
      }

      // Don't retry unknown errors
      return { shouldRetry: false };
    }
  }
);
```

### Circuit Breaker Pattern

**TypeScript:**

```typescript
let failureCount = 0;
let lastFailureTime = 0;
const CIRCUIT_OPEN_DURATION = 60000; // 1 minute

const result = await context.step(
  'call-with-circuit-breaker',
  async () => {
    const now = Date.now();

    // Check if circuit is open
    if (failureCount >= 5 && (now - lastFailureTime) < CIRCUIT_OPEN_DURATION) {
      throw new Error('Circuit breaker is open');
    }

    try {
      const result = await callExternalService();
      failureCount = 0; // Reset on success
      return result;
    } catch (error) {
      failureCount++;
      lastFailureTime = now;
      throw error;
    }
  },
  {
    retryStrategy: (error, attemptCount) => {
      if (error.message === 'Circuit breaker is open') {
        return {
          shouldRetry: true,
          delay: { seconds: 60 } // Wait before checking circuit again
        };
      }

      return {
        shouldRetry: attemptCount < 3,
        delay: { seconds: 2 }
      };
    }
  }
);
```

## Nested Workflows

### Parent-Child Workflow Pattern

**TypeScript:**

```typescript
// Parent orchestrator
export const orchestrator = withDurableExecution(
  async (event, context: DurableContext) => {
    const childFunctionArn = process.env.CHILD_FUNCTION_ARN!;

    // Invoke child workflows in parallel
    const results = await context.parallel(
      'process-batches',
      [
        {
          name: 'batch-1',
          func: async (ctx) => ctx.invoke(
            'process-batch-1',
            childFunctionArn,
            { batch: event.batches[0] }
          )
        },
        {
          name: 'batch-2',
          func: async (ctx) => ctx.invoke(
            'process-batch-2',
            childFunctionArn,
            { batch: event.batches[1] }
          )
        }
      ]
    );

    return results.getResults();
  }
);

// Child worker
export const worker = withDurableExecution(
  async (event, context: DurableContext) => {
    const items = event.batch.items;

    const results = await context.map(
      'process-items',
      items,
      async (ctx, item) => {
        return await ctx.step(async () => processItem(item));
      }
    );

    return results.getResults();
  }
);
```

## Best Practices Summary

1. **Dynamic Step Naming**: Use template literals for dynamic operation names
2. **Structured Logging**: Log reasoning and context with each operation
3. **Timeout Handling**: Always have fallback logic for callback timeouts
4. **Completion Policies**: Understand how combined constraints interact
5. **Retry Strategies**: Implement conditional retries based on error types
6. **Custom Serialization**: Use proper serdes for complex objects
7. **Circuit Breakers**: Protect against cascading failures
8. **Nested Workflows**: Use invoke for modular, composable architectures
