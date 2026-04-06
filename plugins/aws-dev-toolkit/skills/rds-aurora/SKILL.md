---
name: rds-aurora
description: Deep-dive into Amazon RDS and Aurora database design, engine selection, high availability, and operations. This skill should be used when the user asks to "design an RDS database", "choose between RDS and Aurora", "configure Aurora Serverless", "set up read replicas", "plan a database migration", "configure RDS Proxy", "tune database parameters", "set up Multi-AZ", "plan blue/green deployments", or mentions RDS, Aurora, Aurora Serverless v2, database failover, or relational database design on AWS.
---

Specialist guidance for Amazon RDS and Aurora. Covers engine selection, instance sizing, high availability, read scaling, security, migration, and operational best practices.

## Process

1. Identify the workload characteristics: read/write ratio, latency requirements, data volume, connection count
2. Use the `aws-docs` MCP tools to verify current RDS/Aurora limits, engine versions, and features
3. Select the appropriate engine and deployment model (RDS single-instance, RDS Multi-AZ, Aurora provisioned, Aurora Serverless v2)
4. Design the high availability and read scaling topology
5. Configure security (encryption, IAM auth, network isolation)
6. Recommend operational best practices (backups, monitoring, maintenance)

## Engine Selection Decision Matrix

| Requirement | Recommendation | Why |
|---|---|---|
| MySQL/PostgreSQL, predictable workload, cost-sensitive | RDS for MySQL/PostgreSQL | Simpler, cheaper for small-medium workloads |
| MySQL/PostgreSQL, high availability, auto-scaling storage | Aurora (MySQL/PostgreSQL) | 6-way replicated storage, up to 128 TB auto-grow |
| Spiky or unpredictable traffic | Aurora Serverless v2 | Scales ACUs in 0.5 increments, optional scale-to-zero support |
| Oracle or SQL Server licensing | RDS for Oracle / SQL Server | Only option for these engines on managed AWS |
| Very small dev/test database | RDS with `db.t4g.micro` or Aurora Serverless v2 min 0.5 ACU | Lowest cost entry points |
| High write throughput, global | Aurora Global Database | Sub-second cross-region replication, write forwarding |
| Existing on-prem PostgreSQL migration | Aurora PostgreSQL + DMS | Wire-compatible, minimal app changes |

## Aurora vs RDS — Key Differences

### Storage Architecture
- **RDS**: EBS-backed (gp3 or io2), single-AZ storage unless Multi-AZ
- **Aurora**: Distributed storage layer, 6 copies across 3 AZs, auto-heals, auto-grows to 128 TB
- Aurora survives loss of 2 copies for writes, 3 for reads — without manual intervention

### Replication
- **RDS**: Async read replicas (up to 15 for MySQL, 5 for PostgreSQL), separate storage per replica
- **Aurora**: Up to 15 read replicas sharing the same storage volume — replica lag typically <20ms, often <10ms
- Aurora replicas can be failover targets with no data loss (same storage)

### Failover
- **RDS Multi-AZ**: 60-120 second failover to synchronous standby
- **Aurora**: Typically <30 second failover to a read replica (promoted in-place)
- Aurora supports failover priority tiers (0-15) to control which replica gets promoted

### Cost Comparison
- Aurora instances cost ~20% more than equivalent RDS instances
- Aurora eliminates separate EBS costs — storage is included in the Aurora pricing model
- For read-heavy workloads, Aurora's shared storage makes replicas cheaper (no storage duplication)
- Aurora Serverless v2 can be more cost-effective for variable workloads than provisioned instances sitting idle

## Aurora Serverless v2

- Scales in 0.5 ACU increments (1 ACU ≈ 2 GiB RAM + proportional CPU)
- Minimum: 0.5 ACU; Maximum: 256 ACU per instance
- Scales based on CPU, connections, and memory pressure — not request count
- Can mix Serverless v2 and provisioned instances in the same cluster
- Recommended pattern: Serverless v2 reader for variable read traffic, provisioned writer for consistent write load

### When to Use Serverless v2
- Development and staging environments
- Applications with idle periods (nights, weekends)
- Spiky read workloads (reporting, batch queries)
- New applications where traffic patterns are unknown

### When to Avoid Serverless v2
- Sustained high-throughput production writers — provisioned is cheaper at steady state
- Latency-sensitive workloads during scale-up (scaling from minimum takes seconds, not instant)

## High Availability Configurations

### RDS Multi-AZ (Instance)
- Synchronous standby in a different AZ — automatic failover
- Standby is not readable (unlike Aurora replicas)
- Use for: production databases that need simple HA without read scaling

### RDS Multi-AZ (Cluster) — db.r6gd Only
- One writer + two readable standbys across 3 AZs
- Uses local NVMe + synchronous replication
- Sub-35-second failover
- Limited to specific instance classes

### Aurora Multi-AZ
- Create at least one read replica in a different AZ for HA
- All replicas share storage, so failover has zero data loss
- For production: minimum 2 replicas across 2 AZs (writer + 2 readers = 3 AZs)

### Aurora Global Database
- Cross-region replication with <1 second typical lag
- Managed RPO/RTO with automated failover
- Write forwarding lets readers in secondary regions redirect writes to the primary
- Use for: disaster recovery, low-latency global reads

## RDS Proxy

- Fully managed connection pooler sitting between applications and the database
- Multiplexes thousands of application connections to a smaller pool of database connections
- Reduces failover time by maintaining open connections to standby
- Essential for Lambda → RDS/Aurora (Lambda creates many short-lived connections)

### When to Use RDS Proxy
- Lambda functions connecting to RDS/Aurora (connection exhaustion risk)
- Applications with many short-lived connections
- Reducing failover disruption (proxy pins to new primary automatically)

