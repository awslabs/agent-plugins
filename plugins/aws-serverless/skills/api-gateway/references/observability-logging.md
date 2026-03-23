# Observability: Logging

## Execution Logging (REST API and WebSocket)

- Full request/response logs including mapping template output, integration request/response, authorizer output
- Levels: OFF, ERROR, INFO
- **Log events truncated at 1,024 bytes**; use access logs for complete data
- Log group: `API-Gateway-Execution-Logs_<apiId>/<stageName>` (both REST and WebSocket)
- HTTP API does NOT support execution logging
- **Cost warning**: INFO-level execution logging generates many log events per request (10-60+ depending on API complexity: authorizers, mapping templates, and integration details all add entries). At scale, CloudWatch Logs costs can exceed Lambda + API Gateway costs combined. Use ERROR level in production and enable INFO only for targeted debugging

### What API Gateway Does NOT Log

- 413 Request Entity Too Large
- Excessive 429 throttling responses
- 400 errors to unmapped custom domains
- Internal 500 errors from API Gateway itself

## Access Logging

- Customizable log format using `$context` variables
- Formats: CLF, JSON, XML, CSV
- Access log template max: 3 KB
- Destinations: CloudWatch Logs or Kinesis Data Firehose (REST only for Firehose)
- HTTP API: Only access logging supported (no execution logging)
- **Delivery latency**: Access logs can be delayed by several minutes. Use CloudWatch metrics (near-real-time) for dashboards and alarms; use access logs for investigation and deep analysis

## Log Retention

CloudWatch Logs default to **Never Expire**, which causes unbounded storage costs. Always set retention policies:

- **Execution logs (INFO)**: 3-7 days (debugging only, high volume)
- **Execution logs (ERROR)**: 14-30 days
- **Access logs**: 30-90 days (or longer for compliance)
- **Compliance/audit logs**: 1-3 years per organizational policy

Define log groups explicitly in SAM/CloudFormation to control retention:

```yaml
ApiAccessLogGroup:
  Type: AWS::Logs::LogGroup
  Properties:
    LogGroupName: !Sub "/aws/apigateway/${MyApi}/access-logs"
    RetentionInDays: 90
```

## Recommended Access Log Format (REST API)

Use this JSON format for maximum troubleshooting capability with enhanced observability variables:

**Note**: This format is for REST APIs. HTTP API and WebSocket API use different `$context` variables; see the API-specific formats below.

```json
{
  "requestId": "$context.requestId",
  "extendedRequestId": "$context.extendedRequestId",
  "ip": "$context.identity.sourceIp",
  "caller": "$context.identity.caller",
  "user": "$context.identity.user",
  "accountId": "$context.identity.accountId",
  "userAgent": "$context.identity.userAgent",
  "requestTime": "$context.requestTime",
  "requestTimeEpoch": "$context.requestTimeEpoch",
  "httpMethod": "$context.httpMethod",
  "resourcePath": "$context.resourcePath",
  "path": "$context.path",
  "status": "$context.status",
  "protocol": "$context.protocol",
  "responseLength": "$context.responseLength",
  "responseLatency": "$context.responseLatency",
  "integrationLatency": "$context.integrationLatency",
  "domainName": "$context.domainName",
  "apiId": "$context.apiId",
  "stage": "$context.stage",
  "error-message": "$context.error.message",
  "error-responseType": "$context.error.responseType",
  "waf-error": "$context.waf.error",
  "waf-status": "$context.waf.status",
  "waf-latency": "$context.waf.latency",
  "waf-response": "$context.wafResponseCode",
  "authenticate-error": "$context.authenticate.error",
  "authenticate-status": "$context.authenticate.status",
  "authenticate-latency": "$context.authenticate.latency",
  "authorizer-error": "$context.authorizer.error",
  "authorizer-status": "$context.authorizer.status",
  "authorizer-latency": "$context.authorizer.latency",
  "authorizer-integrationLatency": "$context.authorizer.integrationLatency",
  "authorize-error": "$context.authorize.error",
  "authorize-status": "$context.authorize.status",
  "authorize-latency": "$context.authorize.latency",
  "integration-error": "$context.integration.error",
  "integration-status": "$context.integration.status",
  "integration-latency": "$context.integration.latency",
  "integration-requestId": "$context.integration.requestId",
  "integration-integrationStatus": "$context.integration.integrationStatus"
}
```

Key variables explained:

- `requestTimeEpoch`: Epoch-millisecond timestamp. Use for programmatic analysis and Athena queries
- `extendedRequestId`: Maps to `x-amz-apigw-id` header. Needed for AWS Support escalations
- `accountId`: AWS account of the caller. Critical for IAM-authenticated and cross-account APIs
- `error-message`: API Gateway's own error message (e.g., "Authorizer error", "Endpoint request timed out")
- `error-responseType`: Gateway Response type triggered (e.g., `AUTHORIZER_FAILURE`, `INTEGRATION_TIMEOUT`, `THROTTLED`). Categorizes errors without execution logs
- `integration-integrationStatus`: Status code from the Lambda service itself (usually 200 even when the function errors)
- `integration-status`: Status code from your Lambda function code (for proxy integrations)

## HTTP API Access Log Format

HTTP API uses different `$context` variables. Key differences from REST API:

- Uses `$context.routeKey` instead of `$context.resourcePath`
- No WAF, authenticate, or authorize phase variables (HTTP API does not have these phases)
- Authorizer variables are available (HTTP API supports JWT and Lambda authorizers)
- No execution logging; access logs are the only log source

