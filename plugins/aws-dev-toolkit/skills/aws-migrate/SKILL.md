---
name: aws-migrate
description: Guided migration assessment and planning — discover source environment, map services, estimate effort, and plan migration waves. Orchestrates gcp-to-aws, azure-to-aws, and the migration-advisor agent.
argument-hint: [source-cloud or "assess"]
---

You are running a guided cloud migration workflow. This orchestrates discovery, mapping, and planning into one cohesive flow.

## Process

```
DISCOVER SOURCE → MAP SERVICES → ASSESS COMPLEXITY → PLAN WAVES → ESTIMATE COST
```

### Phase 1: Discover Source Environment

Determine the source cloud from `$ARGUMENTS` or by detecting installed CLIs:

```bash
# Auto-detect source cloud
which gcloud >/dev/null 2>&1 && echo "GCP detected"
which az >/dev/null 2>&1 && echo "Azure detected"
which oci >/dev/null 2>&1 && echo "OCI detected"
which doctl >/dev/null 2>&1 && echo "DigitalOcean detected"
```

Then delegate to the appropriate skill:
- **GCP** → invoke the `gcp-to-aws` skill for service mapping
- **Azure** → invoke the `azure-to-aws` skill for service mapping
- **On-prem/Other** → use the `migration-advisor` agent directly

Also spawn the `migration-advisor` agent (`subagent_type: "aws-dev-toolkit:migration-advisor"`) for the detailed discovery commands.

### Phase 2: Discovery Questions

Ask progressively (2-3 at a time):

**First round:**
- What's driving the migration? (cost, compliance, consolidation, end-of-life, acquisition)
- What's the timeline? (hard deadline vs flexible)
- How many workloads are moving? (1, 5, 20, 100+)

**Based on answers, follow up with:**
- Are there data residency requirements?
- What's the acceptable downtime window? (zero, minutes, hours, weekend)
- Are there licensing constraints? (Windows, Oracle, SAP)
- What's the team's AWS experience level? (1-5)
- Is there a parallel-run requirement? (run in both clouds simultaneously)

### Phase 3: Service Mapping

Use the source-specific skill (`gcp-to-aws` or `azure-to-aws`) to produce a mapping table. For each service:

| Source Service | AWS Equivalent | Migration Strategy | Complexity | Notes |
|---------------|---------------|-------------------|-----------|-------|
| ... | ... | Rehost/Replatform/Refactor | Low/Med/High | Gotchas |

### Phase 4: Wave Planning

Group workloads into migration waves:

```markdown
## Wave 0: Foundation (Week 1-2)
- Landing zone setup (Control Tower or manual)
- Networking (VPC, Transit Gateway, VPN/Direct Connect)
- Identity (IAM Identity Center, federation)
- Logging/monitoring baseline

## Wave 1: Quick Wins (Week 3-4)
- Stateless services, low-risk
- Proves the migration pipeline works
- Builds team confidence

## Wave 2: Core Services (Week 5-8)
- Databases, stateful workloads
- Requires cutover planning and rollback

## Wave 3: Complex/Critical (Week 9-12+)
- High-risk or high-complexity workloads
- May need refactoring
- Extended parallel-run period
```

### Phase 5: Security & Compliance

**Mandatory** — spawn the `iac-reviewer` agent or invoke `security-review` to validate the proposed AWS landing zone against:
- IAM baseline (no root access keys, MFA enforced)
- Network isolation (VPC design, security groups)
- Encryption defaults
- SCP guardrails (per CLAUDE.md baseline)
- Compliance mapping (source cloud certifications → AWS equivalents)

### Phase 6: Cost Estimation

Use the `cost-check` skill or `aws-pricing` MCP tools to estimate:
- Current source cloud spend (if accessible)
- Projected AWS spend (baseline + first 12 months)
- Migration tooling costs (DMS, MGN, Transfer Family)
- Potential savings (reserved instances, savings plans, right-sizing)

## Output Format

```markdown
# Migration Plan: [Source] → AWS

## Executive Summary
[2-3 sentences: what, why, when, how much]

## Source Environment
[Inventory summary from discovery]

## Service Mapping
[Table from Phase 3]

## Migration Strategy
| Strategy | Count | Examples |
|----------|-------|---------|
| Rehost (lift & shift) | X | ... |
| Replatform | X | ... |
| Refactor | X | ... |
| Retire | X | ... |

## Wave Plan
[From Phase 4]

## Security & Compliance
[Findings from Phase 5]

## Cost Projection
| Period | Source Cloud | AWS Projected | Delta |
|--------|------------|---------------|-------|
| Current monthly | $X | — | — |
| Post-migration monthly | — | $X | +/-$X |
| 12-month total (incl. migration costs) | $X | $X | +/-$X |

## Risks
[Top 5 risks with mitigation plans]

## Next Steps
1. [Immediate action]
2. [...]
```
