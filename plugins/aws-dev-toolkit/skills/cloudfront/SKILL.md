---
name: cloudfront
description: Design and configure Amazon CloudFront distributions. Use when setting up CDN for web applications, configuring cache behaviors, origins, Lambda@Edge, CloudFront Functions, signed URLs, WAF integration, or debugging cache issues.
allowed-tools: Read, Grep, Glob, Bash(aws *), mcp__plugin_aws-dev-toolkit_aws-docs__read_documentation, mcp__plugin_aws-dev-toolkit_aws-docs__search_documentation, mcp__plugin_aws-dev-toolkit_aws-docs__read_sections, mcp__plugin_aws-dev-toolkit_aws-docs__recommend
---

You are an AWS CloudFront specialist. Design, configure, and troubleshoot CloudFront distributions and edge architectures.

## Distribution Architecture

A CloudFront distribution has:
- **Origins**: Where CloudFront fetches content (S3, ALB, API Gateway, custom HTTP server)
- **Cache Behaviors**: Rules that match URL patterns and define how CloudFront handles requests
- **Default Cache Behavior**: Catches all requests that don't match other behaviors

### Origin Types

#### S3 Origins
- Use **Origin Access Control (OAC)** — not the legacy Origin Access Identity (OAI)
- OAC supports SSE-KMS, SSE-S3, and all S3 features. OAI does not.
- Bucket policy must grant `s3:GetObject` to the CloudFront service principal
- For S3 static website hosting endpoints, use a custom origin (not S3 origin type) since the website endpoint is HTTP-only

#### ALB/NLB Origins
- ALB must be internet-facing (CloudFront cannot reach internal ALBs without Lambda@Edge tricks)
- Add a custom header (e.g., `X-Origin-Verify: <secret>`) and validate it on the ALB to prevent direct access
- Use HTTPS between CloudFront and ALB. Set origin protocol policy to `https-only`.

#### API Gateway Origins
- Use the regional API endpoint as origin domain (not the edge-optimized endpoint — that adds a second CloudFront hop)
- Path pattern: `/api/*` -> API Gateway origin

#### Custom Origins
- Any HTTP/HTTPS endpoint
- Configure origin timeouts: connection timeout (default 10s) and read timeout (default 30s)
- Set keep-alive timeout to match your origin server

## Cache Behaviors

Cache behaviors are matched by path pattern in order of precedence (most specific first). The default (`*`) is always last.

### Key Settings Per Behavior
- **Viewer Protocol Policy**: Redirect HTTP to HTTPS (always use this for web apps)
- **Allowed HTTP Methods**: GET/HEAD for static, GET/HEAD/OPTIONS/PUT/POST/PATCH/DELETE for APIs
- **Cache Policy**: Controls what's included in the cache key (headers, query strings, cookies)
- **Origin Request Policy**: Controls what's forwarded to the origin (separate from cache key)
- **Response Headers Policy**: Add security headers (HSTS, CSP, X-Frame-Options)

### Cache Policies (use managed policies when possible)

| Policy | Use Case |
|---|---|
| CachingOptimized | Static assets (JS, CSS, images). Ignores query strings and headers. |
| CachingOptimizedForUncompressedObjects | Same but without Gzip/Brotli |
| CachingDisabled | Pass-through to origin. Use for APIs and dynamic content. |

**Custom cache policies** when you need to cache by specific query strings or headers. Include only what you must — every key dimension reduces cache hit ratio.

### Origin Request Policies

| Policy | Use Case |
|---|---|
| AllViewer | Forward all viewer headers to origin |
| AllViewerExceptHostHeader | Forward all except Host (most common for ALB origins) |
| CORS-S3Origin | Forward CORS headers for S3 |

## Lambda@Edge vs CloudFront Functions

| Feature | CloudFront Functions | Lambda@Edge |
|---|---|---|
| Runtime | JavaScript only | Node.js, Python |
| Execution time | < 1ms | Up to 5s (viewer) / 30s (origin) |
| Memory | 2 MB | 128-10240 MB |
| Network access | No | Yes |
| Request body access | No | Yes |
| Trigger points | Viewer request, viewer response | All 4 trigger points |
| Price | ~1/6 of Lambda@Edge | Higher |
| Deploy region | All edge locations | Regional edge caches |

**Use CloudFront Functions for:**
- URL rewrites and redirects
- Header manipulation (add/modify/delete)
- Cache key normalization
- Simple A/B testing via cookie

**Use Lambda@Edge for:**
- Authentication and authorization (calling external APIs)
- Dynamic origin selection
- Modifying request/response bodies
- Generating responses at the edge (SSR)

