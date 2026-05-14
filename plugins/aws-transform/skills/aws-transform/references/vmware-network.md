# VMware Network Migration

> **Last Updated:** 2026-05-05

## Table of Contents

- [Capabilities](#capabilities)
- [Workflow](#workflow)
- [Agents and Transforms](#agents--transforms)
- [Decision Points](#decision-points)
- [Hub and Spoke Architecture](#hub-and-spoke-architecture)
- [VPC and Subnet Operations](#vpc-and-subnet-operations)
- [Multi-Account Considerations](#multi-account-considerations)
- [Deployment Approvals](#deployment-approvals)
- [Known Limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [Example Requirements](#example-requirements)
- [Example Tasks](#example-tasks)

## Capabilities

Migrate on-premises network infrastructure to AWS. Translates source environment configuration into AWS-equivalent network resources — VPCs, subnets, security groups, NAT gateways, transit gateways, elastic IPs, routes, and route tables.

- Network segments → AWS VPCs + subnets
- Firewall rules → AWS Security Groups
- Routing → AWS Transit Gateway (Hub and Spoke) or VPC route tables (Isolated)
- Review and modify generated network configuration before deployment
- VPC operations: rename, resize, merge, split, delete, exclude/include, change IP address
- Subnet operations: resize, delete, change IP address
- Security group referencing (within-VPC and cross-VPC/cross-account)
- IP migration: keep existing ranges or update to new CIDRs, static or DHCP assignment
- Guided network recommendations (naming, right-sizing, consolidation, security review)
- Creates network diagrams (PNG and Mermaid)
- Custom tags, MAP 2.0 tags, and automatic launch/replication tags
- Deploy the network using AWS CloudFormation with approval workflow
- Run reachability analysis on deployed VPCs
- Delete deployed network resources (rollback)
- Generates CloudFormation, CDK (TypeScript), Terraform, or Landing Zone Accelerator IaC

### Supported Source Formats

| Format                   | Produces                                               |
| ------------------------ | ------------------------------------------------------ |
| VMware NSX export (.zip) | VPCs + subnets + security groups                       |
| Cisco ACI                | VPCs + subnets + security groups                       |
| Palo Alto Networks       | VPCs + subnets + security groups                       |
| Fortinet FortiGate       | VPCs + subnets + security groups                       |
| RVTools (.xlsx/.zip)     | VPCs + subnets only (no security groups)               |
| modelizeIT               | VPCs + subnets + security groups (hybrid environments) |

### Topology Options

| Topology          | When to use                                                                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **Hub and Spoke** | Multi-tier apps, cross-VPC traffic, shared services, centralized egress/ingress. Creates Transit Gateway + Inspection/Outbound/Inbound VPCs. |
| **Isolated VPCs** | Independent workloads with no cross-VPC communication. Each VPC gets its own internet gateway.                                               |

### Security Group Strategies

| Strategy     | When to use                                                                                                 |
| ------------ | ----------------------------------------------------------------------------------------------------------- |
| **MAP**      | Static IP environments. Translates source firewall rules to SGs with IP-based rules.                        |
| **MAP_DHCP** | Dynamic IP / DHCP environments. Produces broader rules to accommodate IP changes. Use with Transit Gateway. |
| **SKIP**     | Manual SG configuration post-migration. Use when source rules are too complex or need redesign.             |

---

## Workflow

The network migration workflow is one sequence across three phases — Phase 1's 5 steps, Phase 2's 9 steps, and Phase 3's 4 steps run in order (18 steps total). Each phase's numbering restarts at 1, but the phases execute sequentially without gaps.

### Phase 1: Target Account Setup

1. Select "Network Migration" workflow
2. Confirm plan → "Proceed"
3. Select migration type: Single-account or Multi-account
4. MAP agreement (optional)
5. Configure connector (HITL task) — must include `connectorType` in payload

### Phase 2: Network Migration

1. Upload source file (NSX export, RVTools, etc.) — requires `planStepId` in `upload_artifact`
2. Select topology: Hub and Spoke or Isolated VPCs
3. Select security group strategy: MAP, MAP_DHCP, or SKIP
4. Agent presents configuration summary — **this is NOT the mapping step**
5. User confirms → mapping actually begins (2-5 min)
6. Guided Modernization or Direct Edits
7. Apply changes → IaC regeneration
8. Done with network design
9. Network diagram generation (image + Mermaid)

### Confirmation Before Mapping

After the user selects topology and security group strategy, the agent presents a configuration summary and asks for confirmation before starting the actual network mapping. Do NOT tell the user that mapping has started until the user confirms and the agent explicitly begins the mapping process.

The sequence is:

1. Select topology → agent acknowledges
2. Select security group strategy → agent presents **configuration summary** with all selections
3. User confirms "Yes, start network mapping" → mapping actually begins (2-5 min)

The summary step is NOT the mapping step. Do not conflate them.

### Polling and Waiting

Two types of waits occur during the workflow:

**Machine-gated steps** (mapping, job processing, agent responses):

- Poll automatically and silently every 30 seconds
- Do NOT ask the user for permission to poll
- Only surface results to the user (completion, error, or progress update)

**Human-gated steps** (connector approval, deployment approval):

- Do NOT auto-poll — these depend on a human action that may take minutes or hours
- Present the action needed (link, instructions) and ask the user to confirm when done
- When user confirms → verify status once
- If not yet complete → remind them what's needed

### Phase 3: Deployment

1. Tagging (optional)
2. Deployment strategy: self-deploy or AWS Transform deploy
3. Additional IaC format selection (CDK, Terraform, LZA)
4. Download artifacts

### Artifact Handling

The job generates several artifact types. Each has different download behavior:

| Artifact                                            | Location                                        | Download Behavior                                                                                                                                                                                              |
| --------------------------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Network diagram** (PNG, Mermaid)                  | Managed artifact store                          | **Always download automatically** — use `get_resource(resource="artifact", savePath=...)` to save to the user's Downloads directory (full absolute path). Never send the user to the web console for diagrams. |
| **IaC files** (CloudFormation, Terraform, CDK, LZA) | Connector S3 bucket (`code_generation/` prefix) | **Ask the user** — present the S3 console link, then ask if they want a local copy. If yes, run `aws s3 cp` recursively to a local directory (full absolute path).                                             |
| **Checksums**                                       | Inline in agent message (text)                  | **No download needed** — checksums are presented as text in the agent's response. Present them to the user as-is.                                                                                              |

**Diagram download (mandatory, via `aws-transform-mcp`):**

> Note: `get_resource` is an `aws-transform-mcp` wrapper tool — not the platform's native `create_artifact_download_url` + `download_artifact` flow. It accepts `savePath` (full file path), not `output_dir`.

```python
get_resource(resource="artifact", artifactId="<id>", savePath="/Users/<username>/Downloads/network_diagram.png")
```

**IaC download (user choice):**

```bash
aws s3 cp s3://<bucket>/<prefix>code_generation/ ~/Downloads/network-iac/ --recursive --region us-east-1
```

Extract the bucket name and prefix from the S3 link in the agent's response. Requires AWS CLI configured with access to the target account.

### Connector Setup

The VMware Migration Agent creates a HITL task requesting connector configuration. Two steps are needed:

**Step A: Create the connector** (via `aws-transform-mcp` server's `create_connector` tool):

> Note: `aws-transform-mcp` is a wrapper MCP server that provides a unified interface over the platform's customer-facing and agentic APIs. Tool names and parameters may differ from the underlying platform tools.

```python
create_connector(
  workspaceId="<workspace-id>",
  connectorName="network-migration-connector",
  connectorType="vmware_migration|infra_provisioning|2",  # Registered partner type in ConnectorTypeConfigurationProvider; not in base enum (S3|CODE_CONNECTION). Do not use arbitrary values.
  configuration={"encryptionKeyArn": "<kms-key-arn>"},  # MCP wrapper accepts encryptionKeyArn (rejects kmsKeyArn); maps to platform's KMS_KEY_ARN_KEY internally
  awsAccountId="<account-id>",
  targetRegions=["us-east-1"]
)
```

Resolve the KMS key ARN beforehand:

```bash
aws kms describe-key --key-id alias/aws/s3 --region us-east-1 --query 'KeyMetadata.Arn' --output text
```

After creation, the user must approve via the verification link returned in the response. This creates an IAM role with correct permissions. Once the user confirms approval, verify status via `get_resource(resource="connector")`.

**Prerequisites for approval:** The user must be logged into the target AWS account in their browser before opening the verification link. If not logged in, the console will redirect to a sign-in page.

**Connector approval is human-gated** — do NOT auto-poll. Instead:

1. Present the verification link to the user
2. Ask the user to confirm once they've approved
3. When user confirms → check status once via `get_resource(resource="connector")`
4. If `ACTIVE` → proceed. If still `PENDING` → remind them to approve. If `REJECTED` → report error.

**Step B: Complete the HITL task** (via `complete_task`):

- Submit the connector ID and `connectorType: "vmware_migration|infra_provisioning|2"` in the task payload

### File Upload

Upload the source file (NSX export, RVTools, etc.) via the `aws-transform-mcp` server's `upload_artifact` tool with the `planStepId` parameter. The `planStepId` ties the artifact to the correct plan step so the agent can find it.

**CRITICAL: The `planStepId` parameter is REQUIRED in the `upload_artifact` call. Without it, the file uploads but the agent cannot find it.**

**CRITICAL: Resolve ALL paths to absolute form BEFORE calling `upload_artifact`.** The tool does NOT expand `~` or shell variables. `~/file.zip` will fail silently — use `/Users/<username>/file.zip` instead.

> Note: `upload_artifact` is an `aws-transform-mcp` wrapper tool that combines the platform's 3-step flow (`create_artifact_upload_url` → `upload_artifact` → `complete_artifact_upload`) into a single call.

```python
upload_artifact(
  workspaceId="<workspace-id>",
  jobId="<job-id>",
  content="/Users/<username>/Downloads/<filename>.zip",  # MUST be absolute — no ~ or relative paths
  fileName="<filename>.zip",
  fileType="ZIP",
  categoryType="CUSTOMER_INPUT",
  planStepId="<upload-source-file-step-id>"  # REQUIRED — get from list_resources(resource="plan")
)
```

Get the `planStepId` from `list_resources(resource="plan")` — find the step for "Upload source file."

**Path resolution (all tools):** Always resolve `~` and relative paths to their full absolute form before passing to any MCP tool parameter (`content`, `savePath`, etc.). Tools do NOT expand `~` or shell variables — they treat paths as raw strings.
Example: `~/Downloads/file.zip` → `/Users/<username>/Downloads/file.zip`

⚠️ **Without `planStepId`**, the file uploads successfully but the agent cannot find it in "User Uploads." The `planStepId` is required for the mapping engine to access the file.

---

## Agents & Transforms

| Agent                                 | How to Discover                            | Purpose                                                 |
| ------------------------------------- | ------------------------------------------ | ------------------------------------------------------- |
| VMware Migration Agent (orchestrator) | `list_resources` with `resource: "agents"` | Orchestrates full workflow, invokes NMA sub-agent       |
| Network Migration Agent (NMA)         | _(sub-agent, not directly invocable)_      | File processing, mapping, modernization, IaC generation |
| MGN Backend                           | _(external service)_                       | Runs `StartNetworkMigrationMapping` and code generation |

**Discover the orchestrator agent dynamically** — do not hardcode agent names:

```python
list_resources(resource="agents")
# Find the VMware network migration orchestrator from results
```

**Selection criteria** when multiple VMware agents exist: choose the agent whose `description` mentions "network migration" or "infra provisioning." Prefer the highest version number if multiple matches exist. Ignore agents marked as deprecated in their description. Present the matched agent to the user for confirmation before creating a job.

### Job Creation

```python
create_job(
  workspaceId="<workspace-id>",
  jobName="Network Migration <timestamp>",
  objective="Migrate on-premises network to AWS",
  intent="Migrate on-premises network to AWS VPC",
  orchestratorAgent="<discovered>"
)
```

### Monitoring

```python
# Check for agent messages (primary signal)
list_resources(resource="messages", workspaceId="...", jobId="...")

# Check for HITL tasks
list_resources(resource="tasks", workspaceId="...", jobId="...")

# Check plan step status
list_resources(resource="plan", workspaceId="...", jobId="...")
```

---

## Decision Points

| Step            | Question to Ask User                                       | Options                                                         |
| --------------- | ---------------------------------------------------------- | --------------------------------------------------------------- |
| Topology        | "Do your workloads need cross-VPC communication?"          | Hub and Spoke / Isolated VPCs                                   |
| Security groups | "How should security groups be created?"                   | MAP (static IPs) / MAP_DHCP (dynamic IPs) / SKIP (manual setup) |
| Modernization   | "Would you like guided optimization or direct control?"    | Guided Modernization / Direct Edits / Skip                      |
| Naming          | "What naming convention do you use for cloud resources?"   | User provides pattern (e.g., `{env}-{workload}-{type}`) or skip |
| Deployment      | "Do you want AWS Transform to deploy, or deploy yourself?" | Let AWS Transform deploy / I'll deploy myself                   |
| IaC format      | "Which additional IaC format do you need?"                 | CDK Project / Terraform / LZA / None                            |

### Guided Modernization Recommendations

When user selects Guided Modernization, present each recommendation and ask:

- Rename VPCs → user provides new names or skips
- Right-sizing (resize CIDRs) → user approves or skips
- Security posture review → informational, user acknowledges
- Remove unused subnets → user approves or keeps

After all recommendations: "Apply all staged changes" → wait for IaC regeneration → "Done with network design"

---

## Hub and Spoke Architecture

When the user selects Hub and Spoke topology, the agent generates:

### Generated VPCs

| VPC                | Purpose                                                                                                                                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Spoke VPCs**     | One per detected source network segment. Connected to Transit Gateway.                                                                                                                                        |
| **Inspection VPC** | Routes all cross-VPC traffic through this VPC for inspection. User must deploy a firewall appliance (e.g., AWS Network Firewall) here post-migration. TGW attachment uses appliance mode (symmetric routing). |
| **Inbound VPC**    | Handles public internet → workload traffic (north-south inbound). Includes internet gateway + public subnets across AZs.                                                                                      |
| **Outbound VPC**   | Handles workload → public internet traffic (north-south outbound). Includes internet gateway + NAT gateways with elastic IPs per AZ.                                                                          |

### Transit Gateway Route Tables

| Route Table     | Associated With                       | Routes                                  | Purpose                                                               |
| --------------- | ------------------------------------- | --------------------------------------- | --------------------------------------------------------------------- |
| **Uninspected** | Spoke VPCs, Inbound VPC, Outbound VPC | `0.0.0.0/0` → Inspection VPC attachment | Default association table. Forces all traffic through inspection.     |
| **Inspected**   | Inspection VPC                        | Propagated routes from all spoke VPCs   | Default propagation table. Lets inspected traffic reach destinations. |

### Traffic Flow

1. Spoke VPC → Transit Gateway (default route `0.0.0.0/0`)
2. Uninspected route table → Inspection VPC
3. Inspection VPC forwards traffic back to Transit Gateway (firewall appliance inspects here if deployed)
4. Inspected route table → destination spoke VPC (via propagated routes)

Outbound internet: Inspected table routes to Outbound VPC → NAT gateway → internet gateway.
Inbound internet: Internet gateway → Inbound VPC → same inspection path → spoke VPC.

**Note:** Cross-VPC traffic routes through Inspection VPC but is not inspected until the user deploys a firewall appliance (e.g., AWS Network Firewall) there.

For multi-account deployments, Transit Gateway is shared across accounts via AWS Resource Access Manager (RAM).

---

## VPC and Subnet Operations

Operations available during the review and optimization phase (Guided Modernization or Direct Edits).

### VPC Operations

| Operation     | What It Does                       | Constraints                                                                                                                                                                                                                  |
| ------------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Rename**    | Change VPC name                    | —                                                                                                                                                                                                                            |
| **Resize**    | Change CIDR prefix length          | Must be /16–/28. Subnets must fit within new CIDR. SG rules matching old CIDR auto-update.                                                                                                                                   |
| **Change IP** | Change base IP, keep prefix length | Subnets shift by same offset. SG rules matching old CIDR auto-update.                                                                                                                                                        |
| **Merge**     | Combine two VPCs into one          | No subnet CIDR overlap. Merged result must be /16 or smaller (i.e., prefix ≥ /16). Same account (multi-account).                                                                                                             |
| **Split**     | Divide VPC into two                | Exactly two CIDRs, no overlap, each /16–/28. Every subnet must fit entirely within exactly one of the two new CIDRs (split is blocked if any subnet spans the boundary). SG rules NOT auto-updated (manual review required). |
| **Delete**    | Permanently remove                 | Cannot undo.                                                                                                                                                                                                                 |
| **Exclude**   | Temporarily remove from migration  | Can re-include later.                                                                                                                                                                                                        |
| **Include**   | Re-add excluded VPC                | —                                                                                                                                                                                                                            |

### Subnet Operations

| Operation     | What It Does                       | Constraints                                                                                  |
| ------------- | ---------------------------------- | -------------------------------------------------------------------------------------------- |
| **Resize**    | Change CIDR prefix length          | Must be /16–/28. No overlap with other subnets in same VPC. Must fit within parent VPC CIDR. |
| **Delete**    | Permanently remove                 | Cannot undo. Does not affect parent VPC.                                                     |
| **Change IP** | Change base IP, keep prefix length | —                                                                                            |

**Note:** After each operation (except Split), security group referencing is re-evaluated — CIDR-based rules may convert to SG references or vice versa. Split requires manual SG review since rules are not auto-updated.

**Appliance VPC restrictions:** For Inspection, Inbound, and Outbound VPCs in Hub and Spoke, only Change IP address is supported.

---

## Multi-Account Considerations

| Aspect                         | What to Know                                                                                                  |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| **Migration type selection**   | User chooses Single-account or Multi-account during target account setup. Present via user question.          |
| **Cross-account IAM roles**    | Must be configured before starting network migration. Agent handles setup guidance.                           |
| **AWS Organizations**          | Required for multi-account. LZA deployment requires same Organization as the AWS Transform account.           |
| **Transit Gateway sharing**    | In Hub and Spoke, TGW is shared across accounts via RAM. Agent configures this.                               |
| **VPC merge constraint**       | Both VPCs must be assigned to the same account. Present this constraint if user attempts cross-account merge. |
| **Security group referencing** | Cross-account ingress rules use SG references (Hub and Spoke). Cross-account egress uses CIDR-based rules.    |

---

## Deployment Approvals

When the user selects AWS Transform-managed deployment:

1. **Submission** — Confirm deployment intent, agent submits CloudFormation templates for review
2. **Routing** — Request routes automatically to authorized approvers via the AWS Transform Approvals tab
3. **Review** — Approvers validate CloudFormation templates and network configurations against security standards
4. **Decision** — Approver approves or denies:
   - **Approved** → deployment proceeds automatically
   - **Denied** → inform user, suggest contacting approver for required modifications
5. **Audit** — All approval decisions are tracked for audit purposes

**Behavior during approval:**

- After submission, inform user that deployment requires approval
- Inform user that approval is pending — when user confirms approval has been granted, check job status once
- If denied, present the denial to the user and offer to modify the network design and resubmit

**Rollback:** After deployment completes, resources can be deleted (requires separate approval). If resources were modified after deployment, automatic deletion is not available — user must delete manually via Console or CLI.

---

## Known Limitations

1. **File upload requires `planStepId`** — `upload_artifact` without `planStepId` uploads successfully but the agent can't find the file. Always include the plan step ID for the "Upload source file" step.
2. **Connector KMS validation** — `create_connector` accepts invalid KMS key ARNs without validation. Fails silently at mapping time.
3. **MCP requires `encryptionKeyArn`** — Cannot create connector without it, even though webapp doesn't require it.
4. **No artifact deletion** — Cannot delete or overwrite files in User Uploads via MCP.
5. **Connector role reuse** — Reusing a role from a deleted connector may have KMS permissions on the wrong key. Always use the verification link.
6. **Existing mapping definitions** — If a previous job created a mapping in the same workspace, agent asks "existing vs new configuration."

---

## Troubleshooting

| Symptom                                        | Likely Cause                                        | Resolution                                                                                              |
| ---------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Mapping fails silently after connector setup   | Invalid KMS key ARN passed to `create_connector`    | Resolve real ARN via `aws kms describe-key --key-id alias/aws/s3` and recreate connector                |
| Agent can't find uploaded source file          | `upload_artifact` called without `planStepId`       | Re-upload with `planStepId` from `list_resources(resource="plan")` — find the "Upload source file" step |
| Connector status stuck on PENDING              | User hasn't approved via verification link          | Present verification link again — approval creates IAM role with correct permissions                    |
| "Existing configuration found" prompt          | Previous job created a mapping in same workspace    | Ask user: reuse existing or start new configuration                                                     |
| Deployment fails with Organization ID mismatch | LZA deployment account not in same AWS Organization | Verify Organization membership or choose a different IaC format                                         |
| Reachability analysis shows no connectivity    | Security groups or route tables missing rules       | Review generated SGs and route tables; check Transit Gateway route table associations                   |
| Deployment approval denied                     | Approver rejected CloudFormation templates          | Contact approver for required modifications, update network design, resubmit                            |
| Connector creation fails with validation error | Wrong configuration key name                        | Use `encryptionKeyArn` (not `kmsKeyArn`) in the `configuration` parameter                               |
| Cannot replace uploaded file                   | MCP has no artifact deletion/overwrite              | Create a new job or upload with a different filename; existing uploads cannot be removed via MCP        |

---

## Example Requirements

```
## Requirement 1: Network Mapping

**User Story:** As a network engineer, I want my on-premises network configuration
translated to AWS VPC infrastructure so that workload connectivity is preserved after migration.
**Acceptance Criteria:**

1. WHEN mapping completes, EACH source network segment SHALL map to a distinct AWS VPC
2. WHEN mapping completes, source firewall rules SHALL be translated to AWS Security Groups
3. WHEN mapping completes, routing between segments SHALL be preserved via Transit Gateway or VPC route tables
   **Handled by:** AWS Transform VMware Migration Agent (NMA sub-agent)

## Requirement 2: Network Optimization

**User Story:** As a cloud architect, I want to review and optimize the generated network
before deployment so that it follows our naming conventions and right-sizing standards.
**Acceptance Criteria:**

1. WHEN optimization completes, ALL VPCs SHALL follow the organization's naming convention
2. WHEN optimization completes, VPC CIDRs SHALL be right-sized for actual subnet usage
3. WHEN optimization completes, unused subnets SHALL be removed with user approval
   **Handled by:** AWS Transform VMware Migration Agent (Guided Modernization) + IDE (presenting recommendations)

## Requirement 3: Network Deployment

**User Story:** As an infrastructure engineer, I want the approved network configuration
deployed to my AWS account so that VPCs are ready for VM migration.
**Acceptance Criteria:**

1. WHEN deployment completes, ALL VPCs, subnets, and security groups SHALL exist in the target account
2. WHEN reachability analysis runs, cross-VPC connectivity SHALL be confirmed
3. WHEN deployment completes, IaC templates SHALL be available for download in the selected format
   **Handled by:** AWS Transform VMware Migration Agent (CloudFormation deployment)
```

---

## Example Tasks

```
- [ ] 1. Target account setup (AWS Transform)
  - [ ] 1.1 Select migration type (single-account or multi-account)
  - [ ] 1.2 MAP agreement (if applicable)
  - [ ] 1.3 Configure connector (KMS key + verification link approval)
  - [ ] 1.4 Verify connector status = ACTIVE
- [ ] 2. Network mapping (AWS Transform)
  - [ ] 2.1 Upload source file (`upload_artifact` with `planStepId`)
  - [ ] 2.2 Select topology (Hub and Spoke or Isolated VPCs)
  - [ ] 2.3 Select security group strategy (MAP / MAP_DHCP / SKIP)
  - [ ] 2.4 Review configuration summary and confirm → mapping begins
  - [ ] 2.5 Wait for mapping to complete (2-5 min)
- [ ] 3. Network optimization
  - [ ] 3.1 Review generated VPCs and subnets
  - [ ] 3.2 Guided Modernization or Direct Edits
  - [ ] 3.3 Apply changes → IaC regeneration
  - [ ] 3.4 Confirm "Done with network design"
- [ ] 4. Deployment
  - [ ] 4.1 Configure custom tags
  - [ ] 4.2 Select deployment strategy (AWS Transform deploy or self-deploy)
  - [ ] 4.3 If self-deploy: select additional IaC format (CDK / Terraform / LZA)
  - [ ] 4.4 If AWS Transform deploy: wait for approval → deployment → reachability analysis
  - [ ] 4.5 Download artifacts
- [ ] 5. Validation
  - [ ] 5.1 Review reachability analysis results
  - [ ] 5.2 Verify network diagram matches expected topology
  - [ ] 5.3 Confirm VPCs ready for VM migration waves
```
