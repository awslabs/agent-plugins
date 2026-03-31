# Concurrent Operations - Java

## Map with MapConfig

```java
import software.amazon.lambda.durable.config.MapConfig;
import software.amazon.lambda.durable.config.CompletionConfig;

var results = ctx.map("process-items", items, ProcessResult.class,
    (item, index, childCtx) -> {
        return childCtx.step("process-" + index, Result.class,
            stepCtx -> processItem(item));
    },
    MapConfig.builder()
        .maxConcurrency(3)
        .completionConfig(CompletionConfig.allSuccessful())
        .build());
results.throwIfError();
var allResults = results.getResults();
```

## Async Map

```java
var future = ctx.mapAsync("process-items", items, ProcessResult.class,
    (item, index, childCtx) -> {
        return childCtx.step("process-" + index, Result.class,
            stepCtx -> processItem(item));
    },
    MapConfig.builder().maxConcurrency(5).build());
// ... do other work ...
var results = future.get();
```

## CompletionConfig Factory Methods

```java
MapConfig.builder().completionConfig(CompletionConfig.allSuccessful()).build();  // All must succeed (default)
MapConfig.builder().completionConfig(CompletionConfig.firstSuccessful()).build();  // At least one succeeds
MapConfig.builder().completionConfig(CompletionConfig.minSuccessful(3)).build();  // Exactly N must succeed
```

## MapResult and MapResultItem

```java
var results = ctx.map("process", items, Result.class, (item, i, childCtx) ->
    childCtx.step("step-" + i, Result.class, stepCtx -> process(item)));
var succeeded = results.getResults();       // List of successful results
var errors = results.getErrors();           // List of errors
// Individual item results with success/failure status
for (var item : results.getResultItems()) {
    if (item.isSuccess()) {
        process(item.getResult());
    } else {
        log.error("Item {} failed: {}", item.getIndex(), item.getError().getMessage());
    }
}
```

## Error Isolation

```java
// Errors in individual map items don't fail the entire map
var results = ctx.map("safe-process", items, Result.class,
    (item, index, childCtx) -> {
        return childCtx.step("process-" + index, Result.class, stepCtx -> {
            if (shouldFail(item)) throw new RuntimeException("Item failed");
            return processItem(item);
        });
    },
    MapConfig.builder().completionConfig(CompletionConfig.minSuccessful(3)).build());
// Map completes even if some items fail — check errors explicitly
var successResults = results.getResults();
var failedErrors = results.getErrors();
```

## Map with Child Contexts

```java
var results = ctx.map("complex-process", items, ProcessResult.class,
    (item, index, childCtx) -> {
        return childCtx.runInChildContext("item-" + index, ProcessResult.class, inner -> {
            var validated = inner.step("validate", Validated.class, s -> validate(item));
            inner.wait(null, Duration.ofSeconds(1));
            return inner.step("process", ProcessResult.class, s -> process(validated));
        });
    },
    MapConfig.builder().maxConcurrency(5).build());
```
