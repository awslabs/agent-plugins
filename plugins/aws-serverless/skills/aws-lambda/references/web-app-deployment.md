# Web Application Deployment Guide

## Overview

Deploy web applications to AWS Serverless using the `deploy_webapp` tool and Lambda Web Adapter. This covers backend APIs, static frontends, and full-stack applications — from endpoint selection through custom domains and frontend updates.

## Deployment Types

Choose the deployment type based on your application:

| Type          | Use Case                    | What Gets Created                      |
| ------------- | --------------------------- | -------------------------------------- |
| **backend**   | API services, microservices | Lambda + API Gateway                   |
| **frontend**  | Static sites, SPAs          | S3 + CloudFront                        |
| **fullstack** | Complete web apps           | Lambda + API Gateway + S3 + CloudFront |

## API Endpoint Options

| Option                        | Best For                                                            | Notes                                                           |
| ----------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------- |
| **HTTP API (API Gateway v2)** | Most REST/HTTP APIs                                                 | 70% cheaper than REST API, lower latency                        |
| **REST API (API Gateway v1)** | APIs needing WAF, caching, usage plans, request transforms          | More features, higher cost                                      |
| **Lambda Function URL**       | Simple HTTPS endpoints, webhooks, single-function APIs              | No API Gateway; free (pay only for Lambda). Supports streaming. |
| **Application Load Balancer** | High-traffic APIs with mixed Lambda/container targets, existing ALB | Fixed hourly cost; efficient at high request volumes            |

### Lambda Function URLs

The simplest option for a single Lambda function that needs an HTTPS endpoint:

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    FunctionUrlConfig:
      AuthType: AWS_IAM   # or NONE for public endpoints
      Cors:
        AllowOrigins:
          - "https://myapp.example.com"
```

Use `AuthType: NONE` only for public webhook receivers or assets where you handle auth in the function. For internal services, use `AWS_IAM` and sign requests with SigV4.

**Prefer Function URLs over API Gateway when:**

- Serving payloads larger than 10 MB (API Gateway's response limit)
- Handling requests longer than 29 seconds (API Gateway's integration timeout)
- Building a Lambdalith where per-endpoint metrics are managed in-code
- Internal service-to-service calls authenticated with AWS_IAM

**Prefer API Gateway when:**

- You need per-endpoint CloudWatch metrics without custom instrumentation
- You require Cognito authorizers, usage plans, API keys, or request validation
- You are exposing WebSocket APIs
- You want WAF integration at the API level

### CORS

Configure CORS on the API Gateway for browser-based frontend access:

- Set `AllowOrigin` to your frontend domain in production (avoid `*`)
- Include necessary headers: `Content-Type`, `Authorization`, `X-Api-Key`
- Set appropriate `MaxAge` for preflight caching

### Custom Domains

Use the `configure_domain` tool to set up custom domains with:

- ACM certificate (must be in us-east-1 for CloudFront)
- Route 53 DNS record
- API Gateway base path mapping

## Lambda Web Adapter

Lambda Web Adapter allows standard web frameworks to run on Lambda without code changes. The `deploy_webapp` tool automatically configures it.

**How it works:**

- Adds the Lambda Web Adapter layer to your function
- Sets `AWS_LAMBDA_EXEC_WRAPPER` to `/opt/bootstrap`
- Configures the `PORT` environment variable for your application
- Your framework listens on that port as it would normally

**Custom startup**: For applications needing pre-start steps (migrations, config loading), provide a startup script that runs setup commands before `exec`-ing your application.

**Supported backend frameworks:** Express.js, FastAPI, Flask, Spring Boot, ASP.NET Core, Gin

**Supported frontend frameworks:** React, Vue.js, Angular, Next.js, Svelte

## Project Structure

### Backend-Only

```text
my-backend/
├── src/
│   ├── app.js          # Express application
│   ├── routes/         # API routes
│   └── middleware/     # Custom middleware
├── package.json
└── Dockerfile          # Optional
```

### Frontend-Only

```text
my-frontend/
├── dist/               # Built assets
│   ├── index.html
│   └── assets/
└── package.json
```

### Full-Stack

```text
my-fullstack-app/
├── frontend/
│   ├── dist/           # Built frontend
│   └── package.json
├── backend/
│   ├── src/
│   └── package.json
└── deployment-config.json
```

## Frontend Updates

Use `update_webapp_frontend` to push new frontend assets to S3 and optionally invalidate the CloudFront cache. For zero-downtime updates, use content-hashed filenames so old and new assets can coexist.

## Database Integration

### RDS with Lambda

- Place Lambda in VPC with private subnets for RDS access
- Use VPC endpoints to avoid NAT Gateway costs for AWS service calls
- Set connection pool max to 1 per Lambda instance — but note that Lambda Managed Instances handle multiple concurrent requests, so use a proper connection pool there
- Store connection strings in Secrets Manager

For DynamoDB optimization (billing, key design, query patterns), see [optimization.md](optimization.md).

## Environment Management

Use `samconfig.toml` environment-specific sections for multi-environment deployments. See [sam-project-setup.md](../../aws-serverless-deployment/references/sam-project-setup.md) for configuration details.

Store environment-specific secrets in Secrets Manager or SSM Parameter Store, referenced by environment name.

## Authentication & Authorization

### Choosing an Auth Approach

| Approach                                    | Best For                                | API Type             |
| ------------------------------------------- | --------------------------------------- | -------------------- |
| **Cognito User Pools + JWT authorizer**     | User sign-up/sign-in for your own app   | HTTP API (v2)        |
| **Cognito User Pools + Cognito authorizer** | Same, with built-in token validation    | REST API (v1)        |
| **Lambda authorizer (token-based)**         | Custom auth logic, third-party IdPs     | Both                 |
| **Lambda authorizer (request-based)**       | Multi-source auth (headers, query, IP)  | Both                 |
| **IAM authorization**                       | Service-to-service, internal APIs       | Both + Function URLs |
| **API keys + usage plans**                  | Rate limiting third-party API consumers | REST API (v1) only   |

### Cognito User Pools vs Identity Pools

- **User Pools** = authentication (who are you?). Handles sign-up, sign-in, MFA, and issues JWT tokens. This is what most web APIs need.
- **Identity Pools** = authorization (what AWS resources can you access?). Exchanges tokens (from User Pools, Google, Facebook) for temporary AWS credentials. Use this when clients need direct AWS access (S3 upload from browser, IoT).

Most API backends only need User Pools + a JWT or Cognito authorizer on API Gateway.

### JWT Authorizer (HTTP API)

The simplest and cheapest option for HTTP APIs backed by Cognito:

```yaml
MyCognitoUserPool:
  Type: AWS::Cognito::UserPool

