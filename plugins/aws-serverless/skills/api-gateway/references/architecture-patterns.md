# Architecture Patterns

## Topology Patterns

**Three topology patterns:**

1. **Single AWS account**: Simplest. All APIs in one account with routing rules or base path mappings
2. **Separate AWS accounts per domain/application**: Better isolation. Each account owns a subdomain (e.g., `orders.example.com`, `shipping.example.com`) and can contain multiple microservices behind it. No cross-account base path mappings, so subdomain-per-account is the routing mechanism
3. **Central API account**: Central account owns the custom domain and routes to backend APIs in other accounts. Centralized governance, throttling, metering, and observability

### API Gateway as Single Entry Point

- Both single AWS account or central API account scenarios
- Map different custom domain subdomains to the same API with routing rules or different base path mappings
- Route different paths (`/service1`, `/service2`, `/docs`) to different backends

**Endpoint type selection**:

- **Regional** (default): API deployed in a single region. Best when clients are in the same region or when using your own CloudFront distribution for edge caching/WAF control. Supports custom domains with ACM certificates in the same region
- **Edge-optimized**: Routes requests through CloudFront POPs for optimized TCP connections to global clients. Does **NOT** cache at the edge. For actual edge caching, use a self-managed CloudFront distribution with a Regional API. ACM certificate must be in `us-east-1`
- **Private**: Accessible only from within a VPC via `execute-api` VPC endpoint. REST API only. See Private API Endpoints section below

**Trade-offs with central account**:

- X-Ray traces can span accounts using CloudWatch cross-account observability (source/monitoring account linking), but require explicit setup
- Usage plans cannot track across accounts without aggregation
- CloudWatch dashboards require aggregation in central account

## Multi-Tenant SaaS Specific Concerns

- Tiered usage plans (free/pro/enterprise or bronze/silver/gold)
- Lambda authorizer validates JWT from external IdP, extracts tenant ID, retrieves per-tenant API key from DynamoDB, returns it in `usageIdentifierKey` for transparent per-tenant throttling (see `references/authentication.md` for full flow)
- Set `ApiKeySourceType: AUTHORIZER` so API Gateway reads the key from the authorizer response, so tenants never see or manage API keys
- Onboarding automation: create tenant in IdP + API key in API Gateway + mapping in DynamoDB + associate key with usage plan tier
- Forward tenant identification as custom header to backend for tenant-specific logic
- **Lambda tenant isolation mode**: For compute-level tenant isolation beyond throttling, create Lambda functions with `--tenancy-config '{"TenantIsolationMode": "PER_TENANT"}'`. Lambda isolates execution environments per tenant: each environment is reused only for invocations from the same tenant, preventing cross-tenant data access via in-memory or `/tmp` storage. API Gateway maps the tenant ID to the `X-Amz-Tenant-Id` header on the Lambda integration request (e.g., from a Lambda authorizer context value via `context.authorizer.tenantId`, or from a client request header via `method.request.header.x-tenant-id` mapped to `integration.request.header.X-Amz-Tenant-Id`). Tenant ID is available in the handler context object (`context.tenantId` in Node.js, `context.tenant_id` in Python). Must be set at function creation time (cannot be changed later). Expect more cold starts since execution environments are not shared across tenants. All tenants share the function's execution role; for fine-grained per-tenant permissions, propagate tenant-scoped credentials from upstream components

## Integration Patterns

API Gateway supports five integration types: `AWS`, `AWS_PROXY`, `HTTP`, `HTTP_PROXY`, and `MOCK`. See `references/service-integrations.md` for detailed configuration of each pattern.

**Lambda integrations** (`AWS_PROXY` / `AWS`), the most common integration type. `AWS_PROXY` (Lambda proxy) is the recommended default: API Gateway passes the full request to Lambda and returns the Lambda response directly, no mapping templates needed. `AWS` (Lambda non-proxy) allows VTL request/response transformation but requires more setup.

**Direct AWS service integrations**: integrate directly with AWS services without Lambda. Two implementation approaches:

- **REST API and WebSocket API** use `Type: AWS` with VTL mapping templates for full request/response transformation. Supports most of AWS services' actions
- **HTTP API** uses first-class integrations (`Type: AWS_PROXY` with `IntegrationSubtype`) with parameter mapping instead of VTL. Supported services: EventBridge (`PutEvents`), SQS (`SendMessage`, `ReceiveMessage`, `DeleteMessage`, `PurgeQueue`), Kinesis (`PutRecord`), Step Functions (`StartExecution`, `StartSyncExecution`, `StopExecution`), and AppConfig (`GetConfiguration`). DynamoDB, SNS, and S3 are not available as HTTP API first-class integrations; use Lambda proxy instead

