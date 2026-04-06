# RDS/Aurora Monitoring and Operations Reference

## CloudWatch Metrics

### Critical Metrics — Monitor with Alarms

| Metric | Alarm Threshold | Action |
|---|---|---|
| `CPUUtilization` | >80% sustained 5 min | Scale up instance or optimize queries |
| `FreeableMemory` | <10% of total memory | Scale up or reduce max_connections/work_mem |
| `DatabaseConnections` | >80% of max_connections | Add RDS Proxy, increase limit, or fix connection leaks |
| `FreeStorageSpace` (RDS) | <20% of allocated | Enable storage auto-scaling or increase allocated storage |
| `ReplicaLag` | >1 second sustained | Writer overloaded, reader undersized, or network issue |
| `DiskQueueDepth` (RDS) | >10 sustained | IOPS bottleneck — provision more IOPS or move to io2 |
| `SwapUsage` | >0 for extended periods | Instance memory insufficient — scale up |
| `AuroraReplicaLagMaximum` | >100ms sustained | Write pressure exceeding replica capacity |

### Important Metrics — Review Weekly

| Metric | What to Look For | Notes |
|---|---|---|
| `ReadIOPS` / `WriteIOPS` | Approaching provisioned IOPS limit | gp3 baseline is 3,000 IOPS |
| `ReadThroughput` / `WriteThroughput` | Approaching throughput limit | gp3 baseline is 125 MiB/s |
| `ServerlessDatabaseCapacity` | Min/max ACU utilization patterns | Right-size Serverless v2 scaling config |
| `ACUUtilization` | Consistently >90% | Max ACU may be too low |
| `BufferCacheHitRatio` | <95% | Working set exceeds buffer pool — scale up memory |
| `Deadlocks` | Any occurrence | Investigate application transaction patterns |
| `LoginFailures` | Spikes | Possible credential issues or brute-force attempts |

## Performance Insights

### Setup
- Enable at instance creation or via `modify-db-instance --enable-performance-insights`
- Free tier: 7 days retention (sufficient for most troubleshooting)
- Paid: up to 24 months retention ($0.068/vCPU/month) — use for trend analysis

### Key Concepts

**db.load**: The average number of active sessions. Compare to vCPU count:
- db.load < vCPU count → database is not CPU-constrained
- db.load > vCPU count → queries are waiting (bottleneck)
- db.load >> vCPU count → significant contention, immediate action needed

**Wait Events** (what queries are waiting on):
| Wait Event | Engine | Meaning | Fix |
|---|---|---|---|
| `CPU` | Both | Query is actively executing | Optimize query or scale up |
| `IO:DataFileRead` | PostgreSQL | Reading from disk | Increase shared_buffers or scale up memory |
| `wait/io/table/sql/handler` | MySQL | Table I/O wait | Add indexes, optimize queries |
| `Lock:Relation` | PostgreSQL | Table lock contention | Reduce long transactions, check autovacuum |
| `wait/synch/mutex/innodb/...` | MySQL | InnoDB mutex contention | Increase buffer pool instances |
| `LWLock:BufferMapping` | PostgreSQL | Buffer pool contention | Scale up instance (more memory) |
| `Client:ClientRead` | PostgreSQL | Waiting for client to send data | Application or network issue |
| `IO:XactSync` | PostgreSQL | Waiting for WAL sync | Storage throughput limit (RDS only) |

### Top SQL Analysis
1. Sort by `db.load` contribution to find the most resource-consuming queries
2. Check execution plan with `EXPLAIN (ANALYZE, BUFFERS)` for the top offenders
3. Look for sequential scans on large tables, nested loops with large row counts, and sort operations spilling to disk
4. Use `pg_stat_statements` (PostgreSQL) or `performance_schema` (MySQL) for aggregated query stats

## Enhanced Monitoring

- Provides OS-level metrics at 1-60 second granularity
- Separate from CloudWatch metrics — requires an IAM role for the RDS instance
- Essential for distinguishing database issues from OS/instance issues

