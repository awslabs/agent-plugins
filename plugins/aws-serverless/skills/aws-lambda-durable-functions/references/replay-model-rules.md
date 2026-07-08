# Replay Model Rules - CRITICAL

The replay model is the foundation of durable functions. Violations cause subtle, hard-to-debug issues. **Read this carefully.**

## How Replay Works

Durable functions use a "checkpoint and replay" execution model:

1. Code runs from the beginning on every invocation
2. Steps that already completed return their checkpointed results WITHOUT re-executing
3. Code OUTSIDE steps executes again on every replay
4. New steps execute when reached

**Example:**

```typescript
// First execution: Runs lines 1-5
// After wait: Runs lines 1-5 again (line 2 returns cached result)
const data = await context.step('fetch', async () => fetchAPI());  // Line 2: Executes once, cached
await context.wait({ seconds: 60 });                                // Line 3: Waits
const result = await context.step('process', async () => process(data)); // Line 5: Executes after wait
```

## Rule 1: Deterministic Code Outside Steps

**ALL code outside steps MUST produce the same result on every replay.**

### ❌ WRONG - Non-Deterministic Outside Steps

**TypeScript:**

```typescript
// These values change on each replay!
const id = uuid.v4();                    // Different UUID each time
const timestamp = Date.now();            // Different timestamp each time
const random = Math.random();            // Different random number
const now = new Date();                  // Different date each time

await context.step('save', async () => saveData({ id, timestamp }));
```

**Python:**

```python
# These values change on each replay!
id = str(uuid.uuid4())                   # Different UUID each time
timestamp = time.time()                  # Different timestamp each time
random_val = random.random()             # Different random number
now = datetime.now()                     # Different datetime each time

context.step(lambda _: save_data({"id": id}), name='save')
```

**Java:**

```java
// These values change on each replay!
var id = UUID.randomUUID().toString();       // Different UUID each time
var timestamp = System.currentTimeMillis();  // Different timestamp each time
var random = Math.random();                  // Different random number
var now = Instant.now();                     // Different instant each time

// The step itself is fine - the problem is that id/timestamp were generated
// OUTSIDE a step, so each replay passes different values into it.
ctx.step("save", Void.class, s -> { saveData(id, timestamp); return null; });
```

### ✅ CORRECT - Non-Deterministic Inside Steps

**TypeScript:**

```typescript
const id = await context.step('generate-id', async () => uuid.v4());
const timestamp = await context.step('get-time', async () => Date.now());
const random = await context.step('random', async () => Math.random());
const now = await context.step('get-date', async () => new Date());

await context.step('save', async () => saveData({ id, timestamp }));
```

**Python:**

```python
id = context.step(lambda _: str(uuid.uuid4()), name='generate-id')
timestamp = context.step(lambda _: time.time(), name='get-time')
random_val = context.step(lambda _: random.random(), name='random')
now = context.step(lambda _: datetime.now(), name='get-date')

context.step(lambda _: save_data({"id": id}), name='save')
```

**Java:**

```java
var id = ctx.step("generate-id", String.class, s -> UUID.randomUUID().toString());
var timestamp = ctx.step("get-time", Long.class, s -> System.currentTimeMillis());
var random = ctx.step("random", Double.class, s -> Math.random());
var now = ctx.step("get-date", Instant.class, s -> Instant.now());

ctx.step("save", Void.class, s -> { saveData(id, timestamp); return null; });
```

### Must Be In Steps

- `Date.now()`, `new Date()`, `time.time()`, `datetime.now()`
- `Math.random()`, `random.random()`
- UUID generation (`uuid.v4()`, `uuid.uuid4()`)
- API calls, HTTP requests
- Database queries
- File system operations
- Environment variable reads (if they can change)
- Any external system interaction

## Rule 2: No Nested Durable Operations

**You CANNOT call durable operations inside a step function.**

### ❌ WRONG - Nested Operations

**TypeScript:**

```typescript
await context.step('process', async () => {
  await context.wait({ seconds: 1 });      // ERROR!
  await context.step(async () => ...);     // ERROR!
  await context.invoke('other-fn', ...);   // ERROR!
  return result;
});
```

**Python:**

