# Durable Functions Skill — Java SDK Support & Snippet Extraction

## Summary

The AWS Lambda durable functions skill has been restructured to support three languages
(TypeScript, Python, Java). Inline code snippets were extracted from 8 reference files into
a new `references/snippets/` directory with per-language files, and Java SDK snippets were
added alongside the existing TypeScript and Python ones. SKILL.md and deployment-iac.md were
updated to recognize Java as a first-class language.

---

## Structural Changes

### New directory: `references/snippets/`

24 snippet files were created (8 topics × 3 languages):

| Topic                 | TypeScript | Python   | Java      |
| --------------------- | ---------- | -------- | --------- |
| getting-started       | 100 lines  | 64 lines | 100 lines |
| step-operations       | 93 lines   | 94 lines | 88 lines  |
| wait-operations       | 99 lines   | 98 lines | 92 lines  |
| concurrent-operations | 99 lines   | 62 lines | 89 lines  |
| error-handling        | 99 lines   | 91 lines | 100 lines |
| advanced-patterns     | 100 lines  | 32 lines | 100 lines |
| testing-patterns      | 100 lines  | 84 lines | 98 lines  |
| replay-model-rules    | 100 lines  | 80 lines | 95 lines  |

### Rewritten reference files (code blocks removed, conceptual guides retained)

| File                     | Lines | What was kept                                                                                              |
| ------------------------ | ----- | ---------------------------------------------------------------------------------------------------------- |
| getting-started.md       | 100   | Language selection, project structures (TS/Python/Java), setup checklists, dev workflow, key concepts      |
| step-operations.md       | 82    | When-to-use guidance, step vs child context decision table, retry strategies, best practices               |
| wait-operations.md       | 91    | Simple wait/callback/condition tables, CLI callback commands, max wait duration note, best practices       |
| concurrent-operations.md | 88    | Map/parallel API tables, completion policies, error isolation, performance optimization                    |
| error-handling.md        | 88    | Error classification tables (retryable/non-retryable), saga pattern steps, circuit breaker, best practices |
| advanced-patterns.md     | 77    | Step semantics table, completion policy interaction, custom serialization, nested workflows                |
| testing-patterns.md      | 73    | DO/DON'T lists, test runner API summary, common testing errors table, best practices                       |
| replay-model-rules.md    | 60    | 4 rules explanations, "must be in steps" list, child context API table, debugging checklist                |

Each rewritten file ends with a `## Code Examples` section linking to the three language snippet files.

### Updated files

| File              | Lines            | Changes                                                                                                             |
| ----------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------- |
| SKILL.md          | 246 (≤300 limit) | Java prerequisites, language selection, Maven dependencies, handler pattern, API differences section, SDK repo link |
| deployment-iac.md | 559              | Added `java21` / `JAVA_21` runtime in CloudFormation, SAM, and CDK examples                                         |

---

## Java SDK Description

The Java SDK (`aws-durable-execution-sdk-java`) enables building durable Lambda functions in
Java 17+ with Maven. It follows the same replay model as the TypeScript and Python SDKs but
uses Java-idiomatic patterns.

### Handler Pattern

Java handlers extend `DurableHandler<I, O>` and override the `handleRequest` method, receiving a
typed input and a `DurableContext`:

```java
public class MyHandler extends DurableHandler<MyInput, MyOutput> {
  @Override
  public MyOutput handleRequest(MyInput input, DurableContext ctx) {
    var result = ctx.step("process", MyOutput.class, stepCtx -> processData(input));
    return result;
  }
}
```

### Core API

| Operation     | API                                                                      |
| ------------- | ------------------------------------------------------------------------ |
| Step (sync)   | `ctx.step("name", Type.class, stepCtx -> ...)`                           |
| Step (async)  | `ctx.stepAsync("name", Type.class, stepCtx -> ...)` → `DurableFuture<T>` |
| Wait          | `ctx.wait("name", Duration.ofSeconds(N))`                                |
| Wait (async)  | `ctx.waitAsync("name", Duration.ofSeconds(N))` → `DurableFuture<Void>`   |
| Callback      | `ctx.waitForCallback("name", Type.class, (callbackId, stepCtx) -> ...)`  |
| Map           | `ctx.map("name", items, Type.class, (item, index, childCtx) -> ...)`     |
| Map (async)   | `ctx.mapAsync(...)` → `DurableFuture<MapResult<T>>`                      |
| Child context | `ctx.runInChildContext("name", Type.class, child -> ...)`                |
| Logger        | `ctx.getLogger().info(...)` (replay-aware)                               |
| Invoke        | `ctx.invoke("name", functionArn, payload, Type.class)`                   |

### Key Java-Specific Patterns

- **Generic types**: Use `TypeToken<List<T>>` for complex generic return types
- **Configuration**: Builder pattern — `StepConfig.builder().retryStrategy(...).build()`
- **Retry**: `RetryStrategies.exponentialBackoff(b -> b.maxAttempts(5).initialDelay(...).build())`
- **Completion policies**: `CompletionConfig.allSuccessful()`, `.firstSuccessful()`, `.minSuccessful(N)`
- **Concurrent futures**: `DurableFuture.allOf(f1, f2, f3)` then `f1.get()`

### Exception Hierarchy

| Exception                         | Meaning                                               |
| --------------------------------- | ----------------------------------------------------- |
| `StepFailedException`             | Permanent failure — all retries exhausted             |
| `StepInterruptedException`        | Transient/interrupted — may retry at invocation level |
| `CallbackFailedException`         | External system reported callback failure             |
| `CallbackTimeoutException`        | Callback timed out                                    |
| `WaitForConditionFailedException` | Condition polling failed                              |

To prevent retry, throw any unchecked exception from within a step.

### Testing

```xml
<dependency>
  <groupId>software.amazon.lambda.durable</groupId>
  <artifactId>aws-durable-execution-sdk-java-testing</artifactId>
  <scope>test</scope>
</dependency>
```

- Local: `LocalDurableTestRunner.create(Type.class, handler)` → `runner.runUntilComplete(input)`
- Cloud: `CloudDurableTestRunner.create(functionArn, region)`
- Time control: `runner.withSkipTime(false)` + `runner.advanceTime(Duration.ofSeconds(N))`
- Operations: `result.getOperation("name")`, `result.getStatus()` → `OperationStatus`

### Deployment

Java durable functions use the `java21` Lambda runtime. Deploy with CloudFormation
(`Runtime: java21`), CDK (`lambda.Runtime.JAVA_21`), or SAM.
