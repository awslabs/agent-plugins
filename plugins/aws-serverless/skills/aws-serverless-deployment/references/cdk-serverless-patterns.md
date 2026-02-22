# CDK Serverless Patterns

Common CDK patterns for serverless applications. Each example uses L2 constructs with `grant*` methods for least-privilege IAM.

## API Gateway HTTP API + Lambda

```typescript
import * as apigwv2 from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';

const api = new apigwv2.HttpApi(this, 'OrderApi', {
  corsPreflight: {
    allowOrigins: ['https://myapp.example.com'],
    allowMethods: [apigwv2.CorsHttpMethod.GET, apigwv2.CorsHttpMethod.POST],
    allowHeaders: ['Content-Type', 'Authorization'],
  },
});

api.addRoutes({
  path: '/orders',
  methods: [apigwv2.HttpMethod.POST],
  integration: new HttpLambdaIntegration('CreateOrder', createOrderFunction),
});

new cdk.CfnOutput(this, 'ApiUrl', { value: api.apiEndpoint });
```

## Lambda Function URL

```typescript
const fnUrl = myFunction.addFunctionUrl({
  authType: lambda.FunctionUrlAuthType.NONE,   // or AWS_IAM
  invokeMode: lambda.InvokeMode.RESPONSE_STREAM,  // for streaming
  cors: {
    allowedOrigins: ['https://myapp.example.com'],
    allowedMethods: [lambda.HttpMethod.POST],
  },
});

new cdk.CfnOutput(this, 'FunctionUrl', { value: fnUrl.url });
```

## EventBridge Custom Bus + Rule

```typescript
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sqs from 'aws-cdk-lib/aws-sqs';

const orderEventBus = new events.EventBus(this, 'OrderEventBus', {
  eventBusName: 'order-events',
});

// Archive all events for replay
new events.Archive(this, 'OrderEventArchive', {
  sourceEventBus: orderEventBus,
  archiveName: 'order-events-archive',
  retention: cdk.Duration.days(30),
  eventPattern: { source: ['com.mycompany.orders'] },
});

// DLQ for the rule target
const processDlq = new sqs.Queue(this, 'ProcessOrderDLQ', {
  retentionPeriod: cdk.Duration.days(14),
});

// Rule routing to Lambda
new events.Rule(this, 'OrderPlacedRule', {
  eventBus: orderEventBus,
  eventPattern: {
    source: ['com.mycompany.orders'],
    detailType: ['OrderPlaced'],
  },
  targets: [
    new targets.LambdaFunction(processOrderFunction, {
      retryAttempts: 3,
      maxEventAge: cdk.Duration.hours(1),
      deadLetterQueue: processDlq,
    }),
  ],
});

// Allow publisher to send events to the bus
orderEventBus.grantPutEventsTo(publisherFunction);
```

## DynamoDB Table + Lambda

```typescript
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';

const ordersTable = new dynamodb.Table(this, 'OrdersTable', {
  partitionKey: { name: 'orderId', type: dynamodb.AttributeType.STRING },
  sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
  billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
  removalPolicy: cdk.RemovalPolicy.RETAIN,   // never delete in production
  pointInTimeRecoverySpecification: {
    pointInTimeRecoveryEnabled: true,
  },
});

ordersTable.addGlobalSecondaryIndex({
  indexName: 'ByUserId',
  partitionKey: { name: 'userId', type: dynamodb.AttributeType.STRING },
  sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
});

// Least-privilege: read-write for the handler
ordersTable.grantReadWriteData(orderHandler);

// Pass table name via environment (never hardcode)
orderHandler.addEnvironment('TABLE_NAME', ordersTable.tableName);
```

## SQS Queue + Lambda ESM

```typescript
import * as sqs from 'aws-cdk-lib/aws-sqs';
import { SqsEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';

const orderQueue = new sqs.Queue(this, 'OrderQueue', {
  visibilityTimeout: cdk.Duration.seconds(90),  // >= function timeout
});

const dlq = new sqs.Queue(this, 'OrderDLQ', {
  retentionPeriod: cdk.Duration.days(14),
});

orderQueue.addDeadLetterQueue({
  queue: dlq,
  maxReceiveCount: 3,
});

orderHandler.addEventSource(new SqsEventSource(orderQueue, {
  batchSize: 10,
  reportBatchItemFailures: true,  // partial batch success
  filters: [
    lambda.FilterCriteria.filter({
      body: { eventType: lambda.FilterRule.isEqual('ORDER_CREATED') },
    }),
  ],
}));
```
