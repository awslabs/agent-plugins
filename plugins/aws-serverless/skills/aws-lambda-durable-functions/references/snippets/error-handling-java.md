# Error Handling - Java

## Retry Configuration

```java
import software.amazon.lambda.durable.retries.RetryStrategies;

var result = ctx.step("api-call", ApiResponse.class, stepCtx -> callAPI(),
    StepConfig.builder().retryStrategy(RetryStrategies.exponentialBackoff(b -> b
        .maxAttempts(5).initialDelay(Duration.ofSeconds(1))
        .maxDelay(Duration.ofSeconds(60)).backoffRate(2.0)
        .jitter(JitterStrategy.FULL))).build());
```

## Custom Retry

```java
var result = ctx.step("custom-retry", Result.class, stepCtx -> riskyOperation(),
    StepConfig.builder().retryStrategy((error, attemptCount) -> {
        if (error instanceof ClientException) return RetryDecision.noRetry();
        return attemptCount < 5
            ? RetryDecision.retryAfter(Duration.ofSeconds((long) Math.pow(2, attemptCount)))
            : RetryDecision.noRetry();
    }).build());
```

## Error Classification

```java
import software.amazon.lambda.durable.exception.*;

try {
    var result = ctx.step("risky", Result.class, stepCtx -> riskyOperation());
} catch (StepFailedException e) {
    ctx.getLogger().error("Permanent failure: {}", e.getMessage());
} catch (StepInterruptedException e) {
    ctx.getLogger().error("Transient/interrupted: {}", e.getMessage());
}
```

## Saga Pattern

```java
public class OrderHandler extends DurableHandler<OrderRequest, OrderResult> {
    @Override public OrderResult handleRequest(OrderRequest event, DurableContext ctx) {
        var compensations = new ArrayList<Runnable>();
        try {
            var reservation = ctx.step("reserve-inventory", Reservation.class,
                s -> inventoryService.reserve(event.getItems()));
            compensations.add(() -> ctx.step("cancel-reservation", Void.class,
                s -> { inventoryService.cancel(reservation.getId()); return null; }));
            var payment = ctx.step("charge-payment", Payment.class,
                s -> paymentService.charge(event.getPaymentMethod(), event.getAmount()));
            compensations.add(() -> ctx.step("refund-payment", Void.class,
                s -> { paymentService.refund(payment.getId()); return null; }));
            return new OrderResult(true, payment.getOrderId());
        } catch (Exception e) {
            Collections.reverse(compensations);
            for (var comp : compensations) {
                try { comp.run(); }
                catch (Exception ce) { ctx.getLogger().error("Compensation failed", ce); }
            }
            throw e;
        }
    }
}
```

## Unrecoverable Error

```java
// Throw any unchecked exception from step to prevent retry
var user = ctx.step("fetch-user", User.class, stepCtx -> {
    var u = fetchUser(event.getUserId());
    if (u == null) throw new IllegalStateException("User not found");
    return u;
});
```

## Callback Error Handling

```java
try {
    ctx.waitForCallback("approval", ApprovalResult.class,
        (callbackId, stepCtx) -> sendApprovalRequest(callbackId));
} catch (CallbackFailedException e) {
    ctx.getLogger().error("Callback failed: {}", e.getMessage());
} catch (CallbackTimeoutException e) {
    ctx.getLogger().error("Callback timed out: {}", e.getMessage());
}
```

## Partial Failure Handling

```java
var results = ctx.map("process-items", items, Result.class,
    (item, i, childCtx) -> childCtx.step("p-" + i, Result.class, s -> processItem(item)),
    MapConfig.builder().completionConfig(CompletionConfig.minSuccessful((int) (items.size() * 0.9))).build());
if (!results.getErrors().isEmpty()) ctx.getLogger().warn("Failed: {}", results.getErrors().size());
```
