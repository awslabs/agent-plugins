# Wait Operations

Suspend execution without compute charges for delays, external callbacks, and polling.

## Simple Waits

Pause execution for a duration (no compute charges during wait):

**TypeScript:**

```typescript
await context.wait({ seconds: 30 });
await context.wait({ minutes: 5 });
await context.wait({ hours: 1, minutes: 30 });
await context.wait({ days: 7 });

// Named wait (recommended)
await context.wait('rate-limit-delay', { seconds: 60 });
```

**Python:**

```python
from aws_durable_execution_sdk_python.config import Duration

context.wait(duration=Duration.from_seconds(30))
context.wait(duration=Duration.from_minutes(5))
context.wait(duration=Duration.from_hours(1))
context.wait(duration=Duration.from_days(7))

# Named wait (recommended)
context.wait(duration=Duration.from_seconds(60), name='rate-limit-delay')
```

**Java:**

```java
import java.time.Duration;

// Synchronous wait (blocks execution)
ctx.wait("delay", Duration.ofSeconds(30));
ctx.wait("rate-limit-delay", Duration.ofMinutes(5));
ctx.wait("long-delay", Duration.ofHours(1));
ctx.wait("very-long-delay", Duration.ofDays(7));

// Async wait (returns DurableFuture)
var future = ctx.waitAsync("async-delay", Duration.ofHours(1));
// ... do other work ...
future.get();
```

**Max wait duration:** Up to 1 year

## Wait for Callback

Wait for external systems to respond (human approval, webhook, async job):

**TypeScript:**

```typescript
const result = await context.waitForCallback(
  'wait-for-approval',
  async (callbackId, ctx) => {
    // Send callback ID to external system
    await sendApprovalEmail(approverEmail, callbackId);
  },
  {
    timeout: { hours: 24 },
    heartbeatTimeout: { minutes: 5 }
  }
);

// External system calls back with:
// aws lambda send-durable-execution-callback-success \
//   --callback-id <callbackId> \
//   --payload '{"approved": true}'
```

**Python:**

```python
from aws_durable_execution_sdk_python.config import WaitForCallbackConfig

# Wait for external approval
def submit_approval(callback_id: str, ctx):
    ctx.logger.info('Sending approval request')
    send_approval_email(approver_email, callback_id)

result = context.wait_for_callback(
    submitter=submit_approval,
    name='wait-for-approval',
    config=WaitForCallbackConfig(
        timeout=Duration.from_hours(24),
        heartbeat_timeout=Duration.from_minutes(5)
    )
)
```

**Java:**

```java
import software.amazon.lambda.durable.config.WaitForCallbackConfig;
import software.amazon.lambda.durable.config.CallbackConfig;

var result = ctx.waitForCallback("wait-for-approval", ApprovalResult.class,
    (callbackId, stepCtx) -> {
        sendApprovalEmail(approverEmail, callbackId);
    },
    WaitForCallbackConfig.builder()
        .callbackConfig(CallbackConfig.builder()
            .timeout(Duration.ofHours(24))
            .heartbeatTimeout(Duration.ofMinutes(5))
            .build())
        .build());

// External system calls back with:
// aws lambda send-durable-execution-callback-success \
//   --callback-id <callbackId> \
//   --payload '{"approved": true}'
```

### Callback Success

**CLI:**

```bash
aws lambda send-durable-execution-callback-success \
  --callback-id <callbackId> \
  --payload '{"status": "approved", "comments": "Looks good"}'
```

**SDK (TypeScript):**

```typescript
import { LambdaClient, SendDurableExecutionCallbackSuccessCommand } from '@aws-sdk/client-lambda';

const client = new LambdaClient({});
await client.send(new SendDurableExecutionCallbackSuccessCommand({
  CallbackId: callbackId,
  Payload: JSON.stringify({ status: 'approved' })
}));
```

**SDK (Python / boto3):**

```python
import boto3
import json

lambda_client = boto3.client('lambda')
lambda_client.send_durable_execution_callback_success(
    CallbackId=callback_id,
    Result=json.dumps({'status': 'approved'})
)
```

**SDK (Java):**

```java
import software.amazon.awssdk.services.lambda.LambdaClient;
import software.amazon.awssdk.services.lambda.model.SendDurableExecutionCallbackSuccessRequest;

LambdaClient client = LambdaClient.create();
client.sendDurableExecutionCallbackSuccess(
    SendDurableExecutionCallbackSuccessRequest.builder()
        .callbackId(callbackId)
        .payload("{\"status\":\"approved\"}")
        .build()
);
```

### Callback Failure

**CLI:**

