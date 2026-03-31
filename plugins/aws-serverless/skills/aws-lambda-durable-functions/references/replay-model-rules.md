# Replay Model Rules - CRITICAL

The replay model is the foundation of durable functions. Violations cause subtle, hard-to-debug issues.

## How Replay Works

1. Code runs from the beginning on every invocation
2. Steps that already completed return their checkpointed results WITHOUT re-executing
3. Code OUTSIDE steps executes again on every replay
4. New steps execute when reached

## Rule 1: Deterministic Code Outside Steps

ALL code outside steps MUST produce the same result on every replay. Non-deterministic values (timestamps, UUIDs, random numbers) must be generated inside steps so they are checkpointed.

### Must Be In Steps

- `Date.now()`, `new Date()`, `time.time()`, `datetime.now()`, `System.currentTimeMillis()`
- `Math.random()`, `random.random()`, `UUID.randomUUID()`
- UUID generation (`uuid.v4()`, `uuid.uuid4()`)
- API calls, HTTP requests
- Database queries
- File system operations
- Environment variable reads (if they can change)
- Any external system interaction

## Rule 2: No Nested Durable Operations

You CANNOT call durable operations (step, wait, invoke) inside a step function. Use child context instead:

| Language   | Child Context API                                         |
| ---------- | --------------------------------------------------------- |
| TypeScript | `context.runInChildContext('name', async (child) => ...)` |
| Python     | `context.run_in_child_context(func=..., name='...')`      |
| Java       | `ctx.runInChildContext("name", Type.class, child -> ...)` |

## Rule 3: Closure Mutations Are Lost

Variables mutated inside steps are NOT preserved across replays. The step function runs in isolation — mutations to outer variables are discarded. Always return values from steps and use the return value.

## Rule 4: Side Effects Outside Steps Repeat

Side effects outside steps happen on EVERY replay. Wrap all side effects (emails, database writes, logging) in steps. Exception: the SDK logger (`context.logger` / `ctx.getLogger()`) is replay-aware and safe to use anywhere.

## Debugging Replay Issues

If you see inconsistent behavior:

1. Check for non-deterministic code outside steps
2. Verify no nested durable operations
3. Look for closure mutations
4. Search for side effects outside steps
5. Use the SDK logger to trace execution flow
6. Test with multiple invocations to simulate replay

## Code Examples

- [TypeScript](snippets/replay-model-rules-typescript.md)
- [Python](snippets/replay-model-rules-python.md)
- [Java](snippets/replay-model-rules-java.md)
