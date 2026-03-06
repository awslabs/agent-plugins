# CDK Lambda Function Constructs

CDK provides specialized constructs for defining Lambda functions. Always prefer the runtime-specific L2 constructs (`NodejsFunction`, `PythonFunction`) over the base `Function` when available — they handle bundling automatically.

## Node.js — `NodejsFunction`

The `NodejsFunction` construct bundles TypeScript/JavaScript with esbuild automatically. No separate build step needed.

```typescript
import * as cdk from 'aws-cdk-lib';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { Duration } from 'aws-cdk-lib';

export class MyStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const orderHandler = new NodejsFunction(this, 'OrderHandler', {
      entry: 'lambda/order-handler.ts',   // path to TypeScript entry file
      handler: 'handler',                 // exported function name
      runtime: lambda.Runtime.NODEJS_24_X,
      architecture: lambda.Architecture.ARM_64,  // ~20% cheaper than x86_64
      memorySize: 512,
      timeout: Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        TABLE_NAME: myTable.tableName,    // reference, not hardcoded string
      },
      bundling: {
        minify: true,
        sourceMap: true,
        externalModules: ['@aws-sdk/*'],  // exclude AWS SDK (provided by runtime)
      },
    });
  }
}
```

**Entry auto-detection:** If `entry` is omitted, CDK looks for `{stack-filename}.{construct-id}.ts` next to the stack file.

**Handler resolution:** `"handler"` (no dot) resolves to `"index.handler"`.

## Python — `PythonFunction` (Alpha)

`PythonFunction` is in a separate alpha package and requires Docker for bundling.

```bash
npm install @aws-cdk/aws-lambda-python-alpha
```

```typescript
import { PythonFunction } from '@aws-cdk/aws-lambda-python-alpha';
import * as lambda from 'aws-cdk-lib/aws-lambda';

const orderHandler = new PythonFunction(this, 'OrderHandler', {
  entry: 'lambda/order-handler',   // directory containing index.py
  index: 'index.py',               // default
  handler: 'handler',              // default
  runtime: lambda.Runtime.PYTHON_3_14,
  architecture: lambda.Architecture.ARM_64,
  memorySize: 512,
  timeout: Duration.seconds(30),
  tracing: lambda.Tracing.ACTIVE,
  environment: {
    TABLE_NAME: myTable.tableName,
  },
});
```

The `entry` directory should contain a `requirements.txt`, `Pipfile`, or `pyproject.toml`. Docker must be running during `cdk synth` and `cdk deploy`.

> **Alpha warning:** `@aws-cdk/aws-lambda-python-alpha` can introduce breaking changes without a major version bump. Pin the exact version and test after upgrades.

## Other Runtimes — Base `Function`

For Java, Go, .NET, or custom runtimes, use the base `Function` construct with `Code.fromAsset()`:

```typescript
import * as lambda from 'aws-cdk-lib/aws-lambda';

const orderHandler = new lambda.Function(this, 'OrderHandler', {
  code: lambda.Code.fromAsset('build/distributions/order-handler.zip'),
  handler: 'com.example.OrderHandler::handleRequest',
  runtime: lambda.Runtime.JAVA_21,
  architecture: lambda.Architecture.ARM_64,
  memorySize: 1024,
  timeout: Duration.seconds(60),
  snapStart: lambda.SnapStartConf.ON_PUBLISHED_VERSIONS,  // Java 11+
  tracing: lambda.Tracing.ACTIVE,
});
```
