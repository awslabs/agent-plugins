# Server Migration

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

Rehost VMware servers to Amazon EC2 using AWS Application Migration Service (MGN). AWS Transform orchestrates the full wave-based migration lifecycle — wave setup, inventory validation, replication agent deployment, data replication monitoring, test instance launch, and production cutover. This workload covers VMware-sourced servers only; for VMware infrastructure (vSphere networking, vSAN storage, vCenter) see [vmware.md](vmware.md).

- VMware servers → Amazon EC2 instances (rehost/lift-and-shift via MGN)
- Continuous block-level data replication via AWS Replication Agent
- Automated replication agent installation via MGN connector (SSH/WinRM) — reusable across waves and target accounts
- Multi-wave migration with per-wave configuration
- Single-account and multi-account migration support
- Test instance launch and validation before production cutover
- Selective or full-wave cutover with finalization

## Starting Workflow

1. **Confirm prerequisites** — target AWS accounts ready, VPCs/subnets/security groups deployed and tagged, inventory file prepared with wave assignments
2. **Configure execution defaults** — EC2 recommendation preferences and default launch settings (apply to all target accounts)
3. **Set up migration wave** — configure target account, migration mode (single vs multi-account), IP assignment strategy, verify resource tags
4. **Validate inventory** — review and confirm server-to-EC2 mapping, licensing options, and network configuration before loading into MGN
5. **Deploy replication agents** — choose installation method (organization tools, MGN connector, or manual), deploy to all servers in the wave
6. **Monitor replication** — track initial sync and continuous replication until all servers reach Ready for testing
7. **Test** — obtain approval before launching test instances, then launch, validate, mark applications ready for cutover
8. **Cutover** — obtain approval before launching cutover instances, then launch, verify, finalize (stops replication), optionally archive source servers

Individual servers can advance to test and cutover independently of the rest of the wave.

## Agents & Transforms

| Agent                                   | How to Discover                            | Purpose                                                                                      |
| --------------------------------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------- |
| Server migration agent                  | `list_resources` with `resource: "agents"` | Wave setup, inventory validation, agent deployment, replication monitoring, testing, cutover |
| AWS Application Migration Service (MGN) | External                                   | Actual server replication, testing, and cutover execution                                    |
| AWS Migration Hub                       | External                                   | Migration tracking and orchestration                                                         |

**Discover the agent dynamically:**

```python
list_resources(resource="agents")
# Then create job with discovered orchestratorAgent
create_job(workspaceId="...", jobName="Server Migration",
  objective="Migrate VMware servers to EC2 using MGN", orchestratorAgent="<discovered>")
```

## Decision Points

| Decision                  | Options                                                              | When to Ask                            |
| ------------------------- | -------------------------------------------------------------------- | -------------------------------------- |
| Migration mode            | Single-account / Multi-account                                       | Wave setup                             |
| IP assignment strategy    | Static IP / Dynamic IP (DHCP)                                        | Wave setup                             |
| Agent installation method | Organization tools / MGN connector / Manual                          | Before agent deployment                |
| Credential configuration  | Single secret (Linux) / Single secret (Windows) / Per-server secrets | Connector setup (MGN connector method) |
| Testing scope             | Full wave / Selective                                                | Before launching test instances        |
| Cutover scope             | Full wave / Selective                                                | Before launching cutover instances     |

## Example Requirements

```
## Requirement 1: Wave Setup and Inventory Validation

**User Story:** As an infrastructure engineer, I want each migration wave configured and validated
so that servers are correctly mapped to target accounts, subnets, and EC2 instance types.
**Acceptance Criteria:**

1. WHEN wave setup completes, EACH server SHALL have a target account, subnet, security group, and EC2 instance type assigned
2. WHEN inventory is validated, required resource tags SHALL be verified
3. WHEN inventory is loaded, MGN SHALL create source server records for each server in the wave
   **Handled by:** AWS Transform Server Migration Agent

## Requirement 2: Replication Agent Deployment

**User Story:** As an operations engineer, I want replication agents deployed to all source servers
so that continuous block-level replication to AWS begins automatically.
**Acceptance Criteria:**

1. WHEN agents are deployed, ALL servers in the wave SHALL show replication state INITIATING or INITIAL_SYNC
2. WHEN initial sync completes, ALL servers SHALL reach Ready for testing state
3. WHEN a server fails agent installation, the failure reason SHALL be displayed and retry SHALL be available
   **Handled by:** AWS Transform Server Migration Agent

## Requirement 3: Testing and Cutover

**User Story:** As an operations engineer, I want to validate migrated servers before cutover
so that production workloads are moved to AWS with verified functionality.
**Acceptance Criteria:**

1. WHEN test instances are launched, instance IDs SHALL be provided for each server
2. WHEN all applications are marked ready for cutover, replication alerts SHALL be resolved
3. WHEN cutover is finalized, source machine replication SHALL stop and lifecycle state SHALL be locked
4. WHEN cutover completes, downtime SHALL be limited to the window between source shutdown and cutover instance availability
   **Handled by:** AWS Transform Server Migration Agent
```

## Example Tasks

```
- [ ] 1. Prerequisites verification
  - [ ] 1.1 Confirm target AWS accounts are ready
  - [ ] 1.2 Verify VPC, subnets, and security groups are deployed and tagged
  - [ ] 1.3 Confirm inventory file is prepared with wave assignments and EC2 preferences
  - [ ] 1.4 Configure migration execution defaults
- [ ] 2. Wave setup
  - [ ] 2.1 Configure migration mode (single-account or multi-account)
  - [ ] 2.2 Verify MGN is initialized in target accounts
  - [ ] 2.3 Verify resource tagging
  - [ ] 2.4 Configure IP assignment strategy
- [ ] 3. Inventory validation
  - [ ] 3.1 Download and review inventory file (CSV/XLSX)
  - [ ] 3.2 Adjust EC2 instance types, licensing options, tenancy if needed
  - [ ] 3.3 Upload modified inventory or accept as-is
  - [ ] 3.4 Confirm MGN source server records created
- [ ] 4. Deploy replication agents
  - [ ] 4.1 Choose installation method
  - [ ] 4.2 Set up MGN connector if selected
  - [ ] 4.3 Deploy agents to all servers in the wave
  - [ ] 4.4 Verify all agents connected
- [ ] 5. Data replication
  - [ ] 5.1 Monitor initial sync progress per server
  - [ ] 5.2 Confirm all servers reach Ready for testing state
- [ ] 6. Testing
  - [ ] 6.1 Launch test instances (full wave or selective)
  - [ ] 6.2 Validate test instances
  - [ ] 6.3 Mark applications as ready for cutover
- [ ] 7. Cutover
  - [ ] 7.1 Launch cutover instances within maintenance window
  - [ ] 7.2 Verify cutover instances
  - [ ] 7.3 Finalize cutover
  - [ ] 7.4 Archive source servers (optional)
```

## Known Limitations

- Agentless replication is not supported — the AWS Replication Agent must be installed on all servers in a wave
- SSM Hybrid Activations for the MGN connector expire after 30 days — a new connector is required if installing on a new machine after expiration
- Only one inventory import to a given target account and Region is allowed at a time
- IP assignment is constrained by the security group mapping strategy: MAP supports static IP only; MAP_DHCP and SKIP support both static and DHCP
- Deployment approvals require Admin or Approver role in AWS Transform
- Downtime is unavoidable between source shutdown and cutover instance availability — plan maintenance windows accordingly
