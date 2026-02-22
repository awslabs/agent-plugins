# Getting Started with AWS Lambda durable functions

Quick start guide for building your first durable function.

## Check user and project preferences

Ask which IaC framework to use for new projects.
Ask which programming language to use if unclear, clarify between JavaScript and TypeScript if necessary.
Ask to create a git repo for projects if one doesn't exist already.

## Basic Handler

**TypeScript:**

```typescript
import { withDurableExecution, DurableContext } from '@aws/durable-execution-sdk-js';

export const handler = withDurableExecution(async (event, context: DurableContext) => {
  // Execute a step with automatic retry
  const userData = await context.step('fetch-user', async () => 
    fetchUserFromDB(event.userId)
  );

  // Wait without compute charges
  await context.wait({ seconds: 5 });

  // Process in another step
  const result = await context.step('process', async () => 
    processUser(userData)
  );

  return { success: true, data: result };
});
```

**Python:**

```python
from aws_durable_execution_sdk_python import durable_execution, DurableContext, durable_step, StepContext
from aws_durable_execution_sdk_python.config import Duration

@durable_step
def fetch_user(step_ctx: StepContext, user_id: str):
    return fetch_user_from_db(user_id)

@durable_step
def process_user_data(step_ctx: StepContext, user_data: dict):
    return process_user(user_data)

@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    user_data = context.step(fetch_user(event['userId']))
    context.wait(duration=Duration.from_seconds(5))
    result = context.step(process_user_data(user_data))
    return {'success': True, 'data': result}
```

## Common Patterns

### Multi-Step Workflow

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const validated = await context.step('validate', async () => 
    validateInput(event)
  );
  
  const processed = await context.step('process', async () => 
    processData(validated)
  );
  
  await context.wait('cooldown', { seconds: 30 });
  
  await context.step('notify', async () => 
    sendNotification(processed)
  );
  
  return { success: true };
});
```

### GenAI Agent (Agentic Loop)

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const messages = [{ role: 'user', content: event.prompt }];

  while (true) {
    const { response, tool } = await context.step('invoke-model', async () =>
      invokeAIModel(messages)
    );

    if (tool == null) return response;

    const toolResult = await context.step(`tool-${tool.name}`, async () =>
      executeTool(tool, response)
    );
    
    messages.push({ role: 'assistant', content: toolResult });
  }
});
```

**Python:**

```python
@durable_execution
def handler(event: dict, context: DurableContext) -> str:
    messages = [{"role": "user", "content": event["prompt"]}]

    while True:
        result = context.step(
            lambda _: invoke_ai_model(messages),
            name="invoke-model"
        )

        if result.get("tool") is None:
            return result["response"]

        tool = result["tool"]
        tool_result = context.step(
            lambda _: execute_tool(tool, result["response"]),
            name=f"tool-{tool['name']}"
        )
        messages.append({"role": "assistant", "content": tool_result})
```

### Human-in-the-Loop Approval

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const plan = await context.step('generate-plan', async () =>
    generatePlan(event)
  );

  const answer = await context.waitForCallback(
    'wait-for-approval',
    async (callbackId) => sendApprovalEmail(event.approverEmail, plan, callbackId),
    { timeout: { hours: 24 } }
  );

  if (answer === 'APPROVED') {
    await context.step('execute', async () => performAction(plan));
    return { status: 'completed' };
  }
  
  return { status: 'rejected' };
});
```

**Python:**

```python
from aws_durable_execution_sdk_python.waits import WaitForCallbackConfig

@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    plan = context.step(lambda _: generate_plan(event), name='generate-plan')

    def submit_approval(callback_id: str):
        send_approval_email(event['approver_email'], plan, callback_id)

    answer = context.wait_for_callback(
        submitter=submit_approval,
        config=WaitForCallbackConfig(timeout=Duration.from_hours(24)),
        name='wait-for-approval'
    )

    if answer == 'APPROVED':
        context.step(lambda _: perform_action(plan), name='execute')
        return {'status': 'completed'}
    
    return {'status': 'rejected'}
