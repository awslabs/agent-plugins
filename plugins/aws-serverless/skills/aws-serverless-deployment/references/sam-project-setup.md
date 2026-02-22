# SAM Project Setup Guide

## Template Selection

Choose the right template based on your use case:

| Template                     | Best For                                  |
| ---------------------------- | ----------------------------------------- |
| `hello-world`                | Basic Lambda function with API Gateway    |
| `quick-start-web`            | Web application with frontend and backend |
| `quick-start-cloudformation` | Infrastructure-focused templates          |
| `quick-start-scratch`        | Minimal template for custom builds        |

Use `get_serverless_templates` to browse additional templates from Serverless Land for specific patterns (e.g., API + DynamoDB, step functions, event processing).

## Runtime Selection

| Runtime      | Best For                                             |
| ------------ | ---------------------------------------------------- |
| Python 3.12  | Data processing, ML workloads, scripting             |
| Node.js 22.x | Web APIs, real-time applications                     |
| Java 21      | Enterprise applications, high-performance computing  |
| Go 1.x       | Microservices, high-concurrency, low-latency         |
| .NET 8       | Windows-centric applications, enterprise integration |

**Architecture:** Choose `arm64` (Graviton) for better price-performance unless you have x86-specific dependencies.

## Project Structure

```text
my-serverless-app/
├── template.yaml          # SAM template
├── samconfig.toml         # Deployment configuration
├── src/                   # Function source code
│   ├── handlers/          # Lambda function handlers
│   ├── layers/            # Shared layers
│   └── utils/             # Utility functions
├── events/                # Test event files
└── tests/                 # Unit and integration tests
```

**Testability tip:** Extract pure business logic (calculations, validations, decisions) into plain functions that don't import the AWS SDK. This lets you unit test core logic without mocking — reserve mocks for the handler-level tests that exercise SDK calls.

## Template Configuration

### Global Settings

Set global defaults in `template.yaml` to apply to all functions:

```yaml
Globals:
  Function:
    Timeout: 30
    MemorySize: 512
    Runtime: python3.12
    Tracing: Active
    Environment:
      Variables:
        LOG_LEVEL: INFO
        POWERTOOLS_SERVICE_NAME: my-service
```

### Environment Parameters

Use CloudFormation parameters to make templates environment-aware:

```yaml
Parameters:
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
```

Reference `!Ref Environment` in resource names and configuration to differentiate stacks.

## Development Workflow

### 1. Initialize

Use `sam_init` with chosen runtime, template, and dependency manager.

### 2. Develop

Write handler code in `src/handlers/`. Create test events in `events/`.

**Python API handler:**

```python
import json
import os
import boto3
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.event_handler import APIGatewayRestResolver

logger = Logger()
tracer = Tracer()
app = APIGatewayRestResolver()

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])

@app.get("/orders/<order_id>")
@tracer.capture_method
def get_order(order_id: str):
    result = table.get_item(Key={"orderId": order_id})
    item = result.get("Item")
    if not item:
        raise app.not_found()
    return item

@app.post("/orders")
@tracer.capture_method
def create_order():
    body = app.current_event.json_body
    table.put_item(Item=body)
    return {"orderId": body["orderId"]}, 201

@logger.inject_lambda_context
@tracer.capture_lambda_handler
def handler(event, context):
    return app.resolve(event, context)
```

**TypeScript API handler:**

```typescript
import { Logger } from '@aws-lambda-powertools/logger';
import { Tracer } from '@aws-lambda-powertools/tracer';
import type { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, PutCommand } from '@aws-sdk/lib-dynamodb';

const logger = new Logger();
const tracer = new Tracer();
const client = tracer.captureAWSv3Client(DynamoDBDocumentClient.from(new DynamoDBClient({})));
const tableName = process.env.TABLE_NAME!;

export const handler = async (event: APIGatewayProxyEvent, context: Context): Promise<APIGatewayProxyResult> => {
  logger.addContext(context);
  const { httpMethod, pathParameters, body } = event;

  if (httpMethod === 'GET' && pathParameters?.orderId) {
    const result = await client.send(new GetCommand({
      TableName: tableName,
      Key: { orderId: pathParameters.orderId },
    }));
    if (!result.Item) {
      return { statusCode: 404, body: JSON.stringify({ message: 'Not found' }) };
    }
    return { statusCode: 200, body: JSON.stringify(result.Item) };
  }

  if (httpMethod === 'POST' && body) {
    const item = JSON.parse(body);
    await client.send(new PutCommand({ TableName: tableName, Item: item }));
    return { statusCode: 201, body: JSON.stringify({ orderId: item.orderId }) };
  }

  return { statusCode: 400, body: JSON.stringify({ message: 'Bad request' }) };
};
```

### 3. Build

Use `sam_build` before every deployment. Use `--use-container` for consistent builds with Lambda-compatible dependencies.

### 4. Test Locally

Use `sam_local_invoke` with a test event to validate before deploying.

### 5. Deploy

