# PromQL Query Patterns for DSQL Diagnostics

Reusable PromQL templates for diagnosing Aurora DSQL via `db.active_sessions.avg`. Replace `CLUSTER_ID` with the actual `@resource.aws.auroradsql.cluster_id` value.

**Important:** The `get_promql_label_values` tool requires a `match` parameter (series selector) to find DSQL metrics. Without it, queries may return empty results. Always include a match filter when discovering labels.

**Running the templates.** The calls below are CloudWatch MCP server tools. Without that server
(see Prerequisites in [workflow.md](workflow.md)), give the user the string inside `query='...'`
to run in [CloudWatch Query Studio](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-PromQL-QueryStudio.html)
(PromQL, Editor mode) with the time picker set to the `start`/`end` window, and ask them to paste
the table view. Query Studio evaluates a `time=` template at every step of the range, so set the
picker to end at `time`, ask for the values with their timestamps, and use only those at the last
timestamp — `topk` is applied at each step, so series without a value there are not in the result.
For discovery, run
`count by ("LABEL")({"db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})`
for each label below (one row per value; an unaggregated query returns at most 500 series).
CloudWatch commit and OCC metrics come from `aws cloudwatch get-metric-data` (see
[workflow.md Phase 4](workflow.md#phase-4-commit-and-occ-analysis)).

**`sum by`.** As in the AWS docs examples, these templates use `sum by`, which adds the AAS of
every series in a group. The workflow compares each group's share of total AAS, so use `sum by`
in every period being compared.

---

## Discovery Queries

> `get_promql_label_values` defaults to a window ending "now". For a paused, sporadic, or
> lightly-used cluster whose most recent data is older than that default, it returns an empty
> list even though the cluster and labels exist. When the data you care about is not recent,
> **also pass explicit `start`/`end` RFC 3339 timestamps** (as shown in the first template
> below) covering the period you intend to analyze — an empty result then means "no data in
> that window", not "no such cluster/label".

### List available clusters

```promql
get_promql_label_values(
  label_name="@resource.aws.auroradsql.cluster_id",
  match=["{__name__=\"db.active_sessions.avg\"}"],
  start="WINDOW_START", end="WINDOW_END"
)
```

### List wait events on a cluster

```promql
get_promql_label_values(
  label_name="db.wait.event",
  match=["{__name__=\"db.active_sessions.avg\", \"@resource.aws.auroradsql.cluster_id\"=\"CLUSTER_ID\"}"],
  start="WINDOW_START", end="WINDOW_END"
)
```

### List applications connecting

```promql
get_promql_label_values(
  label_name="application.name",
  match=["{__name__=\"db.active_sessions.avg\", \"@resource.aws.auroradsql.cluster_id\"=\"CLUSTER_ID\"}"],
  start="WINDOW_START", end="WINDOW_END"
)
```

### List IAM roles connecting

```promql
get_promql_label_values(
  label_name="aws.auroradsql.session.role.arn",
  match=["{__name__=\"db.active_sessions.avg\", \"@resource.aws.auroradsql.cluster_id\"=\"CLUSTER_ID\"}"],
  start="WINDOW_START", end="WINDOW_END"
)
```

---

## Instant Queries

These return the latest one-minute sample, evaluated at "now" — use them for the current state.
For a period, wrap the selector in `sum_over_time(...[WINDOW])`, divide by the window's minutes,
and pass `time` as the window's end. `topk` results come back unordered, so sort by value.

### Total AAS

```promql
execute_promql_query(query='sum({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})')
```

### AAS by wait event

```promql
execute_promql_query(query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})')
```

### Top 5 SQL by AAS

```promql
execute_promql_query(query='topk(5, sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}))')
```

### Top 5 SQL for a specific wait event

```promql
execute_promql_query(query='topk(5, sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID", "db.wait.event"="WAIT_EVENT"}))')
```

### Top 5 IAM roles

```promql
execute_promql_query(query='topk(5, sum by ("aws.auroradsql.session.role.arn")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}))')
```

### Top 5 applications

```promql
execute_promql_query(query='topk(5, sum by ("application.name")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}))')
```

### AAS for a specific query ID

```promql
execute_promql_query(query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID", "db.query.id"="QUERY_ID"})')
```

### Cross-cluster comparison

```promql
execute_promql_query(query='sum by ("@resource.aws.auroradsql.cluster_id")({__name__="db.active_sessions.avg"})')
```

---

## Range Queries

**Step guidelines** (SHOULD, matching workflow.md): 60s (< 1h), 300s (1–6h), 900s (6–24h), 3600s (> 24h).

**MUST** (except for idle detection, which reads only gaps) wrap the selector in
`sum_over_time(...[STEP])` and divide by the step's minutes —
`[1m]` for `step="60s"`, `[5m]` and `/ 5` for `step="300s"`. A plain selector repeats a series'
last sample for up to 5 minutes, overcounting sporadic queries and wait events, and at longer
steps reads only one minute per step.

Every `start`, `end` and `time` value in this file **MUST** be a concrete RFC 3339
timestamp — e.g. `2026-07-13T15:00:00Z` — not `NOW`-relative expressions, which the API rejects.
Compute the window first (e.g. `date -u -v-1H +%Y-%m-%dT%H:%M:%SZ`), then substitute.

### AAS by wait event over time

```promql
execute_promql_range_query(
  query='sum by ("db.wait.event")(sum_over_time({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}[1m]))',
  start="START_TIME", end="END_TIME", step="60s"
)
```

### Total AAS over time

```promql
execute_promql_range_query(
  query='sum(sum_over_time({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}[1m]))',
  start="START_TIME", end="END_TIME", step="60s"
)
```

### Top SQL over time

```promql
execute_promql_range_query(
  query='topk(5, sum by ("db.query.normalized_text", "db.query.id")(sum_over_time({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}[5m])) / 5)',
  start="START_TIME", end="END_TIME", step="300s"
)
```

### Commit wait trend

```promql
execute_promql_range_query(
  query='sum(sum_over_time({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID", "db.wait.event"="Commit"}[1m]))',
  start="START_TIME", end="END_TIME", step="60s"
)
```

---

## Temporal Comparison Patterns

### Current hour vs same hour yesterday vs same hour last week

Use the Phase 1 calls in [workflow.md](workflow.md#phase-1-discovery-and-baseline-comparison):
one instant query at each window's end, then the current hour in 10-minute chunks.

### Deployment regression detection

```promql
# Compare wait event distribution before and after deploy
execute_promql_range_query(
  query='sum by ("db.wait.event")(sum_over_time({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}[1m]))',
  start="BEFORE_DEPLOY", end="AFTER_DEPLOY", step="60s"
)
```

---

## Diagnostic Scenarios

### Has the cluster's behavior changed?

Compare the wait event distribution across temporal baselines. Flag any wait event where
the proportion of total AAS changed by >30% vs either baseline.

### Which workload drives an anomaly?

```promql
execute_promql_query(
  query='sum by ("aws.auroradsql.session.role.arn", "db.wait.event")(sum_over_time({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}[1h])) / 60',
  time="WINDOW_END"
)
```

### Commit analysis — volume vs conflicts

Run the [Commit wait trend](#commit-wait-trend) query, and for `TotalTransactions` and
`OccConflicts` the batched `get_metric_data` call (or AWS CLI equivalent) in
[workflow.md Phase 4](workflow.md#phase-4-commit-and-occ-analysis).

### SequentialScanRead growth — identify query

Run once at the window's end and once at the baseline's end, then compare.

```promql
execute_promql_query(
  query='topk(5, sum by ("db.query.normalized_text", "db.query.id")(sum_over_time({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID", "db.wait.event"="SequentialScanRead"}[1h])) / 60)',
  time="WINDOW_END"
)
```

### Client-side bottleneck (idle in transaction)

```promql
execute_promql_query(
  query='sum by ("application.name", "aws.auroradsql.session.role.arn")(sum_over_time({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID", "db.wait.event"="ClientRead"}[1h])) / 60',
  time="WINDOW_END"
)
```

### Idle or sporadic cluster detection

```promql
# Look for gaps in the time series — missing timestamps indicate no active sessions.
# start/end MUST be concrete RFC 3339 timestamps (not NOW-relative); compute a trailing
# 24h window first, then substitute.
execute_promql_range_query(
  query='sum({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="WINDOW_START", end="WINDOW_END", step="300s"
)
```