```python
@durable_step
def process(step_ctx: StepContext):
    context.wait(duration=Duration.from_seconds(1))  # ERROR!
    context.step(lambda _: ..., name='nested')       # ERROR!
    return result

context.step(process())
```

**Java:**

```java
ctx.step("process", Result.class, stepCtx -> {
    ctx.wait("delay", Duration.ofSeconds(1));      // ERROR! - cannot nest in a step
    ctx.step("nested", String.class, s -> "");     // ERROR! - cannot nest in a step
    ctx.invoke("other", otherArn, payload, Result.class);  // ERROR! - cannot nest in a step
    return result;
});
```

### ✅ CORRECT - Use Child Context

**TypeScript:**

```typescript
await context.runInChildContext('process', async (childCtx) => {
  await childCtx.wait({ seconds: 1 });
  const step1 = await childCtx.step('validate', async () => validate());
  const step2 = await childCtx.step('process', async () => process(step1));
  return step2;
});
```

**Python:**

```python
# Note: validate and process are decorated with @durable_step
def process_child(child_ctx: DurableContext):
    child_ctx.wait(duration=Duration.from_seconds(1))
    step1 = child_ctx.step(validate())
    step2 = child_ctx.step(process(step1))
    return step2

context.run_in_child_context(func=process_child, name='process')
```

**Java:**

```java
ctx.runInChildContext("process", Result.class, childCtx -> {
    childCtx.wait("processing-delay", Duration.ofSeconds(1));
    var step1 = childCtx.step("validate", Data.class, s -> validate());
    var step2 = childCtx.step("process", Result.class, s -> process(step1));
    return step2;
});
```

## Rule 3: Closure Mutations Are Lost

**Variables mutated inside steps are NOT preserved across replays.**

### ❌ WRONG - Lost Mutations

**TypeScript:**

```typescript
let counter = 0;
await context.step('increment', async () => {
  counter++;  // This mutation is lost!
});
console.log(counter);  // Always 0 on replay!
```

**Python:**

```python
counter = 0
@durable_step
def increment(step_ctx: StepContext):
    nonlocal counter
    counter += 1  # This mutation is lost!

context.step(increment())
print(counter)  # Always 0 on replay!
```

**Java:**

```java
var counter = new AtomicInteger(0);
ctx.step("increment", Void.class, s -> {
    counter.incrementAndGet();  // This mutation is lost on replay!
    return null;
});
System.out.println(counter.get());  // Always 0 on replay!
```

### ✅ CORRECT - Return Values

**TypeScript:**

```typescript
let counter = 0;
counter = await context.step('increment', async () => counter + 1);
console.log(counter);  // Correct value
```

**Python:**

```python
counter = 0
counter = context.step(lambda _: counter + 1, name='increment')
print(counter)  # Correct value
```

**Java:**

```java
int initial = 0;
int counter = ctx.step("increment", Integer.class, s -> initial + 1);
System.out.println(counter);  // Correct value
```

## Rule 4: Side Effects Outside Steps Repeat

**Side effects outside steps happen on EVERY replay.**

### ❌ WRONG - Repeated Side Effects

**TypeScript:**

```typescript
console.log('Starting process');     // Logs multiple times!
await sendEmail(user.email);         // Sends multiple emails!
await updateDatabase(data);          // Updates multiple times!

await context.step('process', async () => process());
```

**Python:**

```python
print('Starting process')            # Prints multiple times!
send_email(user.email)               # Sends multiple emails!
update_database(data)                # Updates multiple times!

context.step(lambda _: process(), name='process')
```

**Java:**

```java
System.out.println("Starting process");  // Prints multiple times!
sendEmail(user.getEmail());              // Sends multiple emails!
updateDatabase(data);                    // Updates multiple times!

ctx.step("process", Result.class, s -> process());
```

### ✅ CORRECT - Side Effects In Steps

**TypeScript:**

```typescript
context.logger.info('Starting process');  // Deduplicated automatically
await context.step('send-email', async () => sendEmail(user.email));
await context.step('update-db', async () => updateDatabase(data));
await context.step('process', async () => process());
```

**Python:**

```python
# Note: Functions are decorated with @durable_step
context.logger.info('Starting process')  # Deduplicated automatically
context.step(send_email(user.email))
context.step(update_database(data))
context.step(process())
```

