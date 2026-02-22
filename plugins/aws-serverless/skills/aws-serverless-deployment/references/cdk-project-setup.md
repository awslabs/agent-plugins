# CDK Project Setup Guide

## SAM vs CDK: When to Use Each

Both SAM and CDK synthesize CloudFormation. Choosing between them is a matter of team preference and project context.

|                          | SAM                                   | CDK                                                       |
| ------------------------ | ------------------------------------- | --------------------------------------------------------- |
| **Language**             | YAML/JSON (declarative)               | TypeScript, Python, Java, Go, C# (imperative)             |
| **Learning curve**       | Lower — close to CloudFormation       | Higher — requires familiarity with a programming language |
| **Local testing**        | `sam local invoke` built-in           | Requires external tools (Localstack, docker)              |
| **Abstraction level**    | Thin layer over CloudFormation        | Rich L2/L3 constructs handle wiring automatically         |
| **Code sharing**         | Template fragments only               | Full reuse via construct libraries (npm, PyPI)            |
| **Loops and conditions** | Limited (`Fn::If`, no loops)          | Native language constructs (`for`, `if`, maps)            |
| **Testing**              | Manual template review                | Unit tests with `aws-cdk-lib/assertions`                  |
| **Best for**             | Lambda-centric apps, teams new to IaC | Large teams building reusable infrastructure patterns     |

**Choose SAM** when your primary concern is Lambda functions and you want `sam local invoke` and the SAM MCP tools.

**Choose CDK** when you have complex infrastructure, want to write reusable construct libraries, prefer a programming-language interface, or your team already uses CDK elsewhere.

Both tools support the `get_iac_guidance` MCP tool for additional context:

```text
get_iac_guidance(iac_tool: "cdk")
```

---

## Getting Started

### Install and Bootstrap

```bash
npm install -g aws-cdk
cdk --version

# One-time account/region bootstrap (creates CDK toolkit stack)
cdk bootstrap aws://ACCOUNT-ID/REGION
```

### Initialize a New Project

```bash
mkdir my-serverless-app && cd my-serverless-app
cdk init app --language typescript
npm install
```

### Project Structure

```text
my-serverless-app/
├── bin/
│   └── my-serverless-app.ts    # App entry point
├── lib/
│   └── my-serverless-app-stack.ts  # Stack definition
├── lambda/
│   └── handler.ts              # Lambda function code
├── test/
│   └── my-serverless-app.test.ts
├── cdk.context.json            # Committed to git — caches lookups
├── cdk.json                    # CDK config
└── tsconfig.json
```

---

## Construct Levels

CDK has three levels of constructs:

| Level             | Description                                                   | Example                           |
| ----------------- | ------------------------------------------------------------- | --------------------------------- |
| __L1 (Cfn_)_*     | Direct CloudFormation resource, 1:1 mapping                   | `CfnFunction`, `CfnTable`         |
| **L2**            | Opinionated wrapper with sensible defaults and helper methods | `Function`, `Table`, `Queue`      |
| **L3 (Patterns)** | Complete patterns that wire multiple resources together       | `LambdaRestApi`, `SqsEventSource` |

**Always prefer L2 constructs.** Use L1 only when a feature is missing from the L2. Use L3 patterns as a starting point, but understand what they create.

---

## Lambda Functions

For CDK Lambda function constructs — `NodejsFunction` (TypeScript/JavaScript with esbuild), `PythonFunction` (alpha, Docker-based), and base `Function` (Java, Go, .NET) — see [cdk-lambda-constructs.md](cdk-lambda-constructs.md).

---

## IAM with `grant*` Methods

CDK L2 constructs expose `grant*` methods that generate least-privilege policies automatically. Prefer these over writing raw `PolicyStatement` objects.

```typescript
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as events from 'aws-cdk-lib/aws-events';

// DynamoDB
table.grantReadWriteData(myFunction);
table.grantReadData(readOnlyFunction);

// S3
bucket.grantRead(myFunction);
bucket.grantPut(myFunction);

// SQS
queue.grantSendMessages(myFunction);
queue.grantConsumeMessages(myFunction);

// EventBridge — put events
eventBus.grantPutEventsTo(myFunction);

// Lambda — invoke another function
otherFunction.grantInvoke(myFunction);

// Secrets Manager
secret.grantRead(myFunction);
```

For resources not covered by `grant*`, add a `PolicyStatement` directly:

```typescript
import * as iam from 'aws-cdk-lib/aws-iam';

myFunction.addToRolePolicy(new iam.PolicyStatement({
  effect: iam.Effect.ALLOW,
  actions: ['bedrock:InvokeModel'],
  resources: [`arn:aws:bedrock:${this.region}::foundation-model/anthropic.claude-3-sonnet*`],
}));
```

---

## Common Serverless Patterns

For CDK code examples of common serverless patterns — API Gateway HTTP API, Lambda Function URL, EventBridge custom bus, DynamoDB table, and SQS queue with Lambda — see [cdk-serverless-patterns.md](cdk-serverless-patterns.md).

---

## Separating Stateful and Stateless Stacks

Stateful resources (databases, queues, S3 buckets, event buses) should be in a separate stack with termination protection. This prevents accidental deletion during routine deployments.

