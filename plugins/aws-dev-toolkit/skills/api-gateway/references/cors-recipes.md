# API Gateway CORS Recipes

Complete CORS configuration patterns for both REST and HTTP APIs, plus common issues and fixes.

## HTTP API CORS (Simple)

HTTP API has built-in CORS support. One command configures everything:

```bash
aws apigatewayv2 update-api \
  --api-id abc123 \
  --cors-configuration \
    AllowOrigins="https://example.com",AllowMethods="GET,POST,OPTIONS",AllowHeaders="Authorization,Content-Type",MaxAge=3600
```

### CDK Example (HTTP API)

```typescript
import { HttpApi, CorsHttpMethod } from 'aws-cdk-lib/aws-apigatewayv2';

const httpApi = new HttpApi(this, 'Api', {
  corsPreflight: {
    allowOrigins: ['https://example.com', 'https://staging.example.com'],
    allowMethods: [CorsHttpMethod.GET, CorsHttpMethod.POST, CorsHttpMethod.PUT, CorsHttpMethod.DELETE],
    allowHeaders: ['Authorization', 'Content-Type', 'X-Request-Id'],
    exposeHeaders: ['X-Request-Id'],
    maxAge: Duration.hours(1),
    allowCredentials: true,
  },
});
```

### CloudFormation / SAM (HTTP API)

```yaml
Resources:
  HttpApi:
    Type: AWS::ApiGatewayV2::Api
    Properties:
      Name: my-http-api
      ProtocolType: HTTP
      CorsConfiguration:
        AllowOrigins:
          - "https://example.com"
        AllowMethods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
        AllowHeaders:
          - Authorization
          - Content-Type
        MaxAge: 3600
        AllowCredentials: true
```

## REST API CORS (Manual Setup)

REST API requires manual CORS setup: an OPTIONS method with mock integration plus CORS headers on every integration response. This is error-prone by hand -- use SAM, CDK, or the console's "Enable CORS" button.

### CDK Example (REST API)

```typescript
import * as apigateway from 'aws-cdk-lib/aws-apigateway';

const api = new apigateway.RestApi(this, 'Api', {
  defaultCorsPreflightOptions: {
    allowOrigins: ['https://example.com'],
    allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Authorization', 'Content-Type', 'X-Amz-Date', 'X-Api-Key'],
    allowCredentials: true,
    maxAge: Duration.hours(1),
  },
});
```

### Manual CLI Setup (REST API)

For each resource that needs CORS:

```bash
# 1. Add OPTIONS method
aws apigateway put-method \
  --rest-api-id abc123 \
  --resource-id xyz789 \
  --http-method OPTIONS \
  --authorization-type NONE

# 2. Add mock integration
aws apigateway put-integration \
  --rest-api-id abc123 \
  --resource-id xyz789 \
  --http-method OPTIONS \
  --type MOCK \
  --request-templates '{"application/json": "{\"statusCode\": 200}"}'

# 3. Add method response
aws apigateway put-method-response \
  --rest-api-id abc123 \
  --resource-id xyz789 \
  --http-method OPTIONS \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Headers": false,
    "method.response.header.Access-Control-Allow-Methods": false,
    "method.response.header.Access-Control-Allow-Origin": false
  }'

# 4. Add integration response with CORS headers
aws apigateway put-integration-response \
  --rest-api-id abc123 \
  --resource-id xyz789 \
  --http-method OPTIONS \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Headers": "'Authorization,Content-Type,X-Amz-Date,X-Api-Key'",
    "method.response.header.Access-Control-Allow-Methods": "'GET,POST,PUT,DELETE,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin": "'https://example.com'"
  }'

# 5. ALSO add CORS headers to your actual method integration responses (GET, POST, etc.)
#    The OPTIONS preflight is not enough -- the actual response must also include
#    Access-Control-Allow-Origin or the browser will reject it.
```

