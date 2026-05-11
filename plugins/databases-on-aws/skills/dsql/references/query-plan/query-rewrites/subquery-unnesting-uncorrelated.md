# Rewrite: Subquery Unnesting — Uncorrelated

When a query contains an uncorrelated `IN (SELECT ...)` subquery, rewrite it as an explicit JOIN. This enables better join order optimizations and index usage.

**SHOULD apply when:** The subquery does not reference columns from the outer query.

**Skip when:** The subquery is correlated (references outer query columns).

```sql
-- Original
SELECT *
FROM R
WHERE R.a IN (
  SELECT S.b
  FROM S
);

-- Rewritten
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
SELECT DISTINCT orders.order_id
FROM orders
JOIN customers
  ON orders.customer_id = customers.customer_id
WHERE customers.country = 'US';
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
