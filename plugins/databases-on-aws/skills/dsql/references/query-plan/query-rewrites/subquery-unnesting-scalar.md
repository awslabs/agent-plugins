# Rewrite: Subquery Unnesting — Scalar

When a query contains a scalar subquery in the SELECT clause computing an aggregate correlated by equality, rewrite it as a LEFT JOIN with GROUP BY. This reduces repeated subquery executions and enables better join planning.

**SHOULD apply when:** The scalar subquery is correlated via equality and contains an aggregate function (MAX, MIN, COUNT, SUM).

**Skip when:** The scalar subquery is uncorrelated.

```sql
-- Original
SELECT
  R.*,
  (SELECT MAX(S.y)
   FROM S
   WHERE S.x = R.x) AS max_y
FROM R;

-- Rewritten
SELECT
  R.*,
  Agg.max_y
FROM R
LEFT JOIN (
  SELECT x, MAX(y) AS max_y
  FROM S
  GROUP BY x
) AS Agg
  ON Agg.x = R.x;
```

```sql
-- Additional example
SELECT
  R.id,
  R.name,
  (SELECT COUNT(*)
   FROM S
   WHERE S.owner_id = R.id) AS s_count
FROM R;

-- Rewritten
SELECT
  R.id,
  R.name,
  Agg.s_count
FROM R
LEFT JOIN (
  SELECT owner_id, COUNT(*) AS s_count
  FROM S
  GROUP BY owner_id
) AS Agg
  ON Agg.owner_id = R.id;
```

```sql
-- Not applicable: scalar subquery is uncorrelated
SELECT
  R.*,
  (SELECT MAX(S.y) FROM S) AS global_max_y
FROM R;
```
