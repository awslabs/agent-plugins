---
name: aws-serverless-deployment
description: "Deploy serverless applications to AWS using AWS SAM and AWS CDK — project scaffolding, IaC templates, CDK constructs, CI/CD pipelines, and deployment workflows"
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

## Guidelines

Ask which IaC framework (SAM or CDK) to use for new projects.
Ask which programming language to use if unclear.

## Resources

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Serverless MCP Server](https://github.com/awslabs/mcp/tree/main/src/aws-serverless-mcp-server)
