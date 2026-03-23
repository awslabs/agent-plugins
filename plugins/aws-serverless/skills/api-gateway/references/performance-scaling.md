# Performance and Scaling

## Throttling

### Account-Level Defaults

**Note**: Throttling values below are **default quotas**; most are adjustable via AWS Support or Service Quotas console. Do not use defaults for capacity planning without checking your account's current limits. See [latest quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html).

- **10,000 requests per second** steady-state across all REST APIs, HTTP APIs, WebSocket APIs, and WebSocket callback APIs in a region (shared quota)
- **5,000 burst** capacity (token bucket algorithm)
- These are defaults; request increases via AWS Support or Service Quotas

### Stage-Level and Method-Level

- Stage/method-level default throttle: configure via MethodSettings on the stage (REST API)
- Per-consumer throttle: configure via usage plans (REST API only)
- Method-level throttling overrides stage-level
- Max method-level throttle settings per stage: 20
- Format: `resourcePath/httpMethod` (e.g., `/pets/GET`)

### HTTP API Throttling

- Route-level throttling only (no usage plans or API keys)
- Configure via stage settings
- Limits apply globally across all callers, with no per-consumer throttling. For per-consumer rate limiting on HTTP API, implement in a Lambda authorizer or backend

### Usage Plans (REST API Only)

- **Quota**: Requests per day, week, or month
- **Throttle**: Rate (requests/second) + burst
- **RPS limits are per API key**, not split across keys. If a usage plan allows 100 rps and has 10 keys, each key gets 100 rps (not 10 rps each)
- Combine with API keys to track and limit per-consumer usage
- Max 300 usage plans per region (adjustable), 10,000 API keys per region
- **API key source**: `HEADER` (default, `x-api-key`) or `AUTHORIZER` (Lambda returns key in `usageIdentifierKey`)
- **Do not associate one API key with multiple usage plans** that cover the same API stage; API Gateway picks one plan non-deterministically. One key per plan per stage is safe; a usage plan can have many keys

### Token Bucket Algorithm

- Bucket size = burst capacity (5,000 tokens). Refill rate = steady-state rate (10,000 tokens/second)
- Each request consumes one token. If the bucket is empty, the request is throttled (429)
- The burst capacity (5,000) is the maximum number of requests that can be served in a single instant. The steady-state rate (10,000 rps) is the maximum sustained throughput. Burst is lower than steady-state because the bucket refills faster (10,000/s) than it can be drained in one instant (5,000). Over any one-second window you can sustain 10,000 rps, but an instantaneous spike cannot exceed 5,000 concurrent requests
- Throttled requests receive 429 Too Many Requests

## Caching (REST API Only)

### Configuration

- Cache sizes: 0.5 GB, 1.6 GB, 6.1 GB, 13.5 GB, 28.4 GB, 58.2 GB, 118 GB, 237 GB
- **Default TTL**: 300 seconds
- **Max TTL**: 3,600 seconds
- **TTL=0**: Disables caching
- **Max cached response size**: 1,048,576 bytes (1 MB)
- Only **GET methods** cached by default
- Cache is **best-effort**, not guaranteed to cache every response
- Cache charges apply per hour regardless of usage; only provision when you have a clear caching use case

### Cache Keys

- Default: resource path
- Add headers, query strings, and path parameters as additional cache keys
- More cache keys = more granular caching but lower hit rate
- Include client identity into cache keys to avoid data leaks across clients

### Cache Invalidation

- Client sends `Cache-Control: max-age=0` header
- Can require authorization for invalidation requests
- Entire stage cache can be flushed via console or API
- **Automatic flush on redeployment**: Creating a new deployment to a stage flushes the entire cache, causing a temporary backend load spike ("thundering herd"). See `references/deployment.md` for mitigations

### Cache Encryption

- Encryption at rest available as option when provisioning cache

### Metrics

- `CacheHitCount`, `CacheMissCount` in CloudWatch
- Monitor miss rate to determine if cache size is adequate

### Capacity Selection

1. Run a load test against the API
2. Monitor `CacheHitCount`, `CacheMissCount`, `Latency`
3. Start with smaller cache, scale up based on miss rates
4. Cache resizing takes time; plan ahead of peak traffic

## Scaling Considerations

### API Gateway Scales Automatically

- Managed service, no capacity provisioning needed
- Be aware of service quotas and request increases proactively