Most commonly used service integrations (REST API `Type: AWS` can integrate with any AWS service that has an HTTP API; the list below covers the most popular patterns; see `references/service-integrations.md` for details):

- **EventBridge**: event ingestion
- **SQS**: async message buffering
- **SNS**: fan-out pub/sub to multiple subscribers (REST/WebSocket only)
- **DynamoDB**: full CRUD with optional Streams for async processing (REST/WebSocket only)
- **Kinesis Data Streams**: high-throughput ordered data ingestion
- **Step Functions**: workflow orchestration (sync Express or async Standard).
- **S3**: file upload/download proxy with binary media type support (REST/WebSocket only)

**HTTP integrations** (`HTTP` / `HTTP_PROXY`): proxy to any HTTP endpoint (ALB, NLB, ECS, EC2, on-premises, external APIs). Use VPC Link for private backends. Available on REST and HTTP APIs. API Gateway is a valid choice for east-west (service-to-service) traffic when API management capabilities are needed beyond what load balancing provides (throttling, usage plans, request validation, authentication, and centralized observability). For internal calls that do not need these controls, prefer direct invocation (ALB, service mesh, or Lambda-to-Lambda) for lower latency and cost.

**Mock integrations** (`Type: MOCK`): responses without any backend (health checks, CORS preflight, prototyping)

Common patterns across all integrations: IAM execution roles, request validation, response mapping, Lambda sync/async invocation, backend bypass prevention (zero trust), and binary media type handling. **Security note for direct service integrations**: Use VTL mapping templates and API Gateway request validators. Every field that reaches the AWS service must be explicitly constructed in the mapping template. Never pass user input directly into service parameters without validation. Scope the IAM execution role to minimum required actions and specific resource ARNs (e.g., a single SQS queue, a single DynamoDB table). For S3 integrations, hardcode the bucket and validate key patterns to prevent path traversal.

## Hybrid / On-Premises Workloads

Connect API Gateway to on-premises or edge applications:

1. VPC with connectivity to on-prem (VPN/Direct Connect/Transit Gateway)
2. NLB/ALB with target group using IP addresses to register on-prem server IPs
3. VPC Link to the NLB/ALB
4. API Gateway with `VPC_LINK` integration type

**AWS Outposts**: Workloads running on Outposts (EC2, ECS, ALB) can also serve as integration targets. Outposts extend the VPC into the on-premises environment, so the same VPC Link + NLB/ALB pattern applies. Register Outposts instance IPs in the NLB target group

**Connectivity considerations**: This pattern assumes stable, low-latency connectivity to the on-premises location. AWS Direct Connect provides the most reliable path. Site-to-Site VPN connections are inherently less stable; tunnel flaps cause NLB/ALB targets to become unreachable. With default NLB/ALB health check settings (30s interval, 3 failures), there is a ~90-second window where API Gateway sends traffic to unreachable targets, resulting in integration timeouts. Tune NLB health check intervals (10s, 2 failures) and set API Gateway integration timeouts to match your SLA. Implement a `/health` endpoint on the on-premises target that validates downstream dependencies. Monitor NLB/ALB `UnHealthyHostCount` and alarm on it

## Private API Endpoints (not accessible from the public Internet)

- REST API only, accessible via VPC interface endpoint for `execute-api`
- Resource policy must allow access from VPC endpoint or VPC
- Deploy VPC endpoints across multiple AZs for high availability
- `disableExecuteApiEndpoint: true` forces traffic through custom domain only

### Private API as External API Proxy

- Private APIs can proxy external/third-party APIs for workloads in isolated VPCs (no NAT gateway or internet access needed)
- API Gateway is a managed service in an AWS-managed VPC; it has internet connectivity even when your VPC does not
- Pattern: Private API (VPC endpoint) -> HTTP_PROXY integration -> external API
- Adds centralized logging, throttling, and access control to external API calls
- **Security warning**: This pattern effectively grants internet egress to an isolated VPC through API Gateway. Lock down the HTTP_PROXY integration to specific allowed external domains. Do not use parameterized URLs that callers can control. Apply a resource policy restricting which VPC endpoints can invoke the API. Enable full access logging. This egress path does not appear in VPC flow logs or network firewall logs, so security teams must be aware of it as a potential data exfiltration vector

