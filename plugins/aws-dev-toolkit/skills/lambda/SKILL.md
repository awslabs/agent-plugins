---
name: lambda
description: Design, build, and optimize AWS Lambda functions. Use when creating new Lambda functions, troubleshooting cold starts, configuring event sources, optimizing performance, managing layers and concurrency, or choosing deployment strategies.
---

You are an AWS Lambda specialist. Help teams build production-grade Lambda functions with the right patterns and avoid common pitfalls.

## Decision Framework: Runtime Selection

| Runtime | Cold Start | Ecosystem | Best For |
|---|---|---|---|
| Python 3.12+ | ~200-400ms | Rich AWS SDK, data libs | Glue scripts, APIs, data processing |
| Node.js 20+ | ~150-300ms | Fast I/O, large npm ecosystem | APIs, real-time processing, event-driven |
| Java 21 (with SnapStart) | ~200-500ms (with SnapStart) | Enterprise libraries, strong typing | Enterprise workloads, existing Java teams |
| Java 21 (without SnapStart) | ~3-8s | Same | Avoid for latency-sensitive workloads |
| Rust (custom runtime) | ~10-30ms | Minimal cold start, max performance | High-throughput, latency-critical |
| .NET 8 (AOT) | ~200-400ms | Enterprise, C# ecosystem | .NET shops, AOT compilation helps |
| Go (custom runtime) | ~20-50ms | Simple deployment, fast | CLI tools, high-perf event processing |

**Opinionated recommendation**: Default to Python or Node.js — they have the fastest cold starts among managed runtimes, the richest AWS SDK ecosystem, and the largest pool of Lambda-specific community examples and tooling (Powertools, Middy, etc.). Use Rust/Go for performance-critical paths where you need sub-50ms cold starts and maximum throughput per dollar. Use Java only with SnapStart enabled — without SnapStart, Java cold starts (3-8s) make it unsuitable for synchronous API workloads. Avoid Ruby and .NET (non-AOT) for new projects because their Lambda ecosystems are smaller, cold starts are worse, and AWS investment in tooling (Powertools, SAM templates, CDK constructs) is concentrated on Python and Node.js.

## SnapStart (Java Only)

SnapStart eliminates Java cold starts by snapshotting the initialized execution environment after the init phase completes. This brings Java cold starts from 3-8s down to 200-500ms — comparable to Python/Node.js. The tradeoff is that SnapStart requires published versions (not $LATEST) and can cause issues with code that assumes unique initialization (random seeds, unique IDs, network connections) since the snapshot is reused. For most Java workloads, the cold start improvement far outweighs the complexity. Enable it for all Java Lambda functions unless you have a specific reason not to (e.g., functions that open database connections during init that can't be restored from snapshot):

```bash
aws lambda update-function-configuration \
  --function-name my-function \
  --snap-start ApplyOn=PublishedVersions

# You MUST publish a version after enabling SnapStart
aws lambda publish-version --function-name my-function
```

**Gotcha**: SnapStart requires published versions. It does NOT work with $LATEST. Use aliases to point to the latest published version.

## Cold Start Optimization

Priority order for reducing cold starts:

1. **Reduce package size**: Strip unused dependencies. Use bundlers (esbuild for Node.js, `--slim` for Python).
2. **Enable SnapStart** (Java): Non-negotiable for Java Lambdas.
3. **Provisioned Concurrency**: Only for strict latency SLAs (<100ms p99). Costs money per hour.
4. **Keep functions warm**: Anti-pattern. Use provisioned concurrency instead.
5. **ARM64 (Graviton)**: 20% cheaper AND often faster cold starts. Always use `arm64` unless a dependency requires x86.

```bash
# Set provisioned concurrency on an alias
aws lambda put-provisioned-concurrency-config \
  --function-name my-function \
  --qualifier prod \
  --provisioned-concurrent-executions 5
```

## Powertools for AWS Lambda

Use Powertools for any Lambda that runs in production. Without it, you end up hand-rolling structured logging, manual X-Ray segment creation, and custom CloudWatch metric publishing — all of which Powertools handles in a few decorators. The alternative is raw `print()` statements and unstructured logs, which make debugging production issues significantly harder because CloudWatch Logs Insights can't query unstructured text efficiently. Powertools also injects Lambda context (request ID, function name, cold start flag) into every log line automatically, which is critical for correlating logs across concurrent invocations. Available for Python and Node.js/TypeScript.

Core capabilities: structured logging with Lambda context injection, X-Ray tracing with annotations/metadata, CloudWatch metrics, and cached parameter/secret retrieval.

See `references/powertools-patterns.md` for full code examples (Python and TypeScript), decorator usage, SAM/CDK setup, and parameters/secrets patterns.

## Concurrency Model

```
Account concurrency limit (default 1000 per region)
  ├── Unreserved concurrency (shared pool)
  ├── Reserved concurrency (function-level guarantee AND cap)
  └── Provisioned concurrency (pre-initialized, subset of reserved)
```

- **Reserved concurrency**: Guarantees capacity AND limits max concurrency. Use to protect downstream services.
- **Provisioned concurrency**: Pre-initialized environments. Eliminates cold starts. Costs ~$0.015/GB-hour.

```bash
# Reserve concurrency (cap and guarantee)
aws lambda put-function-concurrency \
  --function-name my-function \
  --reserved-concurrent-executions 100

# Check account-level concurrency
aws lambda get-account-settings --query 'AccountLimit'
```

## Event Source Mapping Patterns

Key principles for all poll-based event sources (SQS, DynamoDB Streams, Kinesis):
- **SQS**: Always enable `ReportBatchItemFailures` to avoid reprocessing entire batches on partial failures.
- **DynamoDB Streams**: Always configure `bisect-batch-on-function-error`, `maximum-retry-attempts`, and a DLQ destination.
- **Kinesis**: Use `parallelization-factor` (1-10) for concurrent batch processing per shard. Configure bisect and DLQ as with DynamoDB Streams.

See `references/event-sources.md` for full CLI commands, SAM/CDK templates, and patterns for SQS, DynamoDB Streams, Kinesis, API Gateway, S3, and EventBridge.

## Lambda Layers

Use layers for shared dependencies, NOT for shared code (use packages/libraries for that).

```bash
# Publish a layer
aws lambda publish-layer-version \
  --layer-name my-dependencies \
  --compatible-runtimes python3.12 \
  --zip-file fileb://layer.zip

# Add layer to function
aws lambda update-function-configuration \
  --function-name my-function \
  --layers arn:aws:lambda:us-east-1:123456789:layer:my-dependencies:1
```

**Opinionated**: Prefer bundling dependencies into the deployment package over layers. Layers seem convenient for sharing code, but they create hidden version coupling — when you update a layer, every function using it gets the new version on next deploy, which can break functions that weren't tested against the update. Layers also make local testing harder (you need to download/mount them) and make deployment packages non-self-contained (the function ZIP alone doesn't tell you what it depends on). Use layers only for: (1) shared binary dependencies that are large and rarely change (e.g., FFmpeg, Pandoc), (2) Powertools/common utilities used across 10+ functions where the version coupling is intentional, (3) Lambda Extensions.

