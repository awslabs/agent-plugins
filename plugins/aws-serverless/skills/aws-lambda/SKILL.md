---
name: aws-lambda
description: "Design, build, deploy, test, and debug serverless applications with AWS Lambda. Triggers on phrases like: Lambda function, event source, serverless application, API Gateway, EventBridge, Step Functions, serverless API, event-driven architecture, Lambda trigger. For deploying non-serverless apps to AWS, use deploy-on-aws plugin instead."
argument-hint: "[what are you building?]"
---

# AWS Lambda Serverless Development

Design, build, deploy, and debug serverless applications with AWS serverless services. This skill provides access to serverless development guidance through the AWS Serverless MCP Server, helping you to build production-ready serverless applications with best practices built-in.

Use SAM CLI for project initialization and deployment, Lambda Web Adapter for web applications, or Event Source Mappings for event-driven architectures. AWS handles infrastructure provisioning, scaling, and monitoring automatically.

**Key capabilities:**

- **SAM CLI Integration**: Initialize, build, deploy, and test serverless applications
- **Web Application Deployment**: Deploy full-stack applications with Lambda Web Adapter
- **Event Source Mappings**: Configure Lambda triggers for DynamoDB, Kinesis, SQS, Kafka
- **Lambda durable functions**: Resilient multi-step applications with checkpointing — see the [durable-functions skill](../aws-lambda-durable-functions/) for guidance
- **Schema Management**: Type-safe EventBridge integration with schema registry
- **Observability**: CloudWatch logs, metrics, and X-Ray tracing
- **Performance Optimization**: Right-sizing, cost optimization, and troubleshooting

## When to Load Reference Files

Load the appropriate reference file based on what the user is working on:

- **Getting started**, **what to build**, **project type decision**, or **working with existing projects** -> see [references/getting-started.md](references/getting-started.md)
- **SAM**, **CDK**, **deployment**, **IaC templates**, **CDK constructs**, or **CI/CD pipelines** -> see the [aws-serverless-deployment skill](../aws-serverless-deployment/) (separate skill in this plugin)
- **Web app deployment**, **Lambda Web Adapter**, **API endpoints**, **CORS**, **authentication**, or **custom domains** -> see [references/web-app-deployment.md](references/web-app-deployment.md)
- **Event sources**, **DynamoDB Streams**, **Kinesis**, **SQS**, **Kafka**, **S3 notifications**, or **SNS** -> see [references/event-sources.md](references/event-sources.md)
- **EventBridge**, **event bus**, **event patterns**, **event design**, **Pipes**, or **schema registry** -> see [references/event-driven-architecture.md](references/event-driven-architecture.md)
- **Durable functions**, **checkpointing**, **replay model**, **saga pattern**, or **long-running Lambda workflows** -> see the [durable-functions skill](../aws-lambda-durable-functions/) (separate skill in this plugin with full SDK reference, testing, and deployment guides)
- **Orchestration**, **workflows**, or **Durable Functions vs Step Functions** -> see [references/orchestration-and-workflows.md](references/orchestration-and-workflows.md)
- **Step Functions**, **ASL**, **state machines**, **JSONata**, **Distributed Map**, or **SDK integrations** -> see [references/step-functions.md](references/step-functions.md)
- **Observability**, **logging**, **tracing**, **metrics**, **alarms**, or **dashboards** -> see [references/observability.md](references/observability.md)
- **Optimization**, **cold starts**, **memory tuning**, **cost**, **streaming**, or **Powertools** -> see [references/optimization.md](references/optimization.md)
- **Troubleshooting**, **errors**, **debugging**, or **deployment failures** -> see [references/troubleshooting.md](references/troubleshooting.md)

## Best Practices

### Project Setup

- Do: Use `sam_init` or `cdk init` with an appropriate template for your use case
- Do: Set global defaults for timeout, memory, runtime, and tracing (`Globals` in SAM, construct props in CDK)
- Do: Use AWS Lambda Powertools for structured logging, tracing, metrics (EMF), idempotency, and batch processing — available for Python, TypeScript, Java, and .NET
- Don't: Copy-paste templates from the internet without understanding the resource configuration
- Don't: Use the same memory and timeout values for all functions regardless of workload

### Security

- Do: Follow least-privilege IAM policies scoped to specific resources and actions
- Do: Use `secure_esm_*` tools to generate correct IAM policies for event source mappings
- Do: Store secrets in AWS Secrets Manager or SSM Parameter Store, never in environment variables
- Do: Use VPC endpoints instead of NAT Gateways for AWS service access when possible
- Do: Enable Amazon GuardDuty Lambda Protection to monitor function network activity for threats (cryptocurrency mining, data exfiltration, C2 callbacks)
- Don't: Use wildcard (`*`) resource ARNs or actions in IAM policies
- Don't: Hardcode credentials or secrets in application code or templates
- Don't: Store user data or sensitive information in module-level variables — execution environments can be reused across different callers

