# Rewrite: Subquery Unnesting — Uncorrelated

When a query contains an uncorrelated `IN (SELECT ...)` subquery, rewrite it as an EXISTS (preferred, preserves semi-join semantics) or explicit JOIN. This enables better join order optimizations and index usage.

**SHOULD apply when:** The subquery does not reference columns from the outer query and returns a large or variable number of rows.

**SHOULD skip when:** The IN list is a small static set of constants (e.g., `IN ('admin', 'editor')`) or the subquery is correlated (references outer query columns).

```sql
-- Original
SELECT *
FROM R
WHERE R.a IN (
  SELECT S.b
  FROM S
);

-- Rewritten (preferred — EXISTS preserves semi-join semantics)
SELECT *
FROM R
WHERE EXISTS (
  SELECT 1
  FROM S
  WHERE S.b = R.a
);

-- Alternative (JOIN form — apply only when S.b is unique,
-- otherwise DISTINCT collapses pre-existing duplicates in R)
SELECT DISTINCT R.*
FROM R
JOIN S
  ON R.a = S.b;
```

```sql
-- Additional example
SELECT order_id
FROM orders
WHERE customer_id IN (
  SELECT customer_id
  FROM customers
  WHERE country = 'US'
);

-- Rewritten
SELECT order_id
FROM orders
WHERE EXISTS (
  SELECT 1
  FROM customers
  WHERE customers.customer_id = orders.customer_id
    AND customers.country = 'US'
);
```

```sql
-- Not applicable: subquery is correlated
SELECT *
FROM R
WHERE R.a IN (
  SELECT S.b
  FROM S
  WHERE S.c = R.d
);
```
