# PromQL Query Patterns for DSQL Diagnostics

Reusable PromQL templates for diagnosing Aurora DSQL via `db.active_sessions.avg`. Replace `CLUSTER_ID` with the actual `@resource.aws.auroradsql.cluster_id` value.

**Important:** The `get_promql_label_values` tool requires a `match` parameter (series selector) to find DSQL metrics. Without it, queries may return empty results. Always include a match filter when discovering labels.

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

`START_TIME`/`END_TIME` (and the `*_HOUR_START` placeholders below) **MUST** be concrete RFC 3339
timestamps — e.g. `2026-07-13T15:00:00Z` — not `NOW`-relative expressions, which the API rejects.
Compute the window first (e.g. `date -u -v-1H +%Y-%m-%dT%H:%M:%SZ`), then substitute.

### AAS by wait event over time

```promql
execute_promql_range_query(
  query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="START_TIME", end="END_TIME", step="60s"
)
```

### Total AAS over time

```promql
execute_promql_range_query(
  query='sum({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="START_TIME", end="END_TIME", step="60s"
)
```

### Top SQL over time

```promql
execute_promql_range_query(
  query='topk(5, sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"}))',
  start="START_TIME", end="END_TIME", step="300s"
)
```

### Commit wait trend

```promql
execute_promql_range_query(
  query='sum({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID", "db.wait.event"="Commit"})',
  start="START_TIME", end="END_TIME", step="60s"
)
```

---

## Temporal Comparison Patterns

### Current hour vs same hour yesterday vs same hour last week

```promql
# Current hour
execute_promql_range_query(
  query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="CURRENT_HOUR_START", end="CURRENT_HOUR_END", step="60s"
)

# Same hour yesterday (24h ago)
execute_promql_range_query(
  query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="YESTERDAY_HOUR_START", end="YESTERDAY_HOUR_END", step="60s"
)

# Same hour last week (168h ago)
execute_promql_range_query(
  query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
  start="LAST_WEEK_HOUR_START", end="LAST_WEEK_HOUR_END", step="60s"
)
```

### Deployment regression detection

```promql
# Compare wait event distribution before and after deploy
execute_promql_range_query(
  query='sum by ("db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})',
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
execute_promql_query(query='sum by ("aws.auroradsql.session.role.arn", "db.wait.event")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID"})')
```

### Commit analysis — volume vs conflicts

Use standard CloudWatch metrics alongside PromQL:

```
# PromQL: Commit wait AAS trend
execute_promql_range_query(
  query='sum({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID", "db.wait.event"="Commit"})',
  start="START_TIME", end="END_TIME", step="60s"
)

# CW Metrics: TotalTransactions and OccConflicts (detect conflict rate vs volume)
# MUST use namespace="AWS/AuroraDSQL" (bare "AuroraDSQL" returns no data), statistic="Sum"
# (these are cumulative counters — the default AVG reports ~1.0 per sample), and start_time/
# end_time matching the AAS window under investigation (get_metric_data otherwise defaults to
# the last 3 hours, which will not align with the multi-day baselines this analysis compares).
get_metric_data(namespace="AWS/AuroraDSQL", metric_name="TotalTransactions", dimensions=[{name:"ClusterId", value:"CLUSTER_ID"}], statistic="Sum", start_time="START_TIME", end_time="END_TIME")
get_metric_data(namespace="AWS/AuroraDSQL", metric_name="OccConflicts", dimensions=[{name:"ClusterId", value:"CLUSTER_ID"}], statistic="Sum", start_time="START_TIME", end_time="END_TIME")
```

### SequentialScanRead growth — identify query

```promql
execute_promql_query(query='topk(5, sum by ("db.query.normalized_text", "db.query.id")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID", "db.wait.event"="SequentialScanRead"}))')
```

### Client-side bottleneck (idle in transaction)

```promql
execute_promql_query(query='sum by ("application.name", "aws.auroradsql.session.role.arn")({__name__="db.active_sessions.avg", "@resource.aws.auroradsql.cluster_id"="CLUSTER_ID", "db.wait.event"="ClientRead"})')
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
