---
name: api-gateway
description: >
  Build, manage, and operate APIs with Amazon API Gateway (REST, HTTP, and WebSocket).
  Triggers on phrases like: API Gateway, REST API, HTTP API, WebSocket API, custom domain, Lambda authorizer, usage plan, throttling, CORS, VPC link, private API.
  Also covers troubleshooting API Gateway errors (4xx, 5xx, timeout, CORS failures) and IaC templates containing API Gateway resources.
  For general REST API design unrelated to AWS, do not trigger.
metadata:
  tags: [api-gateway, serverless, aws, rest-api, http-api, websocket]
---

# Amazon API Gateway Development

Expert guidance for building, managing, governing, and operating APIs with Amazon API Gateway. Covers REST APIs (v1), HTTP APIs (v2), and WebSocket APIs.

## How to Use This Skill

When answering API Gateway questions:

1. Read the relevant reference file(s) before responding, do not rely solely on this summary
2. For tasks spanning multiple concerns (e.g., "private API with mTLS and custom domain"), read all relevant references
3. When the user needs IaC templates, consult `references/sam-cloudformation.md` or `references/sam-service-integrations.md` and provide complete, working SAM/CloudFormation YAML
4. Always mention relevant pitfalls and limits that affect the user's design

## Quick Decision: Which API Type?

Choose the right API type first. This decision affects every downstream choice.

**REST API** is the full-featured API management platform for enterprises. It provides the governance, security, monetization, and operational controls that organizations need to build, publish, and manage APIs at scale, including usage plans with per-consumer throttling and quotas, API keys, request validation, WAF integration, resource policies, caching, canary deployments, and private endpoints.

**HTTP API** is the lightweight, low-cost proxy optimized for simpler API workloads. It offers ~70% lower cost and lower latency but trades away the API management features. Choose HTTP API when you need a fast, lightweight proxy to Lambda or HTTP backends and don't require the enterprise controls above.

| Factor                    | REST API (v1)                          | HTTP API (v2)                                  | WebSocket API                  |
| ------------------------- | -------------------------------------- | ---------------------------------------------- | ------------------------------ |
| **Positioning**           | **Full API management**                | **Low-cost proxy**                             | **Real-time bidirectional**    |
| Cost                      | Higher                                 | ~70% cheaper                                   | Per-message pricing            |
| Latency                   | Higher                                 | Lower                                          | Persistent connection          |
| Max timeout               | 50ms-29s (up to 300s Regional/Private) | 30s hard limit                                 | 29s                            |
| Payload                   | 10 MB                                  | 10 MB                                          | 128 KB message / 32 KB frame   |
| **API Management**        |                                        |                                                |                                |
| Usage plans/API keys      | Yes                                    | No                                             | No                             |
| Request validation        | Yes (JSON Schema draft 4)              | No                                             | No                             |
| Caching                   | Yes (0.5-237 GB)                       | No                                             | No                             |
| Custom gateway responses  | Yes                                    | No                                             | No                             |
| VTL mapping templates     | Yes                                    | No (parameter mapping only)                    | Yes                            |
| **Security & Governance** |                                        |                                                |                                |
| WAF                       | Yes                                    | No (use CloudFront + WAF)                      | No                             |
| Resource policies         | Yes                                    | No                                             | No                             |
| Private endpoints         | Yes                                    | No                                             | No                             |
| mTLS                      | Yes (Regional custom domain only)      | Yes (Regional custom domain only)              | Via CloudFront viewer mTLS     |
| **Auth**                  |                                        |                                                |                                |
| Lambda authorizer         | Yes (TOKEN + REQUEST)                  | Yes (REQUEST only, simple + IAM policy format) | Yes (REQUEST on $connect only) |
| JWT authorizer            | No (use Cognito authorizer)            | Yes (native)                                   | No                             |
| Cognito authorizer        | Yes (native)                           | Use JWT authorizer                             | No                             |
| **Operations**            |                                        |                                                |                                |
| Canary deployments        | Yes                                    | No                                             | No                             |
| Response streaming        | Yes                                    | No                                             | No                             |
| X-Ray tracing             | Yes                                    | No                                             | No                             |
| Execution logging         | Yes                                    | No                                             | Yes                            |
| Custom domain sharing     | Not with WebSocket                     | Not with WebSocket                             | Not with REST/HTTP             |

**Use REST API when**: you are building APIs for external consumers, partners, or multi-tenant platforms; need to enforce per-consumer rate limits and quotas; require request validation, caching, or WAF at the API layer; need private endpoints, resource policies, or canary deployments; or are building an API product with monetization and governance requirements.

**Use HTTP API when**: you are building lightweight APIs or simple backend proxies; cost and latency are the primary concerns; you don't need per-consumer throttling, request validation, caching, or WAF at the API layer; and native JWT authorization with OIDC/OAuth 2.0 meets your auth needs. Accept the hard 30s timeout and lack of API management features. For WAF, edge caching, or edge compute, place a CloudFront distribution in front of the HTTP API.

