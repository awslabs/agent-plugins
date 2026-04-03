# aws-dev-toolkit

A Claude Code plugin for building, migrating, and reviewing well-architected applications on AWS.

## What's Included

- **30 skills** — slash commands for AWS services, architecture, migration, cost, security, and more
- **11 agents** — specialized sub-agents (explorer, reviewers, SMEs) that run autonomously
- **3 MCP servers** — IaC validation, AWS knowledge base, and pricing data

## Installation

Install via the Claude Code plugin marketplace or clone this repo and symlink:

```bash
claude plugin install aws-dev-toolkit
```

## Skills

| Skill | Description |
|-------|-------------|
| `aws-architect` | Design and review AWS architectures |
| `aws-compare` | Compare 2-3 architecture options side-by-side |
| `aws-debug` | Debug infrastructure issues and deployment failures |
| `aws-diagram` | Generate architecture diagrams (Mermaid/ASCII) |
| `aws-health-check` | Run health checks on AWS environments |
| `aws-migrate` | Guided migration assessment and planning |
| `aws-plan` | End-to-end architecture planning |
| `api-gateway` | API Gateway design and configuration |
| `azure-to-aws` | Azure to AWS migration guidance |
| `bedrock-cost` | Bedrock pricing and cost modeling |
| `challenger` | Adversarial review of architecture recommendations |
| `cloudfront` | CloudFront distribution design |
| `cost-check` | Analyze and optimize AWS costs |
| `customer-ideation` | Guide customers from idea to architecture |
| `dynamodb` | DynamoDB table design and access patterns |
| `ec2` | EC2 instance selection and optimization |
| `ecs` | ECS workload design and troubleshooting |
| `eks` | EKS cluster design and management |
| `gcp-to-aws` | GCP to AWS migration guidance |
| `iac-scaffold` | Scaffold IaC templates |
| `iam` | IAM policy and role design |
| `lambda` | Lambda function design and optimization |
| `messaging` | SQS, SNS, and EventBridge patterns |
| `networking` | VPC design and connectivity |
| `observability` | CloudWatch, X-Ray, and OpenTelemetry |
| `s3` | S3 storage strategies and access control |
| `security-review` | Security assessment of AWS configurations |
| `serverless` | Serverless architecture patterns (alias: `step-functions`) |
| `step-functions` | Step Functions workflow design |
| `strands-agent` | Strands agent patterns |
| `well-architected` | Well-Architected Framework reviews |

## Agents

| Agent | Color | Purpose |
|-------|-------|---------|
| `aws-explorer` | cyan | Read-only environment exploration |
| `iac-reviewer` | red | IaC security and correctness review |
| `cost-optimizer` | yellow | Deep cost analysis and optimization |
| `networking-sme` | blue | VPC, DNS, CDN, and connectivity |
| `bedrock-sme` | magenta | Bedrock solutions and model selection |
| `serverless-sme` | green | Lambda, API GW, Step Functions, EventBridge |
| `container-sme` | blue | ECS, EKS, and Fargate |
| `well-architected-reviewer` | green | Six-pillar workload reviews |
| `observability-sme` | cyan | Monitoring, tracing, and dashboards |
| `migration-advisor` | yellow | Multi-cloud migration planning |
| `agentcore-sme` | magenta | Bedrock AgentCore production agents |

## MCP Servers

| Server | Type | Source |
|--------|------|--------|
| `awsiac` | stdio | `awslabs.aws-iac-mcp-server` — CloudFormation/CDK validation |
| `awsknowledge` | http | `knowledge-mcp.global.api.aws` — AWS documentation search |
| `awspricing` | stdio | `awslabs.aws-pricing-mcp-server` — Service pricing data |

## License

MIT
