# Advanced Patterns

Advanced techniques and patterns for sophisticated durable function workflows.

## Advanced GenAI Agent Patterns

Build agentic loops with durable step-backed tool execution and dynamic step naming. Each AI model invocation and tool execution is a separate durable step, ensuring replay safety. Use template literals or string formatting for dynamic step names (e.g., `execute-tool-{toolName}`).

| Language   | Model Invocation                           | Tool Execution                                       | Dynamic Naming       |
| ---------- | ------------------------------------------ | ---------------------------------------------------- | -------------------- |
| TypeScript | `context.step('invoke-model', fn)`         | `context.step(\`execute-tool-${name}\`, fn)`         | Template literals    |
| Python     | `context.step(fn)`                         | `context.step(func=fn, name=f"execute-tool-{name}")` | f-strings            |
| Java       | `ctx.step("invoke-model", Type.class, fn)` | `ctx.step("execute-tool-" + name, Type.class, fn)`   | String concatenation |

## Step Semantics

Controls whether a step may re-execute during replay:

| Semantic                | Behavior                                     | Use When                                                              |
| ----------------------- | -------------------------------------------- | --------------------------------------------------------------------- |
| **AtMostOncePerRetry**  | Step executes at most once per retry attempt | Operation is idempotent (DB updates, API calls with idempotency keys) |
| **AtLeastOncePerRetry** | Step may execute multiple times per retry    | External deduplication exists (queuing systems, event streams)        |

- TypeScript: `{ semantics: StepSemantics.AtMostOncePerRetry }`
- Python: `StepSemantics.AT_MOST_ONCE_PER_RETRY`
- Java: `StepConfig.builder().stepSemantics(StepSemantics.AT_MOST_ONCE_PER_RETRY).build()`

## Completion Policies — Interaction and Combination

Completion policies can be combined. Execution **stops when the first constraint is met**:

1. `minSuccessful` — require at least N successes
2. `toleratedFailureCount` — allow up to N failures
3. `toleratedFailurePercentage` — allow up to N% failures

**Example with 10 items, minSuccessful=7, toleratedFailureCount=3:**

- 7 successes, 0 failures → stops (minSuccessful reached), 3 items skipped
- 5 successes, 3 failures → stops (toleratedFailureCount reached), 2 items skipped
- 7 successes, 2 failures → stops (minSuccessful reached), 1 item skipped

Use `minSuccessful: 1` for early termination search patterns (stop after first match).

## Custom Serialization

| Language   | Approach                                                                     |
| ---------- | ---------------------------------------------------------------------------- |
| TypeScript | `createClassSerdes(Class)`, `createClassSerdesWithDates(Class, ['field'])`   |
| Python     | Default JSON serialization, custom via `json_serializer`/`json_deserializer` |
| Java       | Implement `SerDes<T>` interface with `serialize`/`deserialize` methods       |

Use custom serialization for Date fields, complex object graphs, or domain-specific types.

## Nested Workflows

Use `invoke` to call child Lambda functions as separate durable executions. Parent orchestrators dispatch work to child workers, enabling modular and composable architectures.

- **TypeScript**: `ctx.invoke('name', functionArn, payload)`
- **Java**: `ctx.invoke("name", functionArn, payload, Type.class)`

## Advanced Error Handling

For timeout handling, conditional retries, and circuit breaker patterns, see [advanced-error-handling.md](advanced-error-handling.md).

## Best Practices

1. **Dynamic step naming** — use template literals/f-strings for unique operation names
2. **Structured logging** — log reasoning and context with each operation
3. **Completion policies** — understand how combined constraints interact
4. **Custom serialization** — use proper serdes for complex objects
5. **Nested workflows** — use invoke for modular, composable architectures

## Code Examples

- [TypeScript](snippets/advanced-patterns-typescript.md)
- [Python](snippets/advanced-patterns-python.md)
- [Java](snippets/advanced-patterns-java.md)
