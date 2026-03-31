# Getting Started with AWS Lambda Durable Functions

Quick start guide for building your first durable function.

## Language Selection

Default: TypeScript

Override syntax:

- "use TypeScript" → TypeScript code (default)
- "use Python" → Python code
- "use Java" → Java code

When not specified, ALWAYS use TypeScript. If unsupported, state: "Durable Execution SDK is not yet available for [language]" and suggest alternatives.

## Project Structure

### TypeScript

```
my-durable-function/
├── src/handler.ts, steps/, utils/
├── tests/handler.test.ts
├── infrastructure/template.yaml
├── eslint.config.js, jest.config.js, tsconfig.json, package.json
```

### Python

```
my-durable-function/
├── src/handler.py, steps/, utils/
├── tests/test_handler.py
├── infrastructure/template.yaml
├── pyproject.toml
```

### Java

```
my-durable-function/
├── pom.xml
├── src/main/java/com/example/Handler.java, steps/, utils/
├── src/test/java/com/example/HandlerTest.java
├── infrastructure/template.yaml
```

## Setup Checklist

### TypeScript

- [ ] Install `@aws/durable-execution-sdk-js`, testing & ESLint packages
- [ ] Create `jest.config.js` with ts-jest preset
- [ ] Configure ESLint with durable execution plugin
- [ ] Create handler with `withDurableExecution` wrapper
- [ ] Write tests using `LocalDurableTestRunner`
- [ ] Review replay model rules

### Python

- [ ] Install `aws-durable-execution-sdk-python` and testing package
- [ ] Create handler with `@durable_execution` decorator
- [ ] Define step functions with `@durable_step` decorator
- [ ] Write tests using `DurableFunctionTestRunner`
- [ ] Review replay model rules

### Java

- [ ] Add Maven dependencies (SDK + testing artifact)
- [ ] Create handler extending `DurableHandler<I, O>`
- [ ] Write tests using `LocalDurableTestRunner.create()`
- [ ] Review replay model rules

## Development Workflow

1. **Write handler** with durable operations (steps, waits, callbacks)
2. **Test locally** with the language-specific test runner
3. **Validate replay rules** — no non-deterministic code outside steps
4. **Deploy** with qualified ARN (version or alias) and **monitor** logs

## Key Concepts

- **Steps**: Atomic operations with automatic retry and checkpointing
- **Waits**: Suspend execution without compute charges (up to 1 year)
- **Child Contexts**: Group multiple durable operations
- **Callbacks**: Wait for external systems to respond
- **Map/Parallel**: Process arrays or run operations concurrently

## Code Examples

- [TypeScript](snippets/getting-started-typescript.md)
- [Python](snippets/getting-started-python.md)
- [Java](snippets/getting-started-java.md)

## Next Steps

- Review **replay-model-rules.md** for common pitfalls
- Explore **step-operations.md** for retry strategies
- Learn **wait-operations.md** for external integrations
