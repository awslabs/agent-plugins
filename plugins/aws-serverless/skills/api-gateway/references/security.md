# Security Best Practices

## TLS Configuration

### TLS Security Policies

- TLS 1.2 is the recommended minimum
- Two naming conventions: legacy policies use `TLS_` prefix (e.g., `TLS_1_0`, `TLS_1_2`), enhanced policies use `SecurityPolicy_` prefix (e.g., `SecurityPolicy_TLS13_1_3_2025_09`) and support TLS 1.3 and post-quantum cryptography
- Edge-optimized endpoints: use CloudFront TLS stack with `_EDGE` suffix policies (e.g., `SecurityPolicy_TLS13_2025_EDGE`). Supports TLS 1.3
- Regional/Private endpoints: use API Gateway TLS stack with date-based suffix policies (e.g., `SecurityPolicy_TLS13_1_2_PQ_2025_09`). Supports TLS 1.3 and post-quantum
- **Endpoint access mode**: `BASIC` (standard) vs `STRICT` (validates SNI matches Host header)
- Migration: Apply enhanced policy with BASIC first, validate with access logs (`$context.tlsVersion`, `$context.cipherSuite`), then switch to STRICT
- STRICT mode takes up to 15 minutes to propagate

### Disable Default Endpoint

- Set `disableExecuteApiEndpoint: true` to force all traffic through custom domain
- REST APIs return 403 when disabled; HTTP APIs return 404 (observed behavior; not explicitly documented in the developer guide)
- **Must redeploy after changing this setting**

## Mutual TLS (mTLS)

### Setup

1. Create CA hierarchy (ACM Private CA or self-managed)
2. Export root CA public key to PEM truststore file
3. Upload to versioned S3 bucket (same region as API Gateway)
4. Configure custom domain with truststore URI (`s3://bucket/truststore.pem`)
5. Use public ACM certificate for the API Gateway domain itself
6. Disable default endpoint

### Automation with ACM Private CA

- Lambda-backed CloudFormation custom resource concatenates certificate chain and uploads to S3
- Certificates issued by root CA or any subordinate CA are automatically trusted
- SAM resources: `AWS::ACMPCA::CertificateAuthority`, `AWS::ACMPCA::Certificate`, `AWS::CertificateManager::Certificate`

### Certificate Revocation Lists (CRL)

- API Gateway does NOT check CRLs natively
- Implement via Lambda authorizer:
  1. Extract client cert serial number
  2. Check against CRL stored in DynamoDB (fast lookups at scale)
  3. Deny access if revoked
- S3 PutObject event triggers preprocessing Lambda: validates CRL signature, decodes ASN.1, stores simplified JSON
- Use function-level caching with S3 ETag for cache invalidation
- **Lambda authorizer caching and CRL checks**: Disable authorizer caching if near-real-time revocation is required. If some latency is acceptable, use a short TTL (e.g., 60s) matching your revocation freshness requirements

### Propagating Client Identity

- Lambda authorizer extracts client cert subject: `from cryptography import x509; cert = x509.load_pem_x509_certificate(event['requestContext']['identity']['clientCert']['clientCertPem'].encode())`
- Returns `clientCertSub` (from `cert.subject.rfc4514_string()`) in authorizer `context`
- API Gateway injects via `RequestParameters: 'integration.request.header.X-Client-Cert-Sub': 'context.authorizer.clientCertSub'`
- Backend receives client identity without performing mTLS validation itself

### CloudFront Viewer mTLS

CloudFront now supports mTLS authentication between viewers (clients) and CloudFront edge locations. This enables mTLS for any origin, including API Gateway HTTP APIs and WebSocket APIs that don't natively support mTLS.

**Architecture**: Client <-> mTLS <-> CloudFront <-> API Gateway (any type)

**Setup**:

1. Upload root CA and intermediate CA certificates (PEM bundle) to S3
2. Create CloudFront Trust Store referencing the S3 path
3. Enable "Viewer mutual authentication (mTLS)" on distribution settings
4. Associate the trust store with the distribution

**Modes**:

- **Required**: All clients must present valid certificates
- **Optional**: Accepts both mTLS and non-mTLS clients on the same distribution; still rejects invalid certificates

**Certificate headers forwarded to origin** (enable in origin request policy):

- `CloudFront-Viewer-Cert-Serial-Number`, `CloudFront-Viewer-Cert-Issuer`, `CloudFront-Viewer-Cert-Subject`
- `CloudFront-Viewer-Cert-Validity`, `CloudFront-Viewer-Cert-PEM`, `CloudFront-Viewer-Cert-Present`, `CloudFront-Viewer-Cert-SHA256`
- Use these headers in Lambda authorizers or backend logic for identity-based access control

**Certificate revocation**: Use CloudFront Connection Functions + KeyValueStore for real-time CRL checks during TLS handshake:

- Store revoked serial numbers in KeyValueStore
- Connection function checks `connection.clientCertificate.certificates.leaf.serialNumber` against KVS
- Call `connection.deny()` for revoked certificates; rejection happens at the edge before any request reaches the origin

**Connection functions**: Execute custom logic during TLS handshake (before viewer request). Can allow, deny, or log connection details. Use `connection.logCustomData()` for custom connection log entries.

**Monitoring**: CloudFront connection logs capture TLS handshake details. Each connection gets a unique `connectionId` that correlates across connection logs, standard logs, and real-time logs.

**Options**:

- `Ignore certificate expiration date`: Accept expired certificates (useful for gradual migration)
- `Advertise trust store CA names`: Send list of accepted CA distinguished names to clients
- Certificate chain depth supported: up to 4 (root + intermediates)

**When to use CloudFront viewer mTLS instead of API Gateway mTLS**:

- HTTP APIs or WebSocket APIs that don't support native mTLS
- Need edge-based certificate validation (lower latency for global clients)
- Need optional mode (mixed mTLS and non-mTLS on same endpoint)
- Need Connection Functions for custom TLS handshake logic
- Need real-time CRL checks via KeyValueStore (faster than Lambda authorizer approach)

### Private APIs + mTLS

- Private APIs do not natively support mTLS
- Pattern: ALB with mTLS "Verify with trust store" mode -> VPC endpoint -> private API
- ALB supports CRL checks on trust store
- Cross-account: client -> PrivateLink -> NLB -> ALB (mTLS) -> VPC endpoint -> private API

## Resource Policies (REST API)

