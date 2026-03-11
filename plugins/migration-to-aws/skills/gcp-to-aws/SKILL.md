---
name: gcp-to-aws
description: "Migrate workloads from Google Cloud Platform to AWS. Triggers on: migrate from GCP, GCP to AWS, move off Google Cloud, migrate Terraform to AWS, migrate Cloud SQL to RDS, migrate GKE to EKS, migrate Cloud Run to Fargate, Google Cloud migration. Runs a 5-phase process: discover GCP resources from Terraform files, clarify migration requirements, design AWS architecture, estimate costs, and plan execution."
---

# GCP-to-AWS Migration Skill

## Philosophy

- **Re-platform by default**: Select AWS services that match GCP workload types (e.g., Cloud Run → Fargate, Cloud SQL → RDS).
- **Dev sizing unless specified**: Default to development-tier capacity (e.g., db.t4g.micro, single AZ). Upgrade only on user direction.
- **Infrastructure-first approach**: v1.0 migrates Terraform-defined infrastructure only. App code scanning and billing import are v1.1+.

## Prerequisites

User must provide GCP infrastructure-as-code:

- One or more `.tf` files (Terraform)
- Optional: `.tfvars` or `.tfstate` files

If no Terraform files are found, stop immediately and ask user to provide them.

## State Management

Migration state lives in `.migration/[MMDD-HHMM]/` directory (created by Phase 1, persists across invocations):

```
.migration/
├── .gitignore                       # Auto-created to protect state files from git
└── 0226-1430/                       # MMDD-HHMM timestamp
    ├── .phase-status.json           # Current phase tracking
    ├── gcp-resource-inventory.json  # All GCP resources found
    ├── gcp-resource-clusters.json   # Clustered resources by affinity
    ├── clarified.json               # User answers (Phase 2 output)
    ├── aws-design.json              # AWS services mapping (Phase 3 output)
    ├── estimation.json              # Cost breakdown (Phase 4 output)
    └── execution.json               # Timeline + risks (Phase 5 output)
```

**Note:** The `.migration/` directory is automatically protected by a `.gitignore` file created in Phase 1. Migration state files will not be accidentally committed to version control.

**.phase-status.json schema:**

```json
{
  "phase": "discover|clarify|design|estimate|execute",
  "status": "in-progress|completed",
  "timestamp": "2026-02-26T14:30:00Z",
  "version": "1.0.0"
}
```

If `.phase-status.json` exists:

- If `status` is `completed`: advance to next phase (discover→clarify, clarify→design, etc.)
- If `status` is `in-progress`: resume from that phase

## Phase Routing

1. **On skill invocation**: Check for `.migration/*/` directory
   - If none exist: Initialize Phase 1 (Discover), set status to `in-progress`
   - If multiple exist: **STOP**. Output: "Multiple migration sessions detected in `.migration/`:" then for each directory, display its name and the contents of its `.phase-status.json` (phase + status). Output: "Pick one to continue: [list with phase info]"
   - If exists: Load `.phase-status.json` and validate:
     - **If empty file (0 bytes)**: STOP. Output: "State file is empty. Delete `.migration/[MMDD-HHMM]/.phase-status.json` and restart."
     - **If invalid JSON**: STOP. Output: "State file corrupted (invalid JSON). Delete `.migration/[MMDD-HHMM]/.phase-status.json` and restart Phase [X]."
     - **If missing required fields** (`phase`, `status`, `timestamp`, `version`): STOP. Output: "State file incomplete (missing [field]). Delete and restart."
     - **If version != "1.0.0"**: STOP. Output: "Incompatible state file version: [version]. This skill requires version 1.0.0."
     - **If unrecognized phase value**: STOP. Output: "Unrecognized phase: [value]. Valid values: discover, clarify, design, estimate, execute."
     - **If status not in {in-progress, completed}**: STOP. Output: "Unrecognized status: [value]. Valid values: in-progress, completed."
     - **If valid**: Determine next action:
       - If phase status is `in-progress`: Resume that phase
       - If phase status is `completed`: Advance to next phase

2. **Phase transition mapping** (when phase is `completed`):
   - discover (completed) → Route to clarify
   - clarify (completed) → Route to design
   - design (completed) → Route to estimate
   - estimate (completed) → Route to execute
   - execute (completed) → Migration complete; offer summary and cleanup options

3. **Phase gate checks**: If prior phase incomplete, do not advance (e.g., cannot enter estimate without completed design)

## Phase Summary Table

