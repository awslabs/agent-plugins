# Rewrite: LEFT JOIN with Null-Rejecting Predicate to INNER JOIN

When a query uses LEFT JOIN but the WHERE clause rejects NULLs on the joined table, rewrite as INNER JOIN. This enables a simpler, more efficient join plan.

**SHOULD apply when:** The WHERE clause rejects NULLs from the right-hand side of a LEFT JOIN (e.g., `IS NOT NULL`, equality comparisons, or any predicate that cannot be true for NULL).

**SHOULD skip when:** NULLs from the right-hand side are intentionally preserved in the result.

```sql
-- Original
SELECT *
FROM R1
LEFT JOIN R2
  ON R1.key = R2.key
WHERE R2.key IS NOT NULL;

-- Rewritten
SELECT *
FROM R1
JOIN R2
  ON R1.key = R2.key;
```

```sql
-- Not applicable: NULLs from R2 are intentionally preserved
SELECT *
FROM R1
LEFT JOIN R2
  ON R1.key = R2.key;
```
