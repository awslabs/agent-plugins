# Getting Started with AWS Lambda durable functions

Quick start guide for building your first durable function.

## Language selection

Default: TypeScript

Override syntax:

- "use Python" → Generate Python code
- "use JavaScript" → Generate JavaScript code
- "use Java" → Generate Java code

When not specified, ALWAYS use TypeScript

### Error Scenarios: Unsupported Language

- List detected language
- State: "Durable Execution SDK is not yet available for [framework]"
- Suggest supported languages as alternatives

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

**Java:**

```java
import java.time.Duration;
import software.amazon.lambda.durable.DurableContext;
import software.amazon.lambda.durable.DurableHandler;

public class MyHandler extends DurableHandler<MyInput, MyOutput> {
    @Override
    public MyOutput handleRequest(MyInput event, DurableContext ctx) {
        // Execute a step with automatic retry
        var userData = ctx.step("fetch-user", UserData.class,
            stepCtx -> fetchUserFromDB(event.getUserId()));

        // Wait without compute charges
        ctx.wait("initial-delay", Duration.ofSeconds(5));

        // Process in another step
        var result = ctx.step("process", ProcessResult.class,
            stepCtx -> processUser(userData));

        return new MyOutput(true, result);
    }
}
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

**Java:**

```java
public class WorkflowHandler extends DurableHandler<WorkflowInput, WorkflowOutput> {
    @Override
    public WorkflowOutput handleRequest(WorkflowInput event, DurableContext ctx) {
        var validated = ctx.step("validate", ValidatedData.class,
            stepCtx -> validateInput(event));

        var processed = ctx.step("process", ProcessedData.class,
            stepCtx -> processData(validated));

        ctx.wait("cooldown", Duration.ofSeconds(30));

        ctx.step("notify", Void.class,
            stepCtx -> { sendNotification(processed); return null; });

        return new WorkflowOutput(true);
    }
}
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
# Note: invoke_ai_model and execute_tool are decorated with @durable_step
@durable_execution
def handler(event: dict, context: DurableContext) -> str:
    messages = [{"role": "user", "content": event["prompt"]}]

    while True:
        result = context.step(invoke_ai_model(messages))

        if result.get("tool") is None:
            return result["response"]

        tool = result["tool"]
        tool_result = context.step(execute_tool(tool, result["response"]))
        messages.append({"role": "assistant", "content": tool_result})
```

**Java:**

```java
public class AgentHandler extends DurableHandler<AgentInput, String> {
    @Override
    public String handleRequest(AgentInput event, DurableContext ctx) {
        var messages = new ArrayList<>(List.of(
            Map.of("role", "user", "content", event.getPrompt())));

        while (true) {
            var result = ctx.step("invoke-model", ModelResult.class,
                stepCtx -> invokeAIModel(messages));

            if (result.getTool() == null) {
                return result.getResponse();
            }

            // Dynamic step name based on the tool being executed
            var toolResult = ctx.step("tool-" + result.getTool().getName(), String.class,
                stepCtx -> executeTool(result.getTool(), result.getResponse()));

            messages.add(Map.of("role", "assistant", "content", toolResult));
        }
    }
}
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
from aws_durable_execution_sdk_python.config import WaitForCallbackConfig

@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    # Note: generate_plan and perform_action are decorated with @durable_step
    plan = context.step(generate_plan(event))

    # Wait for external approval
    def submit_approval(callback_id: str, ctx):
        send_approval_email(event['approver_email'], plan, callback_id)

    answer = context.wait_for_callback(
        submitter=submit_approval,
        name='wait-for-approval',
        config=WaitForCallbackConfig(timeout=Duration.from_hours(24))
    )

    if answer == 'APPROVED':
        context.step(perform_action(plan))
        return {'status': 'completed'}
    
    return {'status': 'rejected'}
```

**Java:**

```java
import software.amazon.lambda.durable.config.WaitForCallbackConfig;
import software.amazon.lambda.durable.config.CallbackConfig;

public class ApprovalHandler extends DurableHandler<ApprovalInput, ApprovalOutput> {
    @Override
    public ApprovalOutput handleRequest(ApprovalInput event, DurableContext ctx) {
        var plan = ctx.step("generate-plan", Plan.class,
            stepCtx -> generatePlan(event));

        var answer = ctx.waitForCallback("wait-for-approval", String.class,
            (callbackId, stepCtx) -> sendApprovalEmail(event.getApproverEmail(), plan, callbackId),
            WaitForCallbackConfig.builder()
                .callbackConfig(CallbackConfig.builder().timeout(Duration.ofHours(24)).build())
                .build());

        if ("APPROVED".equals(answer)) {
            ctx.step("execute", Void.class, stepCtx -> { performAction(plan); return null; });
            return new ApprovalOutput("completed");
        }

        return new ApprovalOutput("rejected");
    }
}
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

**Java:**

