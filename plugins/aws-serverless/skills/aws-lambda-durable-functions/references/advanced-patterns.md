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
# Note: invoke_ai_model and execute_tool are decorated with @durable_step
@durable_execution
def handler(event: dict, context: DurableContext) -> str:
    context.logger.info('Starting AI agent', extra={'prompt': event['prompt']})
    messages = [{'role': 'user', 'content': event['prompt']}]

    while True:
        # Invoke AI model
        result = context.step(invoke_ai_model(messages))

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
            func=execute_tool(tool, response),
            name=f"execute-tool-{tool['name']}"
        )

        messages.append({'role': 'assistant', 'content': tool_result})
        context.logger.debug('Tool result added', extra={'tool': tool['name']})
```

**Java:**

```java
public class AgentHandler extends DurableHandler<AgentRequest, String> {
    @Override
    public String handleRequest(AgentRequest event, DurableContext ctx) {
        ctx.getLogger().info("Starting AI agent with prompt: {}", event.getPrompt());
        var messages = new ArrayList<>(List.of(
            Map.of("role", "user", "content", event.getPrompt())));

        while (true) {
            // Invoke AI model with reasoning
            var result = ctx.step("invoke-model", ModelResult.class, stepCtx -> {
                stepCtx.getLogger().info("Invoking AI model. Message count: {}", messages.size());
                return invokeAIModel(messages);
            });

            // Log AI's reasoning
            if (result.getReasoning() != null) {
                ctx.getLogger().debug("AI reasoning: {}", result.getReasoning());
            }

            // If no tool needed, return response
            if (result.getTool() == null) {
                ctx.getLogger().info("AI agent completed - no tool needed");
                return result.getResponse();
            }

            // Execute tool with dynamic step naming
            var toolResult = ctx.step("execute-tool-" + result.getTool().getName(), String.class,
                stepCtx -> {
                    stepCtx.getLogger().info("Executing tool: {}", result.getTool().getName());
                    return executeTool(result.getTool(), result.getResponse());
                });

            messages.add(Map.of("role", "assistant", "content", toolResult));
            ctx.getLogger().debug("Tool result added. Tool: {}", result.getTool().getName());
        }
    }
}
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

**Java:**

```java
import software.amazon.lambda.durable.config.StepConfig;
import software.amazon.lambda.durable.config.StepSemantics;

// AT_MOST_ONCE_PER_RETRY - the START checkpoint is awaited before user code runs.
// If interrupted, the step is not silently re-run within the same attempt.
// Use semanticsPerRetry(...) so interrupted steps still follow the retry strategy.
ctx.step("update-database", UpdateResult.class,
    stepCtx -> updateUserRecord(userId, data),
    StepConfig.builder()
        .semanticsPerRetry(StepSemantics.AT_MOST_ONCE_PER_RETRY)
        .build());

// AT_LEAST_ONCE_PER_RETRY (default) - may execute multiple times per retry attempt.
// Use when idempotency is handled externally.
ctx.step("send-notification", Void.class,
    stepCtx -> { sendEmail(email, message); return null; },
    StepConfig.builder()
        .semanticsPerRetry(StepSemantics.AT_LEAST_ONCE_PER_RETRY)
        .build());
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

**Java:**

```java
// CompletionConfig is a record; use the canonical constructor to combine constraints.
// Percentage is a 0.0-1.0 fraction.
var results = ctx.map("process-items", items, Result.class,
    (item, index, childCtx) -> childCtx.step("p-" + index, Result.class, s -> process(item)),
    MapConfig.builder()
        .completionConfig(new CompletionConfig(8, 2, 0.20))
        .build());

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

**Java:**

```java
var items = IntStream.range(0, 10).boxed().toList();

var results = ctx.map("process", items, Result.class,
    (item, index, childCtx) -> childCtx.step("p-" + index, Result.class, s -> process(item)),
    MapConfig.builder()
        .maxConcurrency(3)
        .completionConfig(new CompletionConfig(7, 3, null))
        .build());

// Scenario 1: 7 successes, 0 failures
// ✅ Stops after 7th success (minSuccessful reached)
// Remaining 3 items are not processed

// Scenario 2: 5 successes, 3 failures
// ❌ Stops after 3rd failure (toleratedFailureCount reached)
// Remaining 2 items are not processed; results.allSucceeded() is false

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

**Java:**

```java
// Stop after finding the first match
var results = ctx.map("find-match", candidates, Match.class,
    (candidate, index, childCtx) -> childCtx.step("check-" + index, Match.class,
        s -> checkMatch(candidate)),
    MapConfig.builder()
        .completionConfig(CompletionConfig.minSuccessful(1))  // Stop after first success
        .build());

// Only one item processed (assuming the first succeeds)
var matches = results.succeeded();
if (!matches.isEmpty()) {
    var match = matches.get(0);
    ctx.getLogger().info("Found match: {}", match);
}
```

## Advanced Error Handling

For timeout handling (waitForCallback, Promise.race), conditional retries, and circuit breaker patterns, see [advanced-error-handling.md](advanced-error-handling.md).

## Advanced and Retry Strategies

For conditional retry strategies and circuit breaker patterns, see [advanced-error-handling.md](advanced-error-handling.md).

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

**Java:**

```java
import software.amazon.lambda.durable.serde.SerDes;
import software.amazon.lambda.durable.TypeToken;
import software.amazon.lambda.durable.config.StepConfig;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

