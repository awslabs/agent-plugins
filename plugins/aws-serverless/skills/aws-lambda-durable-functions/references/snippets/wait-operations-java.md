# Wait Operations - Java

## Simple Waits

```java
// Synchronous wait (blocks execution)
ctx.wait(null, Duration.ofSeconds(30));
ctx.wait("rate-limit-delay", Duration.ofMinutes(5));

// Async wait (returns DurableFuture)
var future = ctx.waitAsync(null, Duration.ofHours(1));
// ... do other work ...
future.get();
```

## Wait for Callback

```java
var result = ctx.waitForCallback("wait-for-approval", ApprovalResult.class,
    (callbackId, stepCtx) -> {
        sendApprovalEmail(approverEmail, callbackId);
    },
    CallbackConfig.builder()
        .timeout(Duration.ofHours(24))
        .heartbeatTimeout(Duration.ofMinutes(5))
        .build());
```

## Create Callback

```java
var callbackId = ctx.createCallback();
sendToExternalSystem(callbackId);
```

## Wait for Condition

```java
var finalState = ctx.waitForCondition("wait-for-job", JobState.class,
    (currentState, stepCtx) -> {
        var status = checkJobStatus(currentState.getJobId());
        return new JobState(currentState.getJobId(), status);
    },
    WaitForConditionConfig.builder()
        .initialState(new JobState("job-123", "pending"))
        .waitStrategy(WaitStrategies.exponentialBackoff(b -> b
            .maxAttempts(60)
            .initialDelay(Duration.ofSeconds(5))
            .maxDelay(Duration.ofSeconds(30))
            .backoffRate(1.5)))
        .shouldContinuePolling(state -> !"completed".equals(state.getStatus()))
        .timeout(Duration.ofHours(1))
        .build());
```

## Custom Wait Strategy

```java
var result = ctx.waitForCondition("custom-poll", PollState.class,
    (state, stepCtx) -> {
        var data = fetchData();
        return new PollState(data, state.getAttempts() + 1);
    },
    WaitForConditionConfig.builder()
        .initialState(new PollState(null, 0))
        .waitStrategy((state, attempt) -> {
            if (state.getAttempts() >= 10) return WaitForConditionResult.stopPolling();
            var delay = Duration.ofSeconds(Math.min((long) Math.pow(2, attempt), 60));
            return WaitForConditionResult.continuePolling(delay);
        })
        .build());
```

## Error Handling

```java
import software.amazon.lambda.durable.exception.CallbackFailedException;
import software.amazon.lambda.durable.exception.CallbackTimeoutException;
import software.amazon.lambda.durable.exception.WaitForConditionFailedException;

try {
    var result = ctx.waitForCallback("wait-approval", ApprovalResult.class,
        (callbackId, stepCtx) -> sendApproval(callbackId),
        CallbackConfig.builder().timeout(Duration.ofHours(24)).build());
} catch (CallbackTimeoutException e) {
    ctx.getLogger().warn("Approval timed out: {}", e.getMessage());
} catch (CallbackFailedException e) {
    ctx.getLogger().error("Callback failed: {}", e.getMessage());
} catch (WaitForConditionFailedException e) {
    ctx.getLogger().error("Condition polling failed: {}", e.getMessage());
}
```
