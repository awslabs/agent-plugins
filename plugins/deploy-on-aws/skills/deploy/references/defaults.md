# Service Defaults

Default AWS service selections. Override only when user explicitly requests alternatives.

## Compute

| App Pattern                                           | Default              | Override Trigger                         |
| ----------------------------------------------------- | -------------------- | ---------------------------------------- |
| Web framework (Django, Rails, Express, FastAPI, etc.) | Fargate + ALB        | "serverless" → Lambda + API Gateway      |
| Static site / SPA                                     | Amplify Hosting      | "S3" or "more control" → S3 + CloudFront |
| Background workers                                    | Fargate              | Short tasks (<15min) → Lambda            |
| Scheduled jobs                                        | EventBridge + Lambda | Long-running → EventBridge + Fargate     |
| API-only (no web UI)                                  | Fargate + ALB        | "serverless" → API Gateway + Lambda      |

### Why Fargate over Lambda for web frameworks

Most web frameworks (Django, Rails, Flask with WSGI) expect long-running processes.
Lambda's cold starts and request/response model require adapters and introduce latency.
Fargate provides a more natural fit without framework modifications.

### Why Amplify for static sites/SPAs

Amplify Hosting handles CI/CD, HTTPS, custom domains, and CDN automatically.
Less configuration than S3 + CloudFront. Git-based deployments work out of the box.
Use S3 + CloudFront when user needs fine-grained control over caching, edge functions,
or has existing CloudFront infrastructure.

Use `amplify_docs` topic in awsknowledge MCP for framework-specific guidance
(React, Next.js, Vue, Angular, etc.).

## Database

| Data Pattern         | Default (Dev)          | Default (Prod)         | Override Trigger                       |
| -------------------- | ---------------------- | ---------------------- | -------------------------------------- |
| PostgreSQL           | Aurora Serverless v2   | Aurora Serverless v2   | "simple RDS" → RDS                     |
| MySQL                | Aurora Serverless v2   | Aurora Serverless v2   | "simple RDS" → RDS                     |
| DocumentDB / MongoDB | DocumentDB Serverless  | DocumentDB Serverless  | "provisioned" → DocumentDB provisioned |
| NoSQL / Key-Value    | DynamoDB               | DynamoDB               | -                                      |
| Redis / Caching      | ElastiCache Serverless | ElastiCache Serverless | -                                      |
| Full-text search     | OpenSearch Serverless  | OpenSearch Serverless  | -                                      |

### Why Aurora Serverless v2

Scales to near-zero in dev (0.5 ACU minimum), scales up automatically for production.
Single choice works for both environments. Only use provisioned RDS if user has
specific cost constraints or compliance requirements.

### Why DocumentDB Serverless for MongoDB

DocumentDB Serverless is the on-demand, auto-scaling configuration of Amazon DocumentDB.
It dynamically adjusts capacity based on application demand so you only pay for what you
use. Ideal for dev/test, variable workloads, and new applications where capacity needs
are unknown. Compatible with MongoDB 3.6, 4.0, 5.0 and 8.0 APIs.
Use provisioned DocumentDB only when you have predictable, steady-state workloads
or specific compliance requirements that need fixed instance sizing.

## Storage

| Pattern       | Default         |
| ------------- | --------------- |
| Static assets | S3              |
| User uploads  | S3              |
| Secrets       | Secrets Manager |
| Config        | Parameter Store |

## IaC

| Default          | Override Trigger                       |
| ---------------- | -------------------------------------- |
| CDK (TypeScript) | "terraform" → Terraform                |
|                  | "cloudformation" → CloudFormation YAML |
|                  | "sam" → SAM                            |

### Why CDK

Most expressive, best IDE support, generates CloudFormation. TypeScript provides
type safety without requiring Python/Java knowledge. If user's repo already has
`terraform/` or `cdk.json`, match existing choice.

## Sizing (Dev vs Production)

| Component         | Dev           | Production     |
| ----------------- | ------------- | -------------- |
| Fargate           | 0.5 vCPU, 1GB | 1+ vCPU, 2+ GB |
| Aurora Serverless | 0.5-2 ACU     | 2-16+ ACU      |
| ALB               | Single AZ OK  | Multi-AZ       |

Default to **dev sizing** unless user says "production", "prod", or "production-ready".

## Security

See [security.md](security.md) for encryption, VPC placement, IAM, security group defaults, and pre-deployment security checks.