### When to Skip RDS Proxy
- Applications with persistent connection pools (like traditional app servers with HikariCP/pgBouncer)
- Workloads requiring session-level features (prepared statements, temp tables — proxy may pin connections)

## Security

### Encryption
- **At rest**: Enable at creation time (cannot be enabled later without snapshot-restore). Use AWS KMS CMK for key control.
- **In transit**: Enforce SSL via parameter group (`rds.force_ssl = 1` for PostgreSQL, `require_secure_transport = ON` for MySQL)

### Network Isolation
- Deploy in private subnets only — never assign a public IP
- Use security groups to restrict ingress to application subnets
- Use VPC endpoints for API calls (`rds` and `rds-data` endpoints)

### Authentication
- **IAM database authentication**: Token-based, no passwords stored — good for Lambda and automated access
- **Secrets Manager rotation**: Automatic password rotation on a schedule — use for traditional username/password auth
- **Kerberos/Active Directory**: Available for SQL Server and Oracle via AWS Directory Service

## Blue/Green Deployments

- Create a "green" copy of the production database with changes applied (engine upgrade, parameter changes, schema changes)
- RDS keeps the green environment in sync via logical replication
- Switchover takes ~1 minute with minimal downtime
- Automatic rollback if health checks fail

### Supported Changes
- Major engine version upgrades
- Parameter group changes
- Schema changes on the green environment
- Instance class changes

### Limitations
- Not available for Aurora Serverless v1 (v2 supported)
- Requires enough capacity for both environments during the transition

## Backup and Recovery

### Automated Backups
- Default retention: 7 days (configurable 0-35 days; 0 disables)
- Point-in-time recovery (PITR) to any second within the retention window
- Backups are stored in S3 (managed by AWS, not visible in your bucket)

### Manual Snapshots
- Persist indefinitely until deleted
- Can be shared cross-account or copied cross-region
- Use for: pre-change safety nets, archival, cross-region DR

### Aurora Backtrack (MySQL only)
- Rewind the database to a specific point in time without restore
- Operates on the same cluster — much faster than PITR
- Configure a backtrack window (up to 72 hours)
- Use for: recovering from bad queries, accidental deletes

## Anti-Patterns

- **Public subnets for databases.** Never place RDS/Aurora in a public subnet. Use private subnets and access through application layer, VPN, or bastion.
- **Default parameter groups.** Always create custom parameter groups — default ones cannot be modified and make tuning impossible.
- **Unencrypted instances.** Encryption must be enabled at creation. Retrofitting requires snapshot → copy-encrypted → restore, which means downtime and new endpoints.
- **Lambda without RDS Proxy.** Lambda creates new connections per invocation. Without a connection pooler, concurrent Lambdas exhaust `max_connections` within seconds.
- **Single-AZ production databases.** No HA means any AZ failure takes down the database until manual intervention.
- **Oversized instances "just in case".** Start with Performance Insights data, right-size based on actual db.load, not guesswork. Graviton (r7g) instances offer better price-performance.
- **Ignoring storage IOPS limits.** gp3 default is 3,000 IOPS — if the workload exceeds this, provision higher IOPS or move to io2 before hitting throttling.
- **Manual password management.** Use `--manage-master-user-password` (Secrets Manager integration) or IAM authentication. Hardcoded passwords in application config are a security incident waiting to happen.
- **Not enabling deletion protection on production.** A single `delete-db-instance` call without deletion protection can destroy the production database.

## Migration Guidance

For migrating to RDS/Aurora, coordinate with the `aws-migrate` skill for full assessment workflows.

### Common Migration Paths
- **Self-managed MySQL/PostgreSQL → Aurora**: Use AWS DMS for minimal-downtime migration with CDC
- **Oracle/SQL Server → Aurora PostgreSQL**: Use AWS SCT (Schema Conversion Tool) + DMS
- **RDS MySQL → Aurora MySQL**: Use snapshot restore (fastest) or create Aurora read replica of RDS instance then promote

### Key Considerations
- Always run SCT assessment report before cross-engine migrations — it quantifies conversion effort
- Test with DMS validation tasks to verify data integrity post-migration
- Plan for endpoint changes — Aurora uses cluster endpoints (writer) and reader endpoints

## Additional Resources

### Reference Files

For detailed operational guidance, consult:
- **`references/instance-sizing.md`** — Instance family comparison, Graviton recommendations, memory-to-connections ratios, ACU sizing, storage types, and cost optimization patterns
- **`references/parameter-tuning.md`** — PostgreSQL and MySQL parameter recommendations, Aurora-specific parameters, and safe change procedures
- **`references/monitoring-operations.md`** — CloudWatch alarm thresholds, Performance Insights wait event analysis, Enhanced Monitoring, backup verification, failover testing, connection diagnostics, and common CLI commands

### Related Skills
- **`aws-migrate`** — Full migration assessment workflows (DMS, SCT, migration waves)
- **`cost-check`** — Detailed cost analysis and Reserved Instance recommendations
- **`security-review`** — IAM, network, and encryption audit for database configurations
- **`networking`** — VPC design, subnet planning, and security group configuration

## Output Format

When recommending a database design, include:

| Component | Choice | Rationale |
|---|---|---|
| Engine | Aurora PostgreSQL 16.4 | Wire-compatible, storage auto-scaling |
| Writer | db.r7g.xlarge (provisioned) | Consistent write load, 4 vCPU / 32 GiB |
| Reader(s) | db.serverless (Serverless v2, 1-16 ACU) | Variable read traffic |
| HA | Multi-AZ (writer + 2 readers across 3 AZs) | Production requirement |
| Proxy | RDS Proxy | Lambda consumers |
| Encryption | KMS CMK, force SSL | Compliance requirement |

Include estimated monthly cost range using the `cost-check` skill.
