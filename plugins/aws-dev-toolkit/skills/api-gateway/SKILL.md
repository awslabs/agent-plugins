---
name: api-gateway
description: Design and configure Amazon API Gateway APIs. Use when choosing between REST and HTTP APIs, setting up authorizers, configuring throttling, managing custom domains, implementing WebSocket APIs, or troubleshooting API Gateway issues.
---

You are an API Gateway specialist. Help teams design, build, and operate production APIs on AWS API Gateway.

## Decision Framework: REST API vs HTTP API

| Feature | REST API | HTTP API |
|---|---|---|
| Price | ~$3.50/million | ~$1.00/million (70% cheaper) |
| Latency | Higher (~10-30ms overhead) | Lower (~5-10ms overhead) |
| Lambda authorizers | Request & Token | Lambda authorizer v2 (simpler) |
| Cognito authorizer | Built-in | JWT authorizer (works with Cognito) |
| IAM auth | Yes | Yes |
| API keys / Usage plans | Yes | No |
| Request validation | Yes | No |
| Request/response transforms | VTL mapping templates | No (use Lambda) |
| WAF integration | Yes | No |
| Resource policies | Yes | No |
| Caching | Built-in | No (use CloudFront) |
| Private APIs | Yes | No |
| WebSocket | Separate WebSocket API type | No |
| Mutual TLS | Yes | Yes |

**Opinionated recommendation**:
- **Default to HTTP API**. It is cheaper, faster, and simpler for 80% of use cases.
- **Use REST API when you need**: WAF, request validation, API keys/usage plans, VTL transforms, caching, resource policies, or private APIs.
- **Never use REST API just because it's "more feature-rich"** if you don't need those features.

## Authorizer Patterns

### JWT Authorizer (HTTP API) -- Recommended for Cognito/OIDC
```bash
aws apigatewayv2 create-authorizer \
  --api-id abc123 \
  --authorizer-type JWT \
  --identity-source '$request.header.Authorization' \
  --name cognito-auth \
  --jwt-configuration '{"Audience":["your-app-client-id"],"Issuer":"https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXX"}'
```

### Cognito Authorizer (REST API)
```bash
aws apigateway create-authorizer \
  --rest-api-id abc123 \
  --name cognito-auth \
  --type COGNITO_USER_POOLS \
  --provider-arns arn:aws:cognito-idp:us-east-1:123456789:userpool/us-east-1_XXXXX \
  --identity-source 'method.request.header.Authorization'
```

### Lambda Authorizer (when you need custom logic)
```bash
# REST API - REQUEST type (access full request context)
aws apigateway create-authorizer \
  --rest-api-id abc123 \
  --name custom-auth \
  --type REQUEST \
  --authorizer-uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789:function:my-authorizer/invocations \
  --authorizer-result-ttl-in-seconds 300 \
  --identity-source 'method.request.header.Authorization,context.httpMethod'
```

**Opinionated**: Always cache authorizer results (300s default is good). Use REQUEST type over TOKEN type for REST API Lambda authorizers -- it provides more context and is more flexible.

### IAM Authorization
Best for service-to-service communication. Use SigV4 signing. No custom authorizer needed.

```bash
# REST API: set authorizationType on method
aws apigateway put-method \
  --rest-api-id abc123 \
  --resource-id xyz789 \
  --http-method GET \
  --authorization-type AWS_IAM
```

## Throttling and Rate Limiting

### Account-Level Defaults
- **10,000 requests/second** across all APIs in a region (soft limit, can increase)
- **5,000 burst** across all APIs

### Stage-Level Throttling (REST API)
```bash
aws apigateway update-stage \
  --rest-api-id abc123 \
  --stage-name prod \
  --patch-operations \
    op=replace,path='/*/*/throttling/rateLimit',value='1000' \
    op=replace,path='/*/*/throttling/burstLimit',value='500'
```

### Usage Plans and API Keys (REST API only)
```bash
# Create usage plan
aws apigateway create-usage-plan \
  --name "basic-plan" \
  --throttle burstLimit=100,rateLimit=50 \
  --quota limit=10000,period=MONTH \
  --api-stages apiId=abc123,stage=prod

# Create API key
aws apigateway create-api-key --name "customer-key" --enabled

# Associate key with plan
aws apigateway create-usage-plan-key \
  --usage-plan-id plan123 \
  --key-id key456 \
  --key-type API_KEY
```

**Opinionated**: API keys are for throttling and tracking, NOT authentication. They are sent in headers and easily leaked. Always combine with a real authorizer.

## Custom Domains

```bash
# Create custom domain (HTTP API)
aws apigatewayv2 create-domain-name \
  --domain-name api.example.com \
  --domain-name-configurations CertificateArn=arn:aws:acm:us-east-1:123456789:certificate/xxx

# Map to API stage
aws apigatewayv2 create-api-mapping \
  --api-id abc123 \
  --domain-name api.example.com \
  --stage prod

# Create Route53 alias record pointing to the domain's target
```

**Requirements**: ACM certificate must be in **us-east-1** for edge-optimized endpoints. For regional endpoints, the cert must be in the same region as the API.

## Stages and Deployment

