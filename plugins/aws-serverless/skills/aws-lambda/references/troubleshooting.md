# Troubleshooting Guide

## Symptom-Based Diagnosis

### High Latency

**Possible causes (check in order):**

1. Cold start — check if latency is only on first invocations after idle
2. Under-provisioned memory — more memory = more CPU
3. Slow external calls — database, HTTP APIs, other AWS services
4. Large deployment package — increases cold start time

**Diagnosis steps:**

- Use `get_metrics` to check duration (average vs p99) and memory utilization
- Enable X-Ray tracing to identify which segment is slow
- Check if function is in a VPC (adds ENI setup time on cold start)

**Resolution:**

- For cold starts: initialize SDK clients outside handler, reduce package size, consider provisioned concurrency
- For slow external calls: use connection reuse, add VPC endpoints, increase timeout
- For CPU-bound work: increase memory allocation

### Function Errors

**Possible causes:**

1. Unhandled exceptions in application code
2. Timeout exceeded
3. Out of memory (OOM)
4. Permission denied on AWS API calls

**Diagnosis steps:**

- Use `sam_logs` to retrieve recent CloudWatch logs for the function
- Look for `Task timed out`, `Runtime.ExitError`, or `AccessDeniedException` messages
- Check the error rate trend with `get_metrics`

**Resolution by error type:**

| Error Message                    | Cause                        | Fix                                                     |
| -------------------------------- | ---------------------------- | ------------------------------------------------------- |
| `Task timed out after X seconds` | Execution exceeded timeout   | Increase timeout, increase memory, optimize code        |
| `Runtime.ExitError`              | OOM or process crash         | Increase memory, check for memory leaks                 |
| `AccessDeniedException`          | Missing IAM permission       | Add the required action to the function's IAM role      |
| `ResourceNotFoundException`      | Wrong resource ARN or region | Verify the resource exists in the correct region        |
| `TooManyRequestsException`       | Concurrency limit reached    | Increase reserved concurrency or request limit increase |

### Async Invocations and Throttling

**Common misconception:** Async Lambda invocations (`InvocationType: Event`) are subject to throttling like sync invocations.

**Reality:** Async invocations are **always accepted** — Lambda's Event Invoke Frontend queues the request without checking concurrency limits. The invocation call itself never returns a throttle error. Throttling is only checked later when the internal poller attempts to run the function synchronously. If throttled at that point, the event is returned to the internal queue and retried for **up to 6 hours**.

**Practical implications:**

- You do not need SNS or EventBridge as a throttle-protection buffer in front of async Lambda invocations — direct Lambda-to-Lambda async calls are safe
- If you need guaranteed delivery with a DLQ, configure one on the function directly
- Async invocations with reserved concurrency set to 0 will still be accepted but will fail during processing — they will retry and eventually go to the DLQ or on-failure destination

### Throttling and Concurrency Limits

**Symptoms:** `TooManyRequestsException`, 429 errors from API Gateway, `Throttles` metric rising

**Key concurrency facts:**

- Default account limit: **1,000 concurrent executions** per region (shared across all functions)
- **Concurrency ≠ requests per second**: Concurrency = avg_RPS × avg_duration_seconds
- Burst limit: Lambda can scale by **500 new concurrent executions per 10 seconds** (on-demand)

**Diagnosis:**

1. Check `ConcurrentExecutions` and `Throttles` metrics in CloudWatch with `get_metrics`
2. Check if a single function is consuming all available concurrency
3. Run `aws lambda get-account-settings` to see your account limit vs reserved allocations

**Resolution:**

- Set reserved concurrency on high-priority functions to guarantee capacity
- Set reserved concurrency on lower-priority functions to cap their usage
- Request a concurrency quota increase via AWS Service Quotas if the account limit is the bottleneck
- Use SQS as a buffer in front of Lambda to absorb traffic spikes without throttling

### Deployment Failures

**Common errors and solutions:**

| Error                                 | Cause                                        | Solution                                                                             |
| ------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------ |
| `Build Failed`                        | Missing dependencies or incompatible runtime | Run `sam_build` with `use_container: true`, verify `requirements.txt`/`package.json` |
| `CREATE_FAILED` on IAM role           | Missing `CAPABILITY_IAM`                     | Add `capabilities = "CAPABILITY_IAM"` to samconfig.toml                              |
| `ROLLBACK_COMPLETE`                   | Resource creation failed                     | Check CloudFormation events for the specific resource failure                        |
| `No changes to deploy`                | No diff from last deploy                     | Verify `sam_build` ran, check correct samconfig profile                              |
| `Stack is in ROLLBACK_COMPLETE state` | Previous deploy failed                       | Delete the stack with `aws cloudformation delete-stack`, then redeploy               |

## API Gateway Issues

### CORS Errors

**Symptoms:** Browser blocking requests, `Access-Control-Allow-Origin` errors

**Checklist:**

- Verify CORS is configured on the API Gateway (AllowOrigin, AllowMethods, AllowHeaders)
- Check that OPTIONS method returns correct headers
- Ensure AllowOrigin matches the frontend domain (not `*` in production)
- Verify Lambda response includes CORS headers if using proxy integration

### 5xx Errors

**Symptoms:** API returning 500/502/503 errors

**Diagnosis:**

