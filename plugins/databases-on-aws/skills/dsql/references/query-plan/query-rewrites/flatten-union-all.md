# Rewrite: Flatten Nested UNION ALL

When a query contains UNION ALL nested inside another UNION ALL, flatten all branches into a single UNION ALL to simplify the plan and reduce intermediate merge steps.

**SHOULD apply when:** All set operations are UNION ALL (no deduplication).

**SHOULD skip when:** Any branch uses UNION (deduplicating), which MUST remain distinct.

```sql
-- Original
SELECT * FROM sales_q1
UNION ALL (
  SELECT * FROM sales_q2
  UNION ALL
  SELECT * FROM sales_q3
);

-- Rewritten
SELECT * FROM sales_q1
UNION ALL
SELECT * FROM sales_q2
UNION ALL
SELECT * FROM sales_q3;
```

```sql
-- CTE example
-- Original
WITH a AS (
  SELECT * FROM t1
  UNION ALL
  SELECT * FROM t2
)
SELECT * FROM a
UNION ALL
SELECT * FROM t3;

-- Rewritten
SELECT * FROM t1
UNION ALL
SELECT * FROM t2
UNION ALL
SELECT * FROM t3;
```

```sql
-- Not applicable: UNION (deduplicating) must stay distinct
SELECT * FROM t1
UNION
SELECT * FROM t2;
```
