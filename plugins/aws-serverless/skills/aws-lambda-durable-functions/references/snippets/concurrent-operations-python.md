# Concurrent Operations - Python

## Map with MapConfig

```python
from aws_durable_execution_sdk_python.config import MapConfig, CompletionConfig

items = [1, 2, 3, 4, 5]

def process_item(ctx: DurableContext, item: int, index: int, items: list):
    return ctx.step(process(item), name=f'process-{index}')

results = context.map(
    inputs=items,
    func=process_item,
    name='process-items',
    config=MapConfig(
        max_concurrency=3,
        completion_config=CompletionConfig(
            min_successful=4, tolerated_failure_count=1
        )
    )
)
results.throw_if_error()
all_results = results.get_results()
```

## Parallel with ParallelConfig

```python
from aws_durable_execution_sdk_python.config import ParallelConfig

def fetch_user_data(ctx: DurableContext):
    return ctx.step(fetch_user(user_id))

def fetch_orders_data(ctx: DurableContext):
    return ctx.step(fetch_orders(user_id))

def fetch_prefs_data(ctx: DurableContext):
    return ctx.step(fetch_preferences(user_id))

results = context.parallel(
    [fetch_user_data, fetch_orders_data, fetch_prefs_data],
    name='parallel-ops',
    config=ParallelConfig(max_concurrency=3)
)
user, orders, preferences = results.get_results()
```

## Completion Config

```python
# Tolerated failure percentage
results = context.map(
    inputs=items,
    func=process_item,
    config=MapConfig(
        completion_config=CompletionConfig(tolerated_failure_percentage=10)
    ),
    name='process-batch'
)
```