```java
import software.amazon.lambda.durable.exception.DurableExecutionException;

public class SagaHandler extends DurableHandler<BookingInput, BookingOutput> {
    @Override
    public BookingOutput handleRequest(BookingInput event, DurableContext ctx) {
        var compensations = new ArrayList<Runnable>();
        try {
            ctx.step("book-flight", Void.class,
                s -> { flightClient.book(event); return null; });
            compensations.add(() -> ctx.step("cancel-flight", Void.class,
                s -> { flightClient.cancel(event); return null; }));

            ctx.step("book-hotel", Void.class,
                s -> { hotelClient.book(event); return null; });
            compensations.add(() -> ctx.step("cancel-hotel", Void.class,
                s -> { hotelClient.cancel(event); return null; }));

            return new BookingOutput(true);
        } catch (DurableExecutionException e) {
            // Run compensations in reverse order
            Collections.reverse(compensations);
            for (var comp : compensations) {
                comp.run();
            }
            throw e;
        }
    }
}
```

## Project Structure

### TypeScript

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

### Python

```
my-durable-function/
├── src/
│   ├── handler.py              # Main handler
│   ├── steps/                  # Step functions
│   │   ├── __init__.py
│   │   ├── validate.py
│   │   └── process.py
│   └── utils/
│       └── retry_strategies.py
├── tests/
│   └── test_handler.py         # Tests with DurableFunctionTestRunner
├── infrastructure/
│   └── template.yaml           # SAM/CloudFormation
└── pyproject.toml              # Project configuration
```

### Java

```
my-durable-function/
├── src/
│   ├── main/
│   │   └── java/
│   │       └── com/example/
│   │           ├── MyHandler.java          # Main handler
│   │           ├── steps/                  # Step functions
│   │           │   ├── ValidateStep.java
│   │           │   └── ProcessStep.java
│   │           └── utils/
│   │               └── RetryStrategies.java
│   └── test/
│       └── java/
│           └── com/example/
│               └── MyHandlerTest.java      # Tests with LocalDurableTestRunner
├── infrastructure/
│   └── template.yaml                       # SAM/CloudFormation
└── pom.xml                                 # Maven project configuration
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

## Python Project Setup

Add `aws-durable-execution-sdk-python-testing` to your dev/test dependencies in pyproject.toml.

## Java Maven Setup

Add the SDK dependencies to your `pom.xml`. Pin to a specific released `VERSION` (see [Maven Central](https://mvnrepository.com/artifact/software.amazon.lambda.durable/aws-durable-execution-sdk-java)) rather than a floating version, and set the Java compiler to 17 or higher:

```xml
<properties>
  <maven.compiler.source>17</maven.compiler.source>
  <maven.compiler.target>17</maven.compiler.target>
  <aws-durable-execution-sdk-java.version>VERSION</aws-durable-execution-sdk-java.version>
</properties>

<dependencies>
  <dependency>
    <groupId>software.amazon.lambda.durable</groupId>
    <artifactId>aws-durable-execution-sdk-java</artifactId>
    <version>${aws-durable-execution-sdk-java.version}</version>
  </dependency>
  <dependency>
    <groupId>software.amazon.lambda.durable</groupId>
    <artifactId>aws-durable-execution-sdk-java-testing</artifactId>
    <version>${aws-durable-execution-sdk-java.version}</version>
    <scope>test</scope>
  </dependency>
</dependencies>
```

## Development Workflow

### TypeScript

1. **Write handler** with durable operations
2. **Test locally** with `LocalDurableTestRunner`
3. **Validate replay rules** (no non-deterministic code outside steps)
4. **Deploy** with qualified ARN (version or alias)
5. **Monitor** execution state and logs

### Python

1. **Write handler** with `@durable_execution` decorator
2. **Test locally** with `DurableFunctionTestRunner` and pytest
3. **Validate replay rules** (no non-deterministic code outside steps)
4. **Deploy** with qualified ARN (version or alias)
5. **Monitor** execution state and logs

### Java

1. **Write handler** extending `DurableHandler<TInput, TOutput>`
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

### TypeScript

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

### Python

- [ ] Install `aws-durable-execution-sdk-python`
- [ ] Install `aws-durable-execution-sdk-python-testing` and `pytest` for testing
- [ ] Create handler with `@durable_execution` decorator
- [ ] Define step functions with `@durable_step` decorator
- [ ] Write tests using `DurableFunctionTestRunner` class
- [ ] Run tests: `pytest`
- [ ] Review replay model rules (no non-deterministic code outside steps)

### Java

- [ ] Add SDK dependencies to `pom.xml` pinned to a specific released `VERSION`
- [ ] Set Java compiler source/target to 17 or higher in `pom.xml`
- [ ] Create handler class extending `DurableHandler<TInput, TOutput>`
- [ ] Implement `handleRequest(TInput, DurableContext)`
- [ ] Write tests using `LocalDurableTestRunner`
- [ ] Run tests: `mvn test`
- [ ] Review replay model rules (no non-deterministic code outside steps)

## Error Scenarios

### Unsupported Language

- List detected language
- State: "Durable Execution SDK is not yet available for [language]"
- List supported languages as alternatives

## Next Steps

- Review **replay-model-rules.md** to avoid common pitfalls
- Explore **step-operations.md** for retry strategies
- Learn **wait-operations.md** for external integrations
- Check **testing-patterns.md** for comprehensive testing
