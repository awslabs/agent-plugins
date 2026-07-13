# DSQL System Diagnostics

Diagnose Aurora DSQL cluster performance by querying Active Average Sessions (AAS) via PromQL and detecting temporal anomalies in wait event distribution. This skill **observes** via CloudWatch — it identifies which queries and workloads changed, then hands them to Workflow 9 (`EXPLAIN ANALYZE`) for per-query root cause. It does not itself diagnose scan types, index state, or query plans.

**Key capabilities:**

- Temporal trend analysis of AAS via `db.active_sessions.avg` metric
- Wait event distribution shift detection
- Top-SQL regression identification (new or growing queries)
- Workload attribution (application and IAM role changes)
- Commit volume vs OCC conflict analysis
- Handoff to Workflow 9 for per-query investigation

**Important principles:**

- There is no upper bound to AAS in DSQL — absolute values are not inherently problematic
- What matters is **change over time**: shifts in wait event distribution, new queries appearing, or existing queries consuming disproportionately more time
- This skill observes via CloudWatch only — it does **not** recommend schema changes, indexing strategies, or query rewrites. Those require live database access via Workflow 9.
- **A `db.wait.event` label is not an EXPLAIN node type.** It reports _where a session spent time_, not the query plan. You **MUST NOT** infer a scan type ("full scan", "Seq Scan"), an index state (missing / still building / unused), or any per-query root cause from a wait event. In particular, `SequentialScanRead` is a storage-layer range read that accumulates AAS under high concurrency or call frequency — it is **not** evidence of a full table scan or a missing index. Only Workflow 9 (`EXPLAIN ANALYZE`) can establish scan type, index usage, or root cause. A fast, well-indexed query run by thousands of concurrent sessions produces high AAS on read wait events; this is expected, not a defect.

**PromQL syntax rules:**

- Label names containing `.` or `@` **MUST** be quoted in selectors: `"@resource.aws.auroradsql.cluster_id"="value"`
- The `get_promql_label_values` tool **MUST** include a `match` parameter to return results — calls without match return empty
- Use `{__name__="db.active_sessions.avg", ...}` selector form for all queries

---

## Prerequisites

**MUST** have before starting:

