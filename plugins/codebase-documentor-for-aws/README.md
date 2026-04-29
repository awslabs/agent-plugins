# Codebase Documentor for AWS

Analyze codebases — especially legacy and AWS-deployed services — to produce structured technical documentation and architecture diagrams with source-of-truth citations linking every finding back to the code. Understands CDK, CloudFormation, Terraform, and enriches output with AWS service context. Delegates architecture diagram generation to the `aws-architecture-diagram` skill (from the `deploy-on-aws` plugin) for professional draw.io output with official AWS4 icons, or falls back to inline Mermaid.

## How It Works

Unlike ad-hoc "explain this code" prompts, codebase-documentor-for-aws uses an **outline-driven pipeline** to systematically analyze codebases of any size — from small microservices to large legacy monoliths. Step 1 gathers minimal context from you; Steps 2 – 6 then run autonomously.

**The pipeline:**

1. **Gather context** _(interactive)_ — Confirm the target directory and accept any existing docs or business context. Skipped when provided upfront via automation.
2. **Build file tree** — Recursively list all files, filter out noise, detect the project type and entry points
3. **Generate outline** — Analyze the file tree, README, and entry points to produce a documentation outline mapping each section to source files
4. **Analyze** — Two parallel paths: (A) application code analysis (APIs, data models, integrations) and (B) infrastructure-as-code analysis (CDK, CloudFormation, Terraform resources and relationships)
5. **Generate diagram** — Delegate to the `aws-architecture-diagram` skill (deploy-on-aws plugin) for draw.io output, or fall back to inline Mermaid
6. **Assemble** — Combine all sections into `CODEBASE_ANALYSIS.md` (single file with business context included)

**For large codebases**, the outline sections are tracked on a persistent `.codebase-documentor-progress.md` task board in the target project, making the process **resumable** — if a session is interrupted, a new session reads the progress file and continues from where it left off.

## Skills

| Skill              | Purpose                                                                                                                                                                                                                                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `document-service` | Analyze codebases to produce `CODEBASE_ANALYSIS.md` with architecture diagrams (via `aws-architecture-diagram` skill, Mermaid fallback), business context, and source citations. Two core analysis paths: application code (APIs, data models, integrations) and IaC (CDK, CloudFormation, Terraform). |

## MCP Servers

| Server         | Type  | Purpose                                                              | When Used                                 |
| -------------- | ----- | -------------------------------------------------------------------- | ----------------------------------------- |
| `awsknowledge` | HTTP  | AWS service descriptions, architecture guidance, documentation links | When AWS services detected in code or IaC |
| `awsiac`       | stdio | CDK/CloudFormation resource schema validation and IaC best practices | When CDK or CloudFormation files detected |

## Installation

```bash
/plugin install codebase-documentor-for-aws@agent-plugins-for-aws
```

Or test locally:

```bash
claude --plugin-dir ./plugins/codebase-documentor-for-aws
```

## Examples

**Analyze an inherited codebase:**

```text
I inherited this codebase and need to understand it. Analyze and document it.
```

**Document a specific service:**

```text
Analyze the order-processing service and generate documentation.
```

**Analyze with existing context:**

```text
Analyze this service. Here's an existing design doc: [link]
```

**Understand a legacy system:**

```text
Help me understand this legacy system. What does it do and how is it architected?
```
