# Testing Patterns - Python

## Install

```bash
pip install aws-durable-execution-sdk-python-testing pytest
```

## Local Testing

```python
from aws_durable_execution_sdk_python_testing import DurableFunctionTestRunner
from aws_durable_execution_sdk_python.execution import InvocationStatus
from src.my_function import handler

def test_workflow():
    """Test durable function locally."""
    runner = DurableFunctionTestRunner(handler=handler)

    with runner:
        result = runner.run(input={'user_id': '123'}, timeout=10)

    assert result.status is InvocationStatus.SUCCEEDED
```

## Get Steps by Name

```python
from aws_durable_execution_sdk_python.lambda_service import OperationType

def test_steps_execute():
    runner = DurableFunctionTestRunner(handler=handler)

    with runner:
        result = runner.run(input={'test': True}, timeout=10)

    # Get step by name
    fetch_step = result.get_step('fetch-user')
    assert fetch_step is not None

    # Filter operations by type
    step_names = {op.name for op in result.operations if op.operation_type == OperationType.STEP}
    assert step_names >= {'fetch-user', 'process-data'}
```

## Callback Testing

```python
def test_callback_creation():
    runner = DurableFunctionTestRunner(handler=handler)

    with runner:
        result = runner.run(input={'approver': '[email]'}, timeout=10)

    callback_ops = [
        op for op in result.operations
        if op.operation_type == OperationType.CALLBACK
    ]
    assert len(callback_ops) == 1
    assert callback_ops[0].name == 'wait-for-approval'
    assert callback_ops[0].callback_id is not None
```

## Cloud Testing

```bash
export AWS_REGION=us-west-2
export QUALIFIED_FUNCTION_NAME="my-durable-function:$LATEST"
pytest --runner-mode=cloud -k test_workflow
```

```python
from aws_durable_execution_sdk_python_testing import DurableFunctionCloudTestRunner

def test_workflow_cloud():
    runner = DurableFunctionCloudTestRunner(
        function_name='my-function:$LATEST', region='us-west-2'
    )

    with runner:
        result = runner.run(input={'user_id': '123'}, timeout=60)

    assert result.status is InvocationStatus.SUCCEEDED
```
