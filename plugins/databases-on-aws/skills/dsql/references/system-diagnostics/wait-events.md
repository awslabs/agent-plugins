# DSQL Wait Events Reference

Aurora DSQL exposes wait events via the `db.wait.event` label on `db.active_sessions.avg`. Each indicates where sessions spend time.

> **Observe-only guardrail.** A wait event tells you _where_ time was spent, not _why_. The "Possible causes" lists below are **candidates to confirm in Workflow 9 (`EXPLAIN ANALYZE`)** — they are **not** findings you may report from CloudWatch data alone. In particular, a read/IO wait event (`SequentialScanRead`, `ScatteredBatchRead`, `SingleRead`) does **not** establish a full/sequential scan, a missing index, or a plan regression: the same label appears for a fast, fully-indexed query executed by many concurrent sessions. Never restate a wait-event label as a scan type or an index state — that is Workflow 9's output. See the observe-only principles in [workflow.md](workflow.md).
>
> **Query snippet convention.** The PromQL snippets in each section below are illustrative and abbreviated: the `...` inside a selector stands for the mandatory `"@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"` filter (and any time window), which you **MUST** supply. Do not paste a snippet with a literal `...` — substitute the cluster filter first. Full, runnable templates are in [promql-patterns.md](promql-patterns.md).

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
| StartTransaction      | Transaction | Waiting for distributed transaction start                                                                  |
| PgSleep               | Application | Session issued `pg_sleep()` and is waiting for the sleep period to complete                                |

---

## OnCpu

Actively processing in the Query Processor (QP), not waiting for any other resource.

**Possible causes** (candidates to confirm in Workflow 9 — see the observe-only guardrail above):

- Complex plans with nested loops or expensive expressions
- High-frequency short queries from many connections
- SequentialScanRead co-occurrence (CPU time processing scanned tuples)

**Observe-only steps:**

1. Identify top SQL: `topk(5, sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "db.wait.event"="OnCpu", ...}))`
2. Compare against baseline — identify which queries have grown
3. Hand the identified query off to Workflow 9 for `EXPLAIN ANALYZE` analysis

---

## ClientRead

QP is waiting for the next request. This is only reported when the QP has an active transaction (idle in transaction).

**Possible causes** (candidates to confirm — see the observe-only guardrail above):

- Client has an open transaction but is not sending the next query (idle in transaction)
- Application doing work between queries without closing the transaction
- Missing `COMMIT`/`ROLLBACK` after error paths
- Connection pool returning connections with open transactions
- Network latency (cross-region, VPN)

**Observe-only steps:**

1. Identify role/app: `sum by ("aws.auroradsql.session.role.arn", "application.name")({__name__="db.active_sessions.avg", "db.wait.event"="ClientRead", ...})`
2. Compare against baseline — which role/app grew its ClientRead share?
3. Report the observed attribution to the user. This is a client-side / application pattern (idle-in-transaction, pool configuration, cross-region latency) rather than a query-plan issue — surface the candidate causes above for the application owner to confirm; do not prescribe application, pool, or GUC changes from CloudWatch data alone.

---

## ClientWrite

QP is sending data to the application.

**Possible causes** (candidates to confirm in Workflow 9 — see the observe-only guardrail above):

- Client slow processing result sets
- Large result sets saturating network buffers
- Client-side GC pauses or I/O blocking

**Observe-only steps:**

1. Identify app: `sum by ("application.name")({__name__="db.active_sessions.avg", "db.wait.event"="ClientWrite", ...})`
2. Check client-side factors this skill can observe: network throughput and TCP buffers, client GC/IO pauses
3. If a large result set is suspected, hand the query off to Workflow 9 — reducing result size (`LIMIT` / pagination) is a query rewrite, and query rewrites are Workflow 9's responsibility, not this skill's

---

## SequentialScanRead

QP has issued a scan of a contiguous range of tuples. This is a storage-layer range read — it is **not** synonymous with a `Seq Scan` / Full Scan plan node, and high AAS here most often reflects high concurrency or call frequency rather than a slow query. An `Index Only Scan` on a well-chosen key still issues contiguous range reads and surfaces under this event.

**Possible causes** (candidates to confirm in Workflow 9 — see the observe-only guardrail above):

- Many concurrent/high-frequency executions of an efficient indexed query (most common; not a defect)
- A missing index on the WHERE clause — **only Workflow 9's `EXPLAIN` can confirm this; never state it from AAS**
- A plan choosing a scan after statistics changed — **likewise a Workflow 9 determination, not an AAS finding**
- Intentional full-table aggregation

**Observe-only steps:**

1. Identify the query: `topk(3, sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "db.wait.event"="SequentialScanRead", ...}))`
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

