# DSQL Wait Events Reference

Aurora DSQL exposes wait events via the `db.wait.event` label on `db.active_sessions.avg`. Each indicates where sessions spend time.

> **Observe-only guardrail.** A wait event tells you _where_ time was spent, not _why_. The "Possible causes" lists below are **candidates to confirm in Workflow 9 (`EXPLAIN ANALYZE`)** — they are **not** findings you may report from CloudWatch data alone. In particular, a read/IO wait event (`SequentialScanRead`, `ScatteredBatchRead`, `SingleRead`) does **not** establish a full/sequential scan, a missing index, or a plan regression: the same label appears for a fast, fully-indexed query executed by many concurrent sessions. Never restate a wait-event label as a scan type or an index state — that is Workflow 9's output. See the "Important principles" in [workflow.md](workflow.md).

---

## Summary

| Wait Event            | Category    | Description                                                                                                |
| --------------------- | ----------- | ---------------------------------------------------------------------------------------------------------- |
| OnCpu                 | Compute     | Actively processing in QP, not waiting for any other resource                                              |
| ClientRead            | Network     | QP is waiting for the next request (only reported when QP has an active transaction — idle in transaction) |
| ClientWrite           | Network     | QP is sending data to the application                                                                      |
| SequentialScanRead    | IO          | QP has issued a scan of a contiguous range of tuples                                                       |
| ScatteredBatchRead    | IO          | QP has issued one or more non-contiguous tuple reads                                                       |
| SingleRead            | IO          | QP is reading a tuple returned by a streamed storage operation                                             |
| FkExistenceCheck      | Validation  | Storage reads to validate foreign key existence                                                            |
| UniqueConstraintCheck | Validation  | Storage reads to validate unique key constraints for non-primary columns                                   |
| Commit                | Transaction | Commit process has begun, and QP is waiting for a response                                                 |
| PgSleep               | Application | Session issued `pg_sleep()` and is waiting for the sleep period to complete                                |

---

## OnCpu

Actively processing in the Query Processor (QP), not waiting for any other resource.

**Root causes:**

- Complex plans with nested loops or expensive expressions
- High-frequency short queries from many connections
- SequentialScanRead co-occurrence (CPU time processing scanned tuples)

**Remediation:**

1. Identify top SQL: `topk(5, sum by ("db.query.normalized_text", "db.query.id")(db.active_sessions.avg{"db.wait.event"="OnCpu", ...}))`
2. Compare against baseline — identify which queries have grown
3. Defer to `dsql` skill for EXPLAIN analysis

---

## ClientRead

QP is waiting for the next request. This is only reported when the QP has an active transaction (idle in transaction).

**Root causes:**

- Client has an open transaction but is not sending the next query (idle in transaction)
- Application doing work between queries without closing the transaction
- Missing `COMMIT`/`ROLLBACK` after error paths
- Connection pool returning connections with open transactions
- Network latency (cross-region, VPN)

**Remediation:**

1. Identify role/app: `sum by ("aws.auroradsql.session.role.arn", "application.name")(db.active_sessions.avg{"db.wait.event"="ClientRead", ...})`
2. Set `idle_in_transaction_session_timeout` to limit idle transaction duration
3. Fix application error-handling to always close transactions
4. Audit connection pool configuration — ensure pools issue RESET or DISCARD on return
5. Move compute closer to the cluster (same region/AZ) to reduce network latency

---

## ClientWrite

QP is sending data to the application.

**Root causes:**

- Client slow processing result sets
- Large result sets saturating network buffers
- Client-side GC pauses or I/O blocking

**Observe-only steps:**

1. Identify app: `sum by ("application.name")(db.active_sessions.avg{"db.wait.event"="ClientWrite", ...})`
2. Check client-side factors this skill can observe: network throughput and TCP buffers, client GC/IO pauses
3. If a large result set is suspected, hand the query off to Workflow 9 — reducing result size (`LIMIT` / pagination) is a query rewrite, and query rewrites are Workflow 9's responsibility, not this skill's

---

## SequentialScanRead

QP has issued a scan of a contiguous range of tuples. This is a storage-layer range read — it is **not** synonymous with a `Seq Scan` / Full Scan plan node, and high AAS here most often reflects high concurrency or call frequency rather than a slow query. An `Index Only Scan` on a well-chosen key still issues contiguous range reads and surfaces under this event.

**Possible causes** (candidates to confirm in Workflow 9 — see the observe-only guardrail above):

- Many concurrent/high-frequency executions of an efficient indexed query (most common; not a defect)
- Missing index for the WHERE clause
- Plan regression — index exists but planner chose a scan after statistics changed
- Intentional full-table aggregation

**Observe-only steps:**

