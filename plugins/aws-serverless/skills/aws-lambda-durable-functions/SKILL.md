---
name: aws-lambda-durable-functions
description: >
  Build resilient, long-running AWS Lambda durable functions with automatic state persistence,
  retry logic, and workflow orchestration for up to 1 year execution. Covers the critical replay
  model, step operations, wait/callback patterns, concurrent execution (map/parallel), error
  handling with saga pattern, testing with LocalDurableTestRunner, and deployment with
  CloudFormation, CDK, and SAM. Use for: lambda durable functions, workflow orchestration,
  state machines, retry/checkpoint patterns, long-running stateful Lambda functions, saga pattern,
  agentic AI workflows, human-in-the-loop callbacks, and serverless applications.
hooks:
  PostToolUse:
    - matcher: "Edit"
      command: "echo 'REMINDER: If you modified a durable function handler, verify replay model rules — all non-deterministic code (Date.now, Math.random, UUID, API calls) MUST be inside steps, no nested durable operations in step functions, closure mutations must be returned not mutated, and side effects outside steps repeat on replay.'"
    - matcher: "Write"
      command: "echo 'REMINDER: If you created a durable function handler, verify replay model rules — all non-deterministic code (Date.now, Math.random, UUID, API calls) MUST be inside steps, no nested durable operations in step functions, closure mutations must be returned not mutated, and side effects outside steps repeat on replay. Also ensure tests use LocalDurableTestRunner and get operations by NAME not index.'"
---

# AWS Lambda durable functions

Build resilient multi-step applications and AI workflows that can execute for up to 1 year while maintaining reliable progress despite interruptions.

## Prerequisites

Before using AWS Lambda durable functions, verify:

1. **AWS CLI** is installed (2.33.22 or higher) and configured:

   ```bash
   aws --version
   aws sts get-caller-identity
   ```

2. **Runtime environment** is ready:
   - For TypeScript/JavaScript: Node.js 22+ (`node --version`)
   - For Python: Python 3.13+ (`python --version`)

3. **Deployment capability** exists (one of):
   - AWS SAM CLI (`sam --version`) 1.153.1 or higher
   - AWS CDK (`cdk --version`) v2.237.1 or higher
   - Direct Lambda deployment access

## SDK Installation

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
- **Testing**, **local testing**, **cloud testing**, **test runner**, or **flaky tests** -> see [testing-patterns.md](references/testing-patterns.md)
- **Deployment**, **CloudFormation**, **CDK**, **SAM**, **log groups**, or **infrastructure** -> see [deployment-iac.md](references/deployment-iac.md)
- **Advanced patterns**, **GenAI agents**, **completion policies**, **step semantics**, or **custom serialization** -> see [advanced-patterns.md](references/advanced-patterns.md)

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

- `lambda:CheckpointDurableExecutions` - Persist execution state
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

## Guidelines

Ask which IaC framework to use for new projects.
Ask which programming language to use if unclear, clarify between JavaScript and TypeScript if necessary.
Ask to create a git repo for projects if one doesn't exist already.

## Troubleshooting Production Executions

**PROACTIVE AGENT**: When users report issues with production durable function executions, spawn a specialized troubleshooting agent.

### When to Spawn Troubleshooting Agent

Spawn the agent when users mention:

- "My execution is stuck"
- "Execution failed with ID xyz"
- "Debug execution abc123"
- "Troubleshoot production execution"
- "Why is my durable function not completing"
- Provide an execution ID and need diagnosis

### Agent Instructions

When spawning the troubleshooting agent, provide:

```
Diagnose durable function execution issue:
- Function: <function-name>:<alias> (must be qualified ARN)
- Execution ID: <execution-id>

Steps:
1. Run: aws lambda get-durable-execution-history --function-name <function> --execution-id <id>
2. Analyze execution status (RUNNING/SUCCEEDED/FAILED/TIMED_OUT)
3. Check for stuck operations (PENDING/RUNNING status)
4. Identify failed operations and error messages
5. Calculate operation durations and timeline
6. Diagnose specific issue:
   - Stuck in WAIT_FOR_CALLBACK: Extract callback ID, suggest manual callback
   - Failed operations: Show error and retry attempts
   - Timeout: Calculate total duration, identify slow operations
   - Unexpected behavior: Compare operation order with expected flow
7. Provide specific recommendations and next steps

Use jq for JSON parsing and analysis. Reference: references/troubleshooting-production.md for diagnostic patterns.
```

### Example Usage

```
User: "My durable function execution abc-123 is stuck on my-function:prod"

Claude: [Spawns Task agent with troubleshooting instructions]
Agent: [Runs get-durable-execution-history command]
Agent: [Analyzes with jq queries]
Agent: [Returns: "Execution stuck in WAIT_FOR_CALLBACK operation 'wait-for-approval'.
         Callback ID: xyz789. Waiting since 2026-02-14. Timeout in 12 hours.
         Recommendation: Check if approval email was sent, or manually send callback."]
Claude: [Presents findings and offers to send manual callback if needed]
```

## Resources

- [AWS Lambda durable functions Documentation](https://docs.aws.amazon.com/lambda/latest/dg/durable-functions.html)
- [JavaScript SDK Repository](https://github.com/aws/aws-durable-execution-sdk-js)
- [Python SDK Repository](https://github.com/aws/aws-durable-execution-sdk-python)
- [IAM Policy Reference](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AWSLambdaBasicDurableExecutionRolePolicy.html)