### Private API Cross-Account Access

- **Pattern 1**: VPC endpoint in consumer account + resource policy in producer account allowing `aws:SourceVpce`. Combine with IAM authorization (SigV4) or Lambda authorizer for defense in depth. The resource policy controls network-level access, but without authentication any workload in the consumer VPC that can reach the VPC endpoint can invoke the API
- **Pattern 2**: PrivateLink between accounts with VPC endpoint
- **Pattern 3**: Transit Gateway connecting VPCs across accounts (one of them with VPC endpoint )

### Custom Domains for Private APIs

- Private custom domain names (`AWS::ApiGateway::DomainNameV2`), dualstack only
- Share cross-account via AWS RAM using domain name access associations
- Route 53 private hosted zone with alias record pointing to VPC endpoint regional DNS

### Enforcing CloudFront as Sole Entry Point

To prevent clients from bypassing CloudFront and hitting API Gateway directly (skipping WAF, caching, geo-restrictions):

- **Private API approach**: Make the API Gateway endpoint private (VPC endpoint only), place CloudFront in front with VPC Origins: CloudFront → VPC Origin (internal ALB) → execute-api VPC endpoint → private API. All traffic stays within AWS private network and the API is unreachable from the public internet without CloudFront
- **Regional API + restrictions** (defense-in-depth, not a security boundary): Keep a regional endpoint but restrict direct access. Use a custom header from CloudFront (via origin custom headers) and validate it in a Lambda authorizer. Combine with disabling the default `execute-api` endpoint to force traffic through the custom domain fronted by CloudFront. **Caveat**: The header value is a static secret. If leaked through logs, source code, or developer machines, attackers can bypass CloudFront. Rotate the value regularly, store it in AWS Secrets Manager, and treat it as a credential.

### On-Premises Access to Private APIs

- AWS Direct Connect or Site-to-Site VPN to reach VPC with VPC endpoint
- Route 53 Resolver inbound endpoints for on-premises DNS resolution of VPC endpoint DNS names or private custom domain

## VPC Links

VPC Links enable API Gateway to reach **private integration targets** inside a VPC that are not publicly accessible. API Gateway creates a private connection to the VPC without exposing the backend to the internet.

- **VPC Link v2** (`AWS::ApiGatewayV2::VpcLink`): Supported by REST and HTTP APIs, targets ALB, NLB, and Cloud Map (for HTTP APIs) services. One VPC link per VPC can serve multiple backends. Prefer v2 for new integrations
- **VPC Link v1** (`AWS::ApiGateway::VpcLink`): Used by WebSocket API (and legacy REST API integrations), targets NLB only
- **Not the same as private endpoints**: A _private API endpoint_ restricts who can **call** the API (only from within a VPC via `execute-api` VPC endpoint). A _VPC Link_ controls where the API **forwards requests to** (private backends in a VPC). These are independent: a public API can use VPC Links to reach private backends, and a private API can call public HTTP endpoints without VPC Links

## Multi-Region

### Foundational Setup

- API Gateway custom domain names are **regional resources**. Create the same custom domain name (e.g., `api.example.com`) independently in each region
- Each region requires its own ACM certificate for the domain. ACM certificates are also regional. Request or import in every region where the API is deployed
- Route 53 alias records point to each region's API Gateway regional domain name (the `d-xxxxxx.execute-api.{region}.amazonaws.com` target provided when creating the custom domain)
- Deploy the full stack (API Gateway, Lambda, DynamoDB, etc.) independently per region; there is no cross-region replication of API Gateway configuration
- Use IaC (SAM/CDK/Terraform) with parameterized region to ensure consistent deployments across regions

### Active-Passive Failover

- Route 53 failover routing policy with health checks on the primary region
- Health checks monitor a `/health` endpoint or a CloudWatch alarm (e.g., on 5XX error rate or backend availability)
- On primary failure, Route 53 automatically routes all traffic to the secondary region
- Route 53 Application Recovery Controller (ARC) for manual failover switches when automated routing is insufficient (e.g., data corruption in one region)
- **RPO/RTO trade-off**: Health check interval (10s or 30s) + failover propagation (~60-120s DNS TTL) determines theoretical failover speed. **In practice, plan for 3-10 minutes**, as many clients cache DNS aggressively beyond TTL (Java caches successful lookups indefinitely by default, mobile SDKs and corporate resolvers vary). Set Route 53 record TTL to 60s, but do not size SLAs around sub-minute failover. For faster failover, use Global Accelerator (anycast IP, no DNS propagation delay) or CloudFront with origin failover (seconds, not minutes)

