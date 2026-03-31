# Replay Model Rules - Python

## Wrong - Non-Deterministic Outside Steps

```python
id = str(uuid.uuid4())                   # Different UUID each time
timestamp = time.time()                  # Different timestamp each time
random_val = random.random()             # Different random number
context.step(lambda _: save_data({"id": id}), name='save')
```

## Correct - Non-Deterministic Inside Steps

```python
id = context.step(lambda _: str(uuid.uuid4()), name='generate-id')
timestamp = context.step(lambda _: time.time(), name='get-time')
random_val = context.step(lambda _: random.random(), name='random')
context.step(lambda _: save_data({"id": id}), name='save')
```

## Wrong - Nested Operations

```python
@durable_step
def process(step_ctx: StepContext):
    context.wait(duration=Duration.from_seconds(1))  # ERROR!
    context.step(lambda _: ..., name='nested')       # ERROR!
    return result

context.step(process())
```

## Correct - Child Context

```python
def process_child(child_ctx: DurableContext):
    child_ctx.wait(duration=Duration.from_seconds(1))
    step1 = child_ctx.step(validate())
    step2 = child_ctx.step(process(step1))
    return step2

context.run_in_child_context(func=process_child, name='process')
```

## Wrong - Closure Mutations

```python
counter = 0
@durable_step
def increment(step_ctx: StepContext):
    nonlocal counter
    counter += 1  # This mutation is lost on replay!

context.step(increment())
print(counter)  # Always 0 on replay!
```

## Correct - Return Values

```python
counter = 0
counter = context.step(lambda _: counter + 1, name='increment')
print(counter)  # Correct value
```

## Wrong - Side Effects Outside Steps

```python
print('Starting process')            # Prints multiple times!
send_email(user.email)               # Sends multiple emails!
context.step(lambda _: process(), name='process')
```

## Correct - Side Effects In Steps

```python
context.logger.info('Starting process')  # Deduplicated automatically
context.step(send_email(user.email))
context.step(process())
```
