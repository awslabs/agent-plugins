# Getting Started with AWS Serverless Development

## Prerequisites

Verify these tools before proceeding:

```bash
aws --version                  # AWS CLI
aws sts get-caller-identity    # Credentials configured
sam --version                  # SAM CLI
docker --version               # Docker (required for local testing)
```

If `aws sts get-caller-identity` fails, run `aws configure` to set up credentials. If using CDK instead of SAM, also run `cdk --version` — see [cdk-project-setup.md](../../aws-serverless-deployment/references/cdk-project-setup.md).

## What Are You Building?

### REST/HTTP API

An API backend serving JSON over HTTPS — the most common serverless pattern.

**Quick start:**

- Template: `hello-world` (single function + API Gateway) or `quick-start-web` (web framework)
- Runtime: `nodejs22.x` or `python3.12`
- Architecture: `arm64`

**Read next:**

- [sam-project-setup.md](../../aws-serverless-deployment/references/sam-project-setup.md) — project scaffolding, deployment workflow, handler examples, container image packaging for large dependencies
- [web-app-deployment.md](web-app-deployment.md) — API endpoint selection (HTTP API vs REST API vs Function URL vs ALB), CORS, custom domains, authentication

### Full-Stack Web Application

A frontend (React, Vue, Angular, Next.js) with a backend API, deployed together.

**Quick start:**

- Template: `quick-start-web`
- Use `deploy_webapp` with `deployment_type: "fullstack"` for S3 + CloudFront + Lambda + API Gateway

**Read next:**

- [web-app-deployment.md](web-app-deployment.md) — Lambda Web Adapter, project structure, frontend updates

### Event Processor

A Lambda function triggered by a queue, stream, or database change — SQS, Kinesis, DynamoDB Streams, Kafka, or DocumentDB.

**Quick start:**

- Template: `hello-world` (then add an event source in `template.yaml`)
- Use `esm_guidance` to get the correct ESM configuration for your source
- Use `secure_esm_*` tools to generate least-privilege IAM policies

**Read next:**

- [event-sources.md](event-sources.md) — source-specific configuration, event filtering, batch processing examples
- [observability.md](observability.md) — structured logging, tracing, and monitoring for event processors
- [optimization.md](optimization.md) — ESM tuning parameters

### File/Object Processor

A Lambda function triggered when files are uploaded to or deleted from S3 — image processing, file validation, data import, thumbnail generation.

**Quick start:**

- Template: `hello-world` (then add an S3 event in `template.yaml`)
- Use prefix/suffix filters to limit triggers to specific paths or file types

**Read next:**

- [event-sources.md](event-sources.md) — S3 event notification configuration and recursive trigger prevention

### Notification Fan-Out

One event triggers multiple independent consumers — order notifications, alert distribution, cross-service communication.

**Quick start:**

- Create an SNS topic and subscribe multiple Lambda functions
- Use filter policies to route subsets of messages to specific consumers

**Read next:**

- [event-sources.md](event-sources.md) — SNS subscription configuration, filter policies, and DLQ setup
- [event-driven-architecture.md](event-driven-architecture.md) — for complex routing with EventBridge instead of SNS

### Event-Driven Architecture

Multiple services communicating through events on EventBridge — decoupled, independently deployable.

**Quick start:**

- Create a custom event bus (never use the default bus for application events)
- Define event schemas with `metadata` envelope for idempotency and tracing
- Use `search_schema` and `describe_schema` for schema discovery

**Read next:**

- [event-driven-architecture.md](event-driven-architecture.md) — event bus setup, event patterns, event design, Pipes, archive and replay
- [observability.md](observability.md) — correlation ID propagation, EventBridge metrics, and alarm strategy
- [orchestration-and-workflows.md](orchestration-and-workflows.md) — if you need reliable sequencing or human-in-the-loop

### Multi-Step Workflow or AI Pipeline

A workflow with sequential steps, parallel execution, human approval, or checkpointing — order processing, document pipelines, agentic AI.

**Quick start:**

- **Python 3.14+ or Node.js 22+**: Use Lambda Durable Functions for workflows expressed as code — see the [durable-functions skill](../../aws-lambda-durable-functions/) for comprehensive guidance
- **Any runtime**: Use Step Functions for visual orchestration with 200+ AWS service integrations
- **High-throughput, short-lived**: Use Step Functions Express (100k+ exec/sec)

**Read next:**

- [orchestration-and-workflows.md](orchestration-and-workflows.md) — Step Functions ASL, testing, patterns, and a Durable Functions vs Step Functions comparison

### Scheduled Job

A Lambda function triggered on a cron schedule — reports, cleanup tasks, data sync.

Add a `Schedule` event to your function in `template.yaml`:

```yaml
MyScheduledFunction:
  Type: AWS::Serverless::Function
  Properties:
    Handler: src/handlers/report.handler
    Events:
      DailyReport:
        Type: Schedule
        Properties:
          Schedule: cron(0 8 * * ? *)   # 8:00 AM UTC daily
          Enabled: true
```

**Read next:**

- [sam-project-setup.md](../../aws-serverless-deployment/references/sam-project-setup.md) — project setup and deployment workflow

## Working with Existing Projects

When joining or modifying an existing SAM project:

1. Look for `template.yaml` (or `template.yml`) at the project root
2. Check `samconfig.toml` for deployment configuration and environment profiles
3. Run `sam_build` to verify the project builds
4. Use `sam_logs` and `get_metrics` to understand current behavior before making changes

For CDK projects, look for `cdk.json` and run `cdk synth` to verify synthesis. See [cdk-project-setup.md](../../aws-serverless-deployment/references/cdk-project-setup.md).