## Deployment Patterns

- **SAM**: Recommended for Lambda-centric projects. Supports `sam local invoke` for local testing.
- **CDK**: Recommended for complex infrastructure with multiple service integrations.
- **Direct CLI**: For quick iterations during development.

See `references/event-sources.md` for deployment commands and SAM/CDK template examples.

## Common CLI Commands

```bash
# Invoke a function
aws lambda invoke --function-name my-function --payload '{"key":"value"}' response.json

# Tail logs in real time
aws logs tail /aws/lambda/my-function --follow

# Get function configuration
aws lambda get-function-configuration --function-name my-function

# List event source mappings
aws lambda list-event-source-mappings --function-name my-function

# View recent errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/my-function \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s000 2>/dev/null || date -v-1H +%s000)

# Check throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Throttles \
  --dimensions Name=FunctionName,Value=my-function \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Sum
```

## Anti-Patterns

1. **Monolith Lambda**: One giant function handling all routes. Use separate functions per concern or API Gateway + Powertools event handler for REST APIs.
2. **Lambda calling Lambda synchronously**: Creates tight coupling, double billing, and cascading failures. Use Step Functions, SQS, or EventBridge instead.
3. **Storing state in /tmp**: The /tmp directory persists between warm invocations but is NOT guaranteed. Use DynamoDB, S3, or ElastiCache.
4. **No DLQ on async invocations**: Failed async invocations are silently dropped after 2 retries. Always configure a DLQ or on-failure destination.
5. **VPC Lambda without NAT or VPC endpoints**: Lambda in a VPC loses internet access. Add a NAT Gateway or VPC endpoints for AWS service calls.
6. **Ignoring ARM64/Graviton**: x86 is the default but ARM64 is 20% cheaper with equal or better performance for most workloads. Always specify `arm64`.
7. **Oversized deployment packages**: Large packages increase cold starts. Keep packages small. Use layers for large shared binaries.
8. **Hardcoded timeouts at function max**: Set function timeout to actual expected duration + buffer, not the max 15 minutes. Pair with API Gateway's 29s hard limit awareness.
9. **No reserved concurrency on critical functions**: Without reserved concurrency, one runaway function can starve others by consuming the entire account limit.
10. **Using environment variables for secrets**: Use AWS Secrets Manager or SSM Parameter Store (SecureString) with caching via Powertools Parameters.

## Memory and Performance Tuning

Lambda CPU scales proportionally with memory. At 1,769 MB you get 1 full vCPU.

```bash
# Use AWS Lambda Power Tuning (Step Functions-based tool) to find optimal memory
# https://github.com/alexcasalboni/aws-lambda-power-tuning

# Quick rule of thumb:
# - I/O bound (API calls, DB queries): 256-512 MB
# - CPU bound (data processing, image manipulation): 1024-3008 MB
# - Memory bound (large payloads, ML inference): 3008-10240 MB
```

**Always benchmark**. Increasing memory often REDUCES cost because the function finishes faster (you pay for GB-seconds).

## Reference Files

- `references/powertools-patterns.md` -- Full Powertools code examples (Python and TypeScript), structured logging, tracing, parameters/secrets, and SAM/CDK setup.
- `references/event-sources.md` -- Event source mapping CLI commands, SAM/CDK templates for SQS, DynamoDB Streams, Kinesis, API Gateway, S3, EventBridge, and deployment patterns.

## Related Skills

- `api-gateway` -- API Gateway configuration, routing, authorization, and Lambda integration patterns.
- `dynamodb` -- Table design, access patterns, streams, and DynamoDB-Lambda integration.
- `step-functions` -- Orchestrating Lambda functions with state machines instead of direct invocation chains.
- `messaging` -- SQS, SNS, and EventBridge patterns for async Lambda triggers.
- `observability` -- CloudWatch metrics, alarms, dashboards, and X-Ray tracing beyond Powertools.
- `iam` -- Least-privilege execution roles, resource policies, and cross-account access for Lambda.
