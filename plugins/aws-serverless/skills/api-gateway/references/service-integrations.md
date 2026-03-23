# AWS Service Integrations

API Gateway integrates directly with AWS services without Lambda. Two implementation approaches:

- **REST API and WebSocket API**: Use `Type: AWS` with VTL mapping templates for full request/response transformation. Supports any AWS service action. Both synchronous (wait for response) and asynchronous (fire-and-forget) patterns
- **HTTP API**: Uses first-class integrations (`Type: AWS_PROXY` with `IntegrationSubtype`) and parameter mapping instead of VTL. Supported subtypes: `EventBridge-PutEvents`, `SQS-SendMessage`, `SQS-ReceiveMessage`, `SQS-DeleteMessage`, `SQS-PurgeQueue`, `Kinesis-PutRecord`, `StepFunctions-StartExecution`, `StepFunctions-StartSyncExecution`, `StepFunctions-StopExecution`, `AppConfig-GetConfiguration`. For services not in this list (DynamoDB, SNS, S3), use Lambda proxy instead. See [Integration subtype reference](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-aws-services-reference.html)

The patterns below cover the most commonly used service integrations. REST API `Type: AWS` can integrate with any AWS service that exposes an HTTP API; the same approach (URI, IAM role, VTL mapping) applies to services not listed here. For HTTP API first-class integrations, the same services apply but use parameter mapping (`$request.body`, `$request.header`, `$request.path`, `$context`) instead of VTL.

## EventBridge Integration