1. A specific `cluster_id` to investigate — never proceed without one. Ask the user if not provided.
2. The CloudWatch MCP server (`awslabs.cloudwatch-mcp-server`) enabled and configured with PromQL access in the **same region** as the DSQL cluster. See [mcp-setup.md](../../mcp/mcp-setup.md#cloudwatch-mcp-server-system-diagnostics--workflow-12) for how to enable it, the region requirement, PromQL-enabled regions, and the required session restart. If its PromQL tools are unavailable, resolve that before starting rather than working around it — see Error Handling below.
3. The `aurora-dsql` MCP server configured for the target cluster — not used by this workflow itself, but required for the **Workflow 9** handoff (`EXPLAIN ANALYZE`) that per-query root cause is deferred to

**If the PromQL tools are unavailable** (e.g. `execute_promql_range_query` / `get_promql_label_values` are missing, or a call returns "No such tool available"): the diagnostic cannot run, and there is no substitute — AAS is only readable through these tools, so do not fall back to the AWS CLI, standard CloudWatch metrics, or fabricated numbers. The usual cause is that the CloudWatch server is disabled, misconfigured, or was enabled after this session started (its tools only register at session start). **Tell the user to enable/fix it per [mcp-setup.md](../../mcp/mcp-setup.md#cloudwatch-mcp-server-system-diagnostics--workflow-12) and then restart the session**, since a mid-session enable will show as "Connected" yet still expose no callable tools until restart. Report this as the blocker and the fix, rather than reporting only that data is missing.

---

## Reference Files

Load these sibling files as needed:

### [wait-events.md](wait-events.md)

**When:** ALWAYS load when interpreting AAS results
**Contains:** DSQL wait events with canonical descriptions and investigation guidance

### [promql-patterns.md](promql-patterns.md)

**When:** Load when constructing PromQL queries
**Contains:** Reusable PromQL query templates for all diagnostic phases

---

## Core Concept: Active Average Sessions (AAS)

The primary metric is `db.active_sessions.avg` — the average number of sessions actively executing or waiting at a given instant.

**Normalized SQL and AAS interpretation:** All SQL in the metric is normalized (parameterized). The `db.query.normalized_text` label groups all executions of the same query shape. A query with high AAS indicates it is executing frequently and/or concurrently across many sessions. A single slow query can only contribute at most 1 AAS — high AAS always means high concurrency or high call frequency, not a single slow execution. Neither this skill nor the `dsql` skill can currently distinguish frequency from per-execution cost; this will be possible in a future release that publishes per-SQL execution statistics via PromQL.

| Label                                 | Purpose                                                        |
| ------------------------------------- | -------------------------------------------------------------- |
| `db.wait.event`                       | Which wait the session is in (OnCpu, ClientRead, Commit, etc.) |
| `db.query.normalized_text`            | SQL fingerprint — groups identical query shapes                |
| `db.query.id`                         | Correlates with DSQL `EXPLAIN` Query Identifier                |
| `application.name`                    | Client application identifier                                  |
| `aws.auroradsql.session.role.arn`     | IAM role used for the connection                               |
| `db.session.state`                    | Session state (active, idle in transaction)                    |
| `@resource.aws.auroradsql.cluster_id` | Cluster identifier for filtering                               |
| `@resource.cloud.resource_id`         | Full cluster ARN                                               |

---

## Diagnostic Procedure

**MUST** execute ALL phases below in order. Do not stop at the first finding — complete the full sweep before presenting results.

### Phase 1: Discovery and Baseline Comparison

**Goal:** Establish whether the cluster's wait event distribution has changed.

**Steps:**

1. Confirm you have a specific `cluster_id` — do not proceed without one
2. Verify the cluster exists by calling `get_promql_label_values` with a match filter **and an explicit `start`/`end` window covering the period you intend to analyze** (see [promql-patterns.md](promql-patterns.md)). Label-value and series lookups default to a window ending "now"; if the cluster's most recent data is older than that default (for example, a lightly-used or paused cluster), the call returns an empty list even though the cluster exists. An empty result here means "no data in that window," not "no such cluster" — widen or shift the window before concluding the cluster is missing.
3. Query AAS by `db.wait.event` for the **current hour** in 10-minute chunks (step=60s)
4. Query AAS by `db.wait.event` for the **same hour yesterday** (baseline 1)
5. Query AAS by `db.wait.event` for the **same hour last week** (baseline 2)
6. Compute the distribution (% each wait event contributes to total AAS) for each period
7. Flag any wait event where the proportion changed by >30% vs either baseline
8. Compare 10-minute chunks within the current hour against each other to detect recent intra-hour shifts

**Critical rules:**

- **MUST** filter by cluster using `"@resource.aws.auroradsql.cluster_id"` in all queries
- **MUST** quote label names that contain `.` or `@` in PromQL selectors
- **MUST** use the `match` parameter with `get_promql_label_values` — calls without match return empty. When the data you care about is not recent, **also** pass an explicit `start`/`end`, since these lookups default to a window ending "now" and will otherwise miss older data
- **MUST** compare against temporal baselines — do NOT report absolute AAS values as inherently problematic (the >30%-share-change trigger is defined in Step 7)

**Example** (`start`/`end` **MUST** be concrete RFC 3339 timestamps — the API rejects relative
expressions like `NOW-1h`. Compute the three windows first, e.g. with
`date -u -v-1H +%Y-%m-%dT%H:%M:%SZ` on macOS or `date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ`
on Linux, then substitute. The comments below show which window each call covers):

```promql
# Current hour (e.g. start=2026-07-13T15:00:00Z, end=2026-07-13T16:00:00Z)
execute_promql_range_query(
  query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="CURRENT_HOUR_START", end="CURRENT_HOUR_END", step="60s"
)

# Same hour yesterday (current window minus 24h)
execute_promql_range_query(
  query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="YESTERDAY_HOUR_START", end="YESTERDAY_HOUR_END", step="60s"
)

# Same hour last week (current window minus 168h)
execute_promql_range_query(
  query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="LAST_WEEK_HOUR_START", end="LAST_WEEK_HOUR_END", step="60s"
)
```

---

### Phase 2: Top-SQL Regression Detection

**Goal:** Identify SQL statements that have become more prominent. Run regardless of Phase 1 findings.

**Steps:**

1. Query top-N SQL by AAS for the current period
2. Query top-N SQL for the same period last week
3. Identify queries that are **new** in the top-N or have **grown** significantly vs baseline
4. For each regressed query, note which `db.wait.event` dominates

**Critical rules:**

- **MUST** include `db.query.id` in grouping — stable identifier for Workflow 9 handoff
- **MUST** compare top-N across periods — a query being #1 is only notable if it wasn't before
- **MUST NOT** recommend indexing or schema changes — hand off to Workflow 9

**Example:**

```promql
# Top 5 SQL current
execute_promql_query(query='topk(5, sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}))')

# Top 5 SQL with wait event
execute_promql_query(query='topk(10, sum by ("db.query.normalized_text", "db.query.id", "db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}))')
```

---

### Phase 3: Workload Attribution

**Goal:** Identify which applications and IAM roles are driving changes. Run regardless of other findings.

**Steps:**

1. Query top applications and IAM roles for current period
2. Compare against baseline — report only changes, not static dominance
3. For applications or roles that have grown, break down by `db.wait.event`

**Critical rules:**

- **MUST** compare against baseline — an application being dominant is only noteworthy if it has changed
- Report the delta: "application X increased from 30% to 55% of total AAS"

**Example:**

```promql
# Top IAM roles
execute_promql_query(query='topk(5, sum by ("aws.auroradsql.session.role.arn")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}))')

# Top applications
execute_promql_query(query='topk(5, sum by ("application.name")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}))')
```

---

### Phase 4: Commit and OCC Analysis

**Goal:** Determine whether commit behavior has changed. Run regardless of other findings.

**Steps:**

1. Check Commit wait event's share vs baseline (from Phase 1 data)
2. If Commit share changed, query standard CloudWatch metrics:
   - `AWS/AuroraDSQL` namespace, dimension `ClusterId`
   - `TotalTransactions` — commit rate
   - `OccConflicts` — conflict rate
3. Compare ratios:
   - OccConflicts growing faster than TotalTransactions → conflict problem
   - TotalTransactions growing proportionally → legitimate load
   - Commit AAS up but TotalTransactions flat → transactions taking longer

**Example:**

```
# MUST pass start_time/end_time covering the SAME window as the Phase 1 baselines being
# compared — get_metric_data defaults to only the last 3 hours, which will not line up with
# the yesterday / last-week AAS windows. Use concrete RFC 3339 timestamps (no NOW-relative form).
get_metric_data(
  namespace="AWS/AuroraDSQL",
  metric_name="TotalTransactions",
  dimensions=[{name: "ClusterId", value: "CLUSTER_ID"}],
  statistic="Sum",
  start_time="WINDOW_START", end_time="WINDOW_END"
)

get_metric_data(
  namespace="AWS/AuroraDSQL",
  metric_name="OccConflicts",
  dimensions=[{name: "ClusterId", value: "CLUSTER_ID"}],
  statistic="Sum",
  start_time="WINDOW_START", end_time="WINDOW_END"
)
```

---

### Phase 5: Inflection Point Detection

**Goal:** Pinpoint when the change occurred. Run when Phase 1 detects a shift vs last week.

**Steps:**

1. Query a 7-day range for the shifted wait event (3600s step)
2. Identify the inflection point — when did the distribution change?
3. Correlate with known events (deployments, traffic changes)

**Critical rules:**

- **SHOULD** use step: 60s (< 1h), 300s (1–6h), 900s (6–24h), 3600s (> 24h)
- **MUST** specify `start` and `end` in RFC 3339 format
- **MUST** keep each query's range at or under 7 days — split longer investigations

**Example:**

```promql
# Concrete RFC 3339 timestamps; keep the span just under 7 days so it stays within the tool's
# max-range limit (which counts any lookback). Substitute a recent window for your investigation.
execute_promql_range_query(
  query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="WINDOW_START", end="WINDOW_END",
  step="3600s"
)
```

---

## Presenting Results

After completing all phases, present a unified report covering:

1. **Distribution shift summary** — which wait events changed and by how much
2. **Top-SQL regression** — which queries are new or growing, with their dominant wait events
3. **Workload attribution** — which applications/roles changed their share
4. **Commit health** — volume vs conflict analysis (if CW metrics available)
5. **Timeline** — when the change occurred (if a shift was detected)
6. **Queries for investigation** — list of queries to hand off to Workflow 9

---

## Per-Query Investigation

When queries are identified as newly prominent or significantly grown, describe the observed anomaly and proceed to Workflow 9:

> "Query `{NORMALIZED_SQL}` (db.query.id: `{QUERY_ID}`) is using significantly more system time than it did {TIMEFRAME} ago. Its share of cluster AAS on `{WAIT_EVENT}` has grown from {OLD}% to {NEW}%."

The handoff **MUST** describe only what the metric shows — a query's share of a wait event changed vs baseline. It **MUST NOT** append a hypothesized cause (e.g. "because it is full-scanning", "the index is missing", "the plan regressed to a Seq Scan"). Scan type, index usage, and root cause are Workflow 9's _output_, not this handoff's input — stating them here pre-judges the investigation and is exactly the kind of guess this skill must not make.

Then proceed to Workflow 9 (Query Plan Explainability) for each identified query.

---

## Idle Cluster Detection

A cluster is idle when there is no AAS data for a period. Use a range query and look for gaps (missing timestamps) in the time series.

**Pattern: Sporadic workload** — periods of no data interspersed with periods of AAS > 0 indicate a cluster performing scheduled or batch work.

```promql
# start/end MUST be concrete RFC 3339 timestamps (not NOW-relative). For a trailing 24h window,
# compute end = now and start = now - 24h first, then substitute.
execute_promql_range_query(
  query='sum({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="WINDOW_START", end="WINDOW_END", step="300s"
)
```

---

## Error Handling

| Situation                                                 | Action                                                                                                                                                                                                                                                                                                                                |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No cluster_id provided                                    | Ask the user — never proceed without a specific cluster                                                                                                                                                                                                                                                                               |
| PromQL tools not callable (e.g. "No such tool available") | The CloudWatch server is not enabled, is misconfigured, or was enabled after the session started. Enable/fix it per [mcp-setup.md](../../mcp/mcp-setup.md#cloudwatch-mcp-server-system-diagnostics--workflow-12), then **restart the session** — tools are registered at startup. Do not fall back to guessing or to unrelated tools. |
| No series / empty label values                            | Confirm the `match` selector, then widen or shift the `start`/`end` window — these lookups default to "now" and miss older data. Only after that, suspect a wrong cluster ID or region.                                                                                                                                               |
| Empty result (no data)                                    | Cluster is idle for that period. Widen time window.                                                                                                                                                                                                                                                                                   |
| `db.query.id` missing                                     | Not all queries emit it. Filter by `db.query.normalized_text` instead.                                                                                                                                                                                                                                                                |
| PromQL timeout                                            | Reduce cardinality — fewer labels or shorter time range.                                                                                                                                                                                                                                                                              |
| Range > 7 days                                            | Split into multiple 7-day range queries.                                                                                                                                                                                                                                                                                              |
