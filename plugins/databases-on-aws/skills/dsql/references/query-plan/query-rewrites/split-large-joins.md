# Rewrite: Split Large Joins for DP Join Ordering (DSQL-Specific)

When a query joins more tables than the optimizer's DP threshold, rewrite it into multiple subqueries each joining no more tables than the threshold, then join the subquery results. The agent MUST run `SHOW join_collapse_limit;` on the target cluster to determine the actual threshold rather than assuming a fixed value (default is **8** on Aurora DSQL).

This allows the PostgreSQL-based DSQL engine to apply dynamic-programming (DP) join ordering within each smaller block, producing a better overall join plan than a greedy algorithm on many tables.

**SHOULD apply when:** The total number of joined tables exceeds the DP threshold (`join_collapse_limit` or `from_collapse_limit`). Partition the join into CTEs each with table count at or below the threshold, push down relevant filters, and join the CTE results.

**SHOULD skip when:** The total table count is at or below the threshold, or splitting would prevent necessary cross-block optimizations.

```sql
-- Original (11 tables — exceeds default DP threshold of 8)
SELECT *
FROM R1
  JOIN R2 ON R1.id = R2.r1_id
  JOIN R3 ON R2.id = R3.r2_id
  JOIN R4 ON R3.id = R4.r3_id
  JOIN R5 ON R4.id = R5.r4_id
  JOIN R6 ON R5.id = R6.r5_id
  JOIN R7 ON R6.id = R7.r6_id
  JOIN R8 ON R7.id = R8.r7_id
  JOIN R9 ON R8.id = R9.r8_id
  JOIN R10 ON R9.id = R10.r9_id
  JOIN R11 ON R10.id = R11.r10_id
WHERE Filters;

-- Rewritten (DSQL) — split into two CTEs, each ≤ 8 tables
WITH
  sub1 AS (
    SELECT R1.id, R6.id AS r6_id, R6.col
    FROM R1
      JOIN R2 ON R1.id = R2.r1_id
      JOIN R3 ON R2.id = R3.r2_id
      JOIN R4 ON R3.id = R4.r3_id
      JOIN R5 ON R4.id = R5.r4_id
      JOIN R6 ON R5.id = R6.r5_id
    WHERE <Filter 1>
  ),
  sub2 AS (
    SELECT R7.r6_id, R11.col
    FROM R7
      JOIN R8 ON R7.id = R8.r7_id
      JOIN R9 ON R8.id = R9.r8_id
      JOIN R10 ON R9.id = R10.r9_id
      JOIN R11 ON R10.id = R11.r10_id
    WHERE <Filter 2>
  )
SELECT *
FROM sub1
JOIN sub2 ON sub1.r6_id = sub2.r6_id;
```

```sql
-- Not applicable: total tables ≤ DP threshold
SELECT *
FROM R1
  JOIN R2 ON R1.id = R2.id
  JOIN R3 ON R2.id = R3.id
  JOIN R4 ON R3.id = R4.id
WHERE Filters;
```