1. Identify query: `topk(3, sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "db.wait.event"="ScatteredBatchRead", ...}))`
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

1. Identify query: `topk(5, sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "db.wait.event"="SingleRead", ...}))`
2. Check if SingleRead AAS has grown vs baseline — indicates increased call frequency
3. Hand the identified query off to Workflow 9 for query-level diagnostics

---

## FkExistenceCheck

Storage reads to validate foreign key existence.

**Possible causes** (candidates to confirm in Workflow 9 — see the observe-only guardrail above):

- High-throughput INSERT/UPDATE on child tables with foreign key references
- Parent table lookups becoming a bottleneck under concurrent writes

**Observe-only steps:**

1. Identify query: `sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "db.wait.event"="FkExistenceCheck", ...})`
2. Check if insert volume has increased using the `TotalTransactions` CW metric (namespace `AWS/AuroraDSQL`, `statistic="Sum"` — it is a cumulative counter)
3. Hand the identified query off to Workflow 9 for query-level diagnostics

---

## UniqueConstraintCheck

Storage reads to validate unique key constraints for non-primary columns.

**Possible causes** (candidates to confirm in Workflow 9 — see the observe-only guardrail above):

- High-throughput INSERT on a table with unique constraints
- Large batch INSERTs forcing many uniqueness checks
- Conflict-heavy upsert patterns (`INSERT ... ON CONFLICT`)

**Observe-only steps:**

1. Identify query: `sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "db.wait.event"="UniqueConstraintCheck", ...})`
2. Hand the identified query off to Workflow 9 for query-level diagnostics

---

## Commit

Commit process has begun, and QP is waiting for a response.

**Possible causes** (candidates to confirm in Workflow 9 — see the observe-only guardrail above):

- Increased transaction volume (legitimate load growth)
- Increased OCC (optimistic concurrency control) conflicts (write-write contention)
- Large transactions modifying many rows (more commit coordination)

**Note:** All Commit waits are associated with the `COMMIT` statement itself — individual SQL statements do not wait on Commit. Therefore, `db.query.normalized_text` grouping is not useful for identifying which writes cause commit contention.

**Observe-only steps — distinguish volume from conflicts:**

1. Query standard CloudWatch metrics: `AWS/AuroraDSQL` namespace, `ClusterId` dimension, `statistic="Sum"`, with `start_time`/`end_time` covering the window under investigation
2. Compare `TotalTransactions` (commit rate) and `OccConflicts` (conflict rate) over the same period:
   - If OccConflicts grows faster than TotalTransactions → conflict-dominated (report this observation)
   - If TotalTransactions grows proportionally to Commit AAS → legitimate load growth (report this observation)
3. If OCC conflicts are the growing component, hand off to Workflow 9 for transaction-pattern analysis and conflict mitigation — do not prescribe schema or transaction changes from CloudWatch data alone

---

## StartTransaction

Waiting for distributed transaction start — the time a session spends while DSQL coordinates the operations needed to begin a new transaction.

**Possible causes** (candidates to confirm — see the observe-only guardrail above):

- High transaction frequency (many short transactions, each paying the fixed start cost)
- Workload shift toward more fine-grained transactions vs fewer large ones

This is internal DSQL infrastructure overhead; there are no user-tunable parameters that affect the per-transaction start cost itself. Its value in diagnostics is purely **proportional** — a growing share indicates a shift in workload pattern.

**Observe-only steps:**

1. Note whether StartTransaction's proportion of total AAS has changed by >30% vs the temporal baseline: `sum by ("db.wait.event")({__name__="db.active_sessions.avg", "db.wait.event"="StartTransaction", ...})`
2. If the proportion grew significantly, it likely reflects an increase in transaction frequency — correlate with the `TotalTransactions` CW metric (namespace `AWS/AuroraDSQL`, `statistic="Sum"` — it is a cumulative counter) to confirm
3. Report the observation — do not recommend transaction batching, connection pooling changes, or other remediations from CloudWatch data alone. This is fixed internal overhead with no user-facing tuning knob.

---

## PgSleep

Session issued `pg_sleep()` and is waiting for the sleep period to complete.

**Possible causes** (candidates to confirm — see the observe-only guardrail above):

- Application-level polling or throttling
- Health-check queries with built-in delay
- Intentional rate limiting

**Observe-only steps:**

1. Attribute by app: `sum by ("application.name")({__name__="db.active_sessions.avg", "db.wait.event"="PgSleep", ...})`
2. Report the attribution to the user. PgSleep is almost always an intentional application choice (`pg_sleep()` is explicit in the client code), so surface which application is driving it for the owner to confirm — do not recommend removing the call or relocating the delay from CloudWatch data alone.
