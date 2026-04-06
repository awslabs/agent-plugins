# API Gateway Authorizer Patterns

Detailed configuration examples for each API Gateway authorizer type. For guidance on when to use each, see the main SKILL.md.

## JWT Authorizer (HTTP API) -- Recommended for Cognito/OIDC

The simplest authorizer for HTTP APIs when using Cognito or any OIDC-compliant identity provider.

```bash
aws apigatewayv2 create-authorizer \
  --api-id abc123 \
  --authorizer-type JWT \
  --identity-source '$request.header.Authorization' \
  --name cognito-auth \
  --jwt-configuration '{"Audience":["your-app-client-id"],"Issuer":"https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXX"}'
```

**Key points:**
- `Audience` is your Cognito App Client ID (or OIDC client ID)
- `Issuer` must be the exact URL of the Cognito User Pool or OIDC provider
- Identity source defaults to `$request.header.Authorization` (Bearer token)
- No Lambda function needed -- API Gateway validates the JWT directly

### CDK Example

```typescript
import { HttpApi, HttpMethod } from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpJwtAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';

const jwtAuthorizer = new HttpJwtAuthorizer('CognitoAuth', userPool.userPoolProviderUrl, {
  jwtAudience: [userPoolClient.userPoolClientId],
});

httpApi.addRoutes({
  path: '/items',
  methods: [HttpMethod.GET],
  integration: lambdaIntegration,
  authorizer: jwtAuthorizer,
});
```

## Cognito Authorizer (REST API)

Built-in REST API authorizer that validates Cognito User Pool tokens directly.

```bash
aws apigateway create-authorizer \
  --rest-api-id abc123 \
  --name cognito-auth \
  --type COGNITO_USER_POOLS \
  --provider-arns arn:aws:cognito-idp:us-east-1:123456789:userpool/us-east-1_XXXXX \
  --identity-source 'method.request.header.Authorization'
```

### CDK Example

```typescript
import * as apigateway from 'aws-cdk-lib/aws-apigateway';

const auth = new apigateway.CognitoUserPoolsAuthorizer(this, 'Authorizer', {
  cognitoUserPools: [userPool],
  resultsCacheTtl: Duration.minutes(5),
});

api.root.addResource('items').addMethod('GET', lambdaIntegration, {
  authorizer: auth,
  authorizationType: apigateway.AuthorizationType.COGNITO,
});
```

## Lambda Authorizer (Custom Logic)

Use when you need to validate tokens from a non-OIDC provider, check custom headers, query parameters, or implement business-specific authorization logic.

### REST API -- REQUEST Type (Recommended)

```bash
aws apigateway create-authorizer \
  --rest-api-id abc123 \
  --name custom-auth \
  --type REQUEST \
  --authorizer-uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789:function:my-authorizer/invocations \
  --authorizer-result-ttl-in-seconds 300 \
  --identity-source 'method.request.header.Authorization,context.httpMethod'
```

### REST API -- TOKEN Type

```bash
aws apigateway create-authorizer \
  --rest-api-id abc123 \
  --name token-auth \
  --type TOKEN \
  --authorizer-uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789:function:my-authorizer/invocations \
  --authorizer-result-ttl-in-seconds 300 \
  --identity-source 'method.request.header.Authorization'
```

### HTTP API -- Lambda Authorizer v2

```bash
aws apigatewayv2 create-authorizer \
  --api-id abc123 \
  --authorizer-type REQUEST \
  --authorizer-uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789:function:my-authorizer/invocations \
  --authorizer-payload-format-version "2.0" \
  --enable-simple-responses \
  --name custom-auth
```

### Lambda Authorizer Trust Policy

The Lambda function used as an authorizer must allow API Gateway to invoke it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "lambda:InvokeFunction",
      "Resource": "arn:aws:lambda:us-east-1:123456789:function:my-authorizer",
      "Condition": {
        "ArnLike": {
          "AWS:SourceArn": "arn:aws:execute-api:us-east-1:123456789:abc123/authorizers/*"
        }
      }
    }
  ]
}
```

### Lambda Authorizer Response Format

**REST API (v1 format):**

```json
{
  "principalId": "user123",
  "policyDocument": {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "execute-api:Invoke",
        "Effect": "Allow",
        "Resource": "arn:aws:execute-api:us-east-1:123456789:abc123/prod/GET/items"
      }
    ]
  },
  "context": {
    "userId": "user123",
    "role": "admin"
  }
}
```

**HTTP API (v2 simple format, with `enable-simple-responses`):**

```json
{
  "isAuthorized": true,
  "context": {
    "userId": "user123",
    "role": "admin"
  }
}
```

### Best Practices for Lambda Authorizers

- **Always cache results** (300s default is good). Use REQUEST type over TOKEN type for REST API -- it provides more context and is more flexible.
- **Keep authorizer functions fast** -- they add latency to every uncached request. Target under 100ms.
- **Return a Deny policy** (REST) or `isAuthorized: false` (HTTP) instead of throwing errors. Thrown errors result in 500s, not 403s.
- **Use identity source wisely** -- it determines the cache key. Include all values that affect the auth decision.

## IAM Authorization

Best for service-to-service communication. Uses SigV4 signing. No custom authorizer needed.

```bash
# REST API: set authorizationType on method
aws apigateway put-method \
  --rest-api-id abc123 \
  --resource-id xyz789 \
  --http-method GET \
  --authorization-type AWS_IAM
```

### IAM Policy for Callers

The calling service or role needs an IAM policy like:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "execute-api:Invoke",
      "Resource": "arn:aws:execute-api:us-east-1:123456789:abc123/prod/GET/items"
    }
  ]
}
```

### SigV4 Signing Example (Python/boto3)

```python
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials
import boto3

session = boto3.Session()
credentials = session.get_credentials().get_frozen_credentials()

request = AWSRequest(
    method='GET',
    url='https://abc123.execute-api.us-east-1.amazonaws.com/prod/items',
    headers={'Host': 'abc123.execute-api.us-east-1.amazonaws.com'}
)

SigV4Auth(credentials, 'execute-api', 'us-east-1').add_auth(request)
response = requests.get(request.url, headers=dict(request.headers))
```

## Decision Matrix: Which Authorizer to Use

| Scenario | Recommended Authorizer |
|---|---|
| Web/mobile app with Cognito | JWT authorizer (HTTP API) or Cognito authorizer (REST API) |
| Third-party OIDC (Auth0, Okta) | JWT authorizer (HTTP API) |
| Custom token format | Lambda authorizer |
| Multi-header auth (API key + token) | Lambda authorizer (REQUEST type) |
| Service-to-service (internal) | IAM authorization |
| Public API with rate limiting | API keys (for tracking) + any authorizer above |