### IP-Based Access Control

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "execute-api:/*"
    },
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "execute-api:/*",
      "Condition": { "NotIpAddress": { "aws:SourceIp": ["203.0.113.0/24", "198.51.100.0/24"] } }
    }
  ]
}
```

- `execute-api:/*` is a shorthand accepted only in API Gateway resource policies (API Gateway auto-expands it to the full ARN (`arn:aws:execute-api:region:account-id:api-id/*`)). Do not use this shorthand in IAM identity-based policies
- For traffic through VPC endpoint: use `aws:VpcSourceIp` instead of `aws:SourceIp`

### HTTP API IP Control

- No resource policies for HTTP APIs
- Use Lambda authorizer checking `event.requestContext.http.sourceIp` against allowlist
- Support both exact IPs and CIDR ranges

### VPC Endpoint Restriction

```json
{ "Condition": { "StringEquals": { "aws:SourceVpce": "vpce-0123456789abcdef0" } } }
```

## AWS WAF (REST API Direct; HTTP API via CloudFront)

- **REST API**: Associate Web ACL directly with API stage (no CloudFront required)
- **HTTP API**: No direct WAF association. Workaround: Place CloudFront distribution in front of HTTP API and attach WAF to CloudFront. This is a common production pattern
- Gateway response type `WAF_FILTERED` (403) when WAF blocks request
- Access log variables: `$context.waf.error`, `$context.waf.latency`, `$context.waf.status`
- **Body inspection limit**: Default 16 KB for regional API Gateway (configurable up to 64 KB in web ACL for additional cost)
- **Header inspection limit**: First 8 KB or 200 headers (whichever comes first)
- **"Distributed Denial of Wallet" protection**: Without WAF, DDoS traffic invokes Lambda authorizers for every request. WAF blocks malicious traffic before it reaches the authorizer

### Recommended Managed Rule Groups for APIs

**Tier 1: Always enable for API protection.**

| Rule Group       | Name                                    | WCU | Purpose                                                                                                                                                                   |
| ---------------- | --------------------------------------- | --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core Rule Set    | `AWSManagedRulesCommonRuleSet`          | 700 | XSS, LFI, RFI, SSRF, path traversal, size restrictions. **Note**: `SizeRestrictions_BODY` rule blocks bodies >8 KB; override to Count if your API accepts larger payloads |
| Known Bad Inputs | `AWSManagedRulesKnownBadInputsRuleSet`  | 200 | Log4j RCE, Java deserialization, PROPFIND, exploitable paths, localhost Host header                                                                                       |
| SQL Database     | `AWSManagedRulesSQLiRuleSet`            | 200 | SQL injection in query params, body, cookies, URI path                                                                                                                    |
| IP Reputation    | `AWSManagedRulesAmazonIpReputationList` | 25  | Blocks IPs from AWS threat intelligence (MadPot): malicious actors, reconnaissance, DDoS sources                                                                          |

**Tier 2: Enable based on use case.**

| Rule Group                  | Name                                    | WCU | When to use                                                                                                                                                                                                                                                                                                                                                                                                      |
| --------------------------- | --------------------------------------- | --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Anonymous IP List           | `AWSManagedRulesAnonymousIpList`        | 50  | Block TOR nodes, anonymous proxies, VPN services, hosting provider IPs. Use when API should not be accessed anonymously                                                                                                                                                                                                                                                                                          |
| Bot Control                 | `AWSManagedRulesBotControlRuleSet`      | 50  | Detect/block scrapers, automated browsers, bad bots. Common ($1/M requests) for basic detection; Targeted ($10/M requests) adds ML-based detection (same WCU, higher per-request cost). **Note**: `CategoryAI` rule blocks all AI bot traffic (both verified and unverified) unlike other category rules; override to Count and use labels (`bot:category:ai:verified` vs `unverified`) for fine-grained control |
| Admin Protection            | `AWSManagedRulesAdminProtectionRuleSet` | 100 | Block access to admin URI paths. Use if API has admin endpoints                                                                                                                                                                                                                                                                                                                                                  |
| Account Takeover Prevention | `AWSManagedRulesATPRuleSet`             | 50  | Credential stuffing protection on login endpoints. Checks against stolen credential databases. Additional fees apply                                                                                                                                                                                                                                                                                             |

**Tier 3: Custom rules for API-specific protection.**

| Rule Type             | Purpose                                                           |
| --------------------- | ----------------------------------------------------------------- |
| Rate-based rules      | Per-IP request rate limiting (complements API Gateway throttling) |
| Geo-match rules       | Block traffic from regions where you have no customers            |
| IP set rules          | Allow/deny specific IP ranges                                     |
| Size constraint rules | Custom payload size limits per endpoint                           |
| Regex pattern rules   | Block specific patterns in headers/body (e.g., malformed JWTs)    |

### WAF Best Practices for APIs

- **Start in Count mode**: Deploy managed rules in Count mode first, analyze CloudWatch metrics and WAF logs, then switch to Block
- **Use labels for custom logic**: Managed rules add labels to requests. Write custom rules that match on labels for fine-grained control (e.g., allow verified bots but block unverified ones)
- **Override specific rules**: If a managed rule causes false positives, override that single rule to Count rather than disabling the entire rule group
- **Web ACL capacity**: Default allocation is 1,500 WCU per web ACL (hard limit 5,000 via support request). WCU above 1,500 incurs additional cost ($0.20 per million requests per 500 WCU block). Plan rule group selection within this budget. Tier 1 rules alone total 1,125 WCU
- **Scope down statements**: Apply expensive rule groups (Bot Control, ATP) only to specific URI paths to reduce cost and false positives
- **WAF + API Gateway throttling**: WAF rate-based rules operate at the edge; API Gateway throttling operates at the service level. Use both for defense in depth
- **WAF token domain**: When CloudFront fronts a WAF-protected API Gateway, CloudFront rewrites the `Host` header to the origin domain. WAF challenge/CAPTCHA tokens are tied to the client-facing domain, causing a domain mismatch at the origin. Fix: add the CloudFront distribution domain to the token domain list in the origin's web ACL, and forward the `aws-waf-token` cookie to the origin

## CORS Configuration

### REST API

- Configure `OPTIONS` method with Mock integration returning CORS headers
- Lambda must ALSO return CORS headers in actual response (proxy integration)
- **Critical**: Add CORS headers to `DEFAULT_4XX` and `DEFAULT_5XX` gateway responses; otherwise errors are blocked by browser
- SAM `Cors` property helps but does NOT cover gateway responses
- Only one origin allowed in MOCK response; use `*` or Lambda integration for dynamic origin. **Security warning**: dynamically reflecting the `Origin` header without validating against an allowlist is functionally equivalent to `*` but also works with credentials. Always validate against an explicit allowlist
- Add `AddDefaultAuthorizerToCorsPreflight: false` to exclude authorizer from OPTIONS

### HTTP API

- First-class `CorsConfiguration` property: `allowOrigins`, `allowMethods`, `allowHeaders`, `exposeHeaders`, `maxAge`, `allowCredentials`
- API Gateway automatically handles OPTIONS preflight; no MOCK integration needed
- `*` for AllowOrigins does not work when `AllowCredentials` is true

### Common Gotchas

- Forgetting CORS headers on gateway responses means 403/500 errors are blocked by browser
- For private APIs: avoid `x-apigw-api-id` header (triggers preflight that fails); use Host header instead
- `Access-Control-Allow-Origin` must match requesting origin exactly when using credentials

## HttpOnly Cookie Authentication

Pattern for preventing XSS token theft:

1. **OAuth2 callback Lambda**: Exchanges auth code for access token, returns via `Set-Cookie` header with `HttpOnly`, `Secure`, `SameSite=Lax`
2. **Lambda authorizer**: Extracts cookie from request, validates JWT, allows/denies
3. Identity source: `$request.header.cookie` for caching
4. Use `aws-jwt-verify` library; create verifier outside handler for JWKS caching across warm starts

## API Gateway Architecture

- API Gateway is a **multi-tenant managed service** running in an AWS-managed VPC; nothing is deployed into customer VPCs
- This is why VPC Links exist: they bridge the gap between the AWS-managed VPC (where API Gateway runs) and your VPC (where private resources live)
- API Gateway has internet connectivity by default, which is why it can reach external endpoints even when your VPC cannot

## Security at All Layers

Apply security at every component, not just the data plane (who can call APIs). Also secure the **control plane** (who can modify/deploy APIs).

## Cache Encryption (REST API)

- API Gateway cache is **not encrypted at rest by default**; encryption must be explicitly enabled when provisioning the cache
- **Cache is not isolated per API key by default**: one client can receive cached responses generated for another client if the cache key parameters (path, query strings, configured headers) match. To prevent this, add a client-identifying parameter (e.g., API key header) as a cache key
- For APIs handling sensitive data, always enable cache encryption
- Cache encryption can only be set at cache creation time; changing it requires re-provisioning

## Logging Data Sensitivity

- Standard execution logging auto-redacts authorization headers, API key values, and similar sensitive parameters
- **Data tracing** (separate option from execution logging) logs full request/response bodies including PII and credentials. AWS recommends against enabling data tracing in production
- Treat CloudWatch log groups containing execution logs as sensitive data: apply appropriate IAM access controls, retention policies, and CloudWatch Logs data protection policies

## Binary Data Security

- Register binary media types explicitly (e.g., `image/png`, `application/octet-stream`)
- Avoid `*/*` in binary media types unless intentional, as it treats ALL content as binary
- For file uploads via S3: use presigned URLs for large files instead of proxying through API Gateway (10 MB payload limit)
