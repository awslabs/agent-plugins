---
name: aws-lambda-durable-functions
description: >
  Build resilient, long-running, multi-step applications with AWS Lambda durable functions with automatic state persistence, retry logic, and orchestration for long-running executions. Covers the critical replay model, step operations, wait/callback patterns, error handling with saga pattern, testing with LocalDurableTestRunner. Triggers on phrases like: lambda durable functions, workflow orchestration, state machines, retry/checkpoint patterns, long-running stateful Lambda functions, saga pattern, human-in-the-loop callbacks, and reliable serverless applications.
---

# AWS Lambda durable functions

Build resilient multi-step applications and AI workflows that can execute for up to 1 year while maintaining reliable progress despite interruptions.

## Onboarding

### Step 1: Validate Prerequisites

Before using AWS Lambda durable functions, verify:

1. **AWS CLI** is installed (2.33.22 or higher) and configured:

   ```bash
   aws --version
   aws sts get-caller-identity
   ```

2. **Runtime environment** is ready:
   - For TypeScript/JavaScript: Node.js 22+ (`node --version`)
   - For Python: Python 3.11+ (`python --version`. Note that currently only Lambda runtime environments 3.13+ come with the Durable Execution SDK pre-installed. 3.11 is the min supported Python version by the Durable SDK itself, however, you could use OCI to bring your own container image with your own Python runtime + Durable SDK.)

3. **Deployment capability** exists (one of):
   - AWS SAM CLI (`sam --version`) 1.153.1 or higher
   - AWS CDK (`cdk --version`) v2.237.1 or higher
   - Direct Lambda deployment access

### Step 2: Select language and IaC framework

### Language Selection

Default: TypeScript

Override syntax:

- "use Python" → Generate Python code
- "use JavaScript" → Generate JavaScript code

When not specified, ALWAYS use TypeScript

### IaC framework selection

Default: CDK

Override syntax:

- "use CloudFormation" → Generate YAML templates
- "use SAM" → Generate YAML templates

When not specified, ALWAYS use CDK

### Error Scenarios

#### Unsupported Language

- List detected language
- State: "Durable Execution SDK is not yet available for [framework]"
- Suggest supported languages as alternatives

#### Unsupported IaC Framework

- List detected framework
- State: "[framework] might not support Lambda durable functions yet"
- Suggest supported frameworks as alternatives

### Serverless MCP Server Unavailable

- Inform user: "AWS Serverless MCP not responding"
- Ask: "Proceed without MCP support?"
- DO NOT continue without user confirmation

### Step 3: Install SDK

**For TypeScript/JavaScript:**

```bash
npm install @aws/durable-execution-sdk-js
npm install --save-dev @aws/durable-execution-sdk-js-testing
```

**For Python:**

```bash
pip install aws-durable-execution-sdk-python
pip install aws-durable-execution-sdk-python-testing
```

## When to Load Reference Files

Load the appropriate reference file based on what the user is working on:

- **Getting started**, **basic setup**, **example**, **ESLint**, or **Jest setup** -> see [getting-started.md](references/getting-started.md)
- **Understanding replay model**, **determinism**, or **non-deterministic errors** -> see [replay-model-rules.md](references/replay-model-rules.md)
- **Creating steps**, **atomic operations**, or **retry logic** -> see [step-operations.md](references/step-operations.md)
- **Waiting**, **delays**, **callbacks**, **external systems**, or **polling** -> see [wait-operations.md](references/wait-operations.md)
- **Parallel execution**, **map operations**, **batch processing**, or **concurrency** -> see [concurrent-operations.md](references/concurrent-operations.md)
- **Error handling**, **retry strategies**, **saga pattern**, or **compensating transactions** -> see [error-handling.md](references/error-handling.md)
- **Advanced error handling**, **timeout handling**, **circuit breakers**, or **conditional retries** -> see [advanced-error-handling.md](references/advanced-error-handling.md)
- **Testing**, **local testing**, **cloud testing**, **test runner**, or **flaky tests** -> see [testing-patterns.md](references/testing-patterns.md)
- **Deployment**, **CloudFormation**, **CDK**, **SAM**, **log groups**, **deploy**, or **infrastructure** -> see [deployment-iac.md](references/deployment-iac.md)
- **Advanced patterns**, **GenAI agents**, **completion policies**, **step semantics**, or **custom serialization** -> see [advanced-patterns.md](references/advanced-patterns.md)
- **troubleshooting**, **stuck execution**, **failed execution**, **debug execution ID**, or **execution history** -> see [troubleshooting-executions.md](references/troubleshooting-executions.md)