Use `sam_deploy` with `guided: true` for the first deploy, which generates `samconfig.toml`. For subsequent deploys, `sam_deploy` reads from `samconfig.toml`.

### 6. Monitor

Use `sam_logs` to check function output. Use `get_metrics` to monitor health.

## Deployment Strategies

### Canary and Linear Deployments

For production APIs, use SAM's built-in `DeploymentPreference` to shift traffic gradually and automatically roll back on errors. This uses CodeDeploy and Lambda aliases under the hood.

```yaml
Globals:
  Function:
    AutoPublishAlias: live

Resources:
  MyFunction:
    Type: AWS::Serverless::Function
    Properties:
      DeploymentPreference:
        Type: Canary10Percent5Minutes  # 10% for 5 min, then 100%
        Alarms:
          - !Ref MyFunctionErrorAlarm
```

**Available deployment types:**

| Type                            | Traffic shift pattern                            |
| ------------------------------- | ------------------------------------------------ |
| `AllAtOnce`                     | Immediate full cutover (no safety, dev/test use) |
| `Canary10Percent5Minutes`       | 10% for 5 min, then 100%                         |
| `Canary10Percent30Minutes`      | 10% for 30 min, then 100%                        |
| `Linear10PercentEvery1Minute`   | +10% every minute                                |
| `Linear10PercentEvery10Minutes` | +10% every 10 min                                |

Set `DeploymentPreference.Alarms` to a CloudWatch alarm on error rate. CodeDeploy automatically rolls back if the alarm fires during the shift window.

## Lambda Layers

Layers let you share code and dependencies across functions without including them in each deployment package.

**When to use layers:**

- Shared business logic used by multiple functions
- Large dependencies (e.g., pandas, Pillow) you want to cache separately
- AWS Lambda Powertools (AWS provides a managed layer ARN per runtime/region)

**Add a layer in SAM template:**

```yaml
MyLayer:
  Type: AWS::Serverless::LayerVersion
  Properties:
    LayerName: my-shared-utils
    ContentUri: layers/shared-utils/
    CompatibleRuntimes:
      - python3.12
    RetentionPolicy: Retain

MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    Layers:
      - !Ref MyLayer
```

**Limits:** Maximum 5 layers per function. Total uncompressed size of function + layers must be under 250 MB.

## Container Images

Lambda supports container images up to 10 GB as a first-class deployment model alongside zip packages.

### When to Use Container Images

| Criterion                | Zip Package         | Container Image                                 |
| ------------------------ | ------------------- | ----------------------------------------------- |
| Max size                 | 250 MB uncompressed | 10 GB                                           |
| Custom OS dependencies   | Limited (layers)    | Full control via Dockerfile                     |
| Existing Docker workflow | N/A                 | Reuse Dockerfiles and CI pipelines              |
| Cold start               | Faster baseline     | Slower baseline, mitigated by SOCI              |
| Local testing            | `sam local invoke`  | `sam local invoke` (Docker required either way) |

Use container images when your deployment package exceeds 250 MB (ML models, large native dependencies), you need OS-level packages not available in Lambda runtimes, or your team already has Docker build pipelines.

### Dockerfile Examples

**Python (multi-stage build):**

```dockerfile
FROM public.ecr.aws/lambda/python:3.12 AS builder
COPY requirements.txt .
RUN pip install --target /asset -r requirements.txt

FROM public.ecr.aws/lambda/python:3.12
COPY --from=builder /asset ${LAMBDA_TASK_ROOT}
COPY src/ ${LAMBDA_TASK_ROOT}/
CMD ["app.handler"]
```

**Node.js:**

```dockerfile
FROM public.ecr.aws/lambda/nodejs:22
COPY package.json package-lock.json ${LAMBDA_TASK_ROOT}/
RUN npm ci --omit=dev
COPY src/ ${LAMBDA_TASK_ROOT}/
CMD ["app.handler"]
```

### SAM Template Configuration

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    PackageType: Image
    Architectures: [arm64]
    MemorySize: 512
    Timeout: 30
  Metadata:
    Dockerfile: Dockerfile
    DockerContext: ./src
    DockerTag: latest
