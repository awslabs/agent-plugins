---
name: agentcore
description: Deep-dive into Amazon Bedrock AgentCore platform design, service selection, deployment, and production operations. This skill should be used when the user asks to "design an AgentCore architecture", "deploy agents on AgentCore", "configure AgentCore Runtime", "set up AgentCore Memory", "use AgentCore Gateway", "configure AgentCore Identity", "set up AgentCore Policy", "plan agent observability", "evaluate agent quality", "move agent PoC to production", or mentions AgentCore, AgentCore Runtime, AgentCore Memory, AgentCore Gateway, AgentCore Identity, AgentCore Policy, AgentCore Evaluations, AgentCore Code Interpreter, AgentCore Browser, A2A protocol, or multi-agent orchestration on AWS.
---

Specialist guidance for Amazon Bedrock AgentCore. Covers the full platform: Runtime, Memory, Gateway, Identity, Policy, Code Interpreter, Browser, Observability, and Evaluations. Framework-agnostic and model-agnostic.

## Process

1. Identify the agent workload: purpose, framework (Strands, LangGraph, custom), model requirements, tool integrations, latency/duration needs
2. Use the `aws-docs` MCP tools to verify current AgentCore quotas, regional availability, and API changes
3. Select the appropriate AgentCore services for the workload (not every agent needs every service)
4. Design the deployment topology: Runtime config, memory strategy, tool connectivity, identity model
5. Configure security: Identity, Policy (Cedar), VPC connectivity, guardrails
6. Set up observability and evaluations from day one
7. Plan the PoC-to-production migration path

## AgentCore Service Selection Matrix

| Requirement | Service | Why |
|---|---|---|
| Deploy and scale agents serverlessly | **Runtime** | Secure, framework-agnostic hosting with session isolation, auto-scaling, consumption-based pricing |
| Conversation history and learned context | **Memory** | Short-term (session) and long-term (episodic) memory without managing infrastructure |
| Expose APIs/Lambda as agent tools | **Gateway** | Converts existing APIs and Lambda functions into MCP-compatible tools, handles auth |
| Agent-to-third-party auth (OAuth, API keys) | **Identity** | Manages workload identities, OAuth2 token exchange, API key vaults |
| Control what agents can do with tools | **Policy** | Cedar-based deterministic enforcement at the Gateway boundary, natural language authoring |
| Execute code in sandbox | **Code Interpreter** | Isolated sandbox for Python execution, file I/O, data analysis |
| Browse web pages programmatically | **Browser** | Cloud-based browser runtime for web interaction at scale |
| Trace, debug, monitor agent behavior | **Observability** | OpenTelemetry-compatible traces to CloudWatch/X-Ray, unified dashboards |
| Test and score agent quality | **Evaluations** | 13 built-in evaluators, custom scoring, continuous monitoring |

## When You Need Each Service

### Always Start With
- **Runtime** — every production agent needs managed hosting
- **Observability** — instrument from day one, not after the first incident

### Add Based on Workload
- **Memory** — when agents need conversation continuity or personalization
- **Gateway** — when agents call external APIs or Lambda functions (most agents)
- **Identity** — when agents access third-party services requiring OAuth or API keys
- **Policy** — when you need deterministic guardrails on tool usage (compliance, financial, PII)

### Add for Specialized Capabilities
- **Code Interpreter** — data analysis agents, code generation agents
- **Browser** — web scraping, form-filling, UI testing agents
- **Evaluations** — continuous quality monitoring (should be added before production)

## Runtime

AgentCore Runtime is a serverless, purpose-built hosting environment for AI agents.

### Key Capabilities
- Framework-agnostic: Strands Agents, LangGraph, custom Python, any framework
- Model-agnostic: any foundation model (Bedrock, self-hosted, third-party)
- Session isolation: each user session runs in its own execution context
- Supports real-time conversations (<1s latency) through to 8-hour async workloads
- Bidirectional streaming (WebSocket) for natural conversations
- Consumption-based pricing: CPU + memory billed per-second (1-second minimum)
- A2A (Agent-to-Agent) protocol support for cross-framework multi-agent systems

