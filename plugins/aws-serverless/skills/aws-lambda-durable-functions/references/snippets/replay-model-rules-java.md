# Replay Model Rules - Java

## Wrong - Non-Deterministic Outside Steps

```java
// These values change on each replay!
var id = UUID.randomUUID().toString();   // Different UUID each time
var timestamp = System.currentTimeMillis(); // Different timestamp each time
var random = Math.random();              // Different random number
ctx.step("save", Void.class, s -> { saveData(id, timestamp); return null; });
```

## Correct - Non-Deterministic Inside Steps

```java
var id = ctx.step("generate-id", String.class, s -> UUID.randomUUID().toString());
var timestamp = ctx.step("get-time", Long.class, s -> System.currentTimeMillis());
var random = ctx.step("random", Double.class, s -> Math.random());
ctx.step("save", Void.class, s -> { saveData(id, timestamp); return null; });
```

## Wrong - Nested Operations

```java
ctx.step("process", Result.class, stepCtx -> {
    ctx.wait(null, Duration.ofSeconds(1));      // ERROR!
    ctx.step("nested", String.class, s -> ""); // ERROR!
    return result;
});
```

## Correct - Child Context

```java
ctx.runInChildContext("process", Result.class, childCtx -> {
    childCtx.wait(null, Duration.ofSeconds(1));
    var step1 = childCtx.step("validate", Data.class, s -> validate());
    var step2 = childCtx.step("process", Result.class, s -> process(step1));
    return step2;
});
```

## Wrong - Closure Mutations

```java
var counter = new AtomicInteger(0);
ctx.step("increment", Void.class, s -> {
    counter.incrementAndGet();  // This mutation is lost on replay!
    return null;
});
System.out.println(counter.get());  // Always 0 on replay!
```

## Correct - Return Values

```java
int counter = 0;
counter = ctx.step("increment", Integer.class, s -> counter + 1);
System.out.println(counter);  // Correct value
```

## Wrong - Side Effects Outside Steps

```java
System.out.println("Starting process");  // Prints multiple times!
sendEmail(user.getEmail());              // Sends multiple emails!
ctx.step("process", Result.class, s -> process());
```

## Correct - Side Effects In Steps

```java
ctx.getLogger().info("Starting process");  // Deduplicated automatically
ctx.step("send-email", Void.class, s -> { sendEmail(user.getEmail()); return null; });
ctx.step("process", Result.class, s -> process());
```

## Pitfall - Conditional Non-Determinism

```java
// ❌ WRONG
if (Math.random() > 0.5) {
    ctx.step("path-a", Result.class, s -> pathA());
} else {
    ctx.step("path-b", Result.class, s -> pathB());
}

// ✅ CORRECT
var shouldTakePathA = ctx.step("decide", Boolean.class, s -> Math.random() > 0.5);
if (shouldTakePathA) {
    ctx.step("path-a", Result.class, s -> pathA());
} else {
    ctx.step("path-b", Result.class, s -> pathB());
}
```