```typescript
// bin/my-app.ts
const app = new cdk.App();

// Stateful stack — deployed once, termination-protected
const stateful = new StatefulStack(app, 'StatefulStack', {
  env: { account: '123456789012', region: 'us-east-1' },
  terminationProtection: true,
});

// Stateless stack — deployed on every code change
const stateless = new StatelessStack(app, 'StatelessStack', {
  env: { account: '123456789012', region: 'us-east-1' },
  // Pass references from stateful stack
  ordersTable: stateful.ordersTable,
  orderEventBus: stateful.orderEventBus,
});
```

```typescript
// lib/stateful-stack.ts
export class StatefulStack extends cdk.Stack {
  public readonly ordersTable: dynamodb.Table;
  public readonly orderEventBus: events.EventBus;

  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    this.ordersTable = new dynamodb.Table(this, 'OrdersTable', {
      // ...
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    this.orderEventBus = new events.EventBus(this, 'OrderEventBus', {
      eventBusName: 'order-events',
    });
  }
}
```

---

## CDK Testing

CDK constructs can be unit tested without deploying. Use `aws-cdk-lib/assertions` with Jest.

```bash
npm install --save-dev jest @types/jest ts-jest
```

```typescript
// test/order-stack.test.ts
import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { OrderStack } from '../lib/order-stack';

describe('OrderStack', () => {
  let template: Template;

  beforeEach(() => {
    const app = new cdk.App();
    const stack = new OrderStack(app, 'TestOrderStack');
    template = Template.fromStack(stack);
  });

  it('creates Lambda function with ARM64 architecture', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Architectures: ['arm64'],
      Runtime: 'nodejs22.x',
    });
  });

  it('grants DynamoDB read-write to order handler', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: Match.arrayWith([
              'dynamodb:GetItem',
              'dynamodb:PutItem',
            ]),
          }),
        ]),
      },
    });
  });

  it('has exactly one DynamoDB table', () => {
    template.resourceCountIs('AWS::DynamoDB::Table', 1);
  });

  it('DynamoDB table has retention policy', () => {
    template.hasResource('AWS::DynamoDB::Table', {
      DeletionPolicy: 'Retain',
    });
  });
});
```

**Assert logical IDs of stateful resources** to catch accidental replacements early — renaming a CDK construct ID causes CloudFormation to delete and recreate the resource:

```typescript
it('orders table logical ID is stable', () => {
  const resources = template.findResources('AWS::DynamoDB::Table');
  expect(Object.keys(resources)).toContain('OrdersTable1234ABCD');  // update if intentionally renamed
});
```

---

## Deployment Workflow

```bash
# Synthesize CloudFormation template (runs assertions, no AWS calls)
cdk synth

# Preview changes before deploying
cdk diff

# Deploy all stacks
cdk deploy --all

# Deploy a specific stack
cdk deploy StatelessStack

# Deploy with approval prompt disabled (CI/CD)
cdk deploy --require-approval never

# Destroy a stack (respects RemovalPolicy — RETAIN resources are kept)
cdk destroy StatelessStack
```

---

## CDK Pipelines (CI/CD)

CDK Pipelines is a self-mutating CI/CD pipeline construct built on CodePipeline.

```typescript
import { CodePipeline, CodePipelineSource, ManualApprovalStep, ShellStep } from 'aws-cdk-lib/pipelines';

export class PipelineStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const pipeline = new CodePipeline(this, 'Pipeline', {
      pipelineName: 'MyServerlessPipeline',
      synth: new ShellStep('Synth', {
        input: CodePipelineSource.gitHub('my-org/my-repo', 'main'),
        commands: ['npm ci', 'npm run build', 'npx cdk synth'],
      }),
    });

    // Staging stage
    pipeline.addStage(new MyAppStage(this, 'Staging', {
      env: { account: '111111111111', region: 'us-east-1' },
    }));

    // Production stage with manual approval
    pipeline.addStage(new MyAppStage(this, 'Production', {
      env: { account: '222222222222', region: 'us-east-1' },
    }), {
      pre: [new ManualApprovalStep('PromoteToProduction')],
    });
  }
}
```

The pipeline updates itself: when you push changes to the pipeline stack, the next run applies them before deploying the application.

---

## SAM and CDK Coexistence

For guidance on running SAM and CDK side by side — incremental migration, using `sam build` on CDK-synthesized templates, and when to use which — see [sam-cdk-coexistence.md](sam-cdk-coexistence.md).

---

## Best Practices

### Do

- Use TypeScript — type checking catches errors at synthesis time, before any AWS API calls
- Prefer L2 constructs and `grant*` methods over L1 and raw IAM statements
- Never hardcode resource names — always reference generated names (`table.tableName`, `queue.queueUrl`)
- Separate stateful and stateless resources into different stacks; enable termination protection on stateful stacks
- Commit `cdk.context.json` to version control — it caches VPC/AZ lookups for deterministic synthesis
- Write unit tests with `aws-cdk-lib/assertions`; assert logical IDs of stateful resources to detect accidental replacements
- Set `RemovalPolicy.RETAIN` on all databases, S3 buckets, and event buses
- Use `cdk diff` in CI before every deployment to review changes
- Pass all configuration to constructs via props; never read environment variables inside construct constructors

### Don't

- Hardcode account IDs or region strings — use `this.account` and `this.region`
- Use `cdk deploy` directly in production without a pipeline
- Skip `cdk bootstrap` — deployments will fail without the CDK toolkit stack
- Rely on CloudFormation `Parameters` and `Conditions` when you can express the same logic in TypeScript
- Mix `RemovalPolicy.DESTROY` into shared/stateful stacks
- Reference constructs across separate CDK apps using CloudFormation outputs if you can pass object references directly
