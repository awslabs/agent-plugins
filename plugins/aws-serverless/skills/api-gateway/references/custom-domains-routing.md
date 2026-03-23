# Custom Domains and Routing

## Custom Domain Names

### Setup by Endpoint Type

- **Edge-optimized**: ACM certificate must be in `us-east-1`. Creates an internal, AWS-managed CloudFront distribution (not visible in your CloudFront console, not configurable). Does **NOT** cache at the edge. For actual edge caching, use a separate CloudFront distribution with a Regional API. DNS CNAME/alias to CloudFront domain
- **Regional**: ACM certificate must be in same region as API. DNS CNAME/alias to regional domain name (`d-xxx.execute-api.region.amazonaws.com`)
- **Private**: REST API only. Dualstack only (`AWS::ApiGateway::DomainNameV2`). Domain name access associations link the domain to VPC endpoints. Route 53 alias in private hosted zone pointing to VPC endpoint regional DNS. Cross-account sharing via AWS RAM domain name access associations. ACM certificate in the same region

**Certificate requirements:**

- **Edge-optimized**: ACM-issued public certificate or certificate imported into ACM. Must be in us-east-1. Imported certificates must be [manually rotated before expiration](https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-edge-optimized-custom-domain-name.html)
- **Regional and Private**: ACM-issued public certificate or certificate imported into ACM. Private CA certificates (ACM Private CA) are only for mTLS truststores, not for the domain itself

### Limits

- Public custom domains: 120/region
- Private custom domains: 50/region
- API mappings per domain: 200
- Base path max length: 300 characters

### Common Issues

- **CNAMEAlreadyExists** (edge-optimized only): CNAME already associated with another CloudFront distribution. Delete or update existing CNAME first, or use Regional endpoint type to avoid this
- **Wrong certificate returned**: DNS record points to stage URL instead of API Gateway domain name target
- **Deletion quota**: 1 per 30 seconds. Use exponential backoff
- **403 "Missing Authentication Token"**: Stage name included in URL when using custom domain. Remove stage name from path

## Base Path Mappings

### Multi-Segment Paths

- Paths can contain forward slashes: `/sales/reporting`, `/sales/reporting/v2`, `/corp/admin`
- Each routes to a different API endpoint
- Use `AWS::ApiGatewayV2::DomainName` and `AWS::ApiGatewayV2::ApiMapping` with `ApiMappingKey`
- Works with both REST (v1) and HTTP (v2) APIs
- Domain and APIs must be in same account and Region
- Each sub-application deployed independently

### Multi-Tenant White-Label

