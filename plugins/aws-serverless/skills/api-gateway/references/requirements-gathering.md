# API Requirements Gathering Guide

When helping users define requirements for APIs built on Amazon API Gateway, guide them through a structured process. Ask one question at a time; do not overwhelm with lists of questions.

## Workflow

1. Start with API purpose and overview (including multi-tenancy, topology, cost)
2. Determine the right API type (REST, HTTP, WebSocket) based on requirements
3. Progress through each category systematically (skip WebSocket section if not applicable)
4. Ask clarifying questions for gaps
5. Generate a final requirements summary for confirmation

## Requirements Categories

### 1. API Purpose and Overview

- What problem does the API solve?
- Who are the primary consumers (browsers, mobile apps, other services, IoT devices, AI agents)?
- Expected usage volume (requests per day/hour/second)?
- Is this a public API, internal API, or partner API?
- Will AI agents or LLMs consume this API? (Affects documentation depth, error message design, pagination style, and monetization; see architecture-patterns.md "Designing APIs for AI Agent Consumption")
- Is this a multi-tenant API? (Affects throttling, isolation, and architecture; see architecture-patterns.md "Multi-Tenant SaaS")
  - Per-tenant throttling tiers needed (bronze/silver/gold)? (Requires REST API usage plans)
  - Tenant isolation level? (Throttling only, or compute isolation via Lambda `TenantIsolationMode: PER_TENANT`?)
  - Noisy-neighbor prevention requirements?
- Account topology? (Single account for all APIs, separate accounts per domain/application, or central API account with centralized governance? Affects cross-account access, observability aggregation, and custom domain management)
- Cost sensitivity or budget constraints? (HTTP API is significantly cheaper than REST API but has fewer features: no caching, no WAF, no usage plans, no request validation, no VTL, hard 30s timeout. Choose based on feature needs vs cost)

### 2. Endpoints and Operations

- Resources to expose (users, orders, products, etc.)?
- Operations per resource (GET, POST, PUT, DELETE, PATCH)?
- URL paths and naming conventions?
- Nested resources or relationships?
- Query parameters for filtering, sorting, pagination?
- API versioning strategy? (URL path `/v1/` is simplest; header-based `X-API-Version` via routing rules is cleanest for REST API; query parameter `?version=1` is least recommended)
- How many concurrent API versions to support?
- Deprecation and sunsetting plan for old versions?

### 3. Request/Response Specifications

- Data sent in request bodies?
- Required or optional headers?
- Query parameters needed?
- Response format (JSON, XML, binary)?
- Binary content types? (Images, PDFs, files require `binaryMediaTypes` configuration; avoid `*/*` wildcard as it breaks Lambda proxy JSON responses)
- Expected response codes for success and error scenarios?
- Need for multi-value query parameters or headers?

### 4. Data Models and Schemas

- Domain entities and their attributes?
- Data types for each field?
- Required vs optional fields?
- Validation rules and constraints?
- Enumerations or fixed value sets?
- Need for request body validation? (REST API only supports JSON Schema draft 4)

### 5. Authentication and Authorization

- Authentication method?
  - **IAM (SigV4)**: Best for AWS-to-AWS service calls
  - **Lambda authorizer**: Custom logic, third-party IdPs, bearer tokens
  - **JWT authorizer**: HTTP API only, automatic OIDC/OAuth 2.0 validation
  - **Cognito user pools**: REST API native, or JWT authorizer on HTTP API
  - **API keys**: Not for primary auth; use for throttling/metering with usage plans
  - **mTLS**: Certificate-based, good for B2B and IoT
- Authorization model (RBAC, ABAC, resource-based)?
- Different permission levels or user roles?
- IP whitelisting or VPC restrictions needed?
- Cross-account access requirements?

### 6. Integration Requirements

- Backend services (Lambda, DynamoDB, RDS, ECS/EKS, on-premises)?
- Direct AWS service integrations without Lambda? REST API supports any AWS service via VTL mapping templates (SQS, EventBridge, Step Functions, S3, DynamoDB, etc.). HTTP API supports a subset via [first-class integrations](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-aws-services.html) with parameter mapping (SQS, EventBridge, Step Functions, Kinesis, AppConfig)
- VPC integrations for private resources? (VPC Link required; REST uses NLB, HTTP uses ALB/NLB/Cloud Map)
- Does the API need to be completely private (VPC-only access)? (REST API only; requires `execute-api` VPC endpoint + resource policy)
- Private API as proxy to external APIs? (Provides centralized logging, throttling, and access control for outbound calls from isolated VPCs without NAT gateway; security teams must be aware of this egress path)
- On-premises integrations? (Requires VPN/Direct Connect + NLB + VPC Link. Consider connectivity stability and health check tuning)
- Data transformations needed between request/response and backend?
- Need for response streaming (large payloads, LLM responses)? (REST API only; max 15-minute sessions, first 10 MB unrestricted then 2 MB/s bandwidth limit. No VTL response transformation, no caching with streaming)
- Binary data handling needed (images, PDFs, files)? (Configure `binaryMediaTypes`; avoid `*/*` wildcard as it breaks Lambda proxy JSON responses)
- File upload/download requirements? (Direct through API Gateway up to 10 MB, or presigned S3 URLs for larger files)
- Synchronous or asynchronous processing? (REST API default 29s timeout, increasable up to 300s for Regional/Private via quota request. HTTP API has hard 30s limit. For longer operations or better UX, consider async patterns: SQS, EventBridge, Step Functions)

