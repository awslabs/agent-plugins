# Getting Started - Python

## Basic Handler

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

## GenAI Agent (Agentic Loop)

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

## Human-in-the-Loop Approval

```python
from aws_durable_execution_sdk_python.config import WaitForCallbackConfig

@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    # Note: generate_plan and perform_action are decorated with @durable_step
    plan = context.step(generate_plan(event))

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
