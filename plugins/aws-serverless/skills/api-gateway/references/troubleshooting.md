# Troubleshooting Guide

## Table of Contents

- [General Approach](#general-approach)
- [HTTP 400 Bad Request](#http-400-bad-request)
- [HTTP 401 Unauthorized](#http-401-unauthorized)
- [HTTP 403 Forbidden](#http-403-forbidden)
- [HTTP 413 Request Too Large](#http-413-request-too-large)
- [HTTP 429 Too Many Requests](#http-429-too-many-requests)
- [HTTP 500 Internal Server Error](#http-500-internal-server-error)
- [HTTP 502 Bad Gateway](#http-502-bad-gateway)
- [HTTP 504 Gateway Timeout](#http-504-gateway-timeout)
- [SSL/TLS and Certificate Issues](#ssltls-and-certificate-issues)
- [CORS Errors](#cors-errors)
- [Lambda Integration Errors](#lambda-integration-errors)
- [VPC and Private API Issues](#vpc-and-private-api-issues)
- [Mapping Template Errors](#mapping-template-errors)
- [WebSocket Issues](#websocket-issues)
- [SQS Integration Errors](#sqs-integration-errors)
- [Useful Debugging Commands](#useful-debugging-commands)

---

## General Approach

1. Enable execution logging (REST/WebSocket only — [HTTP API supports access logging only](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html)) AND access logging before troubleshooting
2. Use `x-amzn-requestid` response header to trace specific requests in execution logs
3. Check enhanced observability variables in access logs to identify which phase failed (see `references/observability-logging.md`)
4. Use CloudWatch Logs Insights for pattern analysis across many requests

### Request Phase Order

WAF -> Authenticate -> Authorizer -> Authorize -> Integration

Each phase exposes `$context.{phase}.status`, `$context.{phase}.latency`, `$context.{phase}.error` in access logs.

---

## HTTP 400 Bad Request

### Protocol Mismatch with ALB

- **Cause**: Sending HTTP to TLS listener or HTTPS to non-TLS listener
- **Fix**: Match protocol (HTTP/HTTPS) to ALB listener type

### ALB Desync Mode

- **Cause**: ALB desync mitigation set to "strictest" rejects non-RFC-compliant requests
- **Fix**: Switch to "defensive" mode or ensure requests are RFC-compliant

### Invalid Request Body

- **Cause**: Request body fails JSON Schema validation (REST API request validator)
- **Fix**: Check model definition; note `maxItems`/`minItems` are NOT validated

---

## HTTP 401 Unauthorized

### Lambda Authorizer

- **Missing token**: Token source header not sent or wrong header name
- **Regex mismatch**: Token fails the Token Validation regex pattern
- **Missing identity sources**: Required headers/query strings not sent (REQUEST type)
- **Fix**: Verify header name, regex pattern, and all identity sources

### Cognito

- **Wrong token type**: Use ID token when no scopes configured; access token when scopes configured
- **Expired token**: Check token expiration
- **User pool mismatch**: Verify user pool ID in authorizer config

---

## HTTP 403 Forbidden

### "Missing Authentication Token"

- **Cause**: Stage name in URL when using custom domain (stage already mapped)
- **Fix**: Remove stage name from URL path
- Also occurs when: hitting nonexistent resource path, default endpoint disabled
- **Note**: This 403 behavior is REST API specific. HTTP API returns **404 Not Found** for nonexistent paths ([Gateway response types](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-gatewayResponse-definition.html))

### From VPC (All APIs Fail)

- **Cause**: Private DNS on `execute-api` VPC endpoint routes ALL API calls through the endpoint
- **Fix**: Use custom domain names for public APIs, or disable private DNS

### Lambda Authorizer with {proxy+}

- **Cause**: Authorizer returns IAM policy with path-specific resource ARN. When caching is enabled, that policy is reused for requests to different proxy paths, which are denied by the cached partial policy ([Configure Lambda authorizer caching](https://docs.aws.amazon.com/apigateway/latest/developerguide/configure-api-gateway-lambda-authorization-with-console.html))
- **Fix**: Return wildcard resource ARN (`*/*`) in policy, or disable authorizer caching

### Cross-Account IAM

- **Cause**: Missing either IAM policy (caller account) OR resource policy (API account)
- **Fix**: REST API: configure both. HTTP API: use `sts:AssumeRole` (no resource policies)

### Resource Policy

Common causes:

1. IP not in allow list or is in deny list
2. HTTP method/resource not covered by policy
3. Auth type mismatch (e.g., IAM auth expected but not provided)
4. **API not redeployed after policy change**
5. Wrong condition key (`aws:SourceVpce` vs `aws:SourceVpc`)

### mTLS 403

- Certificate issuer not in truststore
- Insecure signature algorithm (must be SHA-256+)
- Self-signed certificates with insufficient key size (RSA-2048+ or ECDSA-256+ required)

### WAF Filtered

- `waf-status: 403` in access logs
- Check WAF rules and web ACL configuration

---

## HTTP 413 Request Too Large

- **Cause**: Payload exceeds 10 MB limit (REST and HTTP API) ([API Gateway quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html))
- REQUEST_TOO_LARGE is the only gateway response that [cannot be customized](https://docs.aws.amazon.com/apigateway/latest/developerguide/supported-gateway-response-types.html). Use `DEFAULT_4XX` as a catch-all to add CORS headers for all 4xx errors including 413
- **For larger payloads**: Use S3 presigned URLs for direct client upload/download

---

## HTTP 429 Too Many Requests

### "429 Too Many Requests"

- **Cause**: API rate or burst limits exceeded at account, stage, or method level
- **Fix**: Implement retries with jittered exponential backoff; request limit increase

### "Limit Exceeded"

- **Cause**: API quota limits exceeded (daily/weekly/monthly)
- **Fix**: Request quota extension via usage plan or AWS Support

---

## HTTP 500 Internal Server Error

### Lambda Stage Variable Permission

- **Cause**: Missing Lambda invoke permission when function referenced via stage variable
- **Fix**: Add resource-based policy: `aws lambda add-permission --function-name <fn> --statement-id apigateway --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn <api-arn>` ([Lambda permissions for API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/getting-started-with-lambda-integration.html#getting-started-with-lambda-integration-add-permission))

### VPC Link Issues

- VPC link in "Failed" state
- Unhealthy NLB targets
- Security group blocks (port 443 TCP)
- NACLs blocking traffic
- TLS certificate mismatch on backend
- **Fix**: Check VPC link status, NLB target health, security groups, backend TLS chain

### Lambda Authorizer Malformed Response

- **Cause**: Lambda authorizer returns invalid JSON, missing `principalId`, or policy exceeding ~8 KB. API Gateway returns **500** (not 401/403) — commonly mistaken for a backend issue ([Authorizer output format](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-lambda-authorizer-output.html))
- **Fix**: Check execution logs for authorizer errors; verify response includes `principalId` and valid `policyDocument`

### General Lambda Integration

- Missing Lambda invoke permissions
- Lambda throttled (concurrency limit)
- Incorrect status code mapping (non-proxy integration)
- **Fix**: Add permissions, implement backoff, configure correct mappings

---

## HTTP 502 Bad Gateway

### Lambda Proxy Integration

- **Cause**: Lambda response not in required format
- **REST API / payload format 1.0** ([response format](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-output-format)):

```json
{
  "statusCode": 200,
  "headers": { "Content-Type": "application/json" },
  "body": "{\"key\": \"value\"}",
  "isBase64Encoded": false
}
```

- `statusCode` must be integer, `body` must be string, `headers` must be object
- **HTTP API payload format 2.0** is more flexible ([response format](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html#http-api-develop-integrations-lambda.response)): `body` can be string or object (auto-serialized to JSON), a bare string return is treated as 200 body, and `cookies` array is supported for Set-Cookie headers
- Also check Lambda permissions and package file permissions

---

## HTTP 504 Gateway Timeout

### REST API

- Default: **29 seconds** integration timeout (increasable up to 300s for Regional/Private via quota request)
- Lambda continues running but client receives 504

### HTTP API

- **30 seconds hard limit** (not increasable)
- Returns HTTP 504 while Lambda continues ([Troubleshoot 504 errors](https://repost.aws/knowledge-center/api-gateway-504-errors))

### Diagnosis

1. Check `IntegrationLatency` metric for spikes
2. Use CloudWatch Logs Insights to identify slow requests
3. Enable [X-Ray tracing](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-xray.html) for detailed latency breakdown (REST API only). For HTTP API, enable X-Ray in Lambda functions and correlate via `$context.integration.requestId`

### Fixes

- Optimize Lambda: increase memory, reduce cold starts, use provisioned concurrency
- Check backend health and response times
- For REST API Regional/Private: **request timeout increase** up to 300s via AWS Support
- For better UX or operations exceeding max timeout: consider async patterns (SQS, EventBridge, Step Functions): acknowledge immediately, process in background

---

## SSL/TLS and Certificate Issues

### PKIX Path Building Failed

- **Cause**: Incomplete certificate chain, unsupported CA, or self-signed cert on backend
- **Fix**: Provide complete certificate chain on backend; use `insecureSkipVerification=true` for testing only

### General SSLEngine Problem

- Unsupported CA, expired certificate, invalid chain, unsupported cipher suite
- **Fix**: Verify CA support, check expiry, ensure valid chain. RSA keys 2048-4096 bits and ECDSA keys are supported

### VPC Link TLS

- NLB TLS listener terminates TLS at NLB; TCP listener passes through
- **Fix**: Use TCP listener for end-to-end TLS; TLS listener for NLB-terminated TLS

### Wrong Certificate Returned

- **Cause**: DNS record points to stage URL instead of API Gateway domain name target
- **Fix**: Point DNS to correct API Gateway domain name

### mTLS Certificate Conflicts

- Multiple CAs with same subject in truststore
- **Fix**: Clean up truststore, remove duplicate/conflicting CA certificates

---

## CORS Errors

### Missing CORS Headers on Error Responses

- **Cause**: Gateway responses (4XX/5XX) bypass integration and don't include CORS headers
- **Fix**: Add CORS headers to `DEFAULT_4XX` and `DEFAULT_5XX` gateway responses

### Proxy Integration Missing CORS

- **Cause**: API Gateway doesn't add CORS headers in proxy integration
- **Fix**: Lambda/backend must return `Access-Control-Allow-Origin` and other CORS headers

### Private API Preflight Failure

- **Cause**: `x-apigw-api-id` header triggers preflight requests that fail
- **Fix**: Use `Host` header instead of `x-apigw-api-id`

---

## Lambda Integration Errors

### "Invalid permissions on Lambda function"

- **Fix (console)**: Re-save Lambda integration to auto-add permissions
- **Fix (CLI)**: `aws lambda add-permission --function-name <fn> --statement-id apigateway --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn <method-arn>`
- **Fix (CloudFormation)**: Add `AWS::Lambda::Permission` resource

### Lambda Authorizer Permission Error

- Create IAM role with `lambda:InvokeFunction` and set as Lambda Invoke Role on the authorizer

### Async Invocation

- REST API: Set `X-Amz-Invocation-Type: 'Event'` in Integration Request HTTP Headers
- HTTP API: Not directly supported. Use proxy Lambda that invokes target Lambda asynchronously

---

## VPC and Private API Issues

### Connection Checklist

1. Resource policy allows VPC endpoint or VPC
2. VPC endpoint policy allows the API
3. Security groups allow TCP 443 inbound
4. DNS resolution works (check private DNS setting)

### Invoke URL Formats (Without Private DNS)

- Route 53 alias to VPC endpoint
- VPC endpoint public DNS + `Host` header
- VPC endpoint public DNS + `x-apigw-api-id` header

### On-Premises DNS Resolution

- Create Route 53 Resolver inbound endpoint in VPC
- Configure on-prem DNS forwarder to forward `amazonaws.com` queries to Resolver

---

## Mapping Template Errors

### "Invalid mapping expression specified"

- **Cause**: `{proxy+}` path variable needs URL path parameter mapping
- **Fix**: Define URL path parameter `proxy` mapped from `method.request.path.proxy`

### "Illegal character in path"

- **Cause**: Without mapping, API Gateway sends literal `{proxy+}` (containing `{`)
- **Fix**: Same as above. Ensure Endpoint URL uses `{proxy}` (without `+`)

---

## WebSocket Issues

### 410 GoneException

- Message sent before connection fully established
- Connection terminated by client
- Invalid connectionId format
- **Fix**: Use `getConnection` before `postToConnection`; do NOT post from $connect route Lambda

### Connection Errors

- Missing Lambda permissions, incorrect API URL, backend errors
- WebSocket URL format: `wss://api-id.execute-api.region.amazonaws.com/stage`

---

## SQS Integration Errors

| Error                     | Cause                                       | Fix                                               |
| ------------------------- | ------------------------------------------- | ------------------------------------------------- |
| UnknownOperationException | Wrong Content-Type or Action name           | Verify Content-Type and action                    |
| AccessDenied              | IAM role missing SQS permissions            | Add SQS permissions to role                       |
| KMS.AccessDeniedException | Missing KMS permissions for encrypted queue | Add KMS permissions                               |
| SignatureDoesNotMatch     | Content-Type header mismatch                | Align Content-Type between method and integration |
| InvalidAddress            | Queue URL doesn't match region              | Use correct regional queue URL                    |

---

## Useful Debugging Commands

### Systems Manager Automation

Use `AWSSupport-TroubleshootAPIGatewayHttpErrors` runbook to automatically analyze CloudWatch logs for 4xx/5xx errors.

### CloudWatch Logs Insights for Specific Request

```
fields @timestamp, @message
| filter @message like "REQUEST_ID_HERE"
| sort @timestamp asc
```

### Execution Log Sequence (REST API Only)

Authorizer -> Usage Plan -> Method Request -> Endpoint Request -> Endpoint Response -> Method Response

### Tracing with x-amzn-requestid

Every API Gateway response includes `x-amzn-requestid` header. Use this to search execution logs for the full request trace.
