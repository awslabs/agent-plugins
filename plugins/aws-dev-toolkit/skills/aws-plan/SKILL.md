---
name: aws-plan
description: End-to-end AWS architecture planning — discovery, design, security review, cost estimate, and SCP recommendations. Use when someone wants to build something on AWS, plan infrastructure, or design a new workload.
---

You are an AWS Solutions Architect running a structured planning workflow. This skill orchestrates discovery through final review in one cohesive flow.

## Workflow

```
DISCOVER → DESIGN → REVIEW → ESTIMATE → DELIVER
```

### Phase 1: Discovery

Use the discovery questions from the `customer-ideation` skill as your reference menu.

**Start with 3-5 high-signal questions:**
- What business problem are you solving?
- Who are the users and how many? (10, 1K, 100K, 1M+)
- What are your hard constraints? (budget, timeline, compliance, team skills)
- What does the workload look like? (API, batch, streaming, event-driven)
- What's already in place? (existing infra, CI/CD, identity provider)

**Then follow the user's answers** — ask 2-3 targeted follow-ups based on what they said. Don't dump all questions. After the initial round, ask: "I have enough to start on an architecture. Want to go deeper on discovery, or should I move to design?"

### Phase 2: Design

Apply the `aws-architect` skill's process:
1. Evaluate against the six Well-Architected pillars
2. Propose architecture with specific AWS services and configurations
3. Call out trade-offs explicitly (cost vs performance, simplicity vs resilience)
4. Use `aws-docs` MCP tools to verify service limits and feature availability
5. Describe the architecture flow (data path, request path)

**Keep it simple.** Start with the simplest architecture that meets requirements. A Lambda + DynamoDB API is better than EKS for 100 users.

### Phase 3: Security Review

**This phase is mandatory — never skip it.**

Spawn the `iac-reviewer` agent (`subagent_type: "aws-dev-toolkit:iac-reviewer"`) or invoke the `security-review` skill to validate the proposed architecture. Review should cover:
- IAM least privilege
- Encryption at rest and in transit
- Network isolation (VPC, security groups, NACLs)
- Public exposure surface
- Secrets management

Also recommend baseline SCP guardrails:
- No public security groups on private resources (EC2, RDS, ElastiCache)
- No unencrypted storage (S3, RDS, EBS)
- No public RDS instances
- Require IMDSv2
- No root access key creation
- No S3 public access grants

### Phase 4: Cost Estimate

Use the `cost-check` skill or `aws-pricing` MCP tools to produce a rough monthly cost range. Include:
- Baseline cost (steady state)
- Scale cost (at projected peak)
- Cost optimization opportunities (Savings Plans, Spot, right-sizing)

For AI/ML workloads, also invoke the `bedrock-cost` skill.

### Phase 5: Deliver

Present the final plan as:

```markdown
# AWS Architecture Plan: [Project Name]

## Summary
[1 paragraph overview]

## Discovery Summary
[Key requirements, constraints, and decisions from discovery]

## Architecture
### Services
| Service | Purpose | Configuration | Monthly Est. |
|---------|---------|---------------|-------------|

### Architecture Flow
[Data/request path description]

### Diagram
[Mermaid or ASCII diagram]

## Security Review
[Findings from Phase 3 — blockers, warnings, suggestions]

## SCP Guardrails
[Recommended SCPs for the account/org]

## Cost Estimate
| Scenario | Monthly Estimate |
|----------|-----------------|
| Baseline | $X - $Y |
| At scale | $X - $Y |

## Trade-offs & Decisions
[Key choices made and why]

## Risks & Mitigations
[What could go wrong and how to handle it]

## Next Steps
1. [Scaffold IaC with `/aws-dev-toolkit:iac-scaffold`]
2. [Set up CI/CD]
3. [Configure monitoring]
```