### Development vs Production Deployment

**Development and testing**: Use the AgentCore CLI or Starter Toolkit for fast iteration — scaffolding, local dev, quick deploys, and testing.

**Production**: Define all AgentCore resources in IaC (CDK, Terraform, CloudFormation, or SAM). CLI-created resources are useful for prototyping but should not be the source of truth for production infrastructure. The Starter Toolkit's CDK templates are a solid starting point for production IaC.

### Deployment Options
- **AgentCore CLI** (dev/test): Fastest path — `agentcore init` → `agentcore deploy` in minutes
- **Starter Toolkit** (reference IaC): Full-stack CDK template with auth, frontend, and all services pre-wired — fork and customize for production
- **CDK / Terraform / SAM** (production): Define resources in IaC, deploy via CI/CD pipeline
- **Container image** (manual): Docker image pushed to ECR, deployed to Runtime — full control over build

## AgentCore CLI

The [AgentCore CLI](https://github.com/aws/agentcore-cli) is the preferred tool for scaffolding, local development, and rapid iteration on agents. It abstracts away container builds, ECR pushes, and runtime configuration into simple commands. Use it for dev/test workflows — for production, define the same resources in IaC.

### Install

```bash
pip install agentcore-cli
```

### Quick Start

```bash
# Initialize a new agent project (choose framework: strands, langgraph, or custom)
agentcore init my-agent --framework strands

# Develop locally
cd my-agent
agentcore dev

# Deploy to AgentCore Runtime
agentcore deploy --region us-east-1

# Test the deployed agent
agentcore invoke --agent-name my-agent --input "Hello, what can you do?"
```

### What the CLI Handles
- **Project scaffolding**: generates agent code, Dockerfile, requirements, and config
- **Local development**: `agentcore dev` runs the agent locally with hot-reload
- **Build + push**: builds the Docker container, pushes to ECR automatically
- **Deploy**: creates/updates the agent runtime and endpoint
- **Invoke**: test deployed agents from the command line
- **Alias management**: create and update aliases for version routing

### CLI vs Direct AWS CLI

| Task | AgentCore CLI | AWS CLI |
|---|---|---|
| Create new agent | `agentcore init` | Manual Dockerfile + ECR + create-agent-runtime |
| Deploy | `agentcore deploy` | docker build + docker push + create/update API calls |
| Local dev | `agentcore dev` | Manual server setup |
| Test | `agentcore invoke` | `aws bedrock-agentcore invoke-agent-runtime` |

Use the AgentCore CLI for day-to-day development and testing. For production, define the equivalent resources in CDK, Terraform, or CloudFormation — the CLI is great for proving out configurations quickly, but IaC is the source of truth for production infrastructure.

## Starter Toolkit (FAST Template)

The [AgentCore Starter Toolkit](https://github.com/aws/bedrock-agentcore-starter-toolkit) provides a full-stack CDK reference architecture. Use it when you need a complete production deployment with authentication, frontend, and all AgentCore services wired together.

### What It Provides
- **CDK infrastructure**: Full IaC for Runtime, Gateway, Memory, Code Interpreter, and Observability — one `cdk deploy`
- **Auth integration**: Amazon Cognito authentication pre-wired for frontend → Runtime, agents → Gateway, and API Gateway
- **Frontend template**: React app with streamable HTTP for real-time agent response streaming via CloudFront
- **Framework templates**: Pre-built agent patterns for Strands Agents and LangGraph (framework-agnostic by design)
- **CI/CD patterns**: GitHub Actions workflow for build, scan (Amazon Inspector), deploy, and alias management
- **Observability**: AWS OpenTelemetry Distro auto-instrumentation for traces → X-Ray, metrics/logs → CloudWatch

### Quick Start

```bash
git clone https://github.com/aws/bedrock-agentcore-starter-toolkit.git
cd bedrock-agentcore-starter-toolkit
pip install -r requirements.txt
cdk deploy --all
```

### Architecture

The Fullstack AgentCore Solution Template (FAST) deploys:

```
CloudFront (React frontend)
  → Cognito (auth)
    → AgentCore Runtime (agent hosting)
      → AgentCore Memory (conversation + episodic)
      → AgentCore Gateway (MCP-compatible tools)
      → AgentCore Code Interpreter (Python sandbox)
      → AgentCore Observability → CloudWatch + X-Ray
```

Four authentication integration points are handled automatically:
1. User sign-in to the frontend
2. Frontend → AgentCore Runtime (token-based)
3. Agent → AgentCore Gateway (token-based)
4. API requests → API Gateway (token-based)

### Tooling Decision Matrix

| Phase | Use | Why |
|---|---|---|
| Scaffolding + local dev | **AgentCore CLI** | `init` → `dev` in minutes, hot-reload |
| Quick PoC deployment | **AgentCore CLI** | `deploy` handles container build, ECR, runtime creation |
| Full-stack reference architecture | **Starter Toolkit** | CDK deploys Runtime + Gateway + Memory + Cognito + CloudFront |
| Production resource definition | **CDK / Terraform / SAM** | IaC is the source of truth — reproducible, reviewable, auditable |
| Add agent to existing IaC | **CDK construct or Terraform resource** | Integrate into your existing infrastructure code |
| Learn AgentCore end-to-end | **Starter Toolkit** | Extensively documented, AI-dev friendly, fork as your production IaC starting point |

### Runtime Configuration

| Setting | Recommendation | Notes |
|---|---|---|
| CPU/Memory | Start with 1 vCPU / 2 GiB | Scale based on model inference needs and tool call overhead |
| Session TTL | 600s for real-time, up to 28,800s for async | Idle sessions consume resources |
| VPC connectivity | Enable for agents accessing private resources | Uses ENIs in your VPC |
| Endpoint type | Use agent endpoints for routing | Supports alias-based traffic splitting |

### Production Deployment Pattern
1. Define all AgentCore resources in IaC (CDK, Terraform, or CloudFormation) — Runtime, Gateway, Memory, Identity, Policy
2. Build agent container with AgentCore SDK decorators (CI/CD pipeline)
3. Push to ECR via pipeline (not manual `docker push`)
4. Deploy via `cdk deploy` / `terraform apply` / CloudFormation changeset
5. Create aliases for version management in IaC (never use TSTALIASID in production)
6. Configure resource-based policies for cross-account access if needed
7. Use the AgentCore CLI's `agentcore invoke` for smoke testing deployed agents

## Memory

### Short-Term Memory
- Session-scoped conversation history
- Automatic — enabled by default in Runtime
- Maintains context within a single conversation

### Long-Term Memory
- Persists across sessions — agent learns and adapts over time
- Episodic memory: stores extracted insights from past interactions
- Extraction jobs process conversation transcripts into retrievable knowledge
- Consumption-based pricing for storage and retrieval

### When to Use Long-Term Memory
- Customer support agents that need to remember past interactions
- Personal assistant agents that build user profiles over time
- Agents that should improve with repeated use

### When to Skip Long-Term Memory
- Stateless utility agents (code formatters, calculators)
- Agents where session isolation is a compliance requirement
- Simple single-turn tool-calling agents

## Gateway

Converts existing APIs, Lambda functions, and services into MCP-compatible tools that any agent framework can consume.

### Key Patterns
- **Lambda targets**: point Gateway at a Lambda function, it becomes an MCP tool
- **API targets**: wrap REST/HTTP APIs as agent-callable tools
- **MCP server federation**: connect to existing MCP servers
- Tools are automatically indexed and discoverable by agents
- Policy enforcement happens at the Gateway boundary

### Gateway + Policy Integration
Gateway intercepts all agent-to-tool traffic. Policy evaluates Cedar rules against each request before allowing or denying. This separation means:
- Security teams write policies without touching agent code
- Policies are deterministic (not LLM-based)
- Audit logging captures every allow/deny decision

## Identity

Manages how agents authenticate to third-party services and AWS resources.

### Workload Identities
- Each agent runtime gets an identity
- Supports IAM role assumption for AWS resources
- OAuth2 token exchange for third-party services (Salesforce, Jira, etc.)
- API key vault for services requiring static credentials
- Custom claims support for enhanced authentication

### Best Practice
- Use workload identities instead of embedding credentials in agent code
- Store OAuth client secrets in token vaults, not Secrets Manager (AgentCore manages rotation)
- Use resource-based policies to scope cross-account access

## Policy

Deterministic control over agent-tool interactions using Cedar language.

### How It Works
1. Create a Policy Engine and attach it to a Gateway
2. Write Cedar policies (or author in natural language — AgentCore converts to Cedar)
3. Gateway intercepts tool calls and evaluates against policies in real-time
4. Allow/deny decisions are logged for audit

### Common Policy Patterns

| Pattern | Cedar Example | Use Case |
|---|---|---|
| Amount limits | `forbid when { resource.refundAmount > 1000 }` | Financial guardrails |
| User-scoped access | `permit when { principal.department == "engineering" }` | Role-based tool access |
| Tool restriction | `forbid action == Action::"invoke" when { resource.toolName == "deleteUser" }` | Prevent dangerous operations |
| Time-based | `permit when { context.hour >= 9 && context.hour <= 17 }` | Business-hours-only actions |

### Policy vs Bedrock Guardrails
- **Policy**: controls *what tools* an agent can call and *with what parameters* — deterministic, Cedar-based
- **Guardrails**: controls *what content* an agent can produce — LLM-based content filtering, PII detection
- Use both: Policy for tool-level control, Guardrails for content-level control

## Multi-Agent Architectures

### Bedrock Multi-Agent Collaboration (Managed)
- Supervisor agent orchestrates collaborator agents
- Built-in task delegation and response aggregation
- Each agent has its own tools, knowledge bases, guardrails
- Best for: teams wanting managed orchestration with minimal custom code

### A2A Protocol (Agent-to-Agent)
- Cross-framework interoperability (Strands + LangGraph + custom agents can communicate)
- Agents advertise capabilities via Agent Cards
- Task-based request lifecycle with artifacts
- OAuth 2.0 and IAM authentication for secure inter-agent communication
- Best for: heterogeneous agent ecosystems, cross-team agent integration

### Agents-as-Tools Pattern
- Specialized agents registered as tools of a supervisor agent
- All agents run within the same AgentCore Runtime
- Supervisor selects and delegates dynamically
- Best for: monolithic deployments where all agents are owned by one team

### Architecture Decision

| Factor | Multi-Agent Collaboration | A2A Protocol | Agents-as-Tools |
|---|---|---|---|
| Framework flexibility | Bedrock Agents only | Any framework | Any framework (same runtime) |
| Cross-account | No | Yes | No |
| Managed orchestration | Yes | No (custom) | Partial |
| Setup complexity | Low | Medium-High | Low |
| Best for | All-in on Bedrock Agents | Cross-team, heterogeneous | Single-team, single runtime |

## Anti-Patterns

- **Using TSTALIASID in production.** Create proper aliases with version pinning. Test aliases have no SLA and no rollback capability.
- **Skipping observability until "later".** Instrument from day one. Debugging an unobservable agent in production is flying blind.
- **God agent that does everything.** If you need "and" in the agent's job description, you need two agents. Decompose into focused, composable agents.
- **Embedding credentials in agent instructions or environment variables.** Use AgentCore Identity for OAuth/API keys, IAM roles for AWS resources.
- **Not setting session TTLs.** Idle sessions consume compute resources. Set appropriate TTLs based on actual usage patterns.
- **Skipping Policy for tool access.** Without Policy, any agent can call any tool with any parameters. In production, that is a compliance and security gap.
- **Over-engineering the PoC.** Ship something that works with Runtime + Observability first. Add Memory, Gateway, Policy as needs emerge.
- **Ignoring token costs during development.** Track token usage per agent/session from the start. Costs compound fast with multi-step reasoning loops.
- **Manual prompt management.** Treat system prompts like code — version control, review, test. Prompt drift is a production incident waiting to happen.
- **Not evaluating before production.** Run evals (built-in or DeepEval) in CI/CD. "It looks right" is not a quality gate.
- **CLI-deployed resources as production infrastructure.** The AgentCore CLI is excellent for dev/test, but production resources should be defined in IaC (CDK, Terraform, CloudFormation). CLI-created resources are not version-controlled, not reproducible, and not auditable.

## Pricing Model

AgentCore uses consumption-based pricing across all services — no upfront commitments.

| Service | Billing Unit | Key Detail |
|---|---|---|
| Runtime | CPU-seconds + memory-seconds | 1-second minimum, active consumption only |
| Memory | Storage + retrieval operations | Short-term included with Runtime sessions |
| Gateway | API calls + search queries + tool indexing | Per-request pricing |
| Identity | Token/key requests for non-AWS resources | Per-request pricing |
| Policy | Authorization requests + NL authoring tokens | Per-request pricing |
| Code Interpreter | CPU-seconds + memory-seconds | Per-session, 1-second minimum |
| Browser | CPU-seconds + memory-seconds | Per-session, 1-second minimum |
| Observability | Telemetry generated + stored + queried | Similar to CloudWatch pricing model |
| Evaluations | Built-in evaluator invocations + custom evals | Per-evaluation pricing |

## Regional Availability

AgentCore services are available across multiple regions. Core services (Runtime, Memory, Gateway, Identity) are available in: us-east-1, us-east-2, us-west-2, ap-southeast-1, ap-southeast-2, ap-south-1, ap-northeast-1, eu-west-1, eu-central-1. Check the `aws-docs` MCP tools for the latest regional availability, as new regions are added regularly.

## Additional Resources

### Reference Files

For detailed operational guidance, consult:
- **`references/runtime-deployment.md`** — Container setup, SDK decorators, CI/CD with GitHub Actions, alias management, VPC configuration, scaling patterns, and Starter Toolkit usage
- **`references/memory-gateway-identity.md`** — Memory configuration (short-term and long-term), Gateway setup with Lambda/API targets, Identity OAuth2/API key patterns, and Policy Cedar examples
- **`references/observability-evaluations.md`** — OpenTelemetry instrumentation, CloudWatch/X-Ray integration, Langfuse for LLM-specific analytics, DeepEval evaluation patterns, CI/CD eval integration, and production monitoring dashboards

### Related Skills
- **`bedrock`** — Bedrock cost modeling and model selection for agent workloads
- **`strands-agent`** — Strands Agents SDK scaffolding (deploys to AgentCore Runtime)
- **`security-review`** — IAM, network, and encryption audit for agent infrastructure
- **`networking`** — VPC design for agents accessing private resources
- **`observability`** — CloudWatch/X-Ray deep-dive for agent monitoring
- **`step-functions`** — Alternative orchestration for deterministic multi-step workflows

## Output Format

When recommending an AgentCore architecture, include:

| Component | Choice | Rationale |
|---|---|---|
| Runtime | Container on ECR, 1 vCPU / 2 GiB | Standard agent workload |
| Framework | Strands Agents | Python-native, AWS-integrated |
| Model | Claude Sonnet via Bedrock | Capable reasoning, tool calling |
| Memory | Short-term + long-term (episodic) | Customer support needs continuity |
| Gateway | 3 Lambda targets (orders, refunds, FAQ KB) | Existing APIs wrapped as MCP tools |
| Identity | OAuth2 for Salesforce, IAM for DynamoDB | Third-party + AWS resource access |
| Policy | Cedar: refund amount limits, role-based tool access | Financial compliance |
| Observability | AgentCore native + Langfuse | Infra health + LLM behavior analytics |
| Evaluations | 5 built-in evaluators + custom tool-use eval | CI/CD quality gate |

Include estimated monthly cost range using the `cost-check` skill or the `awspricing` MCP tools.