- 502 Bad Gateway: Lambda returned invalid response format. Check that response includes `statusCode` and `body`.
- 503 Service Unavailable: Lambda throttled. Check concurrency limits.
- 500 Internal Server Error: Check Lambda logs for unhandled exceptions.

## Event Source Mapping Issues

### When to Use Which Tool

| Symptom                            | Tool to Use                      |
| ---------------------------------- | -------------------------------- |
| Need to set up a new ESM           | `esm_guidance`                   |
| ESM exists but performance is poor | `esm_optimize`                   |
| Kafka/MSK connection failing       | `esm_kafka_troubleshoot`         |
| Need IAM policy for ESM            | `secure_esm_*` (source-specific) |

### DynamoDB Streams — High Iterator Age

**Symptoms:** `IteratorAge` metric increasing in CloudWatch

**Diagnosis steps:**

1. Check `ParallelizationFactor` — default is 1, maximum is 10
2. Check function duration — slow processing causes backlog
3. Check for poison records causing repeated retries
4. Check concurrency — throttling prevents scaling

**Resolution:**

- Increase `ParallelizationFactor` and `BatchSize`
- Enable `BisectBatchOnFunctionError` to isolate bad records
- Set `MaximumRetryAttempts` to limit retries on persistent failures
- Use `esm_optimize` for specific tuning recommendations

### Kinesis — Shard Throttling

**Symptoms:** `ReadProvisionedThroughputExceeded` errors

**Resolution:**

- Check if multiple consumers share the same shard (each shard supports 2 MB/s reads)
- Use enhanced fan-out for multiple consumers
- Consider switching to ON_DEMAND stream mode for automatic scaling
- Increase shard count for PROVISIONED mode

### SQS — Messages Going to DLQ

**Symptoms:** Messages accumulating in dead-letter queue

**Diagnosis:**

- Check that `VisibilityTimeout` on the queue is >= Lambda function timeout
- Check for partial batch failures: enable `ReportBatchItemFailures` in `FunctionResponseTypes`
- Check `maxReceiveCount` in the redrive policy (too low causes premature DLQ routing)

### Kafka/MSK — Connection Failures

**Symptoms:** ESM stays in `Creating` or `Failed` state

**Use `esm_kafka_troubleshoot` with the error message.** Common causes:

- Lambda not in same VPC as MSK cluster
- Security group missing inbound rule on ports 9092/9094
- IAM authentication not configured correctly
- SASL/SCRAM secret not in the correct format

## VPC and Networking

### Lambda Cannot Reach AWS Services

**Symptoms:** Timeouts when calling DynamoDB, S3, SQS from VPC-attached Lambda

**Cause:** Lambda in VPC private subnets cannot reach AWS service endpoints without a path.

**Resolution options (choose one):**

- Add VPC gateway endpoints for DynamoDB and S3 (free, recommended)
- Add VPC interface endpoints for other services (per-hour + per-GB cost)
- Add NAT Gateway in public subnet (higher cost, required for internet access)
- **Use IPv6 + Egress-Only Internet Gateway** for internet access — Lambda now supports IPv6, so if your VPC has IPv6 CIDR blocks and an Egress-Only Internet Gateway, Lambda functions can reach the internet without a NAT Gateway, eliminating NAT Gateway costs entirely

### ENI Exhaustion

**Symptoms:** Lambda functions fail to start, `ENILimitReached` errors

**Resolution:**

- Use multiple subnets across AZs (each /24 subnet provides ~250 IPs)
- Set reserved concurrency to cap the maximum ENI usage
- Lambda uses Hyperplane ENIs which are shared, but high concurrency can still exhaust IPs

## Lambda SnapStart Issues

SnapStart issues are specific to Java 11+, Python 3.12+, and .NET 8+ functions with `SnapStart: ApplyOn: PublishedVersions`.

### Stale unique values

**Symptom:** All invocations share the same UUID, timestamp, or random value

**Cause:** Value was generated during initialization (before snapshot), so all restored environments use the same value.

**Fix:** Move any call to `uuid.uuid4()`, `random`, `time.time()`, or similar into the handler function body, not at module level.

### Stale database connection after restore

**Symptom:** Database errors on the first call after a period of inactivity

**Cause:** The connection object was captured in the snapshot but the actual TCP connection is no longer valid after resume.

**Fix:** Validate the connection before use, or use a `lambda_runtime_api_prepare_to_invoke` hook to re-establish it after restoration.

### SnapStart not activating

**Symptom:** Cold starts still slow despite SnapStart enabled

**Check:**

- SnapStart only applies to **published versions** and aliases pointing to them, not `$LATEST`
- The function is not using provisioned concurrency, EFS, or ephemeral storage > 512 MB
- The runtime is Java 11+, Python 3.12+, or .NET 8+

## Debugging Workflow

When a function is failing and the cause is unclear, follow this sequence:

1. **Check logs**: Use `sam_logs` to get recent log output
2. **Check metrics**: Use `get_metrics` to identify error rate, duration, and throttle trends
3. **Check configuration**: Verify timeout, memory, VPC, and IAM settings in the SAM template
4. **Test locally**: Use `sam_local_invoke` with the failing event payload to reproduce
5. **Test deployed function**: Use `sam remote invoke` with the failing event to test directly in AWS — bypasses local environment differences
6. **Trace calls**: Enable X-Ray tracing to identify which downstream call is failing
7. **Check dependencies**: Verify external services (databases, APIs) are reachable and healthy
