# Testing Patterns

Test durable functions locally and in the cloud with comprehensive test runners.

## Critical Testing Rules

### DO:

- ✅ Name all operations for test reliability
- ✅ Get operations by name, never by index
- ✅ Use local test runner for unit tests, cloud runner for integration tests
- ✅ Test replay behavior with multiple invocations of the same input
- ✅ Use fake clock / time control for time-dependent tests
- ✅ Wait for callback operations to reach STARTED status before sending data
- ✅ JSON.stringify callback parameters (TypeScript)
- ✅ Use `with runner:` context manager (Python)

### DON'T:

- ❌ Use `getOperationByIndex()` — brittle, breaks when operations change
- ❌ Assume operation indices are stable (parallel creates nested operations)
- ❌ Send objects to sendCallbackSuccess — stringify first (TypeScript)
- ❌ Test callbacks without proper synchronization (causes race conditions)
- ❌ Confuse local runner with cloud runner

## Test Runner API Summary

| Language   | Local Runner                                         | Cloud Runner                                            |
| ---------- | ---------------------------------------------------- | ------------------------------------------------------- |
| TypeScript | `new LocalDurableTestRunner({ handlerFunction })`    | `new CloudDurableTestRunner({ functionName, client })`  |
| Python     | `DurableFunctionTestRunner(handler=handler)`         | `DurableFunctionCloudTestRunner(function_name, region)` |
| Java       | `LocalDurableTestRunner.create(Type.class, handler)` | `CloudDurableTestRunner.create(functionArn, region)`    |

## Key Testing Patterns

1. **Local testing** — fast, deterministic, no AWS credentials needed
2. **Operation inspection** — get operations by name, check type/status/result
3. **Replay testing** — run same input twice, verify identical results
4. **Time control** — advance fake clock for wait/timer operations
5. **Callback testing** — wait for STARTED status, then send success/failure
6. **Error scenarios** — verify retry behavior and failure handling
7. **Concurrent operations** — test map/parallel results individually
8. **Cloud testing** — integration tests against deployed Lambda functions

## Common Testing Errors

| Error                            | Cause                   | Solution                                   |
| -------------------------------- | ----------------------- | ------------------------------------------ |
| `'result' is of type 'unknown'`  | Missing type casting    | Cast result: `as Type` or use typed runner |
| `'payload' does not exist`       | Wrong API (TypeScript)  | Wrap event in `payload: {}` object         |
| `Cannot find operation at index` | Using index lookup      | Use `getOperation("name")` instead         |
| Flaky callback tests             | Race condition          | Wait for `STARTED` status before sending   |
| `Unexpected token` in callback   | Forgot to stringify     | Always `JSON.stringify(data)`              |
| Operation not found by name      | Missing name in handler | Always name operations in handler code     |

## Best Practices

1. **Always name operations** for reliable test assertions
2. **Get operations by name**, never by index
3. **Test replay behavior** with multiple invocations
4. **Use fake clock** for time-dependent tests
5. **Test error scenarios** including retries and failures
6. **Test callbacks** with success, failure, and timeout cases
7. **Validate operation details** (type, status, timing, results)
8. **Use cloud tests** for integration testing
9. **Mock external dependencies** in unit tests
10. **Test concurrent operations** individually and as a group

## Code Examples

- [TypeScript](snippets/testing-patterns-typescript.md)
- [Python](snippets/testing-patterns-python.md)
- [Java](snippets/testing-patterns-java.md)
