# VMware Network Migration

> **Last Updated:** 2026-09-16

## Table of Contents

- [Capabilities](#capabilities)
- [Workflow](#workflow)
- [Agents & Transforms](#agents--transforms)
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

Migrate on-premises network infrastructure to AWS. Translates source environment configuration into AWS-equivalent network resources, VPCs, subnets, security groups, NAT gateways, transit gateways, elastic IPs, routes, and route tables.

- Network segments → AWS VPCs + subnets
- Firewall rules → AWS Security Groups
- Routing → AWS Transit Gateway (Hub and Spoke) or VPC route tables (Isolated)
- IP migration: keep existing ranges or update to new CIDRs, static or DHCP assignment
- Review and modify generated network configuration before deployment
- VPC operations: rename, resize, merge, split, delete, exclude/include, change IP address
- Subnet operations: resize, delete, change IP address
- Security groups and their rules operations: create, configure, delete
- Security group referencing (within-VPC and cross-VPC/cross-account)
- Guided network recommendations (naming, right-sizing, consolidation, unused firewall rules, VPCs hosting multiple environments)
- Apply source security posture to VPCs already provisioned in AWS, instead of creating new VPCs (match source subnets to existing VPCs by CIDR, generate corresponding security groups)
- Creates network diagrams (PNG and Mermaid)
- Custom tags, MAP 2.0 tags, and automatic launch/replication tags
- Deploy the network using AWS CloudFormation with approval workflow
- Run reachability analysis on deployed VPCs
- Delete deployed network resources (rollback)
- Generates CloudFormation, CDK (TypeScript), Terraform, or Landing Zone Accelerator IaC

### Supported Source Formats

| Format                                            | Produces                                                                                                                  |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| VMware NSX export (.zip)                          | VPCs + subnets + security groups                                                                                          |
| Cisco ACI                                         | VPCs + subnets + security groups                                                                                          |
| Palo Alto Networks                                | VPCs + subnets + security groups                                                                                          |
| Fortinet FortiGate                                | VPCs + subnets + security groups                                                                                          |
| RVTools (.xlsx/.zip)                              | VPCs + subnets only (no security groups)                                                                                  |
| modelizeIT                                        | VPCs + subnets + security groups (hybrid environments)                                                                    |
| AWS Transform discovery tool (CSV + JSON in .zip) | VPCs + subnets + security groups (hybrid VMware + non-VMware; also provides observed traffic data for stale-rule removal) |
| Any config file (e.g. Checkpoint, F5)             | VPCs + subnets + security groups (auto-converted; conversion can take up to ~2 hours for large or complex files)          |

> **Max source network file size:** 70 MB.

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

The network migration workflow runs across three phases: Target Account Setup, Network Migration, and Deployment. The phases execute sequentially without gaps, and each phase's numbering restarts at 1. Phase 2 has two separate workflows depending on the network approach you select at the start. New Network (Map source network to new VPCs) and Existing Network (Apply security posture to existing VPCs) differ in their steps, so the total step count varies.

### Phase 1: Target Account Setup

1. Select "Network Migration" workflow
2. Confirm plan → "Proceed"
3. Select migration type: Single-account or Multi-account
4. MAP agreement (optional)
5. Configure connector (HITL task), must include `connectorType` in payload (read the version from the task's `agentArtifactContent`; do not hardcode)

### Phase 2: Network Migration

At the start of Phase 2, select the network approach. This determines which of the two workflows below runs.

- **Map source network to new VPCs** (New Network): build a complete target network (VPCs, subnets, security groups, connectivity). Choose when provisioning the AWS network as part of the migration.
- **Apply security posture to existing VPCs** (Existing Network): apply source security groups and rules to VPCs already provisioned in AWS. The rest of the network is left untouched. Choose when target VPCs and subnets already exist and only security posture needs to come over.

#### New Network: Map Source Network to New VPCs

1. Upload source file (NSX export, RVTools, etc.), requires `planStepId` in `upload_artifact`
2. (RVTools only, optional) Upload additional firewall/SDN config file to enable security group generation
3. Select topology: Hub and Spoke or Isolated VPCs
4. Select security group strategy: MAP, MAP_DHCP, or SKIP
5. Agent presents configuration summary. This is NOT the mapping step.
6. User confirms → mapping actually begins (2-5 min)
7. Guided Modernization or Direct Edits
8. Apply changes → IaC regeneration
9. Done with network design
10. Network diagram generation (image + Mermaid)

#### Existing Network: Apply Security Posture to Existing VPCs

Generates security groups from source firewall rules and associates them with VPCs you already provisioned. Nothing else in the account is modified.

1. Upload source network file. Must contain firewall rules. **RVTools NOT supported** (no rules). See file types below.
2. Tag existing VPCs to scope them in. Only tagged VPCs are in scope. Tell the agent once tagged.
3. Match source subnets to existing VPCs by CIDR. See CIDR matching below.
4. Specify VPC topology: Isolated or Connected. See topology below.
5. Agent runs mapping, then HITL review of generated SGs (read-only; existing VPCs not modified).

Deployment for Existing Network is handled by Phase 3, the same as New Network; there is no separate deployment sequence within Existing Network.

**Note:** After cutover, remove the `[ONPREM]`-prefixed rules once the workload no longer needs source-network connectivity.

**Supported file types:** VMware NSX, Cisco ACI, Palo Alto, Fortinet FortiGate, modelizeIT, AWS Transform discovery tool, or any other config file that auto-converts to firewall rules (e.g. Checkpoint, F5). RVTools is not supported (no firewall rules).

**Tagging:** Agent applies `CreatedFor=AWSTransform` and `ATWorkspace=<workspace-id>`. Multi-account: tag VPCs in each target account separately.

**CIDR matching:** Lift-and-shift keeps IPs (VPC CIDRs must match on-prem subnets; auto-covered). Re-IP needs a CIDR mapping (e.g. `10.68.0.0/16`→`172.31.0.0/16`); prefer wider mappings, same prefix length both sides. Unmapped subnets are NOT migrated. Mappings also apply to rule CIDRs: each affected rule is duplicated, one copy prefixed `[ONPREM]` (source space), one for the target space.

**Topology:** Isolated → SG rules use CIDR ranges. Connected → SG rules use SG referencing (needs real connectivity; for TGW, enable `SecurityGroupReferencingSupport` on the TGW and each attachment).

**Differs from New Network:** no network diagram, no Reachability Analyzer, no rollback (creates security groups only).

### Confirmation Before Mapping (New Network)

This applies to New Network (new VPCs). After the user selects topology and security group strategy, the agent presents a configuration summary and asks for confirmation before starting the actual network mapping. Do NOT tell the user that mapping has started until the user confirms and the agent explicitly begins the mapping process.

The sequence is:

1. Select topology → agent acknowledges
2. Select security group strategy → agent presents **configuration summary** with all selections
3. User confirms "Yes, start network mapping" → mapping actually begins (2-5 min)

The summary step is NOT the mapping step. Do not conflate them.

### Polling and Waiting

Network-specific polling cadence: every 30 seconds for machine-gated steps (mapping, job processing, agent responses). Poll silently without asking the user for permission each time, and surface only completion, errors, or useful progress. Never auto-poll a human-gated step such as connector or deployment approval: present the required action, ask the user to confirm when it is done, then check once. For polling priority (messages, tasks, worklogs), see [vmware](vmware.md) → Agent Interaction Rules.

### Phase 3: Deployment

Phase 3 applies to both New Network and Existing Network. New Network deploys network IaC and security IaC; Existing Network deploys security IaC only.

1. Tagging (optional)
2. Deployment strategy: self-deploy or AWS Transform deploy
3. Additional IaC format selection (CDK, Terraform, LZA)
4. Download artifacts

### Artifact Handling

The job generates several artifact types. Each has different download behavior:

| Artifact                              | Location                                                    | Workflow         | Download Behavior                                                                                                                                                             |
| ------------------------------------- | ----------------------------------------------------------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Network diagram** (PNG, Mermaid)    | Managed artifact store                                      | New Network only | **Always download automatically** via `get_resource(resource="artifact", savePath=...)` to the user's Downloads (full absolute path). Never send the user to the web console. |
| **Network IaC** (`network_segments/`) | S3 bucket, `network_segments/` within each format directory | New Network only | **Ask the user.** Part of the IaC bundle. Existing Network does not generate network IaC (it creates security groups only).                                                   |
| **Security IaC** (`security/`)        | S3 bucket, `security/` within each format directory         | Both             | **Ask the user.** Part of the IaC bundle. This is the only IaC Existing Network produces.                                                                                     |
| **Checksums**                         | Inline in agent message (text)                              | Both             | **No download needed.** To verify a downloaded file: `openssl dgst -sha256 -binary <file.zip> \| base64` and compare to the provided checksum.                                |

Network and security are separate outputs. New Network (new VPCs) generates both `network_segments/` and `security/`; Existing Network (existing VPCs) generates `security/` only. Both live in the same S3 bucket in the connector's account/Region (name starts with `transform-vmware-target-`); CDK + CloudFormation are always written, Terraform/LZA if selected, plus a `README.md`.

**Diagram download (via `aws-transform-mcp`):**

> Note: `get_resource` is an `aws-transform-mcp` wrapper tool, not the platform's native `create_artifact_download_url` + `download_artifact` flow. It accepts `savePath` (full file path), not `output_dir`.

```python
get_resource(resource="artifact", artifactId="<id>", savePath="/Users/<username>/Downloads/network_diagram.png")
```

**IaC download (user choice):**

```bash
aws s3 cp s3://transform-vmware-target-<...>/<prefix>code_generation/ ~/Downloads/network-iac/ --recursive --region <connector-region>
```

Extract the exact bucket name, job-specific prefix, and Region from the S3 link in the agent's response. Preserve the prefix before `code_generation/`; copying from the bucket root can mix outputs from different jobs. Requires AWS CLI configured with access to the target account.

**Deploy order (important):** Deploy `network_segments/` before `security/`. Security definitions reference network exports and parameters that must exist first. For CDK, CDK L2, and Terraform, run `validate-references.py` before deploying a segment to confirm the referenced network identifiers exist (needs AWS CLI with target-account credentials).

**Output layout:** Each format has its own directory (`cfn/`, `cdk/`, `cdk_l2/`, `terraform/`, `lza/`). Within each, `network_segments/` holds network definitions and `security/` holds security group definitions. New Network populates both; Existing Network populates `security/` only. Cross-VPC rules deploy last from a `<segment>_security_dependencies/` directory.

**Multi-account:** Adds a per-format manifest at the output root (`manifest-*.json`); single-account has none. Account assignment lives in data fields (`segments[].targetAccount` in the manifest and in `security-interface.json`), not the folder structure.

### Connector Setup

The VMware Migration Agent creates a HITL task requesting connector configuration. Two steps are needed:

**Step A: Create the connector** (via `aws-transform-mcp` server's `create_connector` tool):

> Note: `aws-transform-mcp` is a wrapper MCP server that provides a unified interface over the platform's customer-facing and agentic APIs. Tool names and parameters may differ from the underlying platform tools.

```python
create_connector(
  workspaceId="<workspace-id>",
  connectorName="network-migration-connector",
  connectorType="vmware_migration|infra_provisioning|<version>",  # Version is NOT fixed. Read the required version from the HITL task's `agentArtifactContent`; do not hardcode. Observed values have included 2 and 4. Registered partner type in ConnectorTypeConfigurationProvider; not in base enum (S3|CODE_CONNECTION).
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

**Connector approval is human-gated**: do NOT auto-poll. Instead:

1. Present the verification link to the user
2. Ask the user to confirm once they've approved
3. When user confirms → check status once via `get_resource(resource="connector")`
4. If `ACTIVE` → proceed. If still `PENDING` → remind them to approve. If `REJECTED` → report error.

**Step B: Complete the HITL task** (via `complete_task`):

- Submit the connector ID and `connectorType: "vmware_migration|infra_provisioning|<version>"` in the task payload. Read `<version>` from the task's `agentArtifactContent`; do not hardcode (observed values have included 2 and 4).

### File Upload

Upload the source file (NSX export, RVTools, etc.) via the `aws-transform-mcp` server's `upload_artifact` tool with the `planStepId` parameter. The `planStepId` ties the artifact to the correct plan step so the agent can find it.

**CRITICAL: The `planStepId` parameter is REQUIRED in the `upload_artifact` call. Without it, the file uploads but the agent cannot find it.**

**CRITICAL: Resolve ALL paths to absolute form BEFORE calling `upload_artifact`.** The tool does NOT expand `~` or shell variables. `~/file.zip` will fail silently, use `/Users/<username>/file.zip` instead.

> Note: `upload_artifact` is an `aws-transform-mcp` wrapper tool that combines the platform's 3-step flow (`create_artifact_upload_url` → `upload_artifact` → `complete_artifact_upload`) into a single call.

```python
upload_artifact(
  workspaceId="<workspace-id>",
  jobId="<job-id>",
  content="/Users/<username>/Downloads/<filename>.zip",  # MUST be absolute, no ~ or relative paths
  fileName="<filename>.zip",
  fileType="ZIP",
  categoryType="CUSTOMER_INPUT",
  planStepId="<upload-source-file-step-id>"  # REQUIRED, get from list_resources(resource="plan")
)
```

Get the `planStepId` from `list_resources(resource="plan")`, find the step for "Upload source file."

**Path resolution (all tools):** Always resolve `~` and relative paths to their full absolute form before passing to any MCP tool parameter (`content`, `savePath`, etc.). Tools do NOT expand `~` or shell variables, they treat paths as raw strings.
Example: `~/Downloads/file.zip` → `/Users/<username>/Downloads/file.zip`

⚠️ **Without `planStepId`**, the file uploads successfully but the agent cannot find it in "User Uploads." The `planStepId` is required for the mapping engine to access the file.

---

## Agents & Transforms

| Agent                                 | How to Discover                            | Purpose                                                 |
| ------------------------------------- | ------------------------------------------ | ------------------------------------------------------- |
| VMware Migration Agent (orchestrator) | `list_resources` with `resource: "agents"` | Orchestrates full workflow, invokes NMA sub-agent       |
| Network Migration Agent (NMA)         | _(sub-agent, invoked by orchestrator)_     | File processing, mapping, modernization, IaC generation |
| MGN Backend                           | _(external service)_                       | Runs `StartNetworkMigrationMapping` and code generation |

**Discover the orchestrator agent dynamically**: do not hardcode agent names:

```python
list_resources(resource="agents")
# Find the VMware network migration orchestrator from results
```

**Selection criteria** when multiple VMware agents exist: choose the agent whose `description` mentions "network migration" or "infra provisioning." Prefer the highest version number if multiple matches exist. Ignore agents marked as deprecated in their description. Present the matched agent to the user for confirmation before creating a job.

### Job Creation

**Discover the agent dynamically:**

```python
list_resources(resource="agents")
# Find the VMware network migration orchestrator from results
# Then create job with discovered orchestratorAgent
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

| Step                        | Question to Ask User                                                                                         | Options                                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| Network approach            | "Are you provisioning a new AWS network, or applying your source security posture to VPCs you already have?" | Map source network to new VPCs (New Network) / Apply security posture to existing VPCs (Existing Network) |
| Topology (New Network)      | "Do your workloads need cross-VPC communication?"                                                            | Hub and Spoke / Isolated VPCs                                                                             |
| Topology (Existing Network) | "Are your existing VPCs isolated, or connected (TGW, peering)?"                                              | Isolated (SG rules use CIDRs) / Connected (SG rules use SG referencing)                                   |
| Security groups             | "How should security groups be created?"                                                                     | MAP (static IPs) / MAP_DHCP (dynamic IPs) / SKIP (manual setup)                                           |
| Modernization               | "Would you like guided optimization or direct control?"                                                      | Guided Modernization / Direct Edits / Skip                                                                |
| Multi-environment VPC       | "This VPC hosts multiple environments (e.g. dev and prod). Split to isolate them?"                           | Split VPC (see Split operation) / Keep as-is                                                              |
| Naming                      | "What naming convention do you use for cloud resources?"                                                     | User provides pattern (e.g., `{env}-{workload}-{type}`) or skip                                           |
| Deployment                  | "Do you want AWS Transform to deploy, or deploy yourself?"                                                   | Let AWS Transform deploy / I'll deploy myself                                                             |
| IaC format                  | "Which additional IaC format do you need?"                                                                   | CDK Project / Terraform / LZA / None                                                                      |

**Note:** The question text above is descriptive, not a script. The agent presents its own interactive message with its own exact option labels. Always read those labels from the agent's actual message and relay the option the user picked verbatim, rather than paraphrasing from this table. The backend matches against the interaction's literal option value, so a paraphrase that doesn't match can be misinterpreted.

### Guided Modernization Recommendations

When user selects Guided Modernization, present each recommendation and ask:

- Rename VPCs → user provides new names or skips
- Right-sizing (resize CIDRs) → user approves or skips
- Security posture review → informational, user acknowledges
- Remove unused subnets → user approves or keeps
- Remove unused inbound rules → agent identifies unused ingress rules migrated from source and recommends removal; user approves or keeps. Limited to unused ingress rules (egress is not removed).
- Review broad inbound access → agent flags inbound rules that look broader than typical (e.g. `0.0.0.0/0`) and asks whether the broad access is intentional; it does not assert the rule is wrong. The agent cannot know the original on-premises intent, so the customer decides. If unintentional, agent asks what the intended access should be.
- Split multi-environment VPC → agent flags a VPC hosting applications from multiple environments (e.g. dev and prod) and, when they can be cleanly separated, recommends splitting to isolate them; user approves or skips. Uses the Split operation (see VPC and Subnet Operations); Split constraints apply and SG rules are not auto-updated on split.

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
| **Rename**    | Change VPC name                    | None                                                                                                                                                                                                                         |
| **Resize**    | Change CIDR prefix length          | Must be /16–/28. Subnets must fit within new CIDR. SG rules matching old CIDR auto-update.                                                                                                                                   |
| **Change IP** | Change base IP, keep prefix length | Subnets shift by same offset. SG rules matching old CIDR auto-update.                                                                                                                                                        |
| **Merge**     | Combine two VPCs into one          | No subnet CIDR overlap. Merged result must be /16 or smaller (i.e., prefix ≥ /16). Same account (multi-account).                                                                                                             |
| **Split**     | Divide VPC into two                | Exactly two CIDRs, no overlap, each /16–/28. Every subnet must fit entirely within exactly one of the two new CIDRs (split is blocked if any subnet spans the boundary). SG rules NOT auto-updated (manual review required). |
| **Delete**    | Permanently remove                 | Cannot undo.                                                                                                                                                                                                                 |
| **Exclude**   | Temporarily remove from migration  | Can re-include later.                                                                                                                                                                                                        |
| **Include**   | Re-add excluded VPC                | None                                                                                                                                                                                                                         |

### Subnet Operations

| Operation     | What It Does                       | Constraints                                                                                  |
| ------------- | ---------------------------------- | -------------------------------------------------------------------------------------------- |
| **Resize**    | Change CIDR prefix length          | Must be /16–/28. No overlap with other subnets in same VPC. Must fit within parent VPC CIDR. |
| **Delete**    | Permanently remove                 | Cannot undo. Does not affect parent VPC.                                                     |
| **Change IP** | Change base IP, keep prefix length | None                                                                                         |

**Note:** After each operation (except Split), security group referencing is re-evaluated, CIDR-based rules may convert to SG references or vice versa. Split requires manual SG review since rules are not auto-updated.

**Appliance VPC restrictions:** For Inspection, Inbound, and Outbound VPCs in Hub and Spoke, only Change IP address is supported.

---

## Multi-Account Considerations

| Aspect                         | What to Know                                                                                                  |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| **Migration type selection**   | User chooses Single-account or Multi-account during target account setup. Present via a user question.        |
| **Cross-account IAM roles**    | Must be configured before starting network migration. Agent handles setup guidance.                           |
| **AWS Organizations**          | Required for multi-account. LZA deployment requires same Organization as the AWS Transform account.           |
| **Transit Gateway sharing**    | In Hub and Spoke, TGW is shared across accounts via RAM. Agent configures this.                               |
| **VPC merge constraint**       | Both VPCs must be assigned to the same account. Present this constraint if user attempts cross-account merge. |
| **Security group referencing** | Cross-account ingress rules use SG references (Hub and Spoke). Cross-account egress uses CIDR-based rules.    |

---

## Deployment Approvals

When the user selects AWS Transform-managed deployment:

1. **Submission**: Confirms deployment intent, agent submits CloudFormation templates for review
2. **Routing**: Request routes automatically to authorized approvers via the AWS Transform Approvals tab
3. **Review**: Approvers validate CloudFormation templates and network configurations against security standards
4. **Decision**: Approver approves or denies:
   - **Approved** → deployment proceeds automatically
   - **Denied** → inform user, suggest contacting approver for required modifications
5. **Audit**: All approval decisions are tracked for audit purposes

**Behavior during approval:**

- After submission, inform user that deployment requires approval
- Inform user that approval is pending, when user confirms approval has been granted, check job status once
- If denied, present the denial to the user and offer to modify the network design and resubmit

**Rollback:** After deployment completes, resources can be deleted (requires separate approval). If resources were modified after deployment, automatic deletion is not available, user must delete manually via Console or CLI.

---

## Known Limitations

1. **File upload requires `planStepId`**: `upload_artifact` without `planStepId` uploads successfully but the agent can't find the file. Always include the plan step ID for the "Upload source file" step.
2. **Connector KMS validation**: `create_connector` accepts invalid KMS key ARNs without validation. Fails silently at mapping time.
3. **MCP requires `encryptionKeyArn`**: Cannot create connector without it, even though webapp doesn't require it.
4. **No artifact deletion**: Cannot delete or overwrite files in User Uploads via MCP.
5. **Connector role reuse**: Reusing a role from a deleted connector may have KMS permissions on the wrong key. Always use the verification link.
6. **Existing mapping definitions**: If a previous job created a mapping in the same workspace, agent asks "existing vs new configuration."
7. **Existing Network needs firewall rules.** Apply-security-posture requires a source file containing firewall rules. RVTools alone is not accepted (no rules).
8. **Existing Network posture matching is CIDR-based.** Source subnets match existing VPCs by CIDR. Uncovered subnets left unmapped are not migrated; provide a CIDR mapping (equal prefix length on both sides) to cover them.
9. **Connected topology needs real connectivity.** Selecting Connected when VPCs are not actually connected fails deployment: cross-VPC SG references cannot resolve. For TGW, `SecurityGroupReferencingSupport` must be enabled on the TGW and each attachment.
10. **`[ONPREM]` rules persist until cutover.** Re-IP mappings duplicate each rule (one `[ONPREM]` copy for source space, one for target). These remain until manually removed after cutover; there is no automatic cleanup.
11. **`connectorType` version is not fixed.** The version suffix in `vmware_migration|infra_provisioning|<version>` changes between releases (observed 2 and 4). Read the required version from the HITL task's `agentArtifactContent`; a hardcoded value can silently mismatch and fail connector setup.
12. **`create_connector` intermittently fails for the caller's own identity.** Observed pattern: the call fails via MCP for the calling user's own account/identity, yet the same connector succeeds when created via the web app, or on a later MCP retry. Non-deterministic.
13. **Network migration definition quota per account/Region.** The Service Quota "Max network migration definitions per account per Region" (under **Application Migration**) caps how many network migration definitions an account can hold in a Region. On accounts that have run many prior network migration jobs, it can be exhausted and block **configuration creation** (the step after topology + security group strategy selection). This is an AWS account-level limit, NOT an MCP or agent bug, so do NOT retry around it. Remediation: request a quota increase for "Max network migration definitions per account per Region" (Application Migration) in the affected Region, delete an unused network migration definition, or switch the target account or Region.
14. **One VMware Infra connector per target account (deterministic, non-retryable).** The Connector Control Plane enforces `TARGET_ACCOUNT_CROSS_USER_WORKSPACE_CONNECTORS_LIMIT_BREACHED` — a cross-user limit of **one** VMware Infra connector per target account, applying to the whole `vmware_migration|infra_provisioning|<version>` family (v1/v2/v4). When a connector already exists for the target account, `create_connector` fails **deterministically** — not intermittently — until the existing connector is deleted. This is distinct from #12: if the target account already has a VMware Infra connector, retrying will keep failing. Remediation: reuse the existing connector (`list_resources(resource="connectors")` to find it), or delete it before creating a new one. Do NOT retry blindly.

---

## Troubleshooting

| Symptom                                                                                                                                         | Likely Cause                                                                                                                                                    | Resolution                                                                                                                                                              |
| ----------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mapping fails silently after connector setup                                                                                                    | Invalid KMS key ARN passed to `create_connector`                                                                                                                | Resolve real ARN via `aws kms describe-key --key-id alias/aws/s3` and recreate connector                                                                                |
| Agent can't find uploaded source file                                                                                                           | `upload_artifact` called without `planStepId`                                                                                                                   | Re-upload with `planStepId` from `list_resources(resource="plan")`, find the "Upload source file" step                                                                  |
| Connector status stuck on PENDING                                                                                                               | User hasn't approved via verification link                                                                                                                      | Present verification link again, approval creates IAM role with correct permissions                                                                                     |
| "Existing configuration found" prompt                                                                                                           | Previous job created a mapping in same workspace                                                                                                                | Ask user: reuse existing or start new configuration                                                                                                                     |
| Deployment fails with Organization ID mismatch                                                                                                  | LZA deployment account not in same AWS Organization                                                                                                             | Verify Organization membership or choose a different IaC format                                                                                                         |
| Reachability analysis shows no connectivity                                                                                                     | Security groups or route tables missing rules                                                                                                                   | Review generated SGs and route tables; check Transit Gateway route table associations                                                                                   |
| Deployment approval denied                                                                                                                      | Approver rejected CloudFormation templates                                                                                                                      | Contact approver for required modifications, update network design, resubmit                                                                                            |
| Connector creation fails with validation error                                                                                                  | Wrong configuration key name                                                                                                                                    | Use `encryptionKeyArn` (not `kmsKeyArn`) in the `configuration` parameter                                                                                               |
| Cannot replace uploaded file                                                                                                                    | MCP has no artifact deletion/overwrite                                                                                                                          | Create a new job or upload with a different filename; existing uploads cannot be removed via MCP                                                                        |
| Existing Network rejects the source file                                                                                                        | RVTools uploaded (no firewall rules)                                                                                                                            | Upload a source file with firewall rules (NSX, Cisco ACI, Palo Alto, FortiGate, modelizeIT, discovery tool, or any auto-converted config file such as Checkpoint or F5) |
| Existing VPC gets no security groups                                                                                                            | Source subnet CIDR does not match any tagged VPC                                                                                                                | Confirm the VPC is tagged in scope; provide a CIDR mapping (equal prefix length) for the uncovered subnet                                                               |
| Cross-VPC referencing rules fail to deploy (Existing Network)                                                                                   | Connected topology selected but VPCs lack connectivity, or TGW referencing not enabled                                                                          | Verify actual connectivity; enable `SecurityGroupReferencingSupport` on the TGW and each attachment, or select Isolated                                                 |
| Duplicate `[ONPREM]` rules remain after cutover                                                                                                 | Re-IP mapping duplicated rules; no automatic cleanup                                                                                                            | Remove the `[ONPREM]`-prefixed rules once the workload no longer needs source-network connectivity                                                                      |
| HITL connector task fails or connector setup mismatches                                                                                         | Hardcoded `connectorType` version no longer matches the required version (e.g. `2` vs `4`)                                                                      | Read the version from the task's `agentArtifactContent` and submit `vmware_migration\|infra_provisioning\|<version>` with that value                                    |
| `create_connector` fails, target account already has a VMware Infra connector (`TARGET_ACCOUNT_CROSS_USER_WORKSPACE_CONNECTORS_LIMIT_BREACHED`) | Deterministic per-account limit of one VMware Infra connector (`vmware_migration\|infra_provisioning\|<version>`, family v1/v2/v4). Retrying will keep failing. | Reuse the existing connector (`list_resources(resource="connectors")`), or delete it before creating a new one. Do NOT retry blindly.                                   |
| `create_connector` fails for the caller's own identity (no existing connector)                                                                  | Intermittent MCP-side failure for the calling user's own account                                                                                                | Retry the MCP call, or create the connector via the web app; both are known to succeed where the first MCP attempt failed                                               |
| Configuration creation fails after topology + SG strategy selection                                                                             | "Max network migration definitions per account per Region" quota (Application Migration) exhausted. Account-level limit, not an MCP/agent bug.                  | Do NOT retry. Request a quota increase for that quota in the Region, delete an unused network migration definition, or switch target account/Region.                    |

---

## Example Requirements

### New Network: Map Source Network to New VPCs

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
**Handled by:** AWS Transform VMware Migration Agent (Guided Modernization) and the IDE (presenting recommendations)

## Requirement 3: Network Deployment
**User Story:** As an infrastructure engineer, I want the approved network configuration
deployed to my AWS account so that VPCs are ready for VM migration.
**Acceptance Criteria:**
1. WHEN deployment completes, ALL VPCs, subnets, and security groups SHALL exist in the target account
2. WHEN reachability analysis runs, cross-VPC connectivity SHALL be confirmed
3. WHEN deployment completes, IaC templates SHALL be available for download in the selected format
**Handled by:** AWS Transform VMware Migration Agent (CloudFormation deployment)
```

### Existing Network: Apply Security Posture to Existing VPCs

```
## Requirement 1: Security Posture Mapping
**User Story:** As a network engineer, I want my on-premises firewall rules applied to VPCs I already
provisioned in AWS so that existing workloads inherit the source security posture without rebuilding the network.
**Acceptance Criteria:**
1. WHEN mapping runs, ONLY VPCs tagged in scope SHALL receive generated security groups
2. WHEN a source subnet CIDR has no matching tagged VPC and no CIDR mapping is provided, THAT subnet SHALL be excluded from migration and reported to the user
3. WHEN mapping completes, existing VPC, subnet, and route table configuration SHALL remain unmodified
**Handled by:** AWS Transform VMware Migration Agent (NMA sub-agent)

## Requirement 2: Security Group Review
**User Story:** As a security engineer, I want to review generated security groups before deployment
so that I can catch overly broad rules or unintended access before they reach existing workloads.
**Acceptance Criteria:**
1. WHEN HITL review starts, ALL generated security groups SHALL be presented read-only for approval
2. WHEN a rule appears broader than typical (e.g. `0.0.0.0/0`), the agent SHALL flag it and ask the user to confirm intent rather than asserting it is wrong
3. WHEN the user approves, the generated security groups SHALL be finalized for deployment
**Handled by:** AWS Transform VMware Migration Agent (Guided Modernization) and the IDE (presenting recommendations)

## Requirement 3: Security Group Deployment
**User Story:** As an infrastructure engineer, I want the approved security groups deployed to my existing
AWS account so that on-premises firewall posture is enforced without modifying existing network resources.
**Acceptance Criteria:**
1. WHEN deployment completes, ALL generated security groups SHALL exist in the target account and be associated with the correct tagged VPCs
2. WHEN Connected topology is used, cross-VPC security group references SHALL resolve successfully
3. WHEN cutover completes, the user SHALL be reminded to remove `[ONPREM]`-prefixed rules once source-network connectivity is no longer required
**Handled by:** AWS Transform VMware Migration Agent (CloudFormation deployment)
```

---

## Example Tasks

### New Network: Map Source Network to New VPCs

```
- [ ] 1. Target account setup (AWS Transform)
  - [ ] 1.1 Select migration type (single-account or multi-account)
  - [ ] 1.2 MAP agreement (if applicable)
  - [ ] 1.3 Configure connector (KMS key and verification link approval)
  - [ ] 1.4 Verify connector status = ACTIVE
- [ ] 2. Network mapping (AWS Transform)
  - [ ] 2.1 Select network approach: map source network to new VPCs
  - [ ] 2.2 Upload source file (`upload_artifact` with `planStepId`)
  - [ ] 2.3 Select topology (Hub and Spoke or Isolated VPCs)
  - [ ] 2.4 Select security group strategy (MAP, MAP_DHCP, or SKIP)
  - [ ] 2.5 Review configuration summary and confirm to start mapping
  - [ ] 2.6 Wait for mapping to complete (2-5 min)
- [ ] 3. Network optimization
  - [ ] 3.1 Review generated VPCs and subnets
  - [ ] 3.2 Guided Modernization or Direct Edits
  - [ ] 3.3 Apply changes and regenerate IaC
  - [ ] 3.4 Confirm "Done with network design"
- [ ] 4. Deployment
  - [ ] 4.1 Configure custom tags
  - [ ] 4.2 Select deployment strategy (AWS Transform deploy or self-deploy)
  - [ ] 4.3 If self-deploy: select additional IaC format (CDK, Terraform, or LZA)
  - [ ] 4.4 If AWS Transform deploy: wait for approval, then deployment, then reachability analysis
  - [ ] 4.5 Download artifacts (network diagram always; IaC on request)
- [ ] 5. Validation
  - [ ] 5.1 Review reachability analysis results
  - [ ] 5.2 Verify network diagram matches expected topology
  - [ ] 5.3 Confirm VPCs ready for VM migration waves
```

### Existing Network: Apply Security Posture to Existing VPCs

```
- [ ] 1. Target account setup (AWS Transform)
  - [ ] 1.1 Select migration type (single-account or multi-account)
  - [ ] 1.2 MAP agreement (if applicable)
  - [ ] 1.3 Configure connector (KMS key and verification link approval)
  - [ ] 1.4 Verify connector status = ACTIVE
- [ ] 2. Security posture mapping (AWS Transform)
  - [ ] 2.1 Select network approach: apply security posture to existing VPCs
  - [ ] 2.2 Upload source network file containing firewall rules (RVTools not supported)
  - [ ] 2.3 Tag existing VPCs to scope them in
  - [ ] 2.4 Confirm CIDR matches; provide a CIDR mapping for any uncovered subnets
  - [ ] 2.5 Specify VPC topology (Isolated or Connected)
  - [ ] 2.6 Wait for mapping to complete
- [ ] 3. Security group review
  - [ ] 3.1 Review generated security groups (read-only, existing VPCs unmodified)
  - [ ] 3.2 Confirm intent on any flagged broad-access rules
  - [ ] 3.3 Approve generated security groups
- [ ] 4. Deployment
  - [ ] 4.1 Configure custom tags
  - [ ] 4.2 Select deployment strategy (AWS Transform deploy or self-deploy)
  - [ ] 4.3 If self-deploy: select additional IaC format (CDK, Terraform, or LZA)
  - [ ] 4.4 If AWS Transform deploy: wait for approval, then deployment
  - [ ] 4.5 Download security IaC artifacts
- [ ] 5. Cutover and cleanup
  - [ ] 5.1 Confirm existing workloads function correctly with new security groups
  - [ ] 5.2 After cutover, remove `[ONPREM]`-prefixed rules once source-network connectivity is no longer needed
```