**Use WebSocket API when you need**: persistent bidirectional connections for real-time use cases (chat, notifications, live dashboards).

## Instructions

### Step 1: Design the API

Before implementation, gather requirements systematically. Consult `references/requirements-gathering.md` for the full requirements workflow covering endpoints, auth, data models, performance, security, and deployment needs.

Key design decisions:

1. **API type**: Use the decision table above
2. **Endpoint type**: Edge-optimized (default for global clients; optimizes TCP connections via CloudFront POPs but does not cache at the edge), Regional (same-region clients, or global clients needing their own CloudFront distribution for edge caching, edge compute, granular WAF control, or geo-based routing), Private (VPC-only access, REST API only)
3. **Topology**: Centralized (single domain, path-based routing) vs Distributed (subdomains per service)
4. **Authentication**: See `references/authentication.md` for the decision tree

### Step 2: Implement the API

Consult these references based on what you're building:

- **Architecture patterns**: `references/architecture-patterns.md`: topology, multi-tenant SaaS, hybrid workloads, private APIs, multi-region, streaming
- **WebSocket API**: `references/websocket.md`: route selection, @connections management, session management, client resilience, SAM templates, limits, multi-region
- **Service integrations**: `references/service-integrations.md`: direct AWS service integrations (EventBridge, SQS, SNS, DynamoDB, Kinesis, Step Functions, S3), HTTP proxy, mock, VTL mapping templates, binary media types, Lambda sync/async invocation
- **Custom domains and routing**: `references/custom-domains-routing.md`: base path mappings, routing rules, header-based versioning
- **Security**: `references/security.md`: mTLS (API Gateway native + CloudFront viewer mTLS), TLS policies, resource policies, WAF, HttpOnly cookies, CRL checks
- **SAM/CloudFormation**: `references/sam-cloudformation.md`: IaC patterns, OpenAPI extensions, VTL reference, binary data
- **SAM service integration templates**: `references/sam-service-integrations.md`: EventBridge, SQS, DynamoDB CRUD, Kinesis, Step Functions (REST + WebSocket) templates

### Step 3: Configure Performance and Scaling

- **Throttling**: Account-level default is 10,000 rps / 5,000 burst (adjustable; request increases via AWS Support). Configure stage-level and method-level throttling via usage plans. See `references/performance-scaling.md`
- **Caching** (REST only): Default TTL 300s, max 3600s. Only GET methods cached by default. Max cached response 1 MB
- **Edge caching** (all API types): For edge caching, place a self-managed CloudFront distribution in front of a Regional API. CloudFront reduces latency, backend load, AND cost (cached responses never reach API Gateway). Also enables edge compute (CloudFront Functions, Lambda@Edge) and granular cache behaviors per path. Use a Regional endpoint, not edge-optimized, when pairing with your own CloudFront distribution
- **Scaling**: API Gateway scales automatically but plan the entire stack (Lambda concurrency, DynamoDB capacity)

### Step 4: Set Up Observability

Always configure access logging. For REST and WebSocket APIs, also enable execution logging (ERROR level for production, INFO only for debugging). **HTTP API does not support execution logging**; use access logs with enhanced observability variables instead.

Consult the observability references based on what you need:

- **Logging setup, log formats, retention**: `references/observability-logging.md`
- **Metrics, alarms, metric filters, X-Ray tracing**: `references/observability-metrics-alarms.md`
- **Log analysis and insights, analytics pipeline, cross-account, control plane logs**: `references/observability-analytics.md`

### Step 5: Deploy

- Use Infrastructure as Code (SAM, CDK, CloudFormation, Terraform) for production
- **Canary deployments** (REST only): Route a percentage of traffic to test new versions
- **Blue/green deployments**: Use custom domain API mappings to switch between environments with zero downtime
- **Routing rules** (preferred for new domains): Declarative header/path-based routing on custom domains for versioning, A/B testing, gradual rollouts, and cell-based routing
- See `references/deployment.md` for detailed patterns

### Step 6: Apply Governance

For organization-wide API standards, see `references/governance.md` covering:

- Preventative controls (SCPs, IAM policies)
- Proactive controls (CloudFormation Hooks, Guard rules)
- Detective controls (AWS Config rules, EventBridge)
- Specific enforcement examples for security, observability, and management

## Response Format

When responding to API Gateway questions, structure your answer as:

1. **Recommendation**: Lead with the recommended approach and why
2. **Code**: Include SAM/CloudFormation YAML or code when the user needs implementation (always read the relevant reference file first)
3. **Pitfalls**: Warn about relevant gotchas from the pitfalls below or from `references/pitfalls.md`
4. **Limits**: Mention any service limits that constrain the design

## Troubleshooting Quick Reference

When diagnosing API Gateway errors, consult `references/troubleshooting.md` for detailed resolution steps. Here are the most common issues:

| Error                  | Most Common Cause                                                                                                       | Quick Fix                                                                                         |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| 400 Bad Request        | Protocol mismatch (HTTP/HTTPS) with ALB                                                                                 | Match protocol to listener type                                                                   |
| 401 Unauthorized       | Wrong token type (ID vs access) or missing identity sources                                                             | Check token type matches scope config; verify all identity sources sent                           |
| 403 Missing Auth Token | Stage name in URL when using custom domain                                                                              | Remove stage name from URL path                                                                   |
| 403 from VPC           | Private DNS on VPC endpoint intercepts ALL API calls                                                                    | Use custom domain names for public APIs                                                           |
| 403 Access Denied      | Resource policy + auth type mismatch or missing redeployment                                                            | Review policy, check auth type, redeploy API                                                      |
| 403 mTLS               | Certificate issuer not in truststore or weak signature algorithm                                                        | Verify CA in truststore, use SHA-256+                                                             |
| 429 Too Many Requests  | Account/stage/method throttle limits exceeded                                                                           | Implement jittered exponential backoff; request limit increase                                    |
| 500 Internal Error     | Missing Lambda invoke permission (especially with stage variables)                                                      | Add resource-based policy to Lambda function                                                      |
| 502 Bad Gateway        | Lambda response not in required proxy format                                                                            | Return `{statusCode, headers, body}` from Lambda                                                  |
| 504 Timeout            | Backend exceeds 29s (REST, increasable) or 30s (HTTP, hard). HTTP API body says "Service Unavailable" but status is 504 | Optimize backend, request timeout increase (REST Regional/Private), or switch to async invocation |
| CORS errors            | Missing CORS headers on Gateway Responses (4XX/5XX)                                                                     | Add CORS headers to DEFAULT_4XX and DEFAULT_5XX gateway responses                                 |
| SSL/PKIX errors        | Incomplete certificate chain on backend                                                                                 | Provide full cert chain; use `insecureSkipVerification` only for testing                          |

## Critical Pitfalls

1. **REST API default timeout is 29 seconds** (increasable up to 300s for Regional/Private endpoints via quota request). Lambda continues running but client gets 504. Request a timeout increase, or consider async patterns (SQS, EventBridge) for better user experience on long operations
2. **HTTP API hard timeout is 30 seconds**. Returns `{"message":"Service Unavailable"}` while Lambda continues
3. **`/ping` and `/sping` are reserved paths**. Do not use for API resources
4. **Execution log events truncated at 1,024 bytes**. Use access logs for complete data
5. **413 `REQUEST_TOO_LARGE` is the only gateway response that cannot be customized**. Use DEFAULT_4XX as a catch-all to add CORS headers for all 4xx errors including 413
6. **`maxItems`/`minItems` not validated** in REST API request validation
7. **Root-level `security` in OpenAPI is ignored**. Must set per-operation
8. **JWT authorizer public keys cached 2 hours**. Account for this in key rotation
9. **Management API rate limit: 10 rps / 40 burst**. Heavy automation can hit this
10. **Always redeploy REST API after configuration changes**. Changes don't take effect until deployed
11. **Edge-optimized endpoints do NOT cache at the edge** — they only optimize TCP connections via CloudFront POPs. If you need edge caching, edge compute (CloudFront Functions, Lambda@Edge), or granular CloudFront control, use a Regional API with your own CloudFront distribution instead

For additional pitfalls (header handling, URL encoding, caching charges, canary deployments, usage plans), see `references/pitfalls.md`.

## IaC Framework Selection

Default: CDK TypeScript

Override syntax:

- "use SAM" → Generate SAM/CloudFormation YAML templates
- "use CloudFormation" → Generate CloudFormation YAML templates
- "use Terraform" → Generate Terraform HCL

When not specified, ALWAYS use CDK TypeScript.

## Error Scenarios

### MCP Server Unavailable

- Inform user: "AWS Serverless MCP not responding"
- Ask: "Proceed without MCP support?"
- DO NOT continue without user confirmation

## Service Limits Quick Reference

See `references/service-limits.md` for the complete table. **Most numeric quotas below are default values and adjustable**; check with your AWS account team and the [latest quotas page](https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html) before using them for architectural decisions. Key limits:

| Resource                 | REST API                                 | HTTP API | WebSocket           |
| ------------------------ | ---------------------------------------- | -------- | ------------------- |
| Payload size             | 10 MB                                    | 10 MB    | 128 KB              |
| Integration timeout      | 50ms-29s (up to 300s Regional/Private)   | 30s hard | 29s                 |
| APIs per region          | 600 Regional/Private; 120 Edge-optimized | 600      | 600                 |
| Stages per API           | 10                                       | 10       | 10                  |
| Routes/resources per API | 300                                      | 300      | 300                 |
| Custom domains (public)  | 120                                      | 120      | 120                 |
| Account throttle         | 10,000 rps / 5,000 burst                 | Same     | Same (shared quota) |
| API keys per region      | 10,000                                   | N/A      | N/A                 |
| Usage plans per region   | 300                                      | N/A      | N/A                 |
| Cache sizes              | 0.5 GB - 237 GB                          | N/A      | N/A                 |