### Active-Active

- Route 53 latency-based or geo-based routing to nearest region
- All regions serve traffic simultaneously; both must be fully provisioned, not just on standby
- **Data sovereignty**: Latency-based routing may route EU users to US regions (or vice versa) if latency is lower, potentially violating GDPR or other data residency requirements. Use geo-based routing (combined with tenant locality verification) when data sovereignty is a concern. Note that DynamoDB Global Tables replicate data to all configured regions regardless of routing, so do not add regions that would violate data residency constraints

### Resilient Private APIs (Multi-Region)

- Private API in each region + VPC endpoint + Custom Domain Name
- Route 53 private hosted zone with latency-based or failover routing
- Transit Gateway with inter-Region peering for VPC connectivity
- **Health checks must be CloudWatch alarm-based**: Route 53 health checkers run from the public internet and cannot reach private API endpoints. Create CloudWatch alarms on NLB `UnHealthyHostCount`, API Gateway `5XXError` rate, or custom health metrics, then associate them with Route 53 health checks. Monitor Transit Gateway peering status separately; if inter-region peering fails, failover routing becomes critical

## Response Streaming

- Still a **request/response pattern**: client sends a request and receives a streamed response. The connection is one-directional (server to client) and closes when the response completes. For bidirectional real-time communication, use WebSocket API (see `references/websocket.md`)
- REST API only; not available for HTTP API or WebSocket API
- Set `responseTransferMode: "STREAM"` on integration
- Supports HTTP_PROXY, Lambda proxy, and private integrations (ALB/NLB/Cloud Map backends via VPC Link)
- **Lambda integrations**: Use `awslambda.streamifyResponse()` and `HttpResponseStream.from()`
- **HTTP integrations**: Backend sends a chunked transfer-encoded response (`Transfer-Encoding: chunked`); API Gateway streams chunks to the client as they arrive, with no Lambda required
- First 10 MB unrestricted; beyond 10 MB bandwidth limited to 2 MB/s
- Max streaming session: 15 minutes, removing the 10 MB buffered response limit
- Idle timeouts: 5 min (Regional/Private), 30 sec (edge-optimized)
- Billing: each 10 MB of response (rounded up) = 1 request
- **Limitations**: No VTL response transformation, no caching, no content encoding with streaming
- **Key use cases**: LLM chatbot implementations that stream sentence-by-sentence for better UX; large payload delivery beyond the 10 MB buffered response limit (up to 15 minutes of streaming); real-time data feeds (logs, metrics, event streams) where partial results are useful before the full response completes; file downloads from backend services where the client can begin processing immediately

## Designing APIs for AI Agent Consumption

As AI agents become API consumers, design considerations change:

- **Rich documentation**: API descriptions must be detailed enough for LLMs to understand intent, not just for humans
- **Descriptive error messages**: AI agents need enough context in error responses to retry with corrective information
- **Minimize round-trips**: Consider how many requests are needed to perform one action. Batch operations and intent-based APIs (e.g., "manage user" vs. separate GET/PUT/DELETE) reduce agent complexity
- **Machine-friendly pagination**: Use cursor-based pagination that machine consumers can follow automatically
- **Resource-based vs intent-based**: Consider whether traditional CRUD or intent-based endpoints better serve AI consumers
- **Non-deterministic cost**: AI-backed APIs have variable processing cost per request (LLM token usage varies). Factor this into monetization and usage plan design

## Reducing Backend Load

- **Request validation at the front door**: Use API Gateway validators (headers, query strings, JSON schema) to reject bad requests before they reach the backend
- **WAF rules**: Block traffic from regions with no customers
- **Add pagination and filters**: Reduce response data volume
- **Batch operations**: Combine multiple small actions into single requests
- **Async processing**: Acknowledge request immediately, queue for backend processing at its own pace. Better for constrained backend resources
- **Caching strategy**: Use CloudFront caching first (reduces load, latency, AND cost, since the request never reaches API Gateway). Use API Gateway cache as fallback (reduces load and latency but NOT cost, as the request is still counted by API Gateway). See `references/performance-scaling.md` for cache sizing, TTL configuration, and multi-layer caching details