### Idempotency

- Do: Write idempotent function code — Lambda delivers events **at least once**, so duplicate invocations must be safe
- Do: Use the AWS Lambda Powertools Idempotency utility (backed by DynamoDB) for critical operations
- Do: Validate and deduplicate events at the start of the handler before performing side effects
- Don't: Assume an event will only ever be processed once

For topic-specific best practices, see the dedicated guide files in the reference table above.

## Lambda Limits Quick Reference

Limits that developers commonly hit:

| Resource                                     | Limit                               |
| -------------------------------------------- | ----------------------------------- |
| Function timeout                             | 900 seconds (15 minutes)            |
| Memory                                       | 128 MB – 10,240 MB                  |
| 1 vCPU equivalent                            | 1,769 MB memory                     |
| Synchronous payload (request + response)     | 6 MB each                           |
| Async invocation payload                     | 1 MB                                |
| Streamed response                            | 200 MB                              |
| Deployment package (.zip, uncompressed)      | 250 MB                              |
| Deployment package (.zip upload, compressed) | 50 MB                               |
| Container image                              | 10 GB                               |
| Layers per function                          | 5                                   |
| Environment variables (aggregate)            | 4 KB                                |
| `/tmp` ephemeral storage                     | 512 MB – 10,240 MB                  |
| Account concurrent executions (default)      | 1,000 (requestable increase)        |
| Burst scaling rate                           | 1,000 new executions per 10 seconds |

Check Service Quotas for your account limits: `aws lambda get-account-settings`

## Troubleshooting Quick Reference

| Error                               | Cause                          | Solution                                                                                                                                        |
| ----------------------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `Build Failed`                      | Missing dependencies           | Run `sam_build` with `use_container: true`                                                                                                      |
| `Stack is in ROLLBACK_COMPLETE`     | Previous deploy failed         | Delete stack with `aws cloudformation delete-stack`, redeploy                                                                                   |
| `IteratorAge` increasing            | Stream consumer falling behind | Increase `ParallelizationFactor` and `BatchSize`. Use `esm_optimize`                                                                            |
| EventBridge events silently dropped | No DLQ, retries exhausted      | Add `RetryPolicy` + `DeadLetterConfig` to rule target                                                                                           |
| Step Functions failing silently     | No retry on Task state         | Add `Retry` with `Lambda.ServiceException`, `Lambda.AWSLambdaException`                                                                         |
| Durable Function not resuming       | Missing IAM permissions        | Add `lambda:CheckpointDurableExecution` and `lambda:GetDurableExecutionState` — see [durable-functions skill](../aws-lambda-durable-functions/) |

For detailed troubleshooting, see [references/troubleshooting.md](references/troubleshooting.md).

## Configuration

### Authentication Setup

This skill requires AWS credentials configured on the host machine:

1. **Install AWS CLI**: Follow the [AWS CLI installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
2. **Configure credentials**: Run `aws configure` or set up named profiles in `~/.aws/credentials`
3. **Set environment variables** (if not using the default profile):
   - `AWS_PROFILE` - Named profile to use
   - `AWS_REGION` - Target AWS region
4. **Verify access**: Run `aws sts get-caller-identity` to confirm credentials are valid

### SAM CLI Setup

1. **Install SAM CLI**: Follow the [SAM CLI installation guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)
2. **Install Docker Desktop**: Required for `sam_local_invoke` and container-based builds
3. **Verify**: Run `sam --version` and `docker --version`

### MCP Server Configuration

The MCP server is configured in `.mcp.json` with the following flags:

- `--allow-write`: Enables write operations (project creation, deployments)
- `--allow-sensitive-data-access`: Enables access to Lambda logs and API Gateway logs

### SAM Template Validation Hook

This plugin includes a `PostToolUse` hook that runs `sam validate` automatically after any edit to `template.yaml` or `template.yml`. If validation fails, the error is returned as a system message so you can fix it immediately. The hook requires SAM CLI to be installed and silently skips if it is not available. Users can disable it via `/hooks`.

**Version policy:** `.mcp.json` uses `awslabs.aws-serverless-mcp-server@latest`. This is intentional — the package is pre-1.0 (currently 0.1.x) and under active development, so pinning would miss bug fixes and new tool capabilities. If you need a stable, reproducible setup, pin to a specific version:

```json
"args": ["awslabs.aws-serverless-mcp-server@0.1.17", "--allow-write", "--allow-sensitive-data-access"]
```

Check for new versions with `uvx pip index versions awslabs.aws-serverless-mcp-server`.

## Guidelines

Ask which IaC framework (SAM or CDK) to use for new projects.
Ask which programming language to use if unclear.

## Resources

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS Lambda Powertools](https://docs.powertools.aws.dev/lambda/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Serverless MCP Server](https://github.com/awslabs/mcp/tree/main/src/aws-serverless-mcp-server)
