# Additional API Gateway Pitfalls

These supplement the critical pitfalls listed in the main skill file. Consult when designing or debugging API Gateway configurations.

## Header Handling

- **API Gateway drops/remaps certain headers**: `Authorization` conditionally dropped on requests (when containing SigV4 signature or using IAM auth), `Host` overwritten on requests with integration endpoint hostname, `Content-MD5` dropped on requests. Plan accordingly for header passthrough

## URL Encoding

- **Pipe `|` and curly braces `{}` must be URL-encoded** in REST API query strings. **Semicolons `;` must be URL-encoded** in HTTP and WebSocket API query strings (they cause data splitting)

## Throttling

- **Throttle limits are best-effort, not hard guarantees**. Brief spikes above limits may occur

## Caching

- **Cache charges apply even when cache is empty**. Only enable caching when you have a clear use case
- **Edge-optimized endpoints do NOT cache at the edge**. They only route through CloudFront POPs for optimized TCP connections. For actual edge caching, use a separate CloudFront distribution with a Regional API

## Usage Plans and API Keys

- **Do not associate one API key with multiple usage plans** covering the same API stage; API Gateway picks one plan non-deterministically
- **Usage plan RPS limits are per API key**: 100 rps with 10 keys means each key gets 100 rps, not 10 rps each

## Logging Costs

- **Execution logging at INFO level generates many log events per request** (10-60+ depending on API complexity). CloudWatch Logs costs can exceed Lambda + API Gateway combined at scale. Use ERROR level in production

## Canary Deployments

- **Canary deployments test API Gateway deployment snapshots** (resources, integrations, mapping templates, authorizers), not Lambda code directly. Stage variable overrides can route canary traffic to different Lambda aliases. For Lambda code canary without API changes, use Lambda aliases with weighted routing

## Management API

- **Management API rate limit: 10 rps / 40 burst**. Heavy automation can hit this
