# Rewrite: Replace NOT IN with NOT EXISTS

When a column is filtered with `NOT IN (subquery)`, rewrite as a correlated NOT EXISTS. This avoids building a large intermediate set.

**Semantics warning:** NOT EXISTS does not preserve NOT IN's NULL-propagation behaviour. When the subquery MAY contain NULLs, `NOT IN` returns no rows while `NOT EXISTS` returns the non-matching rows — the rewrite changes results. MUST confirm intent with the user before applying when NULLs are possible.

**SHOULD apply when:** The NOT IN subquery returns many rows and the subquery column is guaranteed NOT NULL (or the user confirms the changed NULL behaviour is acceptable).

**SHOULD skip when:** The exclusion list is a small static set of constants.

```sql
-- Original
SELECT *
FROM customers
WHERE customer_id NOT IN (
  SELECT customer_id
  FROM excluded_customers
);

-- Rewritten
SELECT *
FROM customers c
WHERE NOT EXISTS (
  SELECT 1
  FROM excluded_customers b
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