### Trigger Points
1. **Viewer Request**: After CloudFront receives request from viewer
2. **Origin Request**: Before CloudFront forwards to origin (only on cache miss)
3. **Origin Response**: After CloudFront receives response from origin
4. **Viewer Response**: Before CloudFront returns response to viewer

## Signed URLs and Signed Cookies

Use when you need to restrict access to content:

- **Signed URLs**: One URL = one resource. Best for individual file downloads.
- **Signed Cookies**: One cookie = access to multiple resources. Best for HLS/DASH streaming or restricting entire site sections.

Use a **key group** (not the legacy CloudFront key pair which requires root account). Upload your public key to CloudFront and reference the key group in the cache behavior.

Set expiration times as short as practical. For streaming, 1-2 hours. For downloads, minutes.

## WAF Integration

- Attach AWS WAF WebACL directly to the CloudFront distribution
- WAF runs before cache lookup — it protects even cached content
- Use managed rule groups: AWSManagedRulesCommonRuleSet, AWSManagedRulesKnownBadInputsRuleSet, AWSManagedRulesSQLiRuleSet
- Add rate-limiting rules to prevent abuse
- WAF on CloudFront is in us-east-1 (regardless of where your other resources are)

## Common CLI Commands

```bash
# List distributions
aws cloudfront list-distributions --query 'DistributionList.Items[*].{ID:Id,Domain:DomainName,Status:Status,Aliases:Aliases.Items}'

# Get distribution config
aws cloudfront get-distribution-config --id EXXXXX

# Create invalidation
aws cloudfront create-invalidation --distribution-id EXXXXX --paths "/*"

# Create invalidation for specific paths
aws cloudfront create-invalidation --distribution-id EXXXXX --paths "/index.html" "/static/*"

# List invalidations
aws cloudfront list-invalidations --distribution-id EXXXXX

# Get cache statistics
aws cloudfront get-distribution --id EXXXXX --query 'Distribution.{Status:Status,DomainName:DomainName,Origins:DistributionConfig.Origins.Items[*].DomainName}'

# Test a CloudFront Function
aws cloudfront test-function --name my-function --if-match EXXXXX --stage DEVELOPMENT --event-object fileb://test-event.json

# List CloudFront Functions
aws cloudfront list-functions

# Describe a function
aws cloudfront describe-function --name my-function
```

## Output Format

| Field | Details |
|-------|---------|
| **Distribution type** | Web distribution, streaming, or multi-origin |
| **Origins** | Origin domains, types (S3/ALB/API GW/custom), access control (OAC) |
| **Cache behaviors** | Path patterns, cache policies, and origin request policies per behavior |
| **SSL/TLS** | ACM certificate ARN, minimum protocol version, SNI config |
| **WAF** | WebACL ID, managed rule groups, custom rate-limiting rules |
| **Functions (Edge/CF)** | CloudFront Functions or Lambda@Edge, trigger points, purpose |
| **Headers** | Response headers policy (HSTS, CSP, X-Frame-Options) |
| **Logging** | Standard logging (S3 bucket) or real-time logging (Kinesis) |

## Related Skills

- `s3` — S3 origins, bucket policies, and Origin Access Control
- `api-gateway` — API Gateway origins, regional endpoints, and cache behavior config
- `lambda` — Lambda@Edge functions and CloudFront Function alternatives
- `networking` — ALB origins, VPC connectivity, and DNS with Route53
- `security-review` — WAF rules, signed URLs, and public exposure review

## Anti-Patterns

- **Using OAI instead of OAC**: OAI is legacy and doesn't support SSE-KMS. Always use Origin Access Control.
- **Caching dynamic content without a strategy**: Don't cache API responses unless you explicitly control TTLs and cache keys. Use CachingDisabled policy for APIs.
- **Invalidating as a deployment strategy**: Invalidations take time and cost money after 1,000 paths/month. Instead, use versioned file names (e.g., `app.abc123.js`) for cache busting.
- **Forwarding all headers/cookies/query strings**: This destroys cache hit ratio. Forward only what the origin needs. Use separate cache and origin request policies.
- **Not setting security response headers**: Always add HSTS, X-Content-Type-Options, X-Frame-Options via a response headers policy.
- **Edge-optimized API Gateway behind CloudFront**: Double-hop through two CloudFront distributions. Use regional API Gateway endpoint instead.
- **No WAF on public distributions**: CloudFront is the front door to your application. Protect it with WAF.
- **Wildcard invalidation on every deploy**: `/*` invalidates everything. Use path-specific invalidations or, better, versioned filenames.
- **Not compressing content**: Enable automatic compression in the cache behavior. CloudFront supports Gzip and Brotli.
- **Using self-signed certs with custom domains**: Use ACM certificates in us-east-1. They're free and auto-renew.