// Jackson handles java.time types (Instant, etc.) via JavaTimeModule.
// SerDes is non-generic: serialize(Object) and deserialize(String, TypeToken<T>).
public class DateAwareSerDes implements SerDes {
    private final ObjectMapper mapper = new ObjectMapper().registerModule(new JavaTimeModule());

    @Override
    public String serialize(Object value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public <T> T deserialize(String data, TypeToken<T> typeToken) {
        try {
            return mapper.readValue(data, mapper.constructType(typeToken.getType()));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}

var result = ctx.step("create-user", User.class,
    stepCtx -> new User("Alice", "alice@example.com", Instant.now(), Instant.now()),
    StepConfig.builder().serDes(new DateAwareSerDes()).build());
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

**Java:**

```java
// Nested object graphs serialize automatically with the default Jackson-based
// SerDes - records (or POJOs) compose without per-class registration.
public record Customer(String id, String name) {}
public record OrderItem(String sku, int quantity) {}
public record Order(String id, List<OrderItem> items, Customer customer) {}

var result = ctx.step("process-order", Order.class, stepCtx -> {
    var customer = new Customer("CUST-123", "Alice");
    var items = List.of(new OrderItem("SKU-001", 2), new OrderItem("SKU-002", 1));
    return new Order("ORD-456", items, customer);
});
```

## Java SDK Configuration

The Java SDK is configured per-handler by overriding `createConfiguration()` on
`DurableHandler` and returning a `DurableConfig`. This is the Java-specific entry point for
tuning serialization, the concurrency executor, and checkpoint batching. (TypeScript and
Python expose equivalent configuration through their own SDK options.)

> **Note:** The virtual-thread executor below requires **Java 21+**
> (`Executors.newVirtualThreadPerTaskExecutor()`). The SDK itself targets Java 17+; on
> Java 17 use a platform-thread pool such as `Executors.newFixedThreadPool(n)` instead.

**Java:**

```java
import java.time.Duration;
import java.util.concurrent.Executors;
import software.amazon.lambda.durable.DurableConfig;
import software.amazon.lambda.durable.DurableContext;
import software.amazon.lambda.durable.DurableFuture;
import software.amazon.lambda.durable.DurableHandler;

public class ManyStepsHandler extends DurableHandler<BatchInput, Integer> {

    @Override
    protected DurableConfig createConfiguration() {
        return DurableConfig.builder()
            // Virtual threads scale to large numbers of concurrent async operations
            // (Java 21+). Recommended when a handler fans out into many
            // stepAsync / map / parallel branches.
            .withExecutorService(Executors.newVirtualThreadPerTaskExecutor())
            // A small checkpoint delay batches checkpoint requests together, reducing
            // overall latency when there are many concurrent operations.
            .withCheckpointDelay(Duration.ofMillis(10))
            .build();
    }

    @Override
    public Integer handleRequest(BatchInput event, DurableContext ctx) {
        // Fan out into many async steps - executed on the virtual-thread pool above
        var futures = new java.util.ArrayList<DurableFuture<Integer>>();
        for (int i = 0; i < event.getCount(); i++) {
            int index = i;
            futures.add(ctx.stepAsync("compute-" + i, Integer.class, s -> index * 2));
        }

        // Collect all results in order
        var results = DurableFuture.allOf(futures);
        return results.stream().mapToInt(Integer::intValue).sum();
    }
}
```

**When to use these settings:**

| Setting | Use when |
| --- | --- |
| `withExecutorService(Executors.newVirtualThreadPerTaskExecutor())` | The handler creates many concurrent operations (`stepAsync`, `map`, `parallel`); virtual threads (Java 21+) scale far better than a fixed thread pool |
| `withCheckpointDelay(Duration.ofMillis(...))` | Many concurrent operations checkpoint at once; a small delay batches the checkpoint API calls and lowers latency |

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

**Java:**

```java
import software.amazon.lambda.durable.DurableFuture;

// Parent orchestrator
public class OrchestratorHandler extends DurableHandler<BatchEvent, List<BatchResult>> {
    @Override
    public List<BatchResult> handleRequest(BatchEvent event, DurableContext ctx) {
        var childArn = System.getenv("CHILD_FUNCTION_ARN");

        // Invoke child workflows concurrently with invokeAsync (durable operations
        // cannot be nested inside a step).
        var f1 = ctx.invokeAsync("batch-1", childArn, event.getBatches().get(0), BatchResult.class);
        var f2 = ctx.invokeAsync("batch-2", childArn, event.getBatches().get(1), BatchResult.class);

        // Wait for all child invocations to complete
        DurableFuture.allOf(f1, f2);

        return List.of(f1.get(), f2.get());
    }
}

// Child worker
public class WorkerHandler extends DurableHandler<BatchInput, List<Result>> {
    @Override
    public List<Result> handleRequest(BatchInput event, DurableContext ctx) {
        var items = event.getBatch().getItems();

        var results = ctx.map("process-items", items, Result.class,
            (item, index, childCtx) -> childCtx.step("process-" + index, Result.class,
                stepCtx -> processItem(item)));

        return results.results();
    }
}
```

## Best Practices Summary

1. **Dynamic Step Naming**: Use template literals for dynamic operation names
2. **Structured Logging**: Log reasoning and context with each operation
3. **Error Handling**: See [advanced-error-handling.md](advanced-error-handling.md) for timeout, retry, and circuit breaker patterns
4. **Completion Policies**: Understand how combined constraints interact
5. **Custom Serialization**: Use proper serdes for complex objects
6. **Nested Workflows**: Use invoke for modular, composable architectures