### SAM Template (REST API)

```yaml
Resources:
  ApiGateway:
    Type: AWS::Serverless::Api
    Properties:
      StageName: prod
      Cors:
        AllowMethods: "'GET,POST,PUT,DELETE,OPTIONS'"
        AllowHeaders: "'Authorization,Content-Type'"
        AllowOrigin: "'https://example.com'"
        AllowCredentials: true
        MaxAge: "'3600'"
```

## Common CORS Issues and Fixes

### 1. "No 'Access-Control-Allow-Origin' header" Error

**Cause:** The response is missing the `Access-Control-Allow-Origin` header.

**Fix (HTTP API):** Ensure `cors-configuration` is set on the API.

**Fix (REST API):** You must add CORS headers to BOTH the OPTIONS method AND the actual method (GET, POST, etc.) integration responses. The OPTIONS preflight alone is not enough.

**Fix (Lambda proxy integration):** When using Lambda proxy integration, your Lambda function must return CORS headers in its response:

```javascript
exports.handler = async (event) => {
  return {
    statusCode: 200,
    headers: {
      'Access-Control-Allow-Origin': 'https://example.com',
      'Access-Control-Allow-Headers': 'Authorization,Content-Type',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    },
    body: JSON.stringify({ data: 'hello' }),
  };
};
```

### 2. CORS Works for Simple Requests but Fails for Preflight

**Cause:** The OPTIONS method is missing or misconfigured.

**Fix:** Ensure the OPTIONS method exists on the resource, uses MOCK integration, and returns proper CORS headers. For HTTP API, the built-in CORS handles this automatically.

### 3. "Request header field X is not allowed by Access-Control-Allow-Headers"

**Cause:** The client is sending a header not listed in `AllowHeaders`.

**Fix:** Add the missing header to `AllowHeaders`. Common headers that must be explicitly allowed:
- `Authorization`
- `Content-Type`
- `X-Amz-Date`
- `X-Api-Key`
- `X-Amz-Security-Token`
- Any custom headers your app uses

### 4. CORS Fails When Using Cognito/JWT Authorizer

**Cause:** The authorizer rejects the OPTIONS preflight request (which has no Authorization header).

**Fix (HTTP API):** The built-in CORS handling runs before authorizers, so this should not happen. If it does, check that you haven't attached the authorizer to the OPTIONS route.

**Fix (REST API):** Set the OPTIONS method's `authorization-type` to `NONE`, even if other methods use an authorizer.

### 5. Wildcard Origin with Credentials

**Cause:** `AllowOrigins: *` combined with `AllowCredentials: true`.

**Fix:** Browsers reject this combination. You must specify exact origins when using credentials:

```bash
# WRONG
AllowOrigins="*",AllowCredentials=true

# CORRECT
AllowOrigins="https://example.com",AllowCredentials=true
```

### 6. CORS Headers Duplicated (REST API with Lambda Proxy)

**Cause:** Both the API Gateway CORS configuration and the Lambda function return CORS headers, leading to duplicate headers that some browsers reject.

**Fix:** Choose one approach:
- **Option A (recommended):** Use Lambda proxy integration and return CORS headers from your Lambda only. Do not add CORS headers in the API Gateway integration response.
- **Option B:** Use non-proxy integration and handle CORS entirely in API Gateway mapping templates.

## Production CORS Checklist

- [ ] Specify exact allowed origins (no wildcards in production)
- [ ] Include all required headers in `AllowHeaders`
- [ ] Set `MaxAge` to reduce preflight requests (3600 seconds is reasonable)
- [ ] If using credentials (cookies, Authorization header), set `AllowCredentials: true` with specific origins
- [ ] For REST API with Lambda proxy: return CORS headers from Lambda, not API Gateway
- [ ] Test preflight (OPTIONS) requests separately from actual requests
- [ ] Verify CORS works with your authorizer (OPTIONS must not require auth)
