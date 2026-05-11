# Rewrite: Replace NOT IN with NOT EXISTS

When a column is filtered with `NOT IN (subquery)`, rewrite as a correlated NOT EXISTS. This avoids building a large intermediate set and sidesteps NULL semantics issues with NOT IN.

**SHOULD apply when:** The NOT IN subquery returns many rows or MAY contain NULLs.

**Skip when:** The exclusion list is a small static set of constants.

```sql
-- Original
SELECT *
FROM customers
WHERE customer_id NOT IN (
  SELECT customer_id
  FROM blacklisted_customers
);

-- Rewritten
SELECT *
FROM customers c
WHERE NOT EXISTS (
  SELECT 1
  FROM blacklisted_customers b
  WHERE b.customer_id = c.customer_id
);
```

```sql
-- Additional example
SELECT product_id
FROM products
WHERE product_id NOT IN (
  SELECT product_id
  FROM discontinued_products
  WHERE discontinued = true
);

-- Rewritten
SELECT p.product_id
FROM products p
WHERE NOT EXISTS (
  SELECT 1
  FROM discontinued_products d
  WHERE d.product_id = p.product_id
    AND d.discontinued = true
);
```

```sql
-- Not applicable: small static exclusion set
SELECT *
FROM items
WHERE item_type NOT IN ('typeA', 'typeB');
```
