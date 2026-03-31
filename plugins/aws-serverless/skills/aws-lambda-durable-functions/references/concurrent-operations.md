# Concurrent Operations

Process arrays and run operations in parallel with concurrency control.

## Map Operations

Process arrays with automatic concurrency control and completion policies. Each item runs in its own child context with error isolation.

| Language | Sync Map | Async Map |
|---|---|---|
| TypeScript | `context.map('name', items, func, opts)` | N/A (all maps are async) |
| Python | `context.map(inputs=items, func=fn, config=MapConfig(...))` | N/A |
| Java | `ctx.map("name", items, Type.class, (item, i, childCtx) -> ...)` | `ctx.mapAsync(...)` returns `DurableFuture` |

## Parallel Operations

Run heterogeneous operations concurrently (different functions, not array processing).

| Language | API |
|---|---|
| TypeScript | `context.parallel('name', [{ name, func }], opts)` |
| Python | `context.parallel([func1, func2], config=ParallelConfig(...))` |
| Java | Use `ctx.mapAsync()` or `ctx.stepAsync()` with `DurableFuture.allOf()` |

## Completion Policies

Control when a map operation completes:

| Policy | Behavior | Use Case |
|---|---|---|
| All (default) | All items must succeed | Strict processing |
| Minimum successful | Require N successes | Quorum-based decisions |
| Tolerated failure count | Allow up to N failures | Graceful degradation |
| Tolerated failure percentage | Allow up to N% failures | Large batch tolerance |
| Any (first success) | Stop after first success | Search/match patterns |

### Language-Specific Config

- **TypeScript**: `completionConfig: { minSuccessful, toleratedFailureCount, toleratedFailurePercentage }`
- **Python**: `CompletionConfig(min_successful=N, tolerated_failure_count=N)`
- **Java**: `CompletionConfig.allSuccessful()`, `CompletionConfig.firstSuccessful()`, `CompletionConfig.minSuccessful(N)`

## Batch Result Handling

All languages provide result objects with success/failure inspection:

- Get all successful results or throw on any failure
- Inspect individual item results with success/failure status
- Access failed items for retry or logging
- Check aggregate counts (total, succeeded, failed)

## Error Isolation

Errors in individual map items do not fail the entire map operation. Each item runs independently. Use completion policies to control how many failures are tolerated before the map itself fails.

## Concurrency Control

- **Fixed concurrency**: Set `maxConcurrency` to limit parallel items
- **Dynamic processing**: Vary step logic based on item characteristics within the map function
- **Batch size selection**: Use higher concurrency for small/fast items, lower for large/slow items

## Advanced Patterns

- **Map with callbacks**: Combine map with `waitForCallback` for per-item human approval
- **Nested maps**: Process batches of batches with nested map operations
- **Map with child contexts**: Use `runInChildContext` inside map for complex per-item workflows with multiple steps and waits

## Performance Optimization

1. **Match concurrency to downstream capacity** — avoid overwhelming external services
2. **Use completion policies for early termination** — stop after first match in search patterns
3. **Implement retry for failed items** — re-process only failed items from batch results
4. **Consider circuit breakers** for external service calls within map items

## Best Practices

1. **Set appropriate maxConcurrency** based on downstream system capacity
2. **Use completion policies** to handle partial failures gracefully
3. **Name all operations** for debugging
4. **Handle batch results explicitly** — check for failures
5. **Consider retry strategies** for failed items
6. **Use child contexts** for complex per-item workflows

## Code Examples

- [TypeScript](snippets/concurrent-operations-typescript.md)
- [Python](snippets/concurrent-operations-python.md)
- [Java](snippets/concurrent-operations-java.md)