### Scale the Entire Stack

- No point having high API Gateway quotas if backend cannot handle the load
- Consider: Lambda concurrency limits, DynamoDB provisioned capacity, RDS connection limits, ECS/EKS scaling policies
- **Automatic quota management** via AWS Service Quotas for proactive adjustment

### Strategies for Global Scale

- **Edge-optimized endpoints**: Route to nearest CloudFront POP. **Note**: Edge-optimized endpoints do NOT cache at the edge; they only route through CloudFront POPs to optimize TCP connections. For edge caching, use a separate CloudFront distribution in front of a Regional API
- **Self-managed CloudFront distribution**: More control over caching, WAF, and custom behaviors. This is the only way to get actual edge caching
- **Multi-region deployment**: Active-active with Route 53 latency-based routing

### Multi-Layer Caching Strategy

For maximum performance, layer caches:

1. **CloudFront**: Edge caching (reduces latency, load, AND cost, since the request never reaches API Gateway)
2. **API Gateway cache** (REST only): Regional caching (reduces latency and load but NOT cost, as the request is still counted)
3. **Application-level cache**: ElastiCache or DAX for database query caching

- CloudFront caching should be the first choice, as it provides the most benefit

### API Gateway Billing Notes

- Lambda authorizer invocations are billed by Lambda even if the request is ultimately rejected by the authorizer or by throttling. This is the "Distributed Denial of Wallet" vector below

### Load Shedding

- Use API Gateway request validation to reject invalid requests early (before hitting backend)
- Configure appropriate throttle limits per consumer tier
- Use WAF rate-based rules for DDoS protection
- **"Distributed Denial of Wallet" risk**: Without WAF, DDoS traffic invokes Lambda authorizers for every request, driving up Lambda costs (even though API Gateway itself doesn't charge for the rejected requests). WAF blocks malicious traffic before it reaches the authorizer

### Cell-Based Architecture

- Use multi-account approaches for blast radius control
- Each cell has its own API Gateway, Lambda, and database
- Route traffic to cells via custom domain and routing rules

## Payload Compression

### API Gateway Native Compression

- `minimumCompressionSize`: Set the smallest payload size (in bytes) to compress automatically. Range: 0 bytes to 10 MB
- **Test with real payloads**: compressing very small payloads can actually increase the final size. Find the optimal threshold for your data
- Works bidirectionally: API Gateway decompresses incoming requests (client sends `Content-Encoding` header) before applying mapping templates, and compresses outgoing responses (client sends `Accept-Encoding: gzip`) after applying response mapping templates
- Most effective for text-based formats (JSON, XML, HTML, YAML). Binary data (PDF, JPEG) compresses poorly
- Set on the API level (REST API and HTTP API)
- **Benchmark**: 1 MB JSON payload compressed to 220 KB (78% reduction), response latency improved by 110 ms

### Compressed Passthrough to Lambda

- With native compression, API Gateway decompresses payloads before delivering to Lambda, so the decompressed payload is still subject to Lambda's 6 MB synchronous invoke limit
- To bypass this limit, configure `binaryMediaTypes: ["application/gzip"]` so API Gateway passes compressed payloads directly to Lambda without decompressing
- Lambda then handles decompression in function code, enabling transport of payloads several times larger than the 6 MB limit
- Lambda returns compressed responses with `isBase64Encoded: true` and `Content-Encoding: gzip` headers

### Compression Trade-offs

- Compression is CPU-intensive in Lambda, adding ~124 ms for 1 MB JSON on 1 GB ARM architecture
- Always benchmark with payloads representative of your workload before enabling

## Handling Large Payloads

- **10 MB API Gateway limit** (REST and HTTP): For payloads exceeding this, use S3 presigned URLs. Client uploads/downloads directly to S3, API returns the presigned URL
- **6 MB Lambda synchronous invoke limit**: Use compressed passthrough (binary media types) to transport larger payloads, or use S3 presigned URLs
- **Response streaming** (REST API only): Supports up to 15-minute sessions, first 10 MB unrestricted then bandwidth-limited to 2 MB/s. Useful for LLM responses and large datasets
- **Lambda Function URLs**: Response streaming removes the 6 MB buffered response limit; streamed responses can be much larger (subject to function timeout and bandwidth)
- For SQS/EventBridge/Lambda async invocations (1 MB limit): Use compression or store payload in S3 and pass a reference in the message
