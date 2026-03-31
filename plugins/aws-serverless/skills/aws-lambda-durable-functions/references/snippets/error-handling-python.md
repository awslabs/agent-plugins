# Error Handling - Python

## Retry Configuration

```python
from aws_durable_execution_sdk_python.retries import RetryStrategyConfig, create_retry_strategy, JitterStrategy
from aws_durable_execution_sdk_python.config import StepConfig, Duration

retry_config = RetryStrategyConfig(
    max_attempts=5, initial_delay=Duration.from_seconds(1),
    max_delay=Duration.from_seconds(60), backoff_rate=2.0,
    jitter_strategy=JitterStrategy.FULL
)
result = context.step(
    func=api_call(), config=StepConfig(retry_strategy=create_retry_strategy(retry_config))
)
```

## Custom Retry

```python
from aws_durable_execution_sdk_python.retries import RetryDecision

def custom_retry(error: Exception, attempt: int) -> RetryDecision:
    if hasattr(error, 'status_code') and 400 <= error.status_code < 500:
        return RetryDecision(should_retry=False)
    if attempt < 5:
        return RetryDecision(should_retry=True, delay=Duration.from_seconds(2 ** attempt))
    return RetryDecision(should_retry=False)

result = context.step(risky_operation(), config=StepConfig(retry_strategy=custom_retry))
```

## Error Classification

```python
retry_config = RetryStrategyConfig(
    max_attempts=3, retryable_error_types=[NetworkError, TimeoutError]
)
```

## Saga Pattern

```python
@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    compensations = []
    try:
        reservation = context.step(reserve_inventory(event['items']))
        compensations.append(('cancel-reservation', cancel_reservation, reservation['id']))
        payment = context.step(charge_payment(event['payment_method'], event['amount']))
        compensations.append(('refund-payment', refund_payment, payment['id']))
        shipment = context.step(create_shipment(event['address'], event['items']))
        return {'success': True, 'order_id': shipment['order_id']}
    except Exception as error:
        context.logger.error('Order failed, executing compensations', error)
        for name, comp_step, resource_id in reversed(compensations):
            try:
                context.step(comp_step(resource_id))
            except Exception as comp_error:
                context.logger.error(f'Compensation {name} failed', comp_error)
        raise error
```

## Unrecoverable Error

```python
from aws_durable_execution_sdk_python.exceptions import ExecutionError

@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    @durable_step
    def fetch_user_step(step_ctx: StepContext):
        user = fetch_user(event['user_id'])
        if not user:
            raise ExecutionError('User not found')
        return user

    user = context.step(fetch_user_step())
```

## Error Types

```python
try:
    result = context.step(risky_operation())
except ExecutionError as error:
    context.logger.error('Permanent failure: %s', str(error))
except DurableExecutionsError as error:
    context.logger.error('SDK error: %s', str(error))
```