```bash
aws lambda send-durable-execution-callback-failure \
  --callback-id <callbackId> \
  --error-type "ApprovalDenied" \
  --error-message "Request denied by approver"
```

### Heartbeats

Keep callback alive during long-running external processes:

**TypeScript:**

```typescript
const result = await context.waitForCallback(
  'long-process',
  async (callbackId) => {
    await startLongRunningJob(callbackId);
  },
  {
    timeout: { hours: 24 },
    heartbeatTimeout: { minutes: 5 }  // Must receive heartbeat every 5 min
  }
);

// External system sends heartbeats:
// aws lambda send-durable-execution-callback-heartbeat --callback-id <callbackId>
```

**CLI Heartbeat:**

```bash
aws lambda send-durable-execution-callback-heartbeat \
  --callback-id <callbackId>
```

## Wait for Condition

Poll until a condition is met (job completion, resource availability):

**TypeScript:**

```typescript
const finalState = await context.waitForCondition(
  'wait-for-job',
  async (currentState, ctx) => {
    const status = await checkJobStatus(currentState.jobId);
    return { ...currentState, status };
  },
  {
    initialState: { jobId: 'job-123', status: 'pending' },
    waitStrategy: createWaitStrategy({
      maxAttempts: 60,
      initialDelaySeconds: 5,
      maxDelaySeconds: 30,
      backoffRate: 1.5,
      shouldContinuePolling: (result) => result.status !== "completed"
    }),
    timeout: { hours: 1 }
  }
);
```

**Python:**

```python
# Note: get_job_status is decorated with @durable_step
from aws_durable_execution_sdk_python.waits import WaitForConditionConfig, create_wait_strategy, WaitStrategyConfig
from aws_durable_execution_sdk_python.config import Duration

def check_job(state: dict, check_ctx):
    status = get_job_status(state['job_id'])
    return {'job_id': state['job_id'], 'status': status}

wait_strategy = create_wait_strategy(
    WaitStrategyConfig(
        should_continue_polling=lambda state: state['status'] != 'completed',
        max_attempts=60,
        initial_delay=Duration.from_seconds(2),
        max_delay=Duration.from_seconds(60),
        backoff_rate=1.5
    )
)

result = context.wait_for_condition(
    check=check_job,
    config=WaitForConditionConfig(
        initial_state={'job_id': 'job-123', 'status': 'pending'},
        wait_strategy=wait_strategy
    ),
    name='wait-for-job'
)
```

**Java:**

```java
import software.amazon.lambda.durable.config.WaitForConditionConfig;
import software.amazon.lambda.durable.model.WaitForConditionResult;
import software.amazon.lambda.durable.exception.WaitForConditionFailedException;

// Define state class for job polling
record JobState(String jobId, String status) {}

var finalState = ctx.waitForCondition("wait-for-job", JobState.class,
    (currentState, stepCtx) -> {
        // Check current status and update state
        var status = checkJobStatus(currentState.jobId());
        var newState = new JobState(currentState.jobId(), status);
        
        // Decision logic: stop if completed, continue otherwise
        if ("completed".equals(status)) {
            return WaitForConditionResult.stopPolling(newState);
        }
        return WaitForConditionResult.continuePolling(newState);
    },
    WaitForConditionConfig.<JobState>builder()
        .initialState(new JobState("job-123", "pending"))
        .waitStrategy((state, attempt) -> {
            // Compute delay duration (not decision logic)
            if (attempt >= 60) {
                throw new WaitForConditionFailedException("Max polling attempts exceeded");
            }
            long delaySeconds = Math.min((long) (5 * Math.pow(1.5, attempt)), 30);
            return Duration.ofSeconds(delaySeconds);
        })
        .build());
```

### Custom Wait Strategy

**TypeScript:**

```typescript
const result = await context.waitForCondition(
  'custom-poll',
  async (state) => {
    const data = await fetchData();
    return { ...state, data, attempts: state.attempts + 1 };
  },
  {
    initialState: { attempts: 0 },
    waitStrategy: (state, attempt) => {
      // Stop after 10 attempts
      if (state.attempts >= 10) {
        return { shouldContinue: false };
      }
      
      // Exponential backoff with max 60s
      return {
        shouldContinue: !state.data?.ready,
        delay: { seconds: Math.min(Math.pow(2, attempt), 60) }
      };
    }
  }
);
```

**Java:**

