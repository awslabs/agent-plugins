# Rewrite: Replace IN-Subquery with EXISTS

When a column is compared to a subquery using IN and the subquery may return many rows, rewrite as a correlated EXISTS to leverage short-circuit evaluation.

**SHOULD apply when:** The IN subquery returns a large or variable number of rows.

**Skip when:** The IN list is a small static set of constants.

```sql
-- Original
SELECT *
FROM customers
WHERE customer_id IN (
  SELECT customer_id
  FROM orders
  WHERE order_date >= NOW() - INTERVAL '30 days'
);

-- Rewritten
SELECT *
FROM customers c
WHERE EXISTS (
  SELECT 1
  FROM orders o
  WHERE o.customer_id = c.customer_id
    AND o.order_date >= NOW() - INTERVAL '30 days'
);
```

```sql
-- Additional example
SELECT product_id
FROM products
WHERE product_id IN (
  SELECT product_id
  FROM inventory
  WHERE quantity > 0
);

-- Rewritten
SELECT product_id
FROM products p
WHERE EXISTS (
  SELECT 1
  FROM inventory i
  WHERE i.product_id = p.product_id
    AND i.quantity > 0
);
```

```sql
-- Not applicable: small static set of constants
SELECT *
FROM users
WHERE user_type IN ('admin', 'editor', 'viewer');
```