Integrates directly with EventBridge PutEvents API (see [aws-samples/serverless-patterns/apigw-rest-api-eventbridge-sam](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-rest-api-eventbridge-sam)). For a complete SAM template, see [SAM Service Integration Templates — EventBridge](sam-service-integrations.md#direct-aws-service-integration-eventbridge).

- Use `Type: AWS` integration with URI `arn:aws:apigateway:{region}:events:action/PutEvents`
- Set required headers via `RequestParameters` (e.g., `integration.request.header.X-Amz-Target: "'AWSEvents.PutEvents'"`, `integration.request.header.Content-Type: "'application/x-amz-json-1.1'"`). Alternative: set via VTL `$context.requestOverride.header` in the mapping template, but avoid applying the same header in both places ([double-application causes 5XX](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-override-request-response-parameters.html))
- VTL mapping template transforms HTTP requests into EventBridge events. Use `#foreach` to batch multiple events from a single API call
- **Input escaping**: Use `$util.escapeJavaScript($elem.Detail).replaceAll("\\'","'")`, since `escapeJavaScript` over-escapes single quotes which breaks JSON; the `replaceAll` corrects this
- Supports custom event buses (not just default); pass bus name via `!Sub` in the mapping template
- Lambda authorizer can return `custom:clientId` to enrich events with caller identity
- Request validation via API Gateway models
- Use `PassthroughBehavior: NEVER` or `WHEN_NO_TEMPLATES` to reject unmatched content types. Avoid the default `WHEN_NO_MATCH` which passes malformed payloads through to the backend service
- EventBridge rules route events to Kinesis Data Firehose, Lambda, or API destinations
- **Gotcha**: EventBridge does not add newlines between records when forwarding to Firehose; use `\n` in InputTemplate
- **Gotcha**: `PutEvents` can succeed (200) with `FailedEntryCount > 0` (partial failures are silent). Check `$input.path('$.FailedEntryCount')` in the response template and return an error status if non-zero

## SQS Integration (Async Buffer)

Integrates directly with SQS SendMessage API to decouple producers from consumers (see [aws-samples/serverless-patterns/apigw-sqs-lambda-iot](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-sqs-lambda-iot)). For a complete SAM template, see [SAM Service Integration Templates — SQS](sam-service-integrations.md#direct-aws-service-integration-sqs).

- Use `Type: AWS` integration with URI `arn:aws:apigateway:{region}:sqs:path/{account-id}/{queue-name}`
- Two protocol options:
  - **AWS query protocol**: Set `Content-Type: 'application/x-www-form-urlencoded'` header in integration request. Mapping template: `Action=SendMessage&MessageBody=$util.urlEncode($input.body)`
  - **AWS JSON protocol**: Set `Content-Type: 'application/x-amz-json-1.0'` and `X-Amz-Target: 'AmazonSQS.SendMessage'` headers. Pass JSON body with `QueueUrl` and `MessageBody`
- Set `PassthroughBehavior: NEVER` to reject requests that don't match any mapping template (returns 415 Unsupported Media Type)
- **Always use `$util.urlEncode()`** with the query protocol; special characters in the message body cause `AccessDenied` errors without encoding
- **FIFO queues**: Append `MessageGroupId` to the mapping template: `Action=SendMessage&MessageGroupId=$context.extendedRequestId&MessageBody=$util.urlEncode($input.body)`. Enable content-based deduplication on the queue, or add `MessageDeduplicationId` explicitly
- **KMS-encrypted queues**: IAM execution role needs `kms:GenerateDataKey` and `kms:Decrypt` on the queue's KMS key, otherwise `KMS.AccessDeniedException`
- Lambda consumer processes messages from SQS at its own pace, with built-in retry and DLQ support

## SNS Integration (Fan-Out / Pub-Sub)

Integrates directly with SNS Publish API for fan-out to multiple subscribers (see [aws-samples/serverless-patterns/apigw-websocket-api-sns](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-websocket-api-sns)):

- Use `Type: AWS` integration with URI `arn:aws:apigateway:{region}:sns:action/Publish`
- Uses AWS query protocol: Set `Content-Type: 'application/x-www-form-urlencoded'` header in integration request
- VTL mapping template: `Action=Publish&TopicArn=$util.urlEncode("${TopicArn}")&Message=$util.urlEncode(...)`; always URL-encode both the TopicArn and Message
- Enrich messages with API Gateway context: `$context.connectionId` (WebSocket), `$context.requestTimeEpoch`, `$context.identity.sourceIp`
- **Request validation**: Use API Gateway models to validate the message body before publishing, ensuring only well-formed messages reach SNS
- Subscribers receive messages independently: Lambda, SQS, HTTP/S endpoints, email, SMS. One API call fans out to all
- **KMS-encrypted topics**: IAM execution role needs `kms:GenerateDataKey` and `kms:Decrypt` on the topic's KMS key
- **Message attributes**: Use indexed query parameters for subscription filter policies: `MessageAttributes.entry.1.Name=eventType&MessageAttributes.entry.1.Value.DataType=String&MessageAttributes.entry.1.Value.StringValue=...`. Required for SNS subscription filtering in fan-out architectures
- **FIFO topics**: Append `MessageGroupId` (required) and optionally `MessageDeduplicationId` to the mapping template, same pattern as SQS FIFO queues
- IAM execution role needs `sns:Publish` scoped to the specific topic ARN

## DynamoDB Integration (Write-Through with Streams)

Integrates directly with DynamoDB APIs for full CRUD without Lambda. For complete SAM templates (OpenAPI-based and inline), see [SAM Service Integration Templates — DynamoDB Full CRUD](sam-service-integrations.md#direct-aws-service-integration-dynamodb-full-crud).

- Use `Type: AWS` integration with URI `arn:aws:apigateway:{region}:dynamodb:action/{action}` (supports `GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Query`, and `Scan`)
- VTL mapping template transforms HTTP request into DynamoDB JSON format:
  - **Request template**: Maps request body/parameters to DynamoDB item attributes with type descriptors (`S`, `N`, `M`, `L`, etc.)
  - **Response template**: Extracts DynamoDB response attributes into clean JSON for the client using `$input.path('$.Item.attribute.S')`
- **Full CRUD pattern** (see [aws-samples/serverless-patterns/apigw-dynamodb-lambda-scheduler-ses-auto-deletion-sam](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-dynamodb-lambda-scheduler-ses-auto-deletion-sam)):
  - **Create**: Use `UpdateItem` (not `PutItem`) with `$context.requestId` as auto-generated ID, eliminating client-side ID generation. Set `ReturnValues: ALL_NEW` to return the created item in the response
  - **Read**: `GetItem` with key from path parameter `$input.params().path.id`
  - **Update**: `UpdateItem` with `UpdateExpression` and `ExpressionAttributeValues` mapped from request body. Use `ReturnValues: ALL_NEW` to return the updated item
  - **Delete**: `DeleteItem` with `ReturnValues: ALL_OLD` to return the deleted item for confirmation
  - **List**: `Scan` with `#foreach` loop in response template to build JSON array from `$inputRoot.Items`. **Always include a `Limit` parameter** in the Scan template (e.g., `"Limit": 25`) to cap items per request; without it, a single API call can scan the entire table, consuming all provisioned capacity. Support pagination via `ExclusiveStartKey` mapped from a query parameter
- **Request validation**: Use `x-amazon-apigateway-request-validator` with OpenAPI schemas to validate request bodies at the gateway before reaching DynamoDB
- **OpenAPI-based definition**: Define the full API in a separate OpenAPI file and include via `AWS::Include` transform in the SAM template, keeping the API definition clean and separates API spec from infrastructure
- For async event processing, enable **DynamoDB Streams** on the table:
  - Stream triggers Lambda function on every insert/update/delete
  - Lambda processes changes asynchronously (enrichment, notifications, scheduling, cross-service sync)
  - Example chain: API Gateway → DynamoDB (Streams) → Lambda → EventBridge Scheduler → SES for scheduled email reminders
  - Stream view type options: `KEYS_ONLY`, `NEW_IMAGE`, `OLD_IMAGE`, `NEW_AND_OLD_IMAGES`; choose based on what the processor needs
- **Gotcha**: DynamoDB reserved keywords (`datetime`, `email`, `status`, `name`, `type`, `data`, etc.) require `ExpressionAttributeNames` with `#placeholder` syntax. This applies in VTL templates too, not just SDK calls
- **Security**: Never interpolate request input into DynamoDB expression strings (`UpdateExpression`, `FilterExpression`, `ProjectionExpression`). Hardcode expression structures in VTL and only map user input into `ExpressionAttributeValues` (`:placeholder` values). Interpolating into expressions allows callers to inject additional clauses that expose unintended attributes or modify other items
- Canary deployments for DynamoDB service integrations are managed at the API Gateway stage level (no Lambda alias to canary)

## Kinesis Data Streams Integration (High-Throughput Ingestion)

Integrates directly with Kinesis Data Streams PutRecord/PutRecords APIs for high-volume data ingestion (see [aws-samples/serverless-patterns/apigw-kinesis-lambda](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-kinesis-lambda)). For a complete SAM template, see [SAM Service Integration Templates — Kinesis Data Streams](sam-service-integrations.md#direct-aws-service-integration-kinesis-data-streams).

- Use `Type: AWS` integration with URI `arn:aws:apigateway:{region}:kinesis:action/{action}` (e.g., `action/PutRecord`, `action/PutRecords`)
- Use `PassthroughBehavior: WHEN_NO_TEMPLATES` to ensure requests are only accepted when a matching mapping template exists
- VTL mapping template constructs the Kinesis payload:
  - `StreamName`: Target stream; can be hardcoded via `!Sub` or dynamic via path parameter (`$input.params('stream-name')`)
  - `Data`: Base64-encoded record data. Use `$util.base64Encode()` in VTL. Encode the full body (`$input.body`) or a specific JSON field (`$input.json('$.Data')`)
  - `PartitionKey`: Determines shard placement. Use a high-cardinality value from the request body (e.g., client ID) for even distribution across shards, or `$context.requestId` as a simple default for uniform distribution
- **PutRecords** for batching: VTL `#foreach` loop transforms an array of items in the request body into multiple Kinesis records in a single API call, reducing round-trips
- **KMS-encrypted streams**: IAM execution role needs `kms:GenerateDataKey` and `kms:Decrypt` on the stream's KMS key
- Downstream consumers: Lambda (event source mapping), Kinesis Data Firehose (delivery to S3/Redshift/OpenSearch), Kinesis Data Analytics, or custom KCL applications
- **Shard limits**: Each shard supports 1,000 records/s or 1 MB/s for writes and 2 MB/s for reads. Plan shard count based on expected ingestion rate. Use on-demand capacity mode to auto-scale shards
- **Gotcha**: `PutRecord` response includes `ShardId` and `SequenceNumber`; map these in the response template for client-side tracking if needed
- **Gotcha**: `PutRecords` can succeed (200) with `FailedRecordCount > 0`. Map `$input.path('$.FailedRecordCount')` in the response template so clients know to retry failed records

## Step Functions Integration (Workflow Orchestration)

Integrates directly with Step Functions to orchestrate multi-step workflows without Lambda glue code. For complete SAM templates (REST and WebSocket), see [SAM Service Integration Templates — Step Functions](sam-service-integrations.md#direct-aws-service-integration-step-functions).

**REST API → Step Functions** (see [aws-samples/serverless-patterns/apigw-rest-stepfunction](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-rest-stepfunction)):

- Two execution modes available:
  - **Asynchronous** (Standard workflow): `action/StartExecution`, which returns execution ARN immediately. Client does not wait for workflow completion. IAM role needs `states:StartExecution`
  - **Synchronous** (Express workflow): `action/StartSyncExecution`, which waits for workflow to complete and returns the result in the response. IAM role needs `states:StartSyncExecution`. Must complete within the API Gateway integration timeout (29s default, up to 300s for Regional/Private)
- VTL mapping template passes the request body as workflow input and the state machine ARN:

  ```velocity
  #set($data = $util.escapeJavaScript($input.json('$')).replaceAll("\\'","'"))
  {
    "input": "$data",
    "stateMachineArn": "${StateMachineArn}"
  }
  ```

**WebSocket API → Step Functions** (see [aws-samples/serverless-samples/apigw-ws-integrations](https://github.com/aws-samples/serverless-samples/tree/main/apigw-ws-integrations)):

- Two execution modes via custom routes matched by `routeSelectionExpression`:
  - **Synchronous** (Express workflow): `action/StartSyncExecution`, which waits for workflow to complete and returns the result directly to the WebSocket client. **Constrained by the 29-second WebSocket API integration timeout**, not the 5-minute Express workflow maximum. Workflows exceeding 29 seconds will time out at the API Gateway level. Use for short-lived workflows where the client needs the result immediately
  - **Asynchronous** (Standard workflow): `action/StartExecution`, which returns the execution ARN immediately. Workflow pushes results back to the WebSocket client via the `@connections` Management API (`POST https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/@connections/{connectionId}`) using an HTTP task state or Lambda task. Pass `$context.connectionId` in the input so the workflow knows which client to notify
- VTL escaping for WebSocket: `$util.escapeJavaScript($input.json("$.data")).replaceAll("\\'","'")` (the `replaceAll` handles single quotes that `escapeJavaScript` over-escapes)
- WebSocket `$connect`/`$disconnect` routes can use direct DynamoDB integration (PutItem/DeleteItem) for connection tracking without Lambda
- IAM roles: `states:StartSyncExecution` for Express, `states:StartExecution` for Standard. Async workflow role also needs `execute-api:ManageConnections` to call back the WebSocket client

**Express vs Standard workflows**:

- **Express** (sync): Max 5 minutes, at-least-once execution, lower cost for high-volume short tasks. Good for synchronous REST/WebSocket responses within the API Gateway timeout
- **Standard** (async): Max 1 year, exactly-once execution, full execution history. Good for long-running orchestrations that push results via callback, webhook, or polling

**Lambda durable functions as alternative**: Durable functions are invoked as regular Lambda integrations (proxy or custom) — no `Type: AWS` service integration or VTL needed. See the [aws-lambda-durable-functions skill](../../aws-lambda-durable-functions/) for details.

## S3 Integration (File Storage Proxy)

Acts as an S3 proxy for file upload, download, and listing without Lambda (see [Developer Guide tutorial](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-s3.html)):

- Use `Type: AWS` integration with `Action type: Use path override`. API Gateway forwards requests to S3 REST API path-style (`s3-host-name/{bucket}/{key}`)
- **Resource structure**: `/{folder}` maps to S3 bucket, `/{folder}/{item}` maps to S3 object. Map path parameters in integration request: `method.request.path.folder` → `{bucket}`, `method.request.path.item` → `{object}`
- **Operations**: GET on `/` lists buckets, GET on `/{folder}` lists objects in a bucket, GET on `/{folder}/{item}` downloads an object, PUT on `/{folder}/{item}` uploads an object
- **Binary files** (images, PDFs, etc.): Register media types in `binaryMediaTypes` (e.g., `image/png`), add `Accept` (download) and `Content-Type` (upload) headers to the method request, leave `contentHandling` unset (passthrough behavior); no mapping template for binary content types
- **Payload limit**: 10 MB max through API Gateway. For larger files, generate S3 presigned URLs via Lambda and have the client upload/download directly to S3 (presigned URLs cannot be generated from a direct service integration; Lambda is required)
- Response header mapping: Map `integration.response.header.Content-Type`, `integration.response.header.Content-Length`, and `integration.response.header.Date` to method response headers for proper content delivery
- S3 objects with `/` or special characters in the key must be URL-encoded in the request path (e.g., `test/test.txt` → `test%2Ftest.txt`)
- IAM execution role needs S3 permissions (`s3:GetObject`, `s3:PutObject`, `s3:ListBucket`) scoped to the specific bucket(s)

## HTTP Integration (Proxy to HTTP Endpoints)

Forwards requests to any HTTP-accessible endpoint: ALB, NLB, ECS, EC2, on-premises servers, or external third-party APIs:

- **Two modes**:
  - `HTTP_PROXY`: Passes request through to the backend as-is and returns the backend response directly to the client. Minimal configuration, no VTL templates. Available on both REST and HTTP APIs
  - `HTTP` (non-proxy): Allows VTL mapping templates to transform request and response. REST API only
- **VPC Link** for private backends: Use `connectionType: VPC_LINK` to reach ALB, NLB, or Cloud Map services inside a VPC without exposing them to the internet. VPC Link v2 supports REST and HTTP APIs (targets ALB and NLB); WebSocket API uses VPC Link v1 (NLB only)
- **Path and parameter passthrough**: Map URL path parameters, query strings, and headers from the method request to the integration request. Use `{proxy+}` greedy path parameter for catch-all routing
- **TLS to backend**: API Gateway validates the backend's TLS certificate by default. If the backend uses a self-signed or private CA certificate, set `insecureSkipVerification: true` on the integration (testing/development only; not recommended for production). Provide the full certificate chain on the backend for proper validation
- **Timeouts**: Configure `timeoutInMillis` on the integration (50ms–29s for REST, 30s hard limit for HTTP API). For backends that may exceed this, consider async patterns
- **Connection reuse**: API Gateway reuses connections to HTTP backends by default for lower latency on subsequent requests
- **No automatic retries**: API Gateway does not retry failed HTTP integration requests. If the backend returns 5xx or the connection times out, the error is returned directly to the client. Implement retry logic on the client side or use SQS as a buffer

## Mock Integration (No Backend)

Returns responses directly from API Gateway without calling any backend:

- Use `Type: MOCK` (no integration URI, no IAM role, no backend needed)
- **Health check endpoints**: Return 200 on `/health` for load balancer or monitoring checks
- **CORS preflight**: Handle `OPTIONS` requests with appropriate CORS headers without invoking Lambda
- **API prototyping**: Define request/response contracts before backends are built. Consumers can develop against the mock
- **Static responses**: Return fixed JSON/XML based on request parameters using VTL mapping templates
- VTL request template must return `{"statusCode": 200}` (or appropriate code) to set the integration response status
- Map different status codes using `IntegrationResponses` with selection patterns

## Common Patterns

- **IAM execution role**: Every direct service integration requires an IAM role with the specific action permission (e.g., `sqs:SendMessage`, `dynamodb:PutItem`, `events:PutEvents`, `kinesis:PutRecord`, `states:StartExecution`). Pass the role ARN in the integration `Credentials` field
- **Request validation at the gateway**: Use API Gateway request validators (models) to reject invalid requests before they reach the backend service, reducing cost and protects downstream services
- **Response mapping**: Transform raw AWS service responses into clean API responses using VTL response templates. Map HTTP status codes for error cases in `IntegrationResponses`
- **Lambda invocations support sync and async**: API Gateway Lambda integrations default to synchronous invocation (wait for response). For asynchronous invocation (fire-and-forget, returns 200 immediately while Lambda processes in background), set `X-Amz-Invocation-Type: 'Event'` in the integration request HTTP headers (see [re:Post guide](https://repost.aws/knowledge-center/api-gateway-invoke-lambda)). Async invocation supports Lambda's built-in retry (up to 2 retries) and dead-letter queues. REST API supports this natively via non-proxy integration; HTTP API only supports proxy integrations for Lambda so `X-Amz-Invocation-Type` cannot be set — use a proxy Lambda that invokes the target Lambda asynchronously via the SDK
- **Prevent backend bypass (zero trust)**: Ensure backends can only be reached through API Gateway, not invoked or accessed directly. Apply defense in depth per integration type:
  - **Lambda**: Restrict Lambda resource policies to allow invocations only from the API Gateway source ARN
  - **VPC Link targets (ALB/NLB)**: Use security groups on the load balancer to accept traffic only from the VPC Link's ENIs, not from arbitrary sources
  - **HTTP integrations**: Use mutual TLS, API keys, or signed requests between API Gateway and the backend to authenticate the caller
  - **Direct service integrations** (SQS, DynamoDB, etc.): The IAM execution role scopes access — ensure the role is only assumable by API Gateway (`apigateway.amazonaws.com` principal) and follows least-privilege for the specific resources
- **Parameter overriding (REST API)**: Override request/response parameters and status codes at method level:
  - `RequestParameters` in Integration: Map method request values to integration request values
  - `ResponseParameters` in IntegrationResponses: Map integration response values to method response values
  - Override response status: `#set($context.responseOverride.status = 400)` in VTL
  - Override request headers: `$context.requestOverride.header.<name>`
  - **Gotcha**: Applying override to same parameter twice causes 5XX. Build in a variable first, apply at end
- **Binary media types**: API Gateway request and response payloads can be text or binary (JPEG, GZip, XML, PDF, etc.). Configure `binaryMediaTypes` on the API, specifying content types treated as binary (e.g., `image/png`, `application/octet-stream`). **Avoid `*/*` wildcard**: it treats ALL responses as binary, breaking Lambda proxy integrations that return JSON:
  - **Lambda proxy integrations**: Lambda must return the response body as base64-encoded and set `isBase64Encoded: true`. The API must have matching `binaryMediaTypes` configured. Client sends `Accept` header matching a binary media type
  - **Non-proxy integrations**: Set `binaryMediaTypes` on the API, or use `contentHandling` on the `Integration` and `IntegrationResponse` resources: `CONVERT_TO_BINARY` (base64-decode text to binary), `CONVERT_TO_TEXT` (base64-encode binary to text), or undefined (passthrough)
- **Local testing limitation**: `sam local start-api` does not support `Type: AWS` service integrations; it only supports Lambda proxy/non-proxy integrations. Test direct service integrations by deploying to a dev stage and using the API Gateway test console (AWS Console → method → Test) to validate VTL mapping templates against sample requests without a full deployment cycle