MyCognitoUserPoolClient:
  Type: AWS::Cognito::UserPoolClient
  Properties:
    UserPoolId: !Ref MyCognitoUserPool
    ExplicitAuthFlows:
      - ALLOW_USER_SRP_AUTH
      - ALLOW_REFRESH_TOKEN_AUTH

MyApi:
  Type: AWS::Serverless::HttpApi
  Properties:
    Auth:
      DefaultAuthorizer: MyCognitoAuth
      Authorizers:
        MyCognitoAuth:
          AuthorizationScopes:
            - email
          IdentitySource: $request.header.Authorization
          JwtConfiguration:
            issuer: !Sub "https://cognito-idp.${AWS::Region}.amazonaws.com/${MyCognitoUserPool}"
            audience:
              - !Ref MyCognitoUserPoolClient
```

JWT authorizers validate the token signature and claims at the API Gateway level — no Lambda invocation needed for auth. This is free (no extra cost beyond HTTP API pricing).

### Lambda Authorizer

Use Lambda authorizers when you need custom auth logic: validating tokens from a third-party IdP, checking database-backed permissions, or combining multiple auth signals.

**Token-based** authorizers receive only the `Authorization` header. **Request-based** authorizers receive the full request (headers, query string, path, IP) — use these when auth depends on more than just a bearer token.

```yaml
MyApi:
  Type: AWS::Serverless::Api
  Properties:
    Auth:
      DefaultAuthorizer: MyLambdaAuth
      Authorizers:
        MyLambdaAuth:
          FunctionArn: !GetAtt AuthFunction.Arn
          FunctionPayloadType: TOKEN
          Identity:
            Header: Authorization
            ReauthorizeEvery: 300  # Cache auth result for 5 minutes
```

Set `ReauthorizeEvery` > 0 to cache authorization results and avoid invoking the authorizer Lambda on every request. A value of 300 (5 minutes) is a reasonable default.

### API Keys and Usage Plans

API keys are for tracking and throttling third-party API consumers — they are **not** an authentication mechanism. Always combine API keys with a proper authorizer.

```yaml
MyApi:
  Type: AWS::Serverless::Api
  Properties:
    Auth:
      ApiKeyRequired: true
      UsagePlan:
        CreateUsagePlan: PER_API
        Throttle:
          BurstLimit: 100
          RateLimit: 50
        Quota:
          Limit: 10000
          Period: MONTH
```

API keys and usage plans are REST API (v1) only. HTTP APIs do not support them.

### Auth Best Practices

- [ ] Use JWT authorizers with HTTP API for most web applications — cheapest, lowest latency
- [ ] Cache Lambda authorizer results (`ReauthorizeEvery` > 0) to avoid per-request invocations
- [ ] Never use API keys as the sole authentication mechanism — they are for usage tracking, not identity
- [ ] Use IAM authorization (SigV4) for service-to-service calls, not shared API keys
- [ ] Store JWT client IDs and secrets in SSM Parameter Store, not in template literals

## Performance

- **Caching**: Use CloudFront caching for static assets. Disable caching for API paths.
- **Response streaming**: For LLM/AI responses, large payloads (> 6 MB), or long-running operations, use Lambda response streaming to reduce TTFB. See [optimization.md](optimization.md) for configuration.

For cold start optimization, memory right-sizing, and connection pooling, see [optimization.md](optimization.md).