```java
import software.amazon.lambda.durable.model.WaitForConditionResult;

// Define state class
record PollState(Data data, int attempts) {
    boolean isReady() { return data != null && data.isReady(); }
}

var result = ctx.waitForCondition("custom-poll", PollState.class,
    (state, stepCtx) -> {
        // Fetch data and update state
        var data = fetchData();
        var newState = new PollState(data, state.attempts() + 1);
        
        // Decision logic: stop if ready or max attempts
        if (newState.isReady() || newState.attempts() >= 10) {
            return WaitForConditionResult.stopPolling(newState);
        }
        return WaitForConditionResult.continuePolling(newState);
    },
    WaitForConditionConfig.<PollState>builder()
        .initialState(new PollState(null, 0))
        .waitStrategy((state, attempt) -> {
            // Compute exponential backoff delay (max 60 seconds)
            long delaySeconds = Math.min((long) Math.pow(2, attempt), 60);
            return Duration.ofSeconds(delaySeconds);
        })
        .build());
```

## Callback Patterns

### Human Approval Workflow

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const request = await context.step('create-request', async () =>
    createApprovalRequest(event)
  );

  const decision = await context.waitForCallback(
    'wait-approval',
    async (callbackId) => {
      await sendEmail({
        to: event.approver,
        subject: 'Approval Required',
        body: `Approve: ${approvalUrl}?callback=${callbackId}&action=approve\n` +
              `Reject: ${approvalUrl}?callback=${callbackId}&action=reject`
      });
    },
    { timeout: { hours: 48 } }
  );

  if (decision.action === 'approve') {
    await context.step('execute', async () => executeRequest(request));
    return { status: 'approved' };
  }
  
  return { status: 'rejected' };
});
```

**Java:**

```java
import software.amazon.lambda.durable.config.WaitForCallbackConfig;
import software.amazon.lambda.durable.config.CallbackConfig;

public class ApprovalHandler extends DurableHandler<ApprovalRequest, ApprovalResult> {
    @Override
    public ApprovalResult handleRequest(ApprovalRequest event, DurableContext ctx) {
        var request = ctx.step("create-request", Request.class,
            s -> createApprovalRequest(event));
        
        var decision = ctx.waitForCallback("wait-approval", Decision.class,
            (callbackId, s) -> {
                sendEmail(Map.of(
                    "to", event.getApprover(),
                    "subject", "Approval Required",
                    "body", "Approve: " + approvalUrl + "?callback=" + callbackId + "&action=approve\n" +
                            "Reject: " + approvalUrl + "?callback=" + callbackId + "&action=reject"
                ));
            },
            WaitForCallbackConfig.builder()
                .callbackConfig(CallbackConfig.builder().timeout(Duration.ofHours(48)).build())
                .build());
        
        if ("approve".equals(decision.getAction())) {
            ctx.step("execute", Void.class, s -> { executeRequest(request); return null; });
            return new ApprovalResult("approved");
        }
        
        return new ApprovalResult("rejected");
    }
}
```

### Webhook Integration

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const order = await context.step('create-order', async () =>
    createOrder(event)
  );

  const payment = await context.waitForCallback(
    'wait-payment',
    async (callbackId) => {
      await paymentProvider.createPayment({
        orderId: order.id,
        amount: order.total,
        webhookUrl: `${webhookUrl}?callback=${callbackId}`
      });
    },
    { timeout: { minutes: 15 } }
  );

  if (payment.status === 'success') {
    await context.step('fulfill', async () => fulfillOrder(order));
  }
  
  return { orderId: order.id, paymentStatus: payment.status };
});
```

**Java:**

```java
import software.amazon.lambda.durable.config.WaitForCallbackConfig;
import software.amazon.lambda.durable.config.CallbackConfig;

public class OrderHandler extends DurableHandler<OrderRequest, OrderResult> {
    @Override
    public OrderResult handleRequest(OrderRequest event, DurableContext ctx) {
        var order = ctx.step("create-order", Order.class,
            s -> createOrder(event));
        
        var payment = ctx.waitForCallback("wait-payment", Payment.class,
            (callbackId, s) -> {
                paymentProvider.createPayment(Map.of(
                    "orderId", order.getId(),
                    "amount", order.getTotal(),
                    "webhookUrl", webhookUrl + "?callback=" + callbackId
                ));
            },
            WaitForCallbackConfig.builder()
                .callbackConfig(CallbackConfig.builder().timeout(Duration.ofMinutes(15)).build())
                .build());
        
        if ("success".equals(payment.getStatus())) {
            ctx.step("fulfill", Void.class, s -> { fulfillOrder(order); return null; });
        }
        
        return new OrderResult(order.getId(), payment.getStatus());
    }
}
```

### Async Job Polling

**TypeScript:**

