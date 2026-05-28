# Data Loading with the DSQL Loader

Part of [DSQL Development Guide](development-guide.md).

The [DSQL Loader](https://github.com/aws-samples/aurora-dsql-loader) (`aurora-dsql-loader`)
is the recommended tool for bulk-loading CSV, TSV, or Parquet data into Aurora DSQL. This
page covers throughput expectations, resume and retry mechanics, conflict handling, and a
diagnostic decision tree for loads that come in slower than expected.

For installation and basic invocation, see [connectivity-tools.md](auth/connectivity-tools.md#data-loading-tools).

## Table of Contents

- [Fresh-vs-Warm Partition Behavior](#fresh-vs-warm-partition-behavior)
- [Resume and Retry Mechanics](#resume-and-retry-mechanics)
- [Conflict Handling](#conflict-handling---on-conflict-do-nothing)
- [CSV/TSV Header Handling](#csvtsv-header-handling)
- [Schema Inference Caveats](#schema-inference-caveats)
- [Index Count Affects Throughput](#index-count-affects-throughput)
- [Diagnostic Decision Tree](#diagnostic-decision-tree)

---

## Fresh-vs-Warm Partition Behavior

A DSQL table starts on a single partition. DSQL detects sustained write heat on a partition
and splits it (repeatedly) to keep latency in check. This is DSQL-side behavior — no client
tuning bypasses it.

Practical consequences for any loader run:

- A fresh / empty table absorbs roughly **3-4K rec/s** from a single client. Adding loader
  concurrency does not increase this; all writes serialize against the single partition.
- Aggregate write throughput grows as `partitions × ~3-4K rec/s` until the client saturates.
- Splits are driven by **sustained** write volume — a burst of 10K writes followed by silence
  drives few splits; 10-20 minutes of sustained pressure at the single-partition ceiling
  drives many.
- Random keys (e.g. UUIDs) spread heat across the partition key range. Monotonic / sequential
  keys concentrate heat on one partition, which delays effective parallelism.

**Why this matters:** users who watch a fresh-table load come in at 3K rec/s and assume
something is broken usually just need to keep the load running. Throughput accelerates as
DSQL splits the partition; the curve is sub-linear at first, then approximately linear once
several partitions exist.

If your workload is large and latency-sensitive, run a low-concurrency pre-pass against the
target table to drive splits before the formal load.

---

## Resume and Retry Mechanics

The loader writes a manifest tracking which internal chunks have been committed. On resume,
it restarts from the last committed chunk rather than from row 0. Three flags control this:

### `--manifest-dir <persistent-path>` (strongly recommended)

The default manifest directory is `/tmp`, which is **tmpfs on Amazon Linux 2023** and
several other modern Linux distributions. If the loader process dies — OOM, SIGKILL, host
reboot, or any unclean exit — the manifest evaporates with it and resume becomes impossible.

Always set this explicitly to a persistent path:

```bash
aurora-dsql-loader load \
  --endpoint your-cluster.dsql.us-east-1.on.aws \
  --source-uri data.csv \
  --table my_table \
  --manifest-dir /var/lib/dsql-loader/manifests
```

### `--resume-job-id <id>`

Re-runs continue from the last committed internal chunk. The job id is printed in the
loader's log on the line beginning `Starting load job:`. Capture it from the original run's
log to resume later:

```bash
aurora-dsql-loader load \
  --endpoint your-cluster.dsql.us-east-1.on.aws \
  --source-uri data.csv \
  --table my_table \
  --manifest-dir /var/lib/dsql-loader/manifests \
  --resume-job-id <job-id-from-log> \
  --keep-manifest
```

### `--keep-manifest`

Retains the manifest after a successful load. Useful for auditing or for resuming an
idempotent re-run on the same source.

---

## Conflict Handling: `--on-conflict do-nothing`

`--on-conflict do-nothing` silently skips rows whose primary key already exists in the
target table. This is safe **only when both** of the following hold:

1. The target table has a unique constraint (typically a primary key) on the conflict
   column.
2. The load is idempotent on re-runs — i.e. the same source row produces the same target row,
   so skipping a previously-loaded duplicate yields the same final state.

Common pitfall: if the source CSV itself contains duplicate-PK rows, `do-nothing` silently
drops them and `count(*)` on the target will be lower than the loader's reported "Records
loaded" figure. De-duplicate the source, or accept the loss explicitly.

---

## CSV/TSV Header Handling

The loader defaults to treating **every row as data** — the first row is _not_ skipped.
This matches PostgreSQL `COPY FROM` (default `HEADER false`), Redshift, Snowflake, and
BigQuery defaults.

If your file has a header row, pass `--header` so it gets skipped. Omitting this flag is
the most common source of failure when loading CSV files with column headers.

```bash
aurora-dsql-loader load \
  --endpoint your-cluster.dsql.us-east-1.on.aws \
  --source-uri sales_with_header.csv \
  --table sales \
  --header
```

**Symptoms of a missing `--header`:**

- `invalid input syntax for type <T>: "<column_name>"` — the loader is trying to insert
  the header row's column names as data, and the target column type rejects the literal.
- Per-batch `Records failed` count equal to your `--batch-size` (typically 2000) on the
  chunk containing row 0, with no other failures.

**Legacy behavior (v2.x):** older loader versions defaulted to assuming a header row and
silently dropped the first data row when one was missing. If upgrading from v2.x, add
`--header` to any invocation that loads a header-bearing file.

---

## Schema Inference Caveats

Schema inference is the recommended default for migrating data into a new table. It works
well for homogeneous, well-typed inputs, but can produce surprising results for:

- **Mixed nullability across files.** A column that is non-null in one chunk and contains
  empty strings in another may infer as `TEXT` rather than the intended numeric / date type.
- **Ambiguous numeric / string columns.** Identifiers that look numeric (e.g. ZIP codes with
  leading zeros, phone numbers) often infer as integers and lose the leading characters.
- **Date / timestamp formats.** Inference is conservative — non-ISO formats fall back to
  `TEXT`.

Use `--dry-run` to surface the inferred schema before committing to a long-running load:

```bash
aurora-dsql-loader load \
  --endpoint your-cluster.dsql.us-east-1.on.aws \
  --source-uri data.csv \
  --table my_table \
  --dry-run
```

If the inferred schema is wrong, create the table explicitly and re-run without
`--if-not-exists`.

---

## Index Count Affects Throughput

Each row written costs `1 + num_indexes` index-entry writes. A table with 15 secondary
indexes loads roughly **2× slower** than the same table with 3 indexes on the same host —
and the partition-warming curve is correspondingly slower because warming scales with write
volume.

Practical guidance:

- For multi-hundred-million-row loads, consider creating secondary indexes **after** the
  bulk load using `CREATE INDEX ASYNC`. The bulk load completes faster, and the async
  index build runs in the background.
- For loads where the table will be queried during ingestion, keep the indexes in place —
  the throughput cost is usually preferable to a query that returns wrong results.

---

## Diagnostic Decision Tree

Use these symptom → cause mappings when a load runs slower than expected. Start by
identifying which symptom matches: check host CPU utilization and compare the observed
rec/s against the expected rate, then follow the matching entry below.

### Symptom: throughput stuck at 3-4K rec/s; host CPU is low

**Cause:** partition-constrained. The target table is on a single (or very few) partitions
and writes are serializing.

**Action:** keep the load running. Throughput will accelerate as DSQL splits. If this is a
recurring pattern for fresh-table loads in your workflow, run a 10-minute low-concurrency
pre-pass before the formal load to drive splits.

### Symptom: throughput below expected; host CPU > 90%

**Cause:** host-bound. The loader is saturating local CPU before saturating DSQL.

**Action:** reduce client concurrency (`--workers`, `--batch-concurrency`) or move the load
to a larger host. Network is rarely the constraint at typical row sizes — CPU is.

### Symptom: throughput below expected; host CPU ~50%; persists past 15 minutes

**Cause:** the partition map has not grown to match the write concurrency. Often a hot-key
problem in the source data — many rows hashing to the same partition.

**Action:** inspect the source for skew on the primary key column. If the PK is a UUID,
verify it is genuinely random (some libraries default to v1 UUIDs that share a high-order
prefix). If the skew is real and unavoidable, expect the load to run at the rate of the
hottest partition.

### Symptom: "Records loaded" exceeds `SELECT count(*)` on the target

**Cause:** duplicate primary keys in the source combined with `--on-conflict do-nothing`.
The loader counts every row submitted; `count(*)` reflects only rows that survived the
conflict resolution.

**Action:** check the source for duplicate-PK rows. If duplicates are expected and
intentional, document the gap. If not, de-duplicate the source and re-run.

### Symptom: loader crashed mid-run; manifest is gone

**Cause:** the manifest was in `/tmp` (the default) on a tmpfs-backed system, and the
unclean exit cleared tmpfs.

**Action:** for the current load, you must re-run from the beginning. If the target table
has a unique constraint and the load is idempotent, use `--on-conflict do-nothing` so
already-committed rows are skipped. For all future loads, set `--manifest-dir` to a
persistent path.

---

## Related References

- [connectivity-tools.md](auth/connectivity-tools.md) — loader install and basic invocation
- [scaling-guide.md](auth/scaling-guide.md) — partition behavior and hot-key avoidance
- [development-guide.md](development-guide.md) — DSQL transaction limits and DDL rules
