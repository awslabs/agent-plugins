# Step Operations - Java

## Basic Step

```java
var result = ctx.step("fetch-user", UserData.class, stepCtx -> fetchUserFromAPI(userId));
```

## Retry Configuration

```java
import software.amazon.lambda.durable.retries.RetryStrategies;

var result = ctx.step("api-call", ApiResponse.class, stepCtx -> callExternalAPI(),
    StepConfig.builder()
        .retryStrategy(RetryStrategies.exponentialBackoff(b -> b
            .maxAttempts(5)
            .initialDelay(Duration.ofSeconds(1))
            .maxDelay(Duration.ofSeconds(60))
            .backoffRate(2.0)
            .jitter(JitterStrategy.FULL)))
        .build());
```

## Custom Retry

```java
var result = ctx.step("custom-retry", Result.class, stepCtx -> riskyOperation(),
    StepConfig.builder()
        .retryStrategy((error, attemptCount) -> {
            if (error instanceof ValidationException) return RetryDecision.noRetry();
            if (attemptCount < 3) {
                return RetryDecision.retryAfter(Duration.ofSeconds((long) Math.pow(2, attemptCount)));
            }
            return RetryDecision.noRetry();
        })
        .build());
```

## Step Semantics

```java
import software.amazon.lambda.durable.config.StepSemantics;

// AT_LEAST_ONCE (default) - may execute multiple times on failure/retry
var result = ctx.step("idempotent-op", Result.class, stepCtx -> idempotentAPI());

// AT_MOST_ONCE - never retries, use for non-idempotent operations
var payment = ctx.step("charge-payment", PaymentResult.class, stepCtx -> chargeCard(amount),
    StepConfig.builder()
        .stepSemantics(StepSemantics.AT_MOST_ONCE_PER_RETRY)
        .build());
```

## Generic Types with TypeToken

```java
import software.amazon.lambda.durable.TypeToken;

// Use TypeToken for generic types like List<T>
var users = ctx.step("fetch-users", new TypeToken<List<User>>() {}, stepCtx -> fetchAllUsers());
```

## Child Context

```java
// Use child context when you need durable operations inside a group
var result = ctx.runInChildContext("process", ProcessResult.class, childCtx -> {
    var data = childCtx.step("fetch", Data.class, s -> fetchData());
    childCtx.wait(null, Duration.ofSeconds(1));
    return childCtx.step("save", SaveResult.class, s -> save(data));
});
```

## Error Handling

```java
import software.amazon.lambda.durable.exception.StepFailedException;
import software.amazon.lambda.durable.exception.StepInterruptedException;

try {
    var result = ctx.step("risky", Result.class, stepCtx -> riskyOperation());
} catch (StepFailedException e) {
    ctx.getLogger().error("Step permanently failed: {}", e.getMessage());
} catch (StepInterruptedException e) {
    ctx.getLogger().error("Step interrupted: {}", e.getMessage());
}
```
