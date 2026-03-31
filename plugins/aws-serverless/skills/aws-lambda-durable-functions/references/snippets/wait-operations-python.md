# Wait Operations - Python

## Simple Waits

```python
from aws_durable_execution_sdk_python.config import Duration

context.wait(duration=Duration.from_seconds(30))
context.wait(duration=Duration.from_minutes(5))
context.wait(duration=Duration.from_hours(1))
context.wait(duration=Duration.from_days(7))

# Named wait (recommended)
context.wait(duration=Duration.from_seconds(60), name='rate-limit-delay')
```

## Wait for Callback

```python
from aws_durable_execution_sdk_python.config import WaitForCallbackConfig

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

## Callback Success (boto3)

```python
import boto3
import json

lambda_client = boto3.client('lambda')
lambda_client.send_durable_execution_callback_success(
    CallbackId=callback_id,
    Result=json.dumps({'status': 'approved'})
)
```

## Wait for Condition

```python
from aws_durable_execution_sdk_python.waits import WaitForConditionConfig, create_wait_strategy, WaitStrategyConfig

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

## Error Handling

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