```bash
# Create deployment (REST API)
aws apigateway create-deployment --rest-api-id abc123 --stage-name prod

# Stage variables (REST API) -- use for environment-specific config
aws apigateway update-stage \
  --rest-api-id abc123 \
  --stage-name prod \
  --patch-operations op=replace,path=/variables/lambdaAlias,value=prod

# Reference in integration: arn:aws:lambda:us-east-1:123456789:function:my-func:${stageVariables.lambdaAlias}
```

**Opinionated**: Use separate AWS accounts (not just stages) for prod vs non-prod. Stage variables are useful but don't replace proper environment isolation.

## Request/Response Transforms (REST API)

VTL mapping templates for REST API:

```velocity
## Request transform: extract and reshape body
#set($body = $input.path('$'))
{
  "userId": "$context.authorizer.claims.sub",
  "itemName": "$body.name",
  "timestamp": "$context.requestTime"
}
```

**Opinionated**: VTL is painful to debug and maintain. For complex transforms, use a Lambda integration instead. Reserve VTL for simple cases like adding request context or status code mapping.

## WebSocket APIs

```bash
# Create WebSocket API
aws apigatewayv2 create-api \
  --name my-websocket-api \
  --protocol-type WEBSOCKET \
  --route-selection-expression '$request.body.action'

# Routes you typically need:
# $connect    -- client connects (auth happens here)
# $disconnect -- client disconnects
# $default    -- fallback for unmatched routes
# Custom routes -- matched by route-selection-expression

# Send message to connected client from backend
aws apigatewaymanagementapi post-to-connection \
  --connection-id "abc123" \
  --data '{"message": "hello"}' \
  --endpoint-url "https://xyz.execute-api.us-east-1.amazonaws.com/prod"
```

**Key design decisions for WebSocket**:
- Store connection IDs in DynamoDB (not in-memory)
- Use `$connect` route for authentication
- Set idle timeout (default 10 min, max 2 hours)
- Max message size is 128 KB (frames up to 32 KB)
- Use API Gateway management API to push messages from backend

## CORS Configuration

### HTTP API (simple)
```bash
aws apigatewayv2 update-api \
  --api-id abc123 \
  --cors-configuration \
    AllowOrigins="https://example.com",AllowMethods="GET,POST,OPTIONS",AllowHeaders="Authorization,Content-Type",MaxAge=3600
```

### REST API (manual)
Must add OPTIONS method with mock integration to each resource, plus add CORS headers in integration responses. Use SAM/CDK to automate this -- doing it manually via CLI is error-prone.

## Common CLI Commands

```bash
# List APIs
aws apigatewayv2 get-apis                    # HTTP/WebSocket APIs
aws apigateway get-rest-apis                  # REST APIs

# Test an endpoint
curl -H "Authorization: Bearer $TOKEN" https://abc123.execute-api.us-east-1.amazonaws.com/prod/items

# Get execution logs (must enable logging on stage first)
aws logs filter-log-events \
  --log-group-name "API-Gateway-Execution-Logs_abc123/prod" \
  --filter-pattern "ERROR"

# Enable execution logging (REST API)
aws apigateway update-stage \
  --rest-api-id abc123 \
  --stage-name prod \
  --patch-operations \
    op=replace,path=/accessLogSetting/destinationArn,value=arn:aws:logs:us-east-1:123456789:log-group:api-logs \
    op=replace,path='/*/*/*/logging/loglevel',value=INFO

# Export API definition
aws apigateway get-export \
  --rest-api-id abc123 \
  --stage-name prod \
  --export-type oas30 \
  --accepts application/yaml api-spec.yaml
```

## Anti-Patterns

1. **Using REST API when HTTP API suffices**: Paying 3.5x more for features you don't use. Audit your feature requirements.
2. **API keys as sole authentication**: API keys are identifiers, not authenticators. Always pair with IAM, Cognito, or Lambda authorizers.
3. **No throttling on public APIs**: Without throttling, a single client can exhaust your account-level limit, affecting all APIs.
4. **Deploying without stage-specific settings**: Each stage should have its own logging, throttling, and Lambda alias configuration.
5. **Large payloads through API Gateway**: Payload limit is 10 MB. For file uploads, use pre-signed S3 URLs instead.
6. **Ignoring the 29-second timeout**: API Gateway has a hard 29-second integration timeout. Design for async patterns (return 202, poll/webhook) for long-running operations.
7. **Not enabling CloudWatch Logs**: Without execution logs, you cannot debug 5xx errors. Enable at minimum ERROR-level logging.
8. **Wildcard CORS in production**: `AllowOrigins: *` in production exposes your API to any origin. Specify exact allowed origins.
9. **Complex VTL mapping templates**: VTL is hard to test, debug, and maintain. If your transform is more than 10 lines, move it to Lambda.
10. **Not using a custom domain**: The default `execute-api` URL changes on redeployment (REST API). Custom domains provide stable URLs and allow API migration without client changes.

## Cost Optimization

- HTTP API is 70% cheaper than REST API for the same traffic
- Enable REST API caching to reduce Lambda invocations (but adds ~$0.02/hour per GB)
- Use Lambda authorizer caching to avoid re-executing authorizer on every request
- For high-traffic APIs, consider CloudFront in front of API Gateway for additional caching
- Monitor 4xx errors -- wasted invocations from bad clients still cost money
