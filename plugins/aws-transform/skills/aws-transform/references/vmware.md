# VMware Migration

> **Last Updated:** 2026-05-10

## Table of Contents

- [Capabilities](#capabilities)
- [Job Types](#job-types)
- [Starting Workflow](#starting-workflow)
- [Agents and Transforms](#agents--transforms)
- [Decision Points](#decision-points)
- [Example Requirements](#example-requirements)
- [Example Tasks](#example-tasks)
- [Known Limitations](#known-limitations)

## Capabilities

Migrate VMware environments to AWS using generative AI-driven planning and execution. AWS Transform orchestrates the full migration lifecycle — discovery, migration planning, landing zone setup, network migration, and server rehosting to EC2. Supports Windows and Linux servers on supported operating systems (see [MGN supported OS list](https://docs.aws.amazon.com/mgn/latest/ug/Supported-Operating-Systems.html)).

- VMware VMs → Amazon EC2 instances (rehost/lift-and-shift via MGN)
- AI-driven conversion of VMware network configuration → AWS VPC architecture (VPCs, subnets, security groups, Transit Gateway)
- AI-driven migration plan generation — application grouping and wave planning
- Three discovery options: AWS Application Discovery Service collectors, Export for vCenter tool, or independently collected data import
- Landing zone setup for target AWS accounts
- Multi-wave migration with per-wave configuration
- Single-account and multi-account migration support

For detailed execution guidance see:

- [vmware-server.md](vmware-server.md) — replication agent deployment, data replication, testing, cutover
- [vmware-network.md](vmware-network.md) — network mapping, topology, IaC generation, deployment
- [vmware-landing-zone.md](vmware-landing-zone.md) — landing zone foundation and workload account design
- [vmware-containerization.md](vmware-containerization.md) — source code containerization, Docker artifacts, ECR publishing, EKS/ECS IaC

## Job Types

AWS Transform offers the following VMware migration job types. Steps can be dynamically added or removed at any time to customize the workflow.

| Job Type                                        | Steps Included                                                                                                              |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| **End-to-end migration**                        | Perform discovery → Build migration plan → Connect target accounts → Build landing zone → Migrate network → Migrate servers |
| **Discovery and migration planning**            | Perform discovery → Build migration plan                                                                                    |
| **Network migration**                           | Connect target accounts → Migrate network                                                                                   |
| **Landing zone**                                | Connect target accounts → Build landing zone                                                                                |
| **Landing zone, network, and server migration** | Connect target accounts → Build landing zone → Migrate network → Migrate servers                                            |
| **Migration planning and server migration**     | Perform discovery → Build migration plan → Connect target accounts → Migrate servers                                        |
| **Source code containerization**                | Connect target accounts → Containerize applications → Publish to ECR → Deploy to EKS/ECS                                    |

> One target AWS Region per VMware migration job. To migrate to different Regions, create multiple jobs.

## Starting Workflow

**Before starting:** Confirm job type — determine which steps are in scope based on what the user already has (existing network, existing landing zone, etc.)

1. **Perform discovery** — identify VM count, OS types, resource usage (CPU, memory, storage), and network dependencies using one of the three discovery options
2. **Build migration plan** — AI-driven application grouping, wave planning, and right-sizing recommendations
3. **Connect target accounts** — configure target AWS accounts and verify permissions
4. **Build landing zone** — set up AWS account structure, IAM roles, and baseline infrastructure in target accounts
5. **Migrate network** — translate VMware network configuration to AWS VPC architecture; deploy via CloudFormation
6. **Migrate servers** — deploy replication agents, replicate data, test, and cut over wave by wave

**Key questions to ask user:**

- "Do you already have a landing zone and network set up in the target account(s), or do we need to build those?"
- "Which discovery method do you have available — ADS collectors, Export for vCenter, or an existing data export?"

## Agent Interaction Rules

**After every job interaction** (sending a message, completing a task, uploading an artifact) — always read the latest messages from the job and surface any agent responses or questions to the user immediately. Do not assume silence means the agent is still processing — it may have already responded.

**Polling priority** — check in this order:

1. Messages (agent chat responses and questions) — check first
2. Tasks (formal HITL tasks awaiting human input)
3. Worklogs (agent activity and progress)

**Target account operations — always delegate to the agent:**
When the user asks about resources in the target AWS account (subnets, VPCs, security groups, instances, IAM roles), do NOT query the target account directly. Forward the request to the agent via `send_message` — the agent has connector-based access to the target account.

**Console links — never construct, always use agent-provided:**
Console URLs are dynamically generated and scoped to specific connectors, workspaces, and accounts. Always use links provided by the agent in its messages or HITL tasks. If the agent hasn't provided a link, ask it via `send_message` rather than guessing the URL format.

## Agents & Transforms

| Agent                                                   | How to Discover                            | Purpose                                                                                              |
| ------------------------------------------------------- | ------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| VMware Migration Agent v2 (`vmware-migration-agent-v2`) | `list_resources` with `resource: "agents"` | End-to-end orchestration: discovery, planning, network migration, server migration, containerization |
| Server Migration Agent                                  | `list_resources` with `resource: "agents"` | Wave setup, replication agent deployment, replication monitoring, testing, cutover                   |
| Landing Zone Agent                                      | `list_resources` with `resource: "agents"` | Foundation setup, workload account design, SCP configuration, IaC generation                         |
| Network Migration Agent (NMA)                           | _(sub-agent, invoked by orchestrator)_     | Network mapping, optimization, and IaC generation                                                    |
| Containerization sub-agent                              | _(sub-agent, invoked by orchestrator)_     | Source code analysis, Docker artifact generation, image building, IaC generation                     |
| AWS Application Migration Service (MGN)                 | External                                   | Actual server replication, testing, and cutover execution                                            |
| AWS Migration Hub                                       | External                                   | Migration tracking and orchestration                                                                 |

**Discover agents dynamically:**

```python
list_resources(resource="agents")
# Or ask the chat agent
send_message(workspaceId="...", text="What agents are available for VMware migration?")
# Then create job with discovered orchestratorAgent
create_job(workspaceId="...", jobName="VMware Migration",
  objective="Migrate VMware workloads to EC2", orchestratorAgent="vmware-migration-agent-v2")
```

## Decision Points

| Decision                  | Options                                                                  | When to Ask                                                             |
| ------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| Job type                  | End-to-end / Discovery and planning / Network only / Landing zone / etc. | Before starting — based on what the user already has                    |
| Discovery method          | ADS collectors / Export for vCenter / Independent import                 | Step 1 — before discovery                                               |
| Migration mode            | Single-account / Multi-account                                           | Step 3 — connecting target accounts                                     |
| Network topology          | Hub and Spoke / Isolated VPCs                                            | Step 5 — network migration                                              |
| Security group strategy   | MAP / MAP_DHCP / SKIP                                                    | Step 5 — network migration. Determines IP assignment options in Step 6. |
| IP assignment strategy    | Static IP / Dynamic IP (DHCP)                                            | Step 6 — wave setup. Constrained by SG strategy.                        |
| Agent installation method | Organization tools / MGN connector / Manual                              | Step 6 — before replication agent deployment                            |
| Testing scope             | Full wave / Selective                                                    | Step 6 — before launching test instances                                |
| Cutover scope             | Full wave / Selective                                                    | Step 6 — before launching cutover instances                             |

## Example Requirements

```
## Requirement 1: VM Discovery and Migration Planning

**User Story:** As an infrastructure engineer, I want all VMware VMs assessed and grouped into waves
so that I have a clear, prioritized migration plan with right-sized EC2 targets.
**Acceptance Criteria:**

1. WHEN discovery completes, EACH VM SHALL have a recommended EC2 instance type
2. WHEN discovery completes, network dependencies between VMs SHALL be documented
3. WHEN migration plan is built, VMs SHALL be grouped into migration waves with dependency ordering
   **Handled by:** AWS Transform VMware Migration Agent v2

## Requirement 2: Network Migration

**User Story:** As a network engineer, I want VMware network configuration translated to AWS VPC
so that VM communication patterns are preserved after migration.
**Acceptance Criteria:**

1. WHEN network mapping completes, EACH source network segment SHALL map to a distinct AWS VPC
2. WHEN network mapping completes, source firewall rules SHALL be translated to AWS Security Groups
3. WHEN deployment completes, ALL VPCs, subnets, and security groups SHALL exist in the target account
   **Handled by:** AWS Transform VMware Migration Agent v2 (NMA sub-agent)

## Requirement 3: Server Migration

**User Story:** As an operations engineer, I want VMware servers rehosted to EC2
so that production workloads run natively on AWS with verified functionality.
**Acceptance Criteria:**

1. WHEN replication agents are deployed, ALL servers SHALL show replication state INITIATING or INITIAL_SYNC
2. WHEN test instances are launched (after approval), instance IDs SHALL be provided for each server
3. WHEN cutover is finalized (after approval), source machine replication SHALL stop and lifecycle state SHALL be locked
   **Handled by:** AWS Transform Server Migration Agent
```

## Example Tasks

```
- [ ] 1. Job setup
  - [ ] 1.1 Confirm job type (end-to-end or subset of steps)
  - [ ] 1.2 Confirm single-account or multi-account migration
  - [ ] 1.3 Create and start VMware migration job
- [ ] 2. Discovery (Step 1)
  - [ ] 2.1 Choose discovery method (ADS / Export for vCenter / independent import)
  - [ ] 2.2 Run discovery and collect VM inventory
  - [ ] 2.3 Review discovery results
- [ ] 3. Migration planning (Step 2)
  - [ ] 3.1 Review AI-generated application groupings
  - [ ] 3.2 Review and adjust wave assignments
  - [ ] 3.3 Review right-sizing recommendations
  - [ ] 3.4 Approve migration plan
- [ ] 4. Connect target accounts (Step 3)
  - [ ] 4.1 Provide target AWS account IDs
  - [ ] 4.2 Verify MGN initialized in each target account
  - [ ] 4.3 Verify cross-account IAM roles
- [ ] 5. Build landing zone (Step 4)
  - [ ] 5.1 Configure landing zone settings
  - [ ] 5.2 Deploy landing zone (approval required)
  - [ ] 5.3 Verify baseline infrastructure in target accounts
- [ ] 6. Network migration (Step 5) — see vmware-network.md
  - [ ] 6.1 Upload source network file
  - [ ] 6.2 Select topology and security group strategy
  - [ ] 6.3 Review and optimize network design
  - [ ] 6.4 Deploy network (approval required)
- [ ] 7. Server migration (Step 6) — see vmware-server.md
  - [ ] 7.1 Set up migration wave per wave
  - [ ] 7.2 Validate and confirm inventory
  - [ ] 7.3 Deploy replication agents
  - [ ] 7.4 Monitor data replication
  - [ ] 7.5 Launch test instances (approval required)
  - [ ] 7.6 Mark applications ready for cutover
  - [ ] 7.7 Launch cutover instances (approval required)
  - [ ] 7.8 Finalize cutover and archive source servers
```

## Known Limitations

- One target AWS Region per VMware migration job — create multiple jobs to migrate to different Regions
- Stopping a running migration job is irreversible — VMWARE_V2 jobs cannot be restarted once stopped. A new job must be created to start over. Artifacts from the stopped job are preserved but job progress is lost.
- NSX imports are only supported for end-to-end migration jobs
- Physical servers (non-virtualized) are not in scope
- VMware-specific features (vMotion, DRS, HA) have no direct AWS equivalents — require architectural redesign
- License mapping (Windows Server, SQL Server on VMs) requires manual review
- AWS Transform generates network configurations and migration strategies based on environment assessment — review with stakeholders before proceeding to ensure security and compliance requirements are met
