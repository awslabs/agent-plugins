# Plan Interpretation Reference

## Table of Contents

1. [DSQL Node Types](#dsql-node-types)
2. [Layered Plan Structure](#layered-plan-structure)
3. [Calculating Node Duration](#calculating-node-duration)
4. [Detecting Estimation Errors](#detecting-estimation-errors)
5. [Nested Loop Amplification](#nested-loop-amplification)
6. [Post-Scan Filter Selectivity](#post-scan-filter-selectivity)
7. [Hash Table Resizing](#hash-table-resizing)
8. [High-Loop Storage Lookups](#high-loop-storage-lookups)
9. [Anomalous Values](#anomalous-values)
10. [Type Coercion and Index Bypass](#type-coercion-and-index-bypass)
11. [Projections and Row Width](#projections-and-row-width)
12. [Cost Number Interpretation](#cost-number-interpretation)
13. [DPU Interpretation](#dpu-interpretation)

---

## DSQL Node Types

DSQL stores all table data in B-Tree structures. Secondary indexes are also B-Tree, and contain the primary table keys for the secondary index values that make up the tree. DSQL extends standard PostgreSQL with storage-layer node types:

### DSQL-Specific Nodes

| Node Type               | Description                                                                     |
| ----------------------- | ------------------------------------------------------------------------------- |
| Full Scan (btree-table) | Full table scan                                                                 |
| Storage Scan            | Physical read of >1 rows of data from storage layer via Pushdown Compute Engine |
| B-Tree Scan             | Physical read of rows from storage                                              |
| Storage Lookup          | Point lookup of a row by internal row pointer (follows index scan)              |
| B-Tree Lookup           | Point lookup of a table entry by key                                            |

### Standard PostgreSQL Nodes

| Node Type       | Description                                            |
| --------------- | ------------------------------------------------------ |
| Nested Loop     | Iterates inner side once per outer row                 |
| Hash Join       | Builds hash table from one side, probes with the other |
| Merge Join      | Merges two pre-sorted inputs                           |
| Index Scan      | Scans an index and fetches matching rows               |
| Index Only Scan | Retrieves all data from index access (no table access) |
| Seq Scan        | Sequential full table scan                             |
| Sort            | Sorts rows for Merge Join or ORDER BY                  |
| Aggregate       | Computes GROUP BY / aggregate functions                |

## Layered Plan Structure

A logical scan decomposes into a Storage Scan, which itself has a B-Tree Scan child — not two siblings. Index Scan adds a **second, parallel** Storage Lookup branch (its own B-Tree Lookup child) for columns the index does not cover.

**Full Scan (single branch):**

```
Full Scan (btree-table) on tablename
  Filter: col_a = 'v'              ← query processor filter (post-transfer)
  -> Storage Scan on tablename
       Filters: col_b = 'v'        ← storage filter (pre-transfer)
       -> B-Tree Scan on tablename
```

**Index Scan (two parallel branches; Storage Lookup is a sibling of Storage Scan, not a child):**

```
Index Scan using idx on tablename
  Index Cond: col_a = 'v'
  -> Storage Scan on idx
       -> B-Tree Scan on tablename
  -> Storage Lookup on tablename   ← separate branch for non-covered columns
       -> B-Tree Lookup on tablename
```

A child's timing and row counts roll up into its parent's totals — not into a sibling branch.

### Three-Layer Filter Model

Every predicate is evaluated at one of three layers. The layer determines how much data crosses the network between storage and compute — the primary lever for DSQL optimization.

| Level        | Filter Type            | Where it appears in EXPLAIN                                  | Data Movement                                           | How to push predicates here                                           |
| ------------ | ---------------------- | ------------------------------------------------------------ | ------------------------------------------------------- | --------------------------------------------------------------------- |
| 1 (best)     | Index Condition        | `Index Cond:` on scan node                                   | Minimized — only matching index entries read            | Equality/range on indexed key columns; most selective column leftmost |
| 2 (moderate) | Storage Filter         | `Filters:` inside `Storage Scan` or `Storage Lookup` node    | Reduced — applied at storage before transfer            | Add filter columns to index INCLUDE clause                            |
| 3 (worst)    | Query Processor Filter | `Filter:` above `Storage Scan` (at the scan-type node level) | Maximum — all data transferred before predicate applied | Requires new index, restructured query, or schema change              |

**Optimization goal:** Move predicates from Level 3 → Level 2 → Level 1. Each step reduces network transfer between storage and compute, directly reducing latency and DPU.

### Fixing Storage Lookups (INCLUDE columns)

When a Storage Lookup node appears, the index satisfied the filter but not all projected columns. The fix: add missing columns to the index's INCLUDE clause.

```
-- Before: Storage Lookup fetches created_at from base table
Index Scan using idx1 on account
  -> Storage Scan on idx1
  -> Storage Lookup on account        ← extra round trip
       Projections: created_at

-- Fix: CREATE INDEX ASYNC idx2 ON account (customer_id) INCLUDE (balance, status, created_at)
-- After: Index Only Scan, no Storage Lookup
Index Only Scan using idx2 on account
  -> Storage Scan on idx2
       Projections: customer_id, balance, status, created_at
```

**Trade-off:** INCLUDE columns are copied into every index entry, increasing index size. Only include columns that your most-queried paths actually need.

## Calculating Node Duration

DSQL follows the standard PostgreSQL EXPLAIN convention: `actual time` is reported **per iteration**, not cumulative. The node's total wall-clock time is:

```
Node Duration = actual_time_end × loops
```

Where:

- `actual_time_end` is the per-iteration time reported for the node (in ms)
- `loops` is the number of times the node executed (always 1 at the top level; >1 for the inner side of a Nested Loop)

Rank all nodes by total duration descending. Begin analysis from the most expensive node.

## Detecting Estimation Errors

An estimation error exists when estimated rows diverge significantly from actual rows:

| Error Magnitude | Classification                                            |
| --------------- | --------------------------------------------------------- |
| 2x–5x           | Minor — note but low priority                             |
| 5x–50x          | Significant — investigate statistics                      |
| 50x+            | Severe — likely correlated predicates or stale statistics |

Calculate error ratio: `actual_rows / estimated_rows` (or inverse if estimate is higher).

For each significant error, record:

- The node type and table
- The estimated vs actual row count
- The index or scan method used
- Any filter predicates applied

## Nested Loop Amplification

Flag when a Nested Loop's outer input has a significant estimation error:

**Pattern:**

```
Nested Loop (est: N rows, actual: M rows)
├── [Outer] Hash Join / Scan (est: X, actual: Y where Y >> X)
└── [Inner] Index Scan (per-loop cost × Y loops)
```

**Explanation:** The planner chose Nested Loop expecting X iterations on the inner side. With Y actual iterations (where Y >> X), total inner-side cost = per-loop cost × Y. A Hash Join or Merge Join would have been more efficient at this cardinality.

**Quantify:**

- Expected total inner time: per-loop time × estimated outer rows
- Actual total inner time: per-loop time × actual outer rows
- Amplification factor: actual / estimated

## Post-Scan Filter Selectivity

Calculate filter waste when a node applies a post-scan filter:

```
Filter Selectivity = Rows Removed by Filter / (Rows Removed by Filter + Actual Rows)
```

| Selectivity | Interpretation                                   |
| ----------- | ------------------------------------------------ |
| <10%        | Minimal waste — filter removes few rows          |
| 10%–50%     | Moderate — consider composite index              |
| >50%        | High waste — strong candidate for index pushdown |

For nodes inside loops, calculate total filter waste:

```
Total rows scanned = (Actual Rows + Rows Removed) × loops
Total rows filtered = Rows Removed × loops
```

## Hash Table Resizing

When a Hash Join reports `Buckets: originally N, now M` (where M > N):

- The planner underestimated the build-side cardinality
- The hash table was dynamically resized during execution
- This adds memory pressure and execution overhead

Flag the build-side estimation error and trace it to the source scan node.

## High-Loop Storage Lookups

When a Storage Lookup has a high loop count:

```
Total I/O operations = actual_rows × loops
```

Flag when total I/O operations exceed 10,000. Each Storage Lookup involves a point read from the storage layer — high loop counts with even modest per-loop rows create significant cumulative I/O.

## Anomalous Values

Detect physically impossible row counts in DSQL plan nodes:

**Detection criteria:**

- A node reports `actual rows` exceeding the table's known total row count by 10x or more
- Particularly common on Storage Lookup nodes under high loop counts

**Example:** Storage Lookup reporting 7.7 trillion actual rows for a table with 379,484 rows.

**Action:**

- Flag as a potential DSQL reporting bug
- Verify query results are correct (they typically are — only EXPLAIN output is affected)
- Include in support request template

These anomalous values do not affect query correctness — only diagnostic output accuracy.

## Type Coercion and Index Bypass

An index may exist on a column yet not be used when the predicate value's type does not match the column's declared type and no implicit cast exists between the two types.

### Detection Pattern

Flag this condition when **all** of the following are true:

1. An index exists whose leading column matches a WHERE predicate column
2. The plan uses a Full Scan or Seq Scan on that table instead of an Index Scan
3. The predicate literal's type differs from the indexed column's declared type
4. The `pg_amop` query in catalog-queries.md (B-Tree Cross-Type Operator Support) returns no row for the type pair

### Why It Happens

DSQL (like PostgreSQL) can only use a B-Tree index when a cross-type B-Tree operator is registered in `pg_amop` for the (predicate-type, column-type) pair. When a predicate supplies a value of a different type:

- If a cross-type B-Tree operator is registered (verify via the `pg_amop` query in catalog-queries.md), the index can be used
- If no cross-type operator is registered, the planner MUST apply a per-row cast or comparison function that cannot use the index's ordering — resulting in a full scan

This is particularly surprising to users because the query returns correct results (the cast happens at execution time, row by row) but performance degrades dramatically on large tables.

### Determining Index-Compatible Type Pairs

Rather than relying on a static matrix, query `pg_amop` directly on the cluster to determine which cross-type comparisons the DSQL B-Tree index access method supports. See catalog-queries.md for the exact SQL.

The key insight: DSQL's B-Tree access method (amopmethod `10003`) only supports index scans when a registered operator exists for the specific (left-type, right-type) pair. If no operator is registered for the pair, the index cannot be used — regardless of whether a general-purpose implicit cast exists in `pg_cast`.

At time of writing, cross-type index support is limited to the integer family (smallint, integer, bigint — all combinations). All other indexed types (text, numeric, uuid, timestamp, date, boolean, etc.) require an exact type match. MUST verify via the `pg_amop` query in catalog-queries.md before asserting this to a user, as DSQL MAY add cross-type operator families in future releases.

### Quantifying Impact

When this pattern is detected:

```
Full Scan rows processed = actual_rows from Full Scan node
Index Scan rows (expected) = estimated rows matching the predicate (from pg_stats selectivity)
Scan amplification = Full Scan rows / Index Scan rows (expected)
```

### Recommendation Template

When a type coercion bypass is confirmed:

- **Explicit cast in the predicate:** Rewrite `WHERE col = '42'` as `WHERE col = 42::integer` (cast the literal to the column's declared type)
- **Application-layer fix:** Ensure the application passes parameters with the correct type rather than relying on implicit conversion
- **MUST keep the column type unchanged** — changing it to accommodate mismatched predicates masks the real issue and MAY break other queries

### Evidence Gathering

To confirm this pattern, cross-reference:

1. The column type from `pg_attribute` or `information_schema.columns` (see catalog-queries.md)
2. The index definition from `pg_indexes`
3. The predicate literal in the EXPLAIN output (visible in `Filter:` or `Index Cond:` lines)
4. The `pg_amop` query in catalog-queries.md (B-Tree Cross-Type Operator Support)

## Projections and Row Width

Capture Projections lists from Storage Scan and Storage Lookup nodes:

```
Projections: [col1, col2, col3, ...]
```

Assess row width overhead:

- Count projected columns per node
- Note when `SELECT *` pulls all columns from wide tables
- Flag tables with 50+ columns or estimated row width >5,000 bytes

Wide projections increase I/O on Storage Lookups and memory usage in Hash Joins. Impact scales with result set size.

## Cost Number Interpretation

DSQL cost numbers appear much higher than equivalent PostgreSQL plans. This is expected — the cost model accounts for distributed round-trips.

**Format:** `startup_cost..total_cost` (e.g., `100.28..208.29`)

- **Startup cost ~100** is normal — reflects fixed overhead of initiating a storage round-trip
- **Total cost** includes incremental per-row processing, network transfer, and page access

**MUST NOT** compare cost numbers across queries to determine which is "better." Cost units are internal to the optimizer and non-comparable. Use DPU estimates instead.

## DPU Interpretation

`EXPLAIN ANALYZE VERBOSE` appends a `Statement DPU Estimate` block:

```
Statement DPU Estimate:
  Compute: 0.01724 DPU
  Read:    0.01202 DPU
  Write:   0.00000 DPU
  Total:   0.02926 DPU
```

**Read DPU** is the primary optimization signal for read-heavy queries. High Read DPU with selective filters means those filters aren't pushed down far enough (Level 3 or 2 when they could be Level 1).

**Optimization loop:**

1. Run `EXPLAIN ANALYZE VERBOSE` on the unoptimized query — note Total DPU
2. Apply fix (add index, add INCLUDE columns, restructure query)
3. Re-run — compare DPU delta

**MUST** use DPU as the before/after comparison metric, not cost numbers or execution time (which varies with load).
