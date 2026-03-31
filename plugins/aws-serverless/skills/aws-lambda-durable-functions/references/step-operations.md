# Step Operations

Steps are atomic operations with automatic retry and state persistence.

## When to Use Steps

- Single atomic operations (API calls, database queries, data transformations)
- Operations that should retry as a unit
- Any work that needs checkpointing for replay safety

## Step Definition Patterns

| Language | Recommended Pattern | Alternative |
|---|---|---|
| TypeScript | Named async step: `context.step('name', async () => ...)` | — |
| Python | `@durable_step` decorator for reusable functions | Inline lambda for one-off operations |
| Java | `ctx.step("name", Type.class, stepCtx -> ...)` | `TypeToken<T>` for generic return types |

Always name steps for easier debugging and testing.

## Retry Strategies

### Exponential Backoff (Recommended)

Configure with max attempts, initial/max delay, backoff rate, and jitter. Use `FULL` jitter to avoid thundering herd.

### Custom Retry

Implement a function that receives the error and attempt count, returns a retry decision. Use to skip retries for specific error types (e.g., validation errors).

### Retryable Error Types

Filter retries to specific error types only (e.g., `NetworkError`, `TimeoutError`).

## Step Semantics

| Semantic | Behavior | Use For |
|---|---|---|
| `AT_LEAST_ONCE` (default) | May execute multiple times on failure/retry | Idempotent operations |
| `AT_MOST_ONCE` | Never retries after first execution | Non-idempotent operations (payments, emails) |

## Custom Serialization

- **TypeScript**: `createClassSerdesWithDates` for classes with Date fields
- **Python**: Dataclass serialization handled automatically by SDK
- **Java**: `TypeToken<T>` for generic types; standard types handled automatically

## Steps vs Child Contexts

| Scenario | Use |
|---|---|
| Single atomic operation | Step |
| API call, DB query, transformation | Step |
| Group of multiple durable operations | Child context |
| Workflow with steps + waits + invokes | Child context |
| Isolating state tracking | Child context |

**Key rule**: You cannot nest durable operations (waits, other steps) inside a step. Use `runInChildContext` instead.

## Error Handling

Steps throw errors after all retry attempts are exhausted. Catch language-specific exception types:

- **TypeScript**: `StepError` with `.cause` for original error
- **Python**: `DurableExecutionsError` (SDK) or standard `Exception`
- **Java**: `StepFailedException` (permanent) or `StepInterruptedException` (transient)

## Best Practices

1. **Always name steps** for debugging and testing
2. **Keep steps atomic** — one logical operation per step
3. **Make steps idempotent** when possible
4. **Use appropriate retry strategies** based on operation type
5. **Handle errors explicitly** — don't let them propagate unexpectedly
6. **Use custom serialization** for complex types
7. **Choose correct semantics** (`AT_LEAST_ONCE` vs `AT_MOST_ONCE`)

## Code Examples

- [TypeScript](snippets/step-operations-typescript.md)
- [Python](snippets/step-operations-python.md)
- [Java](snippets/step-operations-java.md)