```

SAM builds the image locally during `sam build` and pushes it to ECR during `sam deploy`. No manual `docker push` needed.

### Seekable OCI (SOCI) Lazy Loading

Container images have longer cold starts than zip because Lambda must download the full image before starting. SOCI creates an index that enables lazy loading — Lambda pulls only the layers needed at startup and fetches the rest in the background.

```bash
# Create a SOCI index for an existing ECR image
aws soci create-index --image-uri 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-function:latest
```

SOCI is most beneficial for images larger than 250 MB. For smaller images, the overhead of maintaining the index may not be worthwhile.

### Best Practices

- [ ] Use multi-stage builds to minimize final image size — install build dependencies in a builder stage, copy only artifacts to the final stage
- [ ] Use AWS base images (`public.ecr.aws/lambda/*`) — they include the Lambda runtime interface client
- [ ] Choose `arm64` architecture for the same 20% cost savings as zip deployments
- [ ] Pin base image tags to specific versions in production (e.g., `python:3.12.2024.11.22` not `python:3.12`)
- [ ] Create SOCI indexes for images larger than 250 MB to reduce cold starts

## Configuration Management

### samconfig.toml

Use environment-specific sections:

```toml
[default.deploy.parameters]
stack_name = "my-serverless-app"
region = "us-east-1"
capabilities = "CAPABILITY_IAM"

[dev.deploy.parameters]
stack_name = "my-app-dev"
parameter_overrides = "Environment=dev LogLevel=DEBUG"

[prod.deploy.parameters]
stack_name = "my-app-prod"
parameter_overrides = "Environment=prod LogLevel=WARN"
```

Deploy to a specific environment with `sam_deploy` using `config_env: prod`.

## Security

- Follow least-privilege IAM: scope each function's role to only the actions and resources it needs
- Use `AWSLambdaBasicExecutionRole` managed policy for CloudWatch logging
- Add VPC configuration only when the function needs access to VPC resources (RDS, ElastiCache)
- Store secrets in Secrets Manager or SSM Parameter Store

## Testing

### Serverless Testing Pyramid

| Level                 | What it tests                 | Speed                  | AWS dependency |
| --------------------- | ----------------------------- | ---------------------- | -------------- |
| **Unit**              | Handler logic, business rules | Fast (ms)              | None (mocked)  |
| **Local integration** | Function + event shape        | Medium (seconds)       | Docker only    |
| **Cloud integration** | Function + real AWS services  | Slow (seconds-minutes) | Full           |
| **End-to-end**        | Complete request path         | Slowest                | Full           |

Invest most effort in unit tests. Use local integration to catch event shape mismatches. Reserve cloud tests for verifying IAM, networking, and service integration behavior.

### Unit Testing

Mock all AWS SDK calls. Use the Arrange-Act-Assert pattern.

**Python (pytest):**

```python
from unittest.mock import MagicMock, patch

def test_get_order_returns_item():
    # Arrange
    mock_table = MagicMock()
    mock_table.get_item.return_value = {"Item": {"orderId": "ord-1", "status": "active"}}

    with patch("src.handlers.orders.table", mock_table):
        from src.handlers.orders import app
        event = {"httpMethod": "GET", "pathParameters": {"orderId": "ord-1"}}
        # Act
        result = app.resolve(event, {})
        # Assert
        assert result["statusCode"] == 200
```

**TypeScript (jest + aws-sdk-client-mock):**

```typescript
import { handler } from '../src/handlers/orders';
import { mockClient } from 'aws-sdk-client-mock';
import { DynamoDBDocumentClient, GetCommand } from '@aws-sdk/lib-dynamodb';

const ddbMock = mockClient(DynamoDBDocumentClient);

afterEach(() => ddbMock.reset());

it('should return order when it exists', async () => {
  // Arrange
  ddbMock.on(GetCommand).resolves({ Item: { orderId: 'ord-1', status: 'active' } });
  const event = { httpMethod: 'GET', pathParameters: { orderId: 'ord-1' } } as any;
  // Act
  const result = await handler(event, {} as any);
  // Assert
  expect(result.statusCode).toBe(200);
});
```

### Local Integration Testing

```bash
# Generate a test event template
sam local generate-event s3 put --bucket my-bucket --key uploads/test.jpg > events/s3_put.json

# Invoke locally with the generated event
sam local invoke MyFunction --event events/s3_put.json

# Enable Powertools dev mode for verbose local output
sam local invoke MyFunction --event events/test.json \
  --env-vars <(echo '{"MyFunction": {"POWERTOOLS_DEV": "true"}}')
```

`sam local generate-event` supports all Lambda event sources (s3, sqs, sns, kinesis, dynamodb, apigateway, etc.). Use it instead of hand-crafting event JSON.

### Cloud Integration Testing

Local testing cannot fully replicate IAM policies, VPC networking, or service integrations. Use cloud-based testing for these.

```bash
# Test a deployed function directly
sam remote invoke MyFunction --stack-name my-app-dev --event-file events/test.json

# Deploy an ephemeral stack for PR testing
sam deploy --config-env ci \
  --parameter-overrides "Environment=pr-${PR_NUMBER}" \
  --stack-name "my-app-pr-${PR_NUMBER}"

# Tear down after tests pass
aws cloudformation delete-stack --stack-name "my-app-pr-${PR_NUMBER}"
```

Ephemeral stacks (one per PR) provide full isolation between test runs without polluting shared environments.

### Testing Checklist

- [ ] Mock all AWS SDK calls in unit tests — never call real AWS services
- [ ] Keep test events in `events/` for repeatability
- [ ] Use `sam local generate-event` rather than hand-crafting event JSON
- [ ] Set `POWERTOOLS_DEV=true` locally for verbose structured log output
- [ ] Run unit tests in CI on every commit; cloud integration tests on PR merge
- [ ] Use ephemeral stacks for integration testing to avoid environment conflicts