```typescript
export const handler = withDurableExecution(async (event, context: DurableContext) => {
  const jobId = await context.step('start-job', async () =>
    startBatchJob(event.data)
  );

  const result = await context.waitForCondition(
    'poll-job',
    async (state) => {
      const job = await getJobStatus(state.jobId);
      return { jobId: state.jobId, status: job.status, result: job.result };
    },
    {
      initialState: { jobId, status: 'running' },
      waitStrategy: createWaitStrategy({
        maxAttempts: 60,
        initialDelaySeconds: 5,
        maxDelaySeconds: 30,
        backoffRate: 1.5,
        shouldContinuePolling: (result) => result.status === "running"
      }),
      timeout: { hours: 2 }
    }
  );

  return result;
});
```

**Java:**

```java
import software.amazon.lambda.durable.model.WaitForConditionResult;
import software.amazon.lambda.durable.exception.WaitForConditionFailedException;

// Define state class for job polling
record JobState(String jobId, String status, String result) {}

public class JobHandler extends DurableHandler<JobRequest, JobResult> {
    @Override
    public JobResult handleRequest(JobRequest event, DurableContext ctx) {
        var jobId = ctx.step("start-job", String.class,
            s -> startBatchJob(event.getData()));
        
        var result = ctx.waitForCondition("poll-job", JobState.class,
            (state, stepCtx) -> {
                // Fetch current job status
                var job = getJobStatus(state.jobId());
                var newState = new JobState(state.jobId(), job.getStatus(), job.getResult());
                
                // Decision logic: stop if not running, continue otherwise
                if (!"running".equals(newState.status())) {
                    return WaitForConditionResult.stopPolling(newState);
                }
                return WaitForConditionResult.continuePolling(newState);
            },
            WaitForConditionConfig.<JobState>builder()
                .initialState(new JobState(jobId, "running", null))
                .waitStrategy((state, attempt) -> {
                    // Compute delay with exponential backoff
                    if (attempt >= 60) {
                        throw new WaitForConditionFailedException("Max polling attempts exceeded");
                    }
                    long delaySeconds = Math.min((long) (5 * Math.pow(1.5, attempt)), 30);
                    return Duration.ofSeconds(delaySeconds);
                })
                .build());
        
        return new JobResult(result.jobId(), result.status(), result.result());
    }
}
```

## Best Practices

1. **Always name wait operations** for debugging
2. **Set appropriate timeouts** to prevent indefinite waits
3. **Use heartbeats** for long-running external processes
4. **Handle callback failures** explicitly
5. **Implement exponential backoff** for polling
6. **Keep check functions lightweight** in waitForCondition
7. **Store callback IDs securely** when sending to external systems
8. **Validate callback payloads** before processing

## Error Handling

**TypeScript:**

```typescript
try {
  const result = await context.waitForCallback(
    'wait-approval',
    async (callbackId) => sendApproval(callbackId),
    { timeout: { hours: 24 } }
  );
} catch (error) {
  if (error instanceof CallbackError) {
    if (error.errorType === 'Timeout') {
      context.logger.warn('Approval timed out');
      // Handle timeout
    } else {
      context.logger.error('Callback failed', error);
      // Handle failure
    }
  }
}
```

**Python:**

```python
from aws_durable_execution_sdk_python.exceptions import CallbackError
from aws_durable_execution_sdk_python.config import WaitForCallbackConfig

try:
    def submit_approval(callback_id: str, ctx):
        send_approval(callback_id)

    result = context.wait_for_callback(
        submitter=submit_approval,
        name='wait-approval',
        config=WaitForCallbackConfig(timeout=Duration.from_hours(24))
    )
except CallbackError as error:
    if error.error_type == 'Timeout':
        context.logger.warn('Approval timed out')
    else:
        context.logger.error('Callback failed', error)
```

**Java:**

```java
import software.amazon.lambda.durable.config.WaitForCallbackConfig;
import software.amazon.lambda.durable.config.CallbackConfig;
import software.amazon.lambda.durable.exception.CallbackFailedException;
import software.amazon.lambda.durable.exception.CallbackTimeoutException;
import software.amazon.lambda.durable.exception.WaitForConditionFailedException;

try {
    var result = ctx.waitForCallback("wait-approval", ApprovalResult.class,
        (callbackId, stepCtx) -> sendApproval(callbackId),
        WaitForCallbackConfig.builder()
            .callbackConfig(CallbackConfig.builder().timeout(Duration.ofHours(24)).build())
            .build());
} catch (CallbackTimeoutException e) {
    ctx.getLogger().warn("Approval timed out: {}", e.getMessage());
    // Handle timeout
} catch (CallbackFailedException e) {
    ctx.getLogger().error("Callback failed: {}", e.getMessage());
    // Handle failure
} catch (WaitForConditionFailedException e) {
    ctx.getLogger().error("Condition polling failed: {}", e.getMessage());
    // Handle polling failure
}
```
