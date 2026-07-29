# Rewrite: Propagate Filter to JOIN Columns

When a query has an equality join condition and a filter predicate on one join attribute, propagate the filter to the corresponding attribute on the other table(s). This enables earlier filtering and reduces intermediate result sizes.

**SHOULD apply when:** The filter predicate is on a column involved in an equality join condition.

**SHOULD skip when:** The predicate is on a non-join column.

```sql
-- Original
SELECT *
FROM R1, R2
WHERE R1.id = R2.id
  AND R1.id > 10;

-- Rewritten
SELECT *
FROM R1, R2
WHERE R1.id = R2.id
  AND R1.id > 10
  AND R2.id > 10;
```

```sql
-- Transitive propagation across multiple tables
SELECT *
FROM R1, R2, R3
WHERE R1.id = R2.id
  AND R2.id = R3.id
  AND R1.id > 10;

-- Rewritten
SELECT *
FROM R1, R2, R3
WHERE R1.id = R2.id
  AND R2.id = R3.id
  AND R1.id > 10
  AND R2.id > 10
  AND R3.id > 10;
```

```sql
-- Not applicable: predicate is on a non-join column
SELECT *
FROM R1, R2
WHERE R1.id = R2.id
  AND R1.other_column > 10;
```
