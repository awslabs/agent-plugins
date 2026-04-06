# RDS/Aurora Parameter Tuning Reference

## Parameter Group Strategy

- Never modify the default parameter group — create a custom one
- Use separate parameter groups for writer and reader instances when tuning differs
- Aurora cluster parameter groups apply to all instances; instance parameter groups override per-instance
- Changes to static parameters require a reboot; dynamic parameters apply immediately
- Always test parameter changes in staging before production — use blue/green deployments for risky changes

## PostgreSQL Parameters

### Memory and Buffers

| Parameter | Recommended Value | Notes |
|---|---|---|
| `shared_buffers` | 25% of instance memory | Aurora manages this automatically; only tune on RDS |
| `effective_cache_size` | 75% of instance memory | Planner hint, does not allocate memory |
| `work_mem` | 4-16 MB | Multiplied by max_connections x sorts per query; too high causes OOM |
| `maintenance_work_mem` | 512 MB - 2 GB | For VACUUM, CREATE INDEX; can be higher since these run infrequently |
| `temp_buffers` | 8 MB (default) | Per-session temp table memory; increase only if using many temp tables |

### Connections and Logging

| Parameter | Recommended Value | Notes |
|---|---|---|
| `max_connections` | Based on instance size (see instance-sizing.md) | Over-provisioning wastes memory; under-provisioning causes connection errors |
| `log_min_duration_statement` | 1000 (ms) | Logs queries taking >1s; start here, tighten to 500ms or 200ms as needed |
| `log_statement` | `ddl` | Log DDL changes for audit; `all` is too verbose for production |
| `log_lock_waits` | `on` | Log when queries wait >deadlock_timeout for a lock |
| `idle_in_transaction_session_timeout` | 60000 (ms) | Kill idle-in-transaction sessions after 60s to prevent lock accumulation |

### Query Performance

| Parameter | Recommended Value | Notes |
|---|---|---|
| `random_page_cost` | 1.1 (Aurora/SSD) or 1.5 (RDS gp3) | Default 4.0 is for spinning disk; too high discourages index scans |
| `effective_io_concurrency` | 200 (Aurora/SSD) | Default 1 is too low for SSD/Aurora; allows parallel I/O during bitmap scans |
| `default_statistics_target` | 100-500 | Higher = better query plans but slower ANALYZE; increase for skewed data distributions |
| `jit` | `off` (default on in PG 12+) | JIT compilation adds latency to short queries; enable only for analytical workloads |

### WAL and Checkpoints (RDS only — Aurora handles this)

| Parameter | Recommended Value | Notes |
|---|---|---|
| `wal_buffers` | 64 MB | Default -1 auto-sizes to 1/32 of shared_buffers |
| `checkpoint_completion_target` | 0.9 | Spread checkpoint writes over 90% of checkpoint interval |
| `max_wal_size` | 4-8 GB | Controls checkpoint frequency; larger = less frequent but longer recovery |

### Vacuum and Autovacuum

| Parameter | Recommended Value | Notes |
|---|---|---|
| `autovacuum_vacuum_scale_factor` | 0.02-0.05 | Default 0.2 waits too long on large tables |
| `autovacuum_analyze_scale_factor` | 0.01-0.05 | Keep statistics fresh |
| `autovacuum_max_workers` | 5-10 | Default 3 may not keep up with heavy write workloads |
| `autovacuum_vacuum_cost_delay` | 2-10 (ms) | Lower = more aggressive vacuum but more I/O impact |
| `autovacuum_naptime` | 15-30 (seconds) | How often autovacuum checks for work; default 60s is fine for most workloads |

**Transaction ID wraparound prevention**: Monitor `age(datfrozenxid)` — if approaching 1 billion, autovacuum is not keeping up. Increase `autovacuum_max_workers` and lower `autovacuum_vacuum_cost_delay`.

## MySQL Parameters

### InnoDB Buffer Pool

| Parameter | Recommended Value | Notes |
|---|---|---|
| `innodb_buffer_pool_size` | 75% of instance memory | Aurora auto-tunes this; only set on RDS |
| `innodb_buffer_pool_instances` | 8-16 | Reduces contention on the buffer pool mutex; set to 8 for <64 GiB, 16 for larger |
| `innodb_buffer_pool_dump_at_shutdown` | `ON` | Warm cache on restart |
| `innodb_buffer_pool_load_at_startup` | `ON` | Pair with dump_at_shutdown |

