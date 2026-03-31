# Advanced Patterns - Java

## GenAI Agent Loop

```java
public class AgentHandler extends DurableHandler<AgentRequest, String> {
    @Override public String handleRequest(AgentRequest event, DurableContext ctx) {
        ctx.getLogger().info("Starting AI agent");
        var messages = new ArrayList<>(List.of(Map.of("role", "user", "content", event.getPrompt())));
        while (true) {
            var result = ctx.step("invoke-model", ModelResult.class,
                stepCtx -> invokeAIModel(messages));
            if (result.getTool() == null) return result.getResponse();
            var toolResult = ctx.step("execute-tool-" + result.getTool().getName(),
                String.class, stepCtx -> executeTool(result.getTool(), result.getResponse()));
            messages.add(Map.of("role", "assistant", "content", toolResult));
        }
    }
}
```

## Async Steps with DurableFuture

```java
// Run concurrent async steps and await all
var future1 = ctx.stepAsync("fetch-user", User.class, s -> fetchUser(userId));
var future2 = ctx.stepAsync("fetch-orders", new TypeToken<List<Order>>() {}, s -> fetchOrders(userId));
var future3 = ctx.stepAsync("fetch-prefs", Preferences.class, s -> fetchPreferences(userId));
DurableFuture.allOf(future1, future2, future3);
var user = future1.get();
var orders = future2.get();
var prefs = future3.get();
```

## Async Child Context

```java
var childFuture = ctx.runInChildContextAsync("process-batch", BatchResult.class, child -> {
    var validated = child.step("validate", ValidatedData.class, s -> validateBatch(data));
    child.wait(null, Duration.ofSeconds(1));
    return child.step("process", BatchResult.class, s -> processBatch(validated));
});
// ... do other work ...
var batchResult = childFuture.get();
```

## MapConfig with CompletionConfig

```java
var results = ctx.map("process-items", items, Result.class,
    (item, index, childCtx) -> childCtx.step("p-" + index, Result.class, s -> process(item)),
    MapConfig.builder()
        .maxConcurrency(3)
        .completionConfig(CompletionConfig.minSuccessful(8))
        .build());
// Stops when 8 items succeed or tolerated failures exceeded
```

## Step Semantics

```java
import software.amazon.lambda.durable.config.StepSemantics;

// AT_MOST_ONCE_PER_RETRY - for non-idempotent operations
var payment = ctx.step("charge", PaymentResult.class, s -> chargeCard(amount),
    StepConfig.builder().stepSemantics(StepSemantics.AT_MOST_ONCE_PER_RETRY).build());

// AT_LEAST_ONCE (default) - for idempotent operations
var result = ctx.step("update-db", Result.class, s -> updateRecord(data));
```

## Custom SerDes

```java
import software.amazon.lambda.durable.serde.SerDes;

public class UserSerDes implements SerDes<User> {
    @Override public String serialize(User user) { return new ObjectMapper().writeValueAsString(user); }
    @Override public User deserialize(String data) { return new ObjectMapper().readValue(data, User.class); }
}
var user = ctx.step("create-user", User.class, s -> createUser(event),
    StepConfig.builder().serDes(new UserSerDes()).build());
```

## Nested Parent-Child Workflows

```java
// Parent orchestrator
public class OrchestratorHandler extends DurableHandler<BatchEvent, List<BatchResult>> {
    @Override public List<BatchResult> handleRequest(BatchEvent event, DurableContext ctx) {
        var childArn = System.getenv("CHILD_FUNCTION_ARN");
        var f1 = ctx.stepAsync("batch-1", BatchResult.class,
            s -> ctx.invoke("invoke-1", childArn, event.getBatches().get(0), BatchResult.class));
        var f2 = ctx.stepAsync("batch-2", BatchResult.class,
            s -> ctx.invoke("invoke-2", childArn, event.getBatches().get(1), BatchResult.class));
        DurableFuture.allOf(f1, f2);
        return List.of(f1.get(), f2.get());
    }
}
```