```json
{
  "requestId": "$context.requestId",
  "ip": "$context.identity.sourceIp",
  "userAgent": "$context.identity.userAgent",
  "requestTime": "$context.requestTime",
  "requestTimeEpoch": "$context.requestTimeEpoch",
  "routeKey": "$context.routeKey",
  "path": "$context.path",
  "status": "$context.status",
  "protocol": "$context.protocol",
  "responseLength": "$context.responseLength",
  "responseLatency": "$context.responseLatency",
  "integrationLatency": "$context.integrationLatency",
  "domainName": "$context.domainName",
  "apiId": "$context.apiId",
  "stage": "$context.stage",
  "error-message": "$context.error.message",
  "authorizer-error": "$context.authorizer.error",
  "integration-error": "$context.integration.error",
  "integration-status": "$context.integration.status",
  "integration-latency": "$context.integration.latency",
  "integration-integrationStatus": "$context.integration.integrationStatus"
}
```

## WebSocket API Access Log Format

WebSocket APIs use connection-oriented variables instead of HTTP method/path:

```json
{
  "requestId": "$context.requestId",
  "extendedRequestId": "$context.extendedRequestId",
  "connectionId": "$context.connectionId",
  "eventType": "$context.eventType",
  "routeKey": "$context.routeKey",
  "connectedAt": "$context.connectedAt",
  "requestTime": "$context.requestTime",
  "requestTimeEpoch": "$context.requestTimeEpoch",
  "ip": "$context.identity.sourceIp",
  "userAgent": "$context.identity.userAgent",
  "accountId": "$context.identity.accountId",
  "status": "$context.status",
  "domainName": "$context.domainName",
  "apiId": "$context.apiId",
  "stage": "$context.stage",
  "error-message": "$context.error.message",
  "error-responseType": "$context.error.responseType",
  "authorizer-error": "$context.authorizer.error",
  "authorizer-status": "$context.authorizer.status",
  "authorizer-latency": "$context.authorizer.latency",
  "authorizer-integrationLatency": "$context.authorizer.integrationLatency",
  "integration-error": "$context.integration.error",
  "integration-status": "$context.integration.status",
  "integration-latency": "$context.integration.latency",
  "integration-requestId": "$context.integration.requestId"
}
```

Key WebSocket-specific variables:

- `connectionId`: Unique ID for the persistent WebSocket connection
- `eventType`: `CONNECT`, `MESSAGE`, or `DISCONNECT`
- `routeKey`: The matched route (`$connect`, `$disconnect`, `$default`, or custom route keys)
- `connectedAt`: Epoch timestamp when the connection was established

## Enhanced Observability Variables

API Gateway divides REST API requests into phases: **WAF -> Authenticate -> Authorizer -> Authorize -> Integration**

Each phase exposes `$context.{phase}.status`, `$context.{phase}.latency`, and `$context.{phase}.error`.

**Note on authorizer phase**: The authorizer has both `$context.authorizer.latency` (total authorizer latency) and `$context.authorizer.integrationLatency` (time spent in the authorizer Lambda/Cognito call). The difference is API Gateway overhead for the authorizer phase.

**Diagnosing 403 errors by phase:**

- `$context.waf.status: 403` = WAF blocked the request
- `$context.authenticate.status: 403` = Invalid credentials (e.g., malformed SigV4)
- `$context.authorizer.status: 403` = Lambda authorizer returned Deny policy
- `$context.authorize.status: 403` with `$context.authorize.error: "The client is not authorized"` = Valid credentials but insufficient permissions (resource policy or IAM policy denied)

**Key distinction (Lambda proxy integration):**

- `$context.integration.integrationStatus`: Status code from the Lambda **service** (usually 200 even when the function throws an error)
- `$context.integration.status`: Status code from your Lambda **function code** (the `statusCode` field in your function's response)

## Additional Access Log Variables

- `$context.identity.apiKey`: Track which API keys are making requests
- `$context.identity.accountId`: Identify which AWS account is calling (IAM auth, cross-account)
- `$context.domainName`: Differentiate traffic across custom domains
- `$context.customDomain.routingRuleIdMatched`: Track routing rule matches
- `$context.tlsVersion`, `$context.cipherSuite`: Monitor TLS migration
- `$context.authorizer.principalId`: Principal from Lambda authorizer (for user-level tracing)
- `$context.authorizer.claims.sub`: Cognito user pool subject claim (for Cognito-authenticated APIs)
- Response streaming (REST only): `$context.integration.responseTransferMode`, `$context.integration.timeToAllHeaders`, `$context.integration.timeToFirstContent`

## Setting Up Logging

### Prerequisites for REST API and WebSocket

1. Create IAM role with `AmazonAPIGatewayPushToCloudWatchLogs` managed policy
2. Set CloudWatch log role ARN in API Gateway Settings (region-level, one-time configuration)
3. Enable logging per stage

### Prerequisites for HTTP API

HTTP APIs do **not** use the account-level CloudWatch log role. Instead:

1. Create the CloudWatch Logs log group
2. Specify the log group ARN when configuring the stage's access logging
3. API Gateway uses a service-linked role to write logs. Ensure the log group's resource-based policy allows `logs:CreateLogStream` and `logs:PutLogEvents` from the API Gateway service principal

### Missing Logs Troubleshooting

- IAM permissions incorrect (most common for REST/WebSocket)
- Log group resource policy missing (most common for HTTP API)
- Logging not enabled at stage level
- Method-level override disabling logging
- Log group does not exist (create it first or let API Gateway create it)

## CloudTrail

- Captures all API Gateway management calls as control plane events
- Does NOT log data plane events (actual API requests); use access logs for that
- Determines: request made, IP address, who made it, when
- Use for audit and compliance, not operational monitoring
- **Do not forget CloudTrail for control plane audit**: who changed API configuration and when