| Phase        | Inputs                                                                        | Outputs                                                                                   | Reference                                |
| ------------ | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------- |
| **Discover** | `.tf` files                                                                   | `gcp-resource-inventory.json`, `gcp-resource-clusters.json`, `.phase-status.json` updated | `references/phases/discover/discover.md` |
| **Clarify**  | `gcp-resource-inventory.json`, `gcp-resource-clusters.json`                   | `clarified.json`, `.phase-status.json` updated                                            | `references/phases/clarify.md`           |
| **Design**   | `gcp-resource-inventory.json`, `gcp-resource-clusters.json`, `clarified.json` | `aws-design.json`, `aws-design-report.md`, `.phase-status.json` updated                   | `references/phases/design.md`            |
| **Estimate** | `aws-design.json`, `clarified.json`                                           | `estimation.json`, `estimation-report.md`, `.phase-status.json` updated                   | `references/phases/estimate.md`          |
| **Execute**  | `aws-design.json`, `estimation.json`                                          | `execution.json`, `execution-timeline.md`, `.phase-status.json` updated                   | `references/phases/execute.md`           |

## MCP Servers

**awspricing** (for cost estimation):

1. Call `get_pricing_service_codes()` to detect availability
2. If success: use live AWS pricing
3. If timeout/error: fall back to `references/shared/pricing-fallback.json` (includes 2026 on-demand rates for major services)

**awsknowledge** (for design validation):

1. Use for regional availability checks (e.g., service available in target region?)
2. Use for feature parity checks (e.g., do required features exist in AWS service?)
3. Use for service constraints and best practices
4. Fallback: if unavailable, set `validation_status: "skipped"` in aws-design.json with note in design report
5. **Important**: Validation is informational; design proceeds either way (not blocking)

## Error Handling

| Condition                                   | Action                                                                                                                       |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| No `.tf` files found                        | Stop. Output: "No Terraform files detected. Please provide `.tf` files with your GCP resources and try again."               |
| `.phase-status.json` missing phase gate     | Stop. Output: "Cannot enter Phase X: Phase Y-1 not completed. Start from Phase Y or resume Phase Y-1."                       |
| awspricing unavailable after 3 attempts     | Display user warning about ±15-25% accuracy. Use `pricing-fallback.json`. Add `pricing_source: fallback` to estimation.json. |
| User does not answer all Q1-8               | Offer Mode C (defaults) or Mode D (free text). Phase 2 completes either way.                                                 |
| `aws-design.json` missing required clusters | Stop Phase 4. Output: "Re-run Phase 3 to generate missing cluster designs."                                                  |

## Defaults

- **IaC output**: None (v1.0 produces design, cost estimates, and execution plans — no IaC code generation)
- **Region**: `us-east-1` (unless user specifies, or GCP region → AWS region mapping suggests otherwise)
- **Sizing**: Development tier (e.g., Aurora Serverless v2 0.5 ACU for databases, 0.5 CPU for Fargate)
- **Migration mode**: Full infrastructure path (no AI-only subset path in v1.0)
- **Cost currency**: USD
- **Timeline assumption**: 8-12 weeks total

## Workflow Execution

When invoked, the agent **MUST follow this exact sequence**:

1. **Load phase status**: Read `.phase-status.json` from `.migration/*/`.
   - If missing: Initialize for Phase 1 (Discover)
   - If exists: Determine current phase based on phase field and status value

2. **Determine phase to execute**:
   - If status is `in-progress`: Resume that phase (read corresponding reference file)
   - If status is `completed`: Advance to next phase (read next reference file)
   - Phase mapping for advancement:
     - discover (completed) → Execute clarify (read `references/phases/clarify.md`)
     - clarify (completed) → Execute design (read `references/phases/design.md`)
     - design (completed) → Execute estimate (read `references/phases/estimate.md`)
     - estimate (completed) → Execute execute (read `references/phases/execute.md`)
     - execute (completed) → Migration complete

3. **Read phase reference**: Load the full reference file for the target phase.

4. **Execute ALL steps in order**: Follow every numbered step in the reference file. **Do not skip, optimize, or deviate.**

5. **Validate outputs**: Confirm all required output files exist with correct schema before proceeding.

6. **Update phase status**: Each phase reference file specifies the final `.phase-status.json` update (records the phase that just completed).

7. **Display summary**: Show user what was accomplished, highlight next phase, or confirm migration completion.

**Critical constraint**: Agent must strictly adhere to the reference file's workflow. If unable to complete a step, stop and report the exact step that failed.

User can invoke the skill again to resume from last completed phase.

## Scope Notes

**v1.0 includes:**

- Terraform infrastructure discovery (no app code scanning)
- User requirement clarification (8 structured questions)
- Structured Design (cluster-based mapping from Terraform)
- AWS cost estimation (from pricing API or fallback)
- Execution timeline and risk assessment

**Deferred to v1.1+:**

- App code scanning (runtime detection of compute workload types)
- AI-only fast-track path in Clarify/Design
- Billing data import from GCP
- Flat Design path (for non-Terraform codebases)