1. Identify the query: `topk(3, sum by ("db.query.normalized_text", "db.query.id")(db.active_sessions.avg{"db.wait.event"="SequentialScanRead", ...}))`
2. Compare against the temporal baseline — has a specific query's share grown, and is the growth proportional to traffic?
3. Hand the identified query off to Workflow 9. **Do not** assert "full scan", "missing index", or "plan regression" — Workflow 9's `EXPLAIN ANALYZE` establishes which (if any) of the causes above is real.

---

## ScatteredBatchRead

QP has issued one or more non-contiguous tuple reads.

**Possible causes** (candidates to confirm in Workflow 9 — see the observe-only guardrail above):

- Query performing lookups across non-contiguous storage locations
- Secondary index lookup followed by wide data fetch
- Batch operations with keys spread across storage
- High concurrency/frequency of an otherwise efficient query

**Observe-only steps:**

1. Identify query: `topk(3, sum by ("db.query.normalized_text", "db.query.id")(db.active_sessions.avg{"db.wait.event"="ScatteredBatchRead", ...}))`
2. Compare against baseline — has a specific query's ScatteredBatchRead grown, and is it proportional to traffic?
3. Hand the identified query off to Workflow 9 for `EXPLAIN` analysis — do not assert a scan type or index state here

---

## SingleRead

QP is reading a tuple returned by a streamed storage operation.

**Possible causes** (candidates to confirm in Workflow 9 — see the observe-only guardrail above):

- A query called at very high frequency (each call is fast but volume accumulates AAS)
- ORM lazy-loading relationships triggering many individual lookups

**Note:** A single slow query only contributes 1 AAS at most. High AAS on SingleRead indicates many concurrent executions or high call frequency, not a single slow query. Because `db.query.normalized_text` groups all executions of the same query shape, a single-key lookup called thousands of times per second will appear as a high-AAS query.

**Observe-only steps:**

1. Identify query: `topk(5, sum by (db.query.normalized_text)(db.active_sessions.avg{"db.wait.event"="SingleRead", ...}))`
2. Check if SingleRead AAS has grown vs baseline — indicates increased call frequency
3. Hand the identified query off to Workflow 9 for query-level diagnostics

---

## FkExistenceCheck

Storage reads to validate foreign key existence.

**Root causes:**

- High-throughput INSERT/UPDATE on child tables with foreign key references
- Parent table lookups becoming a bottleneck under concurrent writes

**Remediation:**

1. Identify query: `sum by (db.query.normalized_text)(db.active_sessions.avg{"db.wait.event"="FkExistenceCheck", ...})`
2. Check if insert volume has increased using `TotalTransactions` CW metric
3. Defer to `dsql` skill for query-level diagnostics

---

## UniqueConstraintCheck

Storage reads to validate unique key constraints for non-primary columns.

**Root causes:**

- High-throughput INSERT on a table with unique constraints
- Large batch INSERTs forcing many uniqueness checks
- Conflict-heavy upsert patterns (`INSERT ... ON CONFLICT`)

**Remediation:**

1. Identify query: `sum by (db.query.normalized_text)(db.active_sessions.avg{"db.wait.event"="UniqueConstraintCheck", ...})`
2. Defer to `dsql` skill for query-level diagnostics

---

## Commit

Commit process has begun, and QP is waiting for a response.

**Root causes:**

- Increased transaction volume (legitimate load growth)
- Increased OCC (optimistic concurrency control) conflicts (write-write contention)
- Large transactions modifying many rows (more commit coordination)

**Note:** All Commit waits are associated with the `COMMIT` statement itself — individual SQL statements do not wait on Commit. Therefore, `db.query.normalized_text` grouping is not useful for identifying which writes cause commit contention.

**Diagnosis — distinguish volume from conflicts:**

- Query standard CloudWatch metrics: `AuroraDSQL` namespace, `ClusterId` dimension
- Compare `TotalTransactions` (commit rate) and `OccConflicts` (conflict rate) over the same period
- If OccConflicts grows faster than TotalTransactions → conflict problem
- If TotalTransactions grows proportionally to Commit AAS → legitimate load

**Remediation:**

1. Check if Commit AAS change is proportional to transaction volume via CW metrics
2. If OCC conflicts are growing, defer to `dsql` skill for transaction pattern analysis and conflict mitigation

---

## PgSleep

Session issued `pg_sleep()` and is waiting for the sleep period to complete.

**Root causes:**

- Application-level polling or throttling
- Health-check queries with built-in delay
- Intentional rate limiting

**Remediation:**

1. Verify intentional: `sum by ("application.name")(db.active_sessions.avg{"db.wait.event"="PgSleep", ...})`
2. If unintentional, remove the `pg_sleep()` call
3. If consuming too many connections, move the delay to the application layer