**Java:**

```java
ctx.getLogger().info("Starting process");  // Deduplicated automatically
ctx.step("send-email", Void.class, s -> { sendEmail(user.getEmail()); return null; });
ctx.step("update-db", Void.class, s -> { updateDatabase(data); return null; });
ctx.step("process", Result.class, s -> process());
```

### Exception: context.logger

`context.logger` is replay-aware and safe to use anywhere. It automatically deduplicates logs across replays.

## Common Pitfalls

### Pitfall 1: Reading Environment Variables

```typescript
// ❌ WRONG if env vars can change
const apiKey = process.env.API_KEY;
await context.step('call-api', async () => callAPI(apiKey));

// ✅ CORRECT
const apiKey = await context.step('get-key', async () => process.env.API_KEY);
await context.step('call-api', async () => callAPI(apiKey));
```

```java
// ❌ WRONG if env vars can change
var apiKey = System.getenv("API_KEY");
ctx.step("call-api", Result.class, s -> callAPI(apiKey));

// ✅ CORRECT
var key = ctx.step("get-key", String.class, s -> System.getenv("API_KEY"));
ctx.step("call-api", Result.class, s -> callAPI(key));
```

### Pitfall 2: Array/Object Mutations

```typescript
// ❌ WRONG
const items = [];
await context.step('add-item', async () => {
  items.push(newItem);  // Lost on replay
});

// ✅ CORRECT
let items = [];
items = await context.step('add-item', async () => [...items, newItem]);
```

```java
// ❌ WRONG
final var items = new ArrayList<Item>();
ctx.step("add-item", Void.class, s -> {
    items.add(newItem);  // Lost on replay
    return null;
});

// ✅ CORRECT
var items = ctx.step("add-item", new TypeToken<List<Item>>() {}, s -> {
    var updated = new ArrayList<>(items);
    updated.add(newItem);
    return updated;
});
```

### Pitfall 3: Conditional Logic with Non-Deterministic Values

```typescript
// ❌ WRONG
if (Math.random() > 0.5) {  // Different on each replay!
  await context.step('path-a', async () => ...);
} else {
  await context.step('path-b', async () => ...);
}

// ✅ CORRECT
const shouldTakePathA = await context.step('decide', async () => Math.random() > 0.5);
if (shouldTakePathA) {
  await context.step('path-a', async () => ...);
} else {
  await context.step('path-b', async () => ...);
}
```

```java
// ❌ WRONG
if (Math.random() > 0.5) {  // Different on each replay!
    ctx.step("path-a", Result.class, s -> ...);
} else {
    ctx.step("path-b", Result.class, s -> ...);
}

// ✅ CORRECT
var shouldTakePathA = ctx.step("decide", Boolean.class, s -> Math.random() > 0.5);
if (shouldTakePathA) {
    ctx.step("path-a", Result.class, s -> ...);
} else {
    ctx.step("path-b", Result.class, s -> ...);
}
```

## Debugging Replay Issues

If you see inconsistent behavior:

1. **Check for non-deterministic code outside steps**
2. **Verify no nested durable operations**
3. **Look for closure mutations**
4. **Search for side effects outside steps**
5. **Use `context.logger` to trace execution flow**

## Testing Replay Behavior

Always test with multiple invocations to simulate replay:

```typescript
const runner = new LocalDurableTestRunner({ handlerFunction: handler });
const execution = await runner.run({ payload: { test: true } });

// Verify operations executed correctly
const step1 = runner.getOperation('step-name');
expect(step1.getStatus()).toBe(OperationStatus.SUCCEEDED);
```

```java
import software.amazon.lambda.durable.testing.LocalDurableTestRunner;
import software.amazon.lambda.durable.model.ExecutionStatus;
import software.amazon.awssdk.services.lambda.model.OperationStatus;

var runner = LocalDurableTestRunner.create(MyInput.class, new MyHandler());
// runUntilComplete simulates the Lambda re-invocation (replay) loop
var result = runner.runUntilComplete(new MyInput(true));

assertEquals(ExecutionStatus.SUCCEEDED, result.getStatus());

// Operation-level status uses OperationStatus
var step1 = result.getOperation("step-name");
assertEquals(OperationStatus.SUCCEEDED, step1.getStatus());
```