## Quick Reference

### Basic Handler Pattern

**TypeScript:**

```typescript
import { withDurableExecution, DurableContext } from '@aws/durable-execution-sdk-js';

export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const result = await context.step('process', async () => processData(event));
  return result;
});
```

**Python:**

```python
from aws_durable_execution_sdk_python import durable_execution, DurableContext

@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    result = context.step(lambda _: process_data(event), name='process')
    return result
```

### Critical Rules

1. **All non-deterministic code MUST be in steps** (Date.now, Math.random, API calls)
2. **Cannot nest durable operations** - use `runInChildContext` to group operations
3. **Closure mutations are lost on replay** - return values from steps
4. **Side effects outside steps repeat** - use `context.logger` (replay-aware)

### Python API Differences

The Python SDK differs from TypeScript in several key areas:

- **Steps**: Use `@durable_step` decorator + `context.step(my_step(args))`, or inline `context.step(lambda _: ..., name='...')`. Prefer the decorator for automatic step naming.
- **Wait**: `context.wait(duration=Duration.from_seconds(n), name='...')`
- **Exceptions**: `ExecutionError` (permanent), `InvocationError` (transient), `CallbackError` (callback failures)
- **Testing**: Use `DurableFunctionTestRunner` class directly - instantiate with handler, use context manager, call `run(input=...)`

### Invocation Requirements

Durable functions **require qualified ARNs** (version, alias, or `$LATEST`):

```bash
# Valid
aws lambda invoke --function-name my-function:1 output.json
aws lambda invoke --function-name my-function:prod output.json

# Invalid - will fail
aws lambda invoke --function-name my-function output.json
```

## IAM Permissions

Your Lambda execution role MUST have the `AWSLambdaBasicDurableExecutionRolePolicy` managed policy attached. This includes:

- `lambda:CheckpointDurableExecution` - Persist execution state
- `lambda:GetDurableExecutionState` - Retrieve execution state
- CloudWatch Logs permissions

**Additional permissions needed for:**

- **Durable invokes**: `lambda:InvokeFunction` on target function ARNs
- **External callbacks**: Systems need `lambda:SendDurableExecutionCallbackSuccess` and `lambda:SendDurableExecutionCallbackFailure`

## Validation Guidelines

When writing or reviewing durable function code, ALWAYS check for these replay model violations:

1. **Non-deterministic code outside steps**: `Date.now()`, `Math.random()`, UUID generation, API calls, database queries must all be inside steps
2. **Nested durable operations in step functions**: Cannot call `context.step()`, `context.wait()`, or `context.invoke()` inside a step function — use `context.runInChildContext()` instead
3. **Closure mutations that won't persist**: Variables mutated inside steps are NOT preserved across replays — return values from steps instead
4. **Side effects outside steps that repeat on replay**: Use `context.logger` for logging (it is replay-aware and deduplicates automatically)

When implementing or modifying tests for durable functions, ALWAYS verify:

1. All operations have descriptive names
2. Tests get operations by NAME, never by index
3. Replay behavior is tested with multiple invocations
4. Use `LocalDurableTestRunner` for local testing

### MCP Server Configuration

**Write access is enabled by default.** The plugin ships with `--allow-write` in `.mcp.json`, so the MCP server can create projects, generate IaC, and deploy on behalf of the user.

Access to sensitive data (like Lambda and API Gateway logs) is **not** enabled by default. To grant it, add `--allow-sensitive-data-access` to `.mcp.json`.

## Resources

- [AWS Lambda durable functions Documentation](https://docs.aws.amazon.com/lambda/latest/dg/durable-functions.html)
- [JavaScript SDK Repository](https://github.com/aws/aws-durable-execution-sdk-js)
- [Python SDK Repository](https://github.com/aws/aws-durable-execution-sdk-python)
- [IAM Policy Reference](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AWSLambdaBasicDurableExecutionRolePolicy.html)
