# Step Operations - Python

## Decorator Step (Recommended)

```python
from aws_durable_execution_sdk_python import durable_step, StepContext

@durable_step
def fetch_user(step_ctx: StepContext, user_id: str):
    return fetch_user_from_api(user_id)

result = context.step(fetch_user(user_id))
```

## Inline Lambda Step

```python
result = context.step(func=lambda step_ctx: fetch_user_from_api(user_id), name='fetch-user')
```

## Retry Configuration

```python
from aws_durable_execution_sdk_python.config import StepConfig, Duration
from aws_durable_execution_sdk_python.retries import RetryStrategyConfig, create_retry_strategy, JitterStrategy

retry_config = RetryStrategyConfig(
    max_attempts=5, initial_delay=Duration.from_seconds(5),
    max_delay=Duration.from_seconds(60), backoff_rate=2.0, jitter_strategy=JitterStrategy.FULL
)
result = context.step(
    func=api_call(), config=StepConfig(retry_strategy=create_retry_strategy(retry_config))
)
```

## Custom Retry

```python
from aws_durable_execution_sdk_python.retries import RetryDecision

def custom_retry(error: Exception, attempt: int) -> RetryDecision:
    if isinstance(error, ValidationError):
        return RetryDecision(should_retry=False)
    if attempt < 3:
        return RetryDecision(should_retry=True, delay=Duration.from_seconds(2 ** attempt))
    return RetryDecision(should_retry=False)

result = context.step(risky_operation(), config=StepConfig(retry_strategy=custom_retry))
```

## Retryable Error Types

```python
retry_config = RetryStrategyConfig(
    max_attempts=3, retryable_error_types=[NetworkError, TimeoutError]
)
```

## Step Semantics

```python
from aws_durable_execution_sdk_python.config import StepSemantics

result = context.step(
    charge_card(amount), config=StepConfig(step_semantics=StepSemantics.AT_MOST_ONCE_PER_RETRY)
)
```

## Serialization

```python
from dataclasses import dataclass
from datetime import datetime

@dataclass
class User:
    id: str
    name: str
    created_at: datetime

# Python SDK handles dataclass serialization automatically
user = context.step(lambda _: User('123', 'Alice', datetime.now()), name='fetch-user')
```

## Error Handling

```python
try:
    result = context.step(risky_operation())
except DurableExecutionsError as error:
    context.logger.error('SDK error: %s', str(error))
except Exception as error:
    context.logger.error('Application error: %s', str(error))
```