White-label domain support allows SaaS providers to serve multiple external customers through customer-specific subdomains (e.g., `customer1.example.com`, `customer2.example.com`) while routing all traffic through a single API Gateway API. Based on the pattern described in [Using API Gateway as a Single Entry Point for Web Applications and API Microservices](https://aws.amazon.com/blogs/architecture/using-api-gateway-as-a-single-entry-point-for-web-applications-and-api-microservices/) (AWS Architecture Blog).

**Setup:**

1. Register a domain (e.g., `example.com`) and create CNAME records for each customer subdomain (`customer1.example.com`, `customer2.example.com`) via Route 53 or your DNS provider
2. Create an ACM wildcard certificate (`*.example.com`), which covers one subdomain level only (`tenant1.example.com` matches, `a.tenant1.example.com` does not)
3. Create a custom domain in API Gateway for each customer subdomain using the wildcard certificate. Each subdomain can have its own base path mappings or routing rules, or use a shared mapping with backend routing based on the forwarded Host header
4. Point each subdomain's CNAME record to the API Gateway domain name target
5. Forward the original `Host` header as a custom header to the backend so it can identify the customer:
   - REST API: map `method.request.header.host` to `integration.request.header.Customer` via `RequestParameters`
   - HTTP API: use parameter mapping: `overwrite` on `integration.request.header.Customer` from `$request.header.host`

**Key considerations:**

- The wildcard certificate applied to API Gateway allows multiple subdomains to be served by a single API endpoint
- Each customer subdomain is created as a separate custom domain in API Gateway, enabling per-customer base path mappings or routing rules
- Backend microservices use the forwarded customer header to apply customer-specific business logic
- API Gateway's request/response transformation can insert or modify headers per customer
- The 120 public custom domains per region quota limits the number of customer subdomains (request increase if needed)

## Routing Rules (Preferred for New Domains)

**Routing rules are the recommended approach** over base path mappings for new custom domains, offering header-based routing, priority-based evaluation, and simpler management. Supports public and private REST APIs only. HTTP API and WebSocket API do not support routing rules; use base path mappings instead.

### Rule Structure

- **Conditions**: Up to 2 `MatchHeaders` + 1 `MatchBasePaths` (AND logic)
- **Actions**: Invoke any stage of any REST API in the same account and region
- **Priority**: 1-1,000,000 (lower = higher precedence, no duplicates). Leave gaps between priorities (100, 200, 300) to allow inserting new rules later. Creating a rule with a duplicate priority fails with `ConflictException`
- Header matching supports wildcards: `*latest` (matches values ending with "latest"), `alpha*` (matches values starting with "alpha"), `*v2*` (contains). Header names are case-insensitive; header values are case-sensitive

### Routing Modes

1. **API mappings only** (default): Traditional base path mapping behavior. Use if not adopting routing rules
2. **Routing rules then API mappings**: Routing rules take precedence; unmatched requests fall back to base path mappings. Use for zero-downtime migration from base path mappings to routing rules
3. **Routing rules only**: **Recommended mode** for new custom domains or after completing migration from base path mappings. Requests that match no routing rule receive a 404 response

### Migration from Base Path Mappings

1. Set routing mode to "Routing rules then API mappings" — existing base path mappings continue as fallback
2. Progressively create routing rules (e.g., start with a test header rule for controlled traffic). Include a catch-all rule (no conditions) at the lowest priority as a safety net; without this, unmatched requests will receive a 404 after switching modes in step 4
3. Monitor with `$context.customDomain.routingRuleIdMatched` in access logs to verify routing behavior and confirm all expected traffic paths are covered by rules
4. Once all traffic is covered by rules, switch to "Routing rules only" mode

### Implementation

- CloudFormation: `AWS::ApiGatewayV2::RoutingRule`
- Observability: `$context.customDomain.routingRuleIdMatched` in access logs
- No additional charges for routing rules; standard API Gateway request pricing applies
- A rule with no conditions serves as a catch-all matching all requests

### Use Cases

- **API versioning**: Route by `Accept` or `X-API-Version` header to different API implementations
- **Gradual rollouts**: Route a percentage of users to new version by adding a header in application code, then gradually increase
- **A/B testing**: Route specific user cohorts by custom header (e.g., `x-test-group: beta-testers`)
- **Cell-based architecture**: Route by tenant ID or hostname header to different cell backends
- **Dynamic backend selection**: Route by cookie value, media type, or any custom header

## Header-Based API Versioning

Route API requests to different backend implementations based on a version header (REST APIs only).

- Create a routing rule per version with `MatchHeaders` on the version header (e.g., `X-API-Version: v1`, `X-API-Version: v2`)
- Each rule invokes the corresponding API/stage
- Add a catch-all rule at the lowest priority to route unversioned requests to the default (latest stable) version
- Monitor with `$context.customDomain.routingRuleIdMatched` in access logs to track version adoption
- No additional infrastructure, no Lambda@Edge, no DynamoDB. Purely declarative

## Host Header Forwarding

- API Gateway overwrites Host header with integration endpoint hostname
- Cannot forward original Host header directly
- **REST API workaround**: Create custom header in Method Request, map in Integration Request: `method.request.header.host` -> `integration.request.header.my_host`
- **HTTP API workaround**: Use parameter mapping to forward the host header: `overwrite` on `integration.request.header.X-Original-Host` from `$request.header.host`