### 7. WebSocket Requirements (if WebSocket API selected)

- Route selection expression? (e.g., `$request.body.action` for JSON messages)
- Custom routes beyond `$connect`/`$disconnect`/`$default`?
- Session management strategy? (Store connectionId with user ID in DynamoDB on `$connect`; GSI on user ID for targeted messaging)
- Message patterns? (Request-response, server push/broadcast, targeted push to specific users)
- Expected concurrent connections and message throughput?
- Client resilience requirements? (Automatic reconnect with exponential backoff is mandatory; 2-hour max connection duration, 10-minute idle timeout require client-side handling)
- Heartbeat/keep-alive strategy? (Send periodic messages every 5-9 minutes to prevent idle timeout)
- Connection state recovery on reconnect? (Re-authenticate, re-subscribe to topics, restore application state)
- Backend message delivery? (Lambda via `@connections` Management API; handle `GoneException` for stale connections)
- Multi-region WebSocket? (ConnectionId is region-specific; cross-region message propagation via EventBridge or DynamoDB Streams)

### 8. Performance and Scalability

- Expected peak request rates (per second)? (Account default: 10,000 rps / 5,000 burst across all APIs in a region, adjustable via Service Quotas)
- Latency requirements (target response time)?
- Need for response caching? (REST API only, TTL 0-3600s, 0.5-237 GB)
- Multi-layer caching strategy? (CloudFront edge → API Gateway regional → application-level)
- Throttling requirements (rate limit, burst limit)?
- Different throttling tiers for different consumers? (Requires REST API usage plans for per-API-key rate limits)
- Expected payload sizes? (Max 10 MB for REST/HTTP, consider presigned S3 URLs for larger files, or compressed passthrough via binary media types to exceed Lambda's 6 MB limit)
- Large payload strategy? (Presigned S3 URLs for >10 MB; response streaming for REST API up to 15-minute sessions; compressed passthrough for >6 MB Lambda payloads)
- Need for payload compression? (`minimumCompressionSize` on REST API; reduces bandwidth, latency, and data transfer costs through NAT Gateway/VPC Endpoints)
- Per-tenant or per-consumer throttling tiers? (Requires REST API usage plans; HTTP API has no per-consumer throttling natively)

### 9. Error Handling

- Custom error response format?
- CORS headers needed on error responses?
- Specific gateway response customizations?
- How to communicate validation errors?

### 10. Observability

- Execution logging level (ERROR recommended for production, INFO for debugging)? (REST/WebSocket only; HTTP API does not support execution logging)
- Custom access log format requirements? (Use enhanced observability variables for phase-level troubleshooting)
- AWS X-Ray tracing needed? (REST API only)
- Custom CloudWatch metrics? (Consider CloudWatch Embedded Metrics Format for business metrics)
- Alerting requirements (latency thresholds, error rate, throttle count)?
- API analytics pipeline needed? (Firehose → S3 → Athena → QuickSight for deep analytics beyond CloudWatch)

### 11. Security Requirements

- AWS WAF needed? (REST API direct; HTTP API via CloudFront + WAF)
- Which WAF managed rules? (Core Rule Set, SQL injection, Known Bad Inputs, IP Reputation at minimum)
- CORS configuration (which origins, methods, headers)? Don't forget CORS headers on gateway error responses (DEFAULT_4XX, DEFAULT_5XX)
- TLS version requirements (TLS 1.2 minimum recommended)?
- mTLS for client certificate authentication? (REST/HTTP native on custom domain, or CloudFront viewer mTLS for any API type)
- Certificate revocation checking needed? (Lambda authorizer + DynamoDB, or CloudFront Connection Functions + KeyValueStore)
- Data encryption requirements? (Cache encryption at rest is off by default)
- Compliance requirements (HIPAA, PCI-DSS, SOC2)?
- Need to disable default execute-api endpoint? (Force traffic through custom domain)
- DDoS protection considerations? (WAF rate-based rules, Shield)

### 12. Deployment, Environment, and Testing

- How many environments (dev, staging, production)?
- Separate stacks per environment (full isolation) or stages within one API?
- Canary deployment needed? (REST API only; tests API configuration, not Lambda code)
- Blue/green deployment strategy? (Custom domain API mappings for zero-downtime switching)
- Stage variables for environment-specific config?
- CI/CD pipeline (CodePipeline, GitHub Actions, GitLab CI, etc.)?
- IaC tool (SAM, CDK, CloudFormation, Terraform)?
- Local testing approach? (`sam local start-api` supports Lambda proxy/non-proxy only; direct service integrations require a deployed dev stage or API Gateway console Test Invoke)
- Integration testing strategy? (Deployed dev stage, contract testing, synthetic canaries)
- Load/performance testing plans? (Identify bottlenecks before production; test full stack, not just API Gateway)

### 13. Custom Domain and Routing

- Custom domain name needed?
- Endpoint type? Edge-optimized (default for global clients; optimizes TCP connections but does not cache at edge), Regional (same-region clients, or pair with own CloudFront distribution when edge caching, edge compute, granular WAF control, or geo-based routing is needed), Private (VPC-only access, REST API only)
- Multiple APIs behind one domain? REST API: use routing rules (preferred, supports header-based routing) or base path mappings. HTTP API/WebSocket: use base path mappings (routing rules are REST API only)
- Header-based routing needed? (API versioning, A/B testing, tenant routing; requires routing rules, REST API only)
- Multi-region deployment? (Active-passive failover or active-active with Route 53 latency-based routing)
- Data consistency requirements for multi-region? (DynamoDB Global Tables uses last-writer-wins; conditional writes do NOT prevent cross-region conflicts. For conflict-sensitive data, use single-region write routing or commutative operations. Data sovereignty concerns may require geo-based routing instead of latency-based)
- Cross-account topology? (Central API account with shared domain, or per-team subdomains)

### 14. Governance and Compliance

- Organization-wide API standards to enforce? (SCPs for preventative, CloudFormation Hooks for proactive, AWS Config for detective controls)
- Required tags on API resources?
- Control plane access restrictions? (Who can create, modify, deploy APIs)
- Audit requirements? (CloudTrail for control plane, access logs for data plane)
- API documentation and developer portal needed?
- API lifecycle management (versioning, deprecation, sunsetting)? See also "Endpoints and Operations" for versioning strategy details

## Output Format

```markdown
# API Requirements Summary

## Overview

- API Name: [name]
- API Type: [REST API / HTTP API / WebSocket API]
- Endpoint Type: [Edge-optimized / Regional / Private]
- Purpose: [description]
- Target Consumers: [who]
- Expected Volume: [requests/day, peak rps]
- Multi-tenant: [yes/no, isolation level]
- Account Topology: [single account / per-domain accounts / central API account]
- Cost Sensitivity: [budget constraints, API type preference]

## Endpoints

| Resource | Method | Path | Description | Auth |
| -------- | ------ | ---- | ----------- | ---- |
| ...      | ...    | ...  | ...         | ...  |

## API Versioning

- Strategy: [URL path / header-based / query parameter]
- Concurrent Versions: [number]
- Deprecation Policy: [timeline, communication plan]

## Authentication and Authorization

- Method: [auth method]
- Authorization Model: [model]
- Roles/Permissions: [details]

## Data Models

[Entity definitions with attributes and types]

## Binary Data and Large Payloads

- Binary Media Types: [list or none]
- File Upload/Download: [direct API / presigned S3 URLs]
- Max Expected Payload Size: [size]

## WebSocket Requirements (if applicable)

- Route Selection Expression: [field]
- Custom Routes: [list]
- Session Management: [connection tracking strategy]
- Message Patterns: [request-response / broadcast / targeted push]
- Expected Concurrent Connections: [number]
- Client Resilience: [reconnect, heartbeat strategy]

## Performance Requirements

- Target Latency: [ms]
- Rate Limits: [requests/second]
- Burst Limit: [requests]
- Caching: [yes/no, TTL]
- Per-Tenant Throttling: [yes/no, tier structure]

## Security Requirements

- WAF: [yes/no]
- CORS: [origins, methods, headers]
- TLS: [minimum version]
- mTLS: [yes/no]
- Compliance: [standards]

## Observability

- Execution Logging: [level]
- Access Logging: [format]
- X-Ray Tracing: [yes/no]
- Key Metrics: [list]
- Alarms: [list]

## Deployment and Testing

- Environments: [list]
- Strategy: [canary/blue-green/direct]
- IaC Tool: [SAM/CDK/CloudFormation/Terraform]
- CI/CD: [pipeline tool]
- Local Testing: [sam local / deployed dev stage]
- Integration Testing: [approach]

## Custom Domain and Routing

- Domain: [domain name]
- Endpoint Type: [edge-optimized/regional/private]
- Routing: [routing rules (recommended) / base path mappings]
- Header-Based Routing: [yes/no, use case]
- Multi-region: [yes/no, strategy]
- Data Consistency: [conflict resolution strategy]

## Governance

- Tag Requirements: [required tags]
- Audit: [CloudTrail/Config requirements]
- Standards Enforcement: [SCPs/Hooks/Config rules]
```