### Key OS Metrics
| Metric | What to Look For |
|---|---|
| CPU per core | Uneven core utilization (single-threaded bottleneck) |
| Memory breakdown | Shared buffers vs free vs cached |
| Swap | Any swap activity indicates memory pressure |
| Disk I/O latency | >5ms average indicates storage bottleneck |
| Network throughput | Approaching instance network bandwidth limit |

## Operational Procedures

### Maintenance Windows

- Schedule during lowest-traffic period (review CloudWatch metrics to identify)
- Enable `auto_minor_version_upgrade` for security patches
- For major version upgrades: use blue/green deployments, never in-place on production
- Aurora: minor patches apply with zero-downtime patching (ZDP) when possible

### Backup Verification

Quarterly backup verification procedure:
1. Restore from the latest automated backup to a test instance
2. Run application smoke tests against the restored instance
3. Verify point-in-time recovery (PITR) works by restoring to a specific timestamp
4. Document restore time — this is the actual RTO
5. Delete the test instance after verification

### Connection Management

#### Diagnosing Connection Issues
```sql
-- PostgreSQL: active connections by state
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

-- PostgreSQL: long-running queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
  AND state != 'idle';

-- PostgreSQL: idle-in-transaction connections (lock holders)
SELECT pid, now() - xact_start AS xact_duration, query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND (now() - xact_start) > interval '1 minute';
```

```sql
-- MySQL: connection overview
SHOW STATUS LIKE 'Threads_%';
SHOW PROCESSLIST;

-- MySQL: long-running queries
SELECT * FROM information_schema.processlist
WHERE TIME > 300 AND COMMAND != 'Sleep';
```

#### Connection Leak Prevention
- Set `idle_in_transaction_session_timeout` (PostgreSQL) or `wait_timeout` (MySQL) to kill idle connections
- Monitor `DatabaseConnections` metric trend — steady increase indicates a leak
- Use RDS Proxy to absorb connection spikes and multiplex connections

### Failover Testing

Quarterly failover drill:
1. Initiate failover via `aws rds failover-db-cluster` (Aurora) or `aws rds reboot-db-instance --force-failover` (RDS Multi-AZ)
2. Measure actual failover time (Aurora target: <30s, RDS Multi-AZ target: <120s)
3. Verify application reconnects without manual intervention
4. Check that monitoring alerts fired as expected
5. Document actual RTO for DR planning

### Diagnostic CLI Commands

Resource creation and modification belong in IaC (CDK, CloudFormation, Terraform). Use the `iac-scaffold` skill for templates. The CLI commands below are for diagnostics, investigation, and operational procedures only.

```bash
# Describe cluster (endpoints, status, instances, engine version)
aws rds describe-db-clusters --db-cluster-identifier my-cluster

# Describe a specific instance (class, AZ, storage, parameter group)
aws rds describe-db-instances --db-instance-identifier my-instance

# List all instances in the account
aws rds describe-db-instances --query "DBInstances[].{ID:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,Status:DBInstanceStatus,AZ:AvailabilityZone}" --output table

# Check current parameter values
aws rds describe-db-parameters --db-parameter-group-name my-param-group \
  --query "Parameters[?ParameterName=='max_connections']"

# List all parameter groups
aws rds describe-db-parameter-groups --query "DBParameterGroups[].{Name:DBParameterGroupName,Family:DBParameterGroupFamily}" --output table

# View pending maintenance actions
aws rds describe-pending-maintenance-actions

# List snapshots for a cluster
aws rds describe-db-cluster-snapshots --db-cluster-identifier my-cluster \
  --query "DBClusterSnapshots[].{ID:DBClusterSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime}" --output table

# Check events (last 24 hours)
aws rds describe-events --duration 1440 --source-type db-cluster

# View Performance Insights metrics (requires PI enabled)
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier db-XXXXX \
  --metric-queries '[{"Metric":"db.load.avg"}]' \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period-in-seconds 60

# Initiate failover drill (Aurora) — use during planned DR testing
aws rds failover-db-cluster --db-cluster-identifier my-cluster

# Initiate failover drill (RDS Multi-AZ) — use during planned DR testing
aws rds reboot-db-instance --db-instance-identifier my-rds-instance --force-failover
```
