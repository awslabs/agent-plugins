# Landing Zone

> **Last Updated:** 2026-05-10

## Table of Contents

- [Capabilities](#capabilities)
- [Starting Workflow](#starting-workflow)
- [Agents and Transforms](#agents--transforms)
- [Decision Points](#decision-points)
- [Example Requirements](#example-requirements)
- [Example Tasks](#example-tasks)
- [Known Limitations](#known-limitations)

## Capabilities

Build an AWS landing zone as the foundation for your migration project. AWS Transform analyzes your migration inventory and business requirements to recommend an Organizational Unit (OU) and account structure, apply Service Control Policies (SCPs), and generate or deploy the infrastructure as code (IaC).

The landing zone agent operates in two phases:

1. **Foundation setup** — Establish the core landing zone: AWS Control Tower, foundational OUs (Security, Infrastructure, Sandbox, Workloads), and core accounts (Log Archive, Audit).
2. **Workload account design** — Design and create workload OUs and accounts based on migration waves, business units, and environment separation requirements.

Supports both **greenfield** (no existing landing zone) and **brownfield** (existing OUs and accounts already deployed) environments.

## Starting Workflow

1. **Connector setup** — Create a target AWS account connector pointing to the organization management account in the Control Tower home Region
2. **Confirm organization context** — AWS Transform presents the management account ID and target Region for confirmation
3. **Foundation setup** — Design and deploy (or generate IaC for) the core OU structure, Control Tower initialization, and SCPs
4. **Workload account design** — Answer discovery questions; AWS Transform proposes OU and account structure based on migration waves and business requirements
5. **Workload deployment** — Deploy workload OUs, accounts, and SCPs, or download IaC artifacts

**Key questions to ask user:**

- "Do you already have AWS Control Tower or AWS Organizations set up (brownfield), or are we starting from scratch (greenfield)?"
- "What is your Control Tower home Region?"
- "What email prefix and domain for account email addresses?"
- "How many business units or teams will use AWS?"
- "Do you have compliance requirements that affect account isolation?"

## Agents & Transforms

| Agent              | How to Discover                            | Purpose                                                                      |
| ------------------ | ------------------------------------------ | ---------------------------------------------------------------------------- |
| Landing zone agent | `list_resources` with `resource: "agents"` | Foundation setup, workload account design, SCP configuration, IaC generation |

**Discover the agent dynamically:**

```python
list_resources(resource="agents")
create_job(workspaceId="...", jobName="Landing Zone Setup",
  objective="Build AWS landing zone foundation and workload account structure",
  orchestratorAgent="<discovered>")
```

## Decision Points

| Decision                       | Options                                                                | When to Ask                               |
| ------------------------------ | ---------------------------------------------------------------------- | ----------------------------------------- |
| Greenfield vs brownfield       | Greenfield (new) / Brownfield (existing OUs/accounts)                  | Start — determines what gaps to fill      |
| Deployment method (foundation) | Deploy for me / I'll deploy on my own / Design workload accounts first | Phase 1 Step 5                            |
| Deployment method (workload)   | Deploy for me / I'll deploy on my own                                  | Phase 2 Step 10                           |
| IaC format (if self-deploying) | AWS CDK / Landing Zone Accelerator (LZA)                               | When user selects "I'll deploy on my own" |
| Foundation OU customization    | Accept recommended structure / Customize OUs and accounts              | Phase 1 Step 1                            |
| SCP selection                  | Which SCPs to apply and to which OUs                                   | Phase 1 Step 4 and Phase 2 Step 9         |
| Account strategy               | Single app per account / Grouped / Environment-based                   | Phase 2 discovery                         |
| Environment separation         | Separate accounts per env / Shared accounts                            | Phase 2 discovery                         |
| Compliance sub-OUs             | Regulated / Standard separation                                        | Phase 2 — if frameworks identified        |

## Example Requirements

```
## Requirement 1: Foundation Setup

**User Story:** As a cloud platform engineer, I want the core landing zone foundation deployed
so that governance controls, centralized logging, and account isolation are in place before any workloads arrive.
**Acceptance Criteria:**

1. WHEN foundation setup completes, Control Tower SHALL be initialized with Security OU, Log Archive account, and Audit account
2. WHEN foundation setup completes, Infrastructure, Sandbox, and Workloads OUs SHALL exist in the organization
3. WHEN SCPs are applied, member accounts SHALL be unable to exceed the boundaries defined by the SCPs
   **Handled by:** AWS Transform Landing Zone Agent

## Requirement 2: Workload Account Structure

**User Story:** As a cloud platform engineer, I want workload OUs and accounts designed around my migration waves
so that servers can be migrated into correctly isolated accounts without splitting waves.
**Acceptance Criteria:**

1. WHEN workload structure is proposed, ALL servers in a migration wave SHALL map to the same target account
2. WHEN environment isolation is required, Workloads/Production and Workloads/Non-Production sub-OUs SHALL be created
3. WHEN sensitive-data applications are identified, they SHALL each receive a dedicated account
   **Handled by:** AWS Transform Landing Zone Agent

## Requirement 3: IaC Generation

**User Story:** As a platform engineer, I want IaC artifacts generated for the landing zone
so that I can review, version-control, and deploy the infrastructure through my own pipeline.
**Acceptance Criteria:**

1. WHEN IaC generation completes, artifacts SHALL be available in CDK (TypeScript) or LZA (YAML) format
2. WHEN artifacts are downloaded, a checksum SHALL be provided to verify file integrity
3. WHEN LZA format is selected, the generated YAML SHALL be compatible with LZA Universal Configuration version 1.1.0
   **Handled by:** AWS Transform Landing Zone Agent
```

## Example Tasks

```
- [ ] 1. Connector setup
  - [ ] 1.1 Create target AWS account connector for the management account
  - [ ] 1.2 Confirm connector Region matches Control Tower home Region
  - [ ] 1.3 Approve connector via AWS Console verification link
- [ ] 2. Foundation design
  - [ ] 2.1 Review recommended foundation OU structure
  - [ ] 2.2 Confirm email prefix and domain
  - [ ] 2.3 Review and select SCPs
- [ ] 3. Foundation deployment
  - [ ] 3.1 Choose deployment method
  - [ ] 3.2 Submit deployment for approval
  - [ ] 3.3 Confirm OUs and accounts created
- [ ] 4. Workload account design
  - [ ] 4.1 Check for migration planning artifacts
  - [ ] 4.2 Answer discovery questions
  - [ ] 4.3 Review proposed workload structure
  - [ ] 4.4 Select workload SCPs
- [ ] 5. Workload deployment
  - [ ] 5.1 Choose deployment method
  - [ ] 5.2 Submit for approval or download IaC
  - [ ] 5.3 Confirm all OUs and accounts created
```

## Known Limitations

- Once an OU or account is deployed, it cannot be removed through the landing zone agent
- The Security OU is managed by Control Tower — cannot be modified through this tool
- All servers in a migration wave must go to the same account — waves cannot be split across accounts
- The connector Region must match the Control Tower home Region and IAM Identity Center Region
- LZA deployment requires the AWS Transform account and LZA installation to be in the same AWS Organization
- SCPs cannot grant permissions — they only restrict what IAM policies allow
- Brownfield environments may require remediation before Control Tower can be initialized