### Connections and Threads

| Parameter | Recommended Value | Notes |
|---|---|---|
| `max_connections` | Based on instance size (see instance-sizing.md) | Each connection reserves ~1-5 MB |
| `thread_cache_size` | 16-64 | Cache threads for reuse; avoids thread creation overhead |
| `innodb_thread_concurrency` | 0 (auto) | Let InnoDB manage; only set if you observe thread contention |
| `wait_timeout` | 300 (seconds) | Kill idle connections after 5 minutes |
| `interactive_timeout` | 300 (seconds) | Same as wait_timeout for interactive sessions |

### Logging and Slow Queries

| Parameter | Recommended Value | Notes |
|---|---|---|
| `slow_query_log` | `ON` | Must be enabled to capture slow queries |
| `long_query_time` | 1 (second) | Queries taking >1s are logged; tighten to 0.5s as needed |
| `log_queries_not_using_indexes` | `ON` | Catch full table scans |
| `performance_schema` | `ON` | Essential for troubleshooting; ~5% overhead |
| `general_log` | `OFF` | Never enable in production — massive I/O and storage impact |

### InnoDB I/O and Durability

| Parameter | Recommended Value | Notes |
|---|---|---|
| `innodb_io_capacity` | 3000 (gp3) or 10000 (io2) | Match to provisioned IOPS |
| `innodb_io_capacity_max` | 6000 (gp3) or 20000 (io2) | 2x of innodb_io_capacity |
| `innodb_flush_log_at_trx_commit` | 1 (default) | Full ACID; set to 2 only for non-critical data where slight data loss on crash is acceptable |
| `sync_binlog` | 1 (default) | Sync binary log on each commit; 0 is faster but risks data loss |

### Replication (RDS Read Replicas)

| Parameter | Recommended Value | Notes |
|---|---|---|
| `binlog_format` | `ROW` | Required for RDS replication; `STATEMENT` causes inconsistencies |
| `binlog_row_image` | `MINIMAL` | Reduces replication traffic; only log changed columns |
| `replica_parallel_workers` | 4-16 | Parallel replication on read replicas; reduces replica lag |
| `replica_preserve_commit_order` | `ON` | Maintain commit order on replicas |

## Aurora-Specific Parameters

Aurora manages many parameters automatically. Avoid overriding these unless there is a specific, measured need:

- `shared_buffers` / `innodb_buffer_pool_size` — Aurora manages buffer allocation
- WAL/redo log settings — Aurora's distributed storage handles this
- Checkpoint settings — Aurora's storage layer handles persistence

### Aurora Parameters Worth Tuning

| Parameter | Engine | Recommended | Notes |
|---|---|---|---|
| `aurora_parallel_query` | MySQL | `ON` for analytical queries | Offloads query processing to storage layer |
| `apg_plan_mgmt.use_plan_baselines` | PostgreSQL | `ON` for plan stability | Aurora Query Plan Management prevents plan regressions |
| `rds.force_ssl` | PostgreSQL | 1 | Enforce TLS for all connections |
| `require_secure_transport` | MySQL | `ON` | Enforce TLS for all connections |

## Applying Parameter Changes

### Dynamic Parameters (No Reboot Required)
Apply immediately with `modify-db-parameter-group` or `modify-db-cluster-parameter-group`.

Common dynamic parameters: `max_connections`, `work_mem`, `log_min_duration_statement`, `slow_query_log`, `long_query_time`

### Static Parameters (Reboot Required)
Change takes effect after the next reboot or during the maintenance window.

Common static parameters: `shared_buffers`, `max_worker_processes`, `innodb_buffer_pool_size`

### Safe Change Process
1. Change parameters in staging, monitor for 24-48 hours
2. For production: use blue/green deployment for static parameters to minimize downtime
3. For dynamic parameters: apply during low-traffic periods and monitor immediately
4. Always record parameter changes and rationale — use parameter group descriptions or tags
