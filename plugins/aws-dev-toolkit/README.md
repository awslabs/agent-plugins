# aws-dev-toolkit

A Claude Code plugin for AWS development. Ships 30 skills, 11 sub-agents, 3 MCP servers, and hooks that help you build well-architected applications on AWS.

## Quick Start

```bash
# Add the marketplace
/plugin marketplace add rsmets/aws-dev-toolkit

# Install the plugin (plugin@marketplace format)
/plugin install aws-dev-toolkit@rsmets
```

Or test locally during development:

```bash
claude --plugin-dir ./plugins/aws-dev-toolkit
```

> **Note**: `--plugin-dir` loads the plugin from disk at **session start**. File changes are picked up on the next session — not live. `/plugin update` does not work for local plugins (it requires a marketplace source). Restart Claude Code to pick up changes. See [Plugins Guide](https://code.claude.com/docs/en/plugins) for details.

## Usage

Once installed, the plugin's skills, agents, and MCP servers are available automatically in Claude Code. Here's how each piece works:

### Skills (Automatic)

Skills activate automatically based on context — no special commands needed. Just ask naturally:

```
"Review this architecture for Well-Architected best practices"  → aws-architect
"Why is my CloudFormation stack failing?"                       → aws-debug
"How much is this infrastructure costing me?"                   → cost-check
"Are there security issues in my Terraform?"                    → security-review
"Estimate Bedrock costs for 50k daily invocations"              → bedrock-cost
"I want to build a serverless API for processing images"        → aws-plan
"Compare ECS vs EKS for my workload"                            → aws-compare
"Show me a diagram of this architecture"                        → aws-diagram
"We're moving from GCP to AWS"                                  → aws-migrate
```

### Slash Commands

Some skills are invoked explicitly via slash commands:

```
/aws-dev-toolkit:iac-scaffold terraform "VPC with public/private subnets and NAT"
/aws-dev-toolkit:iac-scaffold cdk "Serverless API with Lambda and DynamoDB"
/aws-dev-toolkit:aws-health-check us-east-1
/aws-dev-toolkit:aws-diagram from-iac
/aws-dev-toolkit:aws-migrate gcp
```

### Sub-Agents (Automatic)

Sub-agents are spun up automatically when Claude determines a specialist is needed. You can also invoke them directly:

```
"Explore my AWS environment and summarize what's deployed"      → aws-explorer
"Run a Well-Architected review on my production workload"       → well-architected-reviewer
"Review my IaC changes before I deploy"                         → iac-reviewer
"Help me plan a migration from Azure to AWS"                    → migration-advisor
"Help me pick the right Bedrock model for classification"       → bedrock-sme
"I have a PoC agent, help me productionize it"                  → agentcore-sme
"Should I use ECS or EKS for this workload?"                    → container-sme
"Help me optimize my AWS bill"                                  → cost-optimizer
```

### MCP Servers

The plugin ships 3 MCP servers. In Kiro, MCP configs are not auto-loaded from the plugin directory — you need to add them to your Kiro MCP settings.

Add to `~/.kiro/settings/mcp.json` (user-level) or `.kiro/settings/mcp.json` (workspace-level):

```jsonc
{
  "mcpServers": {
    // AWS IaC validation and security scanning
    "awsiac": {
      "command": "uvx",
      "args": ["awslabs.aws-iac-mcp-server@latest"],
      "env": { "FASTMCP_LOG_LEVEL": "ERROR" },
      "disabled": false
    },
    // AWS documentation, recommendations, and regional availability
    "awsknowledge": {
      "type": "http",
      "url": "https://knowledge-mcp.global.api.aws",
      "disabled": false
    },
    // AWS pricing data and cost analysis
    "awspricing": {
      "command": "uvx",
      "args": ["awslabs.aws-pricing-mcp-server@latest"],
      "env": { "FASTMCP_LOG_LEVEL": "ERROR" },
      "timeout": 120000,
      "disabled": false
    }
  }
}
```

These are used behind the scenes by skills and agents — you don't need to invoke them directly.

| Server | Type | Package / URL | Description |
|---|---|---|---|
| `awsiac` | stdio | `awslabs.aws-iac-mcp-server` | CDK/Terraform/CloudFormation development with security scanning |
| `awsknowledge` | http | `https://knowledge-mcp.global.api.aws` | AWS documentation search, service recommendations, and regional availability |
| `awspricing` | stdio | `awslabs.aws-pricing-mcp-server` | AWS service pricing data, cost reports, and IaC cost analysis |

### Hooks

Hooks run automatically on events. Currently configured:

- After editing an IaC file (`.tf`, `template.yaml`, `*-stack.ts`, etc.), Claude reminds you to validate before deploying

### Example Workflows

**"I need a new service on AWS"**
1. Describe what you're building — `aws-plan` kicks in automatically
2. Answer 3-5 discovery questions (it won't overwhelm you)
3. Review the proposed architecture, security findings, and cost estimate
4. Scaffold it — `/iac-scaffold cdk "your description"`
5. Edit the generated code — the hook reminds you to `cdk synth && cdk diff`

**"Should I use Lambda or Fargate?"**
1. Describe your workload — `aws-compare` evaluates both side-by-side
2. Get a comparison table across cost, complexity, performance, and team fit
3. Receive an opinionated recommendation tied to your constraints

**"What does this architecture look like?"**
1. Ask for a diagram — `/aws-diagram from-iac` reverse-engineers your IaC files
2. Or describe the architecture — it generates Mermaid + ASCII diagrams

**"Is my AWS account in good shape?"**
1. Run `/aws-health-check us-east-1`
2. Get a quick score with critical findings, warnings, and quick wins
3. See SCP recommendations if baseline guardrails are missing

**"My Bedrock agent is too expensive"**
1. Ask about your Bedrock usage — `bedrock-sme` analyzes your patterns
2. Get model selection guidance — it'll steer you toward the cheapest model that works
3. Ask `cost-check` to look at your overall AWS bill for context

**"I built a PoC agent, now what?"**
1. Share your agent code — `agentcore-sme` reviews it against the production checklist
2. Get guidance on adding DeepEval for model evaluation
3. Choose between AgentCore native observability or Langfuse
4. Walk through the PoC → production migration path

**"Run a Well-Architected review on my workload"**
1. The `well-architected-reviewer` agent scans your AWS environment
2. Evaluates each of the six pillars with real CLI evidence
3. Rates findings as HRI (high risk), MRI (medium risk), or LRI (low risk)
4. Produces a structured report with prioritized remediation steps
5. Use the `awsknowledge` MCP server for AWS documentation and best-practice references

**"We're moving from GCP to AWS"**
1. Describe your GCP environment — `gcp-to-aws` maps services to AWS equivalents
2. Run the assessment commands to inventory what's deployed
3. Review the gotchas for your specific services (global VPCs, Spanner, BigQuery)
4. Use `iac-scaffold` to generate the target AWS infrastructure
5. Ask `migration-advisor` for wave planning and cutover strategy

**"We're moving from Azure to AWS"**
1. Describe your Azure environment — `azure-to-aws` maps services to AWS equivalents
2. Run az CLI discovery commands to inventory resources
3. Pay special attention to identity migration (Azure AD → IAM Identity Center)
4. Review Cosmos DB and Synapse migration paths (these are complex)
5. Use `iac-scaffold` to generate the target AWS infrastructure

**"I have an idea for something on AWS"**
1. Describe your idea — `customer-ideation` guides you through discovery
2. Answer the structured questions about requirements and constraints
3. Review the proposed architecture with Well-Architected checklist
4. Use `/iac-scaffold` to generate starter infrastructure code
5. Ask for a cost estimate before committing

## What's Included

### Plugins

#### `aws-dev-toolkit`

**Skills (30):**
| Skill | Trigger | Description |
|---|---|---|
| **Workflows & Planning** | | |
| `aws-plan` | Auto | End-to-end architecture planning — discovery, design, security review, cost estimate |
| `aws-architect` | Auto | Design & review AWS architectures against Well-Architected Framework |
| `well-architected` | Auto | Formal Well-Architected Framework reviews with pillar-by-pillar assessment |
| `customer-ideation` | Auto | Guided ideation from concept to AWS architecture with service selection |
| `aws-compare` | Auto | Compare 2-3 architecture options side-by-side across cost, complexity, and trade-offs |
| `aws-diagram` | Auto / `/aws-diagram` | Generate Mermaid/ASCII architecture diagrams from descriptions or existing IaC |
| `aws-health-check` | `/aws-health-check [region]` | Quick account health scan — security, cost waste, reliability gaps |
| `aws-migrate` | Auto | Guided migration assessment — discover source, map services, plan waves, estimate cost |
| **Scaffolding** | | |
| `iac-scaffold` | `/iac-scaffold <framework> <desc>` | Scaffold CDK, Terraform, SAM, or CloudFormation projects |
| `strands-agent` | `/strands-agent <description>` | Scaffold Strands Agents SDK projects on Bedrock AgentCore (TS/Python) |
| **Debugging & Review** | | |
| `aws-debug` | Auto | Debug AWS deployment failures, Lambda errors, permission issues |
| `security-review` | Auto | Audit IaC and AWS configs for security issues (mandatory for all IaC changes) |
| `cost-check` | Auto | Analyze and optimize AWS costs |
| `bedrock-cost` | Auto | Bedrock pricing, token economics, and cost modeling |
| `challenger` | Auto | Adversarial reviewer that stress-tests architecture recommendations |
| **AWS Services** | | |
| `lambda` | Auto | Design, build, and optimize Lambda functions — runtimes, cold starts, concurrency |
| `ec2` | Auto | Design, configure, and optimize EC2 workloads — instance selection, AMIs, ASGs |
| `ecs` | Auto | Deploy and troubleshoot ECS workloads — task definitions, services, Fargate |
| `eks` | Auto | Deploy and troubleshoot EKS clusters — Kubernetes on AWS, Karpenter, IRSA |
| `s3` | Auto | S3 bucket configuration, storage optimization, and access patterns |
| `dynamodb` | Auto | DynamoDB table design, access patterns, single-table design, GSIs |
| `api-gateway` | Auto | Design and configure API Gateway — REST vs HTTP APIs, authorizers, throttling |
| `cloudfront` | Auto | CloudFront distributions — caching, origins, Lambda@Edge, Functions |
| `iam` | Auto | IAM policies, roles, permission boundaries, and least-privilege design |
| `networking` | Auto | VPC architecture, subnets, security groups, Transit Gateway, VPC endpoints |
| `messaging` | Auto | SQS, SNS, and EventBridge — queue design, fan-out, event routing |
| `observability` | Auto | CloudWatch, X-Ray, and OpenTelemetry — dashboards, alarms, tracing |
| `step-functions` | Auto | Step Functions workflows — state machines, error handling, service integrations |
| **Migration** | | |
| `gcp-to-aws` | Auto | GCP to AWS migration service mapping, gotchas, and environment assessment |
| `azure-to-aws` | Auto | Azure to AWS migration service mapping, gotchas, and environment assessment |

**Sub-Agents (11):**
| Agent | Model | Description |
|---|---|---|
| `aws-explorer` | Opus | Read-only AWS environment exploration and context gathering |
| `well-architected-reviewer` | Opus | Deep Well-Architected Framework reviews with evidence-based assessment |
| `iac-reviewer` | Opus | Reviews IaC changes for correctness, security, and best practices |
| `migration-advisor` | Opus | Cloud migration expert — 6Rs framework, wave planning, cutover strategy |
| `bedrock-sme` | Opus | Bedrock subject matter expert emphasizing cost-efficient usage patterns |
| `agentcore-sme` | Opus | AgentCore expert for PoC-to-production agent development |
| `container-sme` | Opus | Container expert for ECS, EKS, and Fargate architecture decisions |
| `serverless-sme` | Opus | Serverless architecture expert for Lambda, API Gateway, Step Functions |
| `networking-sme` | Opus | AWS networking expert — VPC design, hybrid connectivity, DNS, CDN |
| `observability-sme` | Opus | CloudWatch, X-Ray, and OpenTelemetry observability expert |
| `cost-optimizer` | Opus | Deep AWS cost optimization — rightsizing, Savings Plans, waste elimination |

**MCP Servers (3):**
| Server | Type | Package / URL | Description |
|---|---|---|---|
| `awsiac` | stdio | `awslabs.aws-iac-mcp-server` | CDK/Terraform/CloudFormation development with security scanning |
| `awsknowledge` | http | `https://knowledge-mcp.global.api.aws` | AWS documentation search, service recommendations, and regional availability |
| `awspricing` | stdio | `awslabs.aws-pricing-mcp-server` | AWS service pricing data, cost reports, and IaC cost analysis |

**Hooks:**
- Post-edit reminder to validate IaC files before deploying

## Prerequisites

- [Claude Code](https://code.claude.com) v1.0.33+
- [uv](https://docs.astral.sh/uv/getting-started/installation/) (for MCP servers via `uvx`)
- AWS CLI configured with appropriate credentials
- (Optional) `checkov`, `cfn-nag`, `tfsec` for security scanning

## Project Structure

```
aws-dev-toolkit/
├── .claude-plugin/
│   └── marketplace.json              # Marketplace catalog
├── plugins/
│   └── aws-dev-toolkit/              # First plugin
│       ├── .claude-plugin/
│       │   └── plugin.json           # Plugin manifest
│       ├── .mcp.json                 # MCP server configs (3 servers)
│       ├── skills/                   # 30 skills
│       │   ├── aws-plan/             # End-to-end architecture planning
│       │   ├── aws-architect/        # Architecture design & review
│       │   ├── aws-compare/          # Side-by-side architecture comparison
│       │   ├── aws-diagram/          # Architecture diagram generation
│       │   ├── aws-health-check/     # Quick account health scan
│       │   ├── aws-migrate/          # Guided migration assessment
│       │   ├── well-architected/     # Formal WA Framework reviews
│       │   ├── customer-ideation/    # Idea → AWS architecture workflow
│       │   ├── iac-scaffold/         # IaC project scaffolding
│       │   ├── aws-debug/            # Deployment & runtime debugging
│       │   ├── security-review/      # Security auditing
│       │   ├── cost-check/           # Cost analysis & optimization
│       │   ├── bedrock-cost/         # Bedrock pricing & cost modeling
│       │   ├── strands-agent/        # Strands Agents SDK scaffolding
│       │   ├── challenger/           # Adversarial architecture reviewer
│       │   ├── lambda/               # Lambda functions
│       │   ├── ec2/                  # EC2 instances
│       │   ├── ecs/                  # ECS containers
│       │   ├── eks/                  # EKS Kubernetes
│       │   ├── s3/                   # S3 storage
│       │   ├── dynamodb/             # DynamoDB tables
│       │   ├── api-gateway/          # API Gateway
│       │   ├── cloudfront/           # CloudFront CDN
│       │   ├── iam/                  # IAM policies & roles
│       │   ├── networking/           # VPC & networking
│       │   ├── messaging/            # SQS, SNS, EventBridge
│       │   ├── observability/        # CloudWatch, X-Ray
│       │   ├── step-functions/       # Step Functions workflows
│       │   ├── gcp-to-aws/           # GCP migration mapping
│       │   └── azure-to-aws/         # Azure migration mapping
│       ├── agents/                   # 11 sub-agents
│       │   ├── aws-explorer.md
│       │   ├── well-architected-reviewer.md
│       │   ├── iac-reviewer.md
│       │   ├── migration-advisor.md
│       │   ├── bedrock-sme.md
│       │   ├── agentcore-sme.md
│       │   ├── container-sme.md
│       │   ├── serverless-sme.md
│       │   ├── networking-sme.md
│       │   ├── observability-sme.md
│       │   └── cost-optimizer.md
│       └── hooks/
│           └── hooks.json            # PostToolUse IaC validation
└── README.md
```

## Adding More Plugins

This marketplace is designed to host multiple plugins. To add a new one:

1. Create a directory under `plugins/<your-plugin-name>/`
2. Add `.claude-plugin/plugin.json` with the manifest
3. Add your skills, agents, hooks, and MCP configs
4. Register it in `.claude-plugin/marketplace.json`

## Available AWS MCP Servers

The [awslabs/mcp](https://awslabs.github.io/mcp/servers) project provides 60+ official MCP servers. Some notable ones to consider adding:

| Server | Use Case |
|---|---|
| `awslabs.aws-api-mcp-server` | Direct AWS API access via CLI |
| `awslabs.cdk-mcp-server` | CDK-specific development |
| `awslabs.terraform-mcp-server` | Terraform-specific workflows |
| `awslabs.lambda-mcp-server` | Lambda function management |
| `awslabs.s3-mcp-server` | S3 operations |
| `awslabs.cloudformation-mcp-server` | CloudFormation resource management |
| `awslabs.bedrock-mcp-server` | Bedrock AI model integration |
| `awslabs.cloudwatch-mcp-server` | Metrics, alarms, and log analysis |
| `awslabs.iam-mcp-server` | IAM user, role, and policy management |
| `awslabs.cost-analysis-mcp-server` | Cost analysis and optimization |

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