```

### Saga Pattern (Compensating Transactions)

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const compensations: Array<{ name: string; fn: () => Promise<void> }> = [];

  try {
    await context.step('book-flight', async () => flightClient.book(event));
    compensations.push({
      name: 'cancel-flight',
      fn: () => flightClient.cancel(event)
    });

    await context.step('book-hotel', async () => hotelClient.book(event));
    compensations.push({
      name: 'cancel-hotel',
      fn: () => hotelClient.cancel(event)
    });

    return { success: true };
  } catch (error) {
    for (const comp of compensations.reverse()) {
      await context.step(comp.name, async () => comp.fn());
    }
    throw error;
  }
});
```

## Project Structure

```
my-durable-function/
├── src/
│   ├── handler.ts              # Main handler
│   ├── steps/                  # Step functions
│   │   ├── validate.ts
│   │   └── process.ts
│   └── utils/                  # Utilities
│       └── retry-strategies.ts
├── tests/
│   └── handler.test.ts         # Tests with LocalDurableTestRunner
├── infrastructure/
│   └── template.yaml           # SAM/CloudFormation
├── eslint.config.js            # ESLint configuration
├── jest.config.js              # Jest configuration
├── tsconfig.json               # TypeScript configuration
└── package.json
```

## ESLint Plugin Setup

Install the ESLint plugin to catch common durable function mistakes at development time:

```bash
npm install --save-dev @aws/durable-execution-sdk-js-eslint-plugin
```

### Option A: Flat Config (eslint.config.js)

```javascript
import durableExecutionPlugin from '@aws/durable-execution-sdk-js-eslint-plugin';

export default [
  {
    plugins: {
      '@aws/durable-execution-sdk-js': durableExecutionPlugin,
    },
    rules: {
      '@aws/durable-execution-sdk-js/no-nested-durable-operations': 'error',
    },
  },
];
```

### Option B: Recommended Config

```javascript
import durableExecutionPlugin from '@aws/durable-execution-sdk-js-eslint-plugin';

export default [
  durableExecutionPlugin.configs.recommended,
  // Your other configs...
];
```

### Option C: Legacy .eslintrc.json

```json
{
  "plugins": ["@aws/durable-execution-sdk-js-eslint-plugin"],
  "extends": ["plugin:@aws/durable-execution-sdk-js-eslint-plugin/recommended"],
  "rules": {
    "@aws/durable-execution-sdk-js-eslint-plugin/no-nested-durable-operations": "error"
  }
}
```

**What the plugin catches:**

- Nested durable operations inside step functions
- Incorrect usage of durable context outside handler
- Common replay model violations

## Jest Configuration

**jest.config.js:**

```javascript
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.test.ts'],
  transform: {
    '^.+\\.ts$': 'ts-jest',
  },
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.d.ts',
  ],
};
```

**Key Configuration:**

- `preset: 'ts-jest'` - Essential for TypeScript support
- `transform` - Maps .ts files to ts-jest transformer
- `testMatch` - Specifies test file patterns

## Development Workflow

1. **Write handler** with durable operations
2. **Test locally** with `LocalDurableTestRunner`
3. **Validate replay rules** (no non-deterministic code outside steps)
4. **Deploy** with qualified ARN (version or alias)
5. **Monitor** execution state and logs

## Key Concepts

- **Steps**: Atomic operations with automatic retry and checkpointing
- **Waits**: Suspend execution without compute charges (up to 1 year)
- **Child Contexts**: Group multiple durable operations
- **Callbacks**: Wait for external systems to respond
- **Map/Parallel**: Process arrays or run operations concurrently

## Setup Checklist

When starting a new durable function project:

- [ ] Install dependencies (`@aws/durable-execution-sdk-js`, testing & eslint packages)
- [ ] Create `jest.config.js` with ts-jest preset
- [ ] Configure `tsconfig.json` with proper module resolution
- [ ] Set up ESLint with durable execution plugin
- [ ] Create handler with `withDurableExecution` wrapper
- [ ] Write tests using `LocalDurableTestRunner`
- [ ] Use `skipTime: true` for fast test execution
- [ ] Verify TypeScript compilation: `npx tsc --noEmit`
- [ ] Run tests to confirm setup: `npm test`
- [ ] Review replay model rules (no non-deterministic code outside steps)

## Next Steps

- Review **replay-model-rules.md** to avoid common pitfalls
- Explore **step-operations.md** for retry strategies
- Learn **wait-operations.md** for external integrations
- Check **testing-patterns.md** for comprehensive testing
