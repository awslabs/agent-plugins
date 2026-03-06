---
name: aws-serverless-deployment
description: "AWS SAM and AWS CDK deployment for serverless applications. Triggers on phrases like: use SAM, SAM template, SAM init, SAM deploy, CDK serverless, CDK Lambda construct, NodejsFunction, PythonFunction, SAM and CDK together, serverless CI/CD pipeline. For general app deployment with service selection, use deploy-on-aws plugin instead."
argument-hint: "[what are you deploying?]"
---

# AWS Serverless Deployment

Deploy serverless applications to AWS using SAM or CDK. This skill covers project scaffolding, IaC templates, CDK constructs and patterns, deployment workflows, CI/CD pipelines, and SAM/CDK coexistence.

For Lambda runtime behavior, event sources, orchestration, observability, and optimization, see the [aws-lambda skill](../aws-lambda/).

## When to Load Reference Files

Load the appropriate reference file based on what the user is working on:

- **SAM project setup**, **templates**, **deployment workflow**, **local testing**, or **container images** -> see [references/sam-project-setup.md](references/sam-project-setup.md)
- **CDK project setup**, **constructs**, **CDK testing**, or **CDK pipelines** -> see [references/cdk-project-setup.md](references/cdk-project-setup.md)
- **CDK Lambda constructs**, **NodejsFunction**, **PythonFunction**, or **CDK Function** -> see [references/cdk-lambda-constructs.md](references/cdk-lambda-constructs.md)
- **CDK serverless patterns**, **API Gateway CDK**, **Function URL CDK**, **EventBridge CDK**, **DynamoDB CDK**, or **SQS CDK** -> see [references/cdk-serverless-patterns.md](references/cdk-serverless-patterns.md)
- **SAM and CDK coexistence**, **migrating from SAM to CDK**, or **using sam build with CDK** -> see [references/sam-cdk-coexistence.md](references/sam-cdk-coexistence.md)

## Best Practices

### SAM

- Do: Use `sam_init` with an appropriate template for your use case
- Do: Set global defaults for timeout, memory, runtime, and tracing in the `Globals` section
- Do: Use `samconfig.toml` environment-specific sections for multi-environment deployments
- Do: Use `sam build --use-container` when native dependencies are involved
- Don't: Copy-paste templates from the internet without understanding the resource configuration
- Don't: Hardcode resource ARNs or account IDs in templates — use `!Ref`, `!GetAtt`, and `!Sub`

### CDK

- Do: Use TypeScript — type checking catches errors at synthesis time, before any AWS API calls
- Do: Prefer L2 constructs and `grant*` methods over L1 and raw IAM statements
- Do: Separate stateful and stateless resources into different stacks; enable termination protection on stateful stacks
- Do: Commit `cdk.context.json` to version control — it caches VPC/AZ lookups for deterministic synthesis
- Do: Write unit tests with `aws-cdk-lib/assertions`; assert logical IDs of stateful resources to detect accidental replacements
- Do: Use `cdk diff` in CI before every deployment to review changes
- Don't: Hardcode account IDs or region strings — use `this.account` and `this.region`
- Don't: Use `cdk deploy` directly in production without a pipeline
- Don't: Skip `cdk bootstrap` — deployments will fail without the CDK toolkit stack

## Configuration

### AWS CLI Setup

This skill requires that AWS credentials are configured on the host machine:

**Verify access**: Run `aws sts get-caller-identity` to confirm credentials are valid

### SAM CLI Setup

**Verify**: Run `sam --version`

### Container Runtime Setup

1. **Install a Docker compatible container runtime**: Required for `sam_local_invoke` and container-based builds
2. **Verify**: Use an appropriate command such as `docker --version` or `finch --version`

### AWS Serverless MCP Server

**Write access is enabled by default.** The plugin ships with `--allow-write` in `.mcp.json`, so the MCP server can create projects, generate IaC, and deploy on behalf of the user.

Access to sensitive data (like Lambda and API Gateway logs) is **not** enabled by default. To grant it, add `--allow-sensitive-data-access` to `.mcp.json`.

### SAM Template Validation Hook

This plugin includes a `PostToolUse` hook that runs `sam validate` automatically after any edit to `template.yaml` or `template.yml`. If validation fails, the error is returned as a system message so you can fix it immediately. The hook requires SAM CLI and `jq` to be installed; if either is missing, validation is skipped with a system message. Users can disable it via `/hooks`.

**Verify**: Run `jq --version`

## IaC framework selection

Default: CDK

Override syntax:

- "use CloudFormation" → Generate YAML templates
- "use SAM" → Generate YAML templates

When not specified, ALWAYS use CDK

### Language selection for CDK

Default: TypeScript

Override syntax:

- "use Python" → Generate Python code
- "use JavaScript" → Generate JavaScript code

When not specified, ALWAYS use TypeScript

## Error Scenarios

### Serverless MCP Server Unavailable

- Inform user: "AWS Serverless MCP not responding"
- Ask: "Proceed without MCP support?"
- DO NOT continue without user confirmation

## Resources

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Serverless MCP Server](https://github.com/awslabs/mcp/tree/main/src/aws-serverless-mcp-server)
