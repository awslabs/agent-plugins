# Rewrite: Subquery Unnesting — Correlated

When a query contains a correlated EXISTS subquery, rewrite it as an explicit JOIN. This exposes the subquery to better join optimizations, especially when indexes exist on the join columns.

**SHOULD apply when:** The correlated subquery is inside an EXISTS clause and the correlation is expressible as a JOIN condition (typically equality).

**Skip when:** The correlation cannot be expressed as a simple JOIN condition.

```sql
-- Original
SELECT *
FROM R
WHERE EXISTS (
  SELECT 1
  FROM S
  WHERE S.x = R.x
    AND S.y > 0
);

-- Rewritten
SELECT DISTINCT R.*
FROM R
JOIN S
  ON S.x = R.x
 AND S.y > 0;
```

```sql
-- Additional example
SELECT product_id
FROM products
WHERE EXISTS (
  SELECT 1
  FROM product_reviews
  WHERE product_reviews.product_id = products.product_id
    AND product_reviews.rating >= 4
);

-- Rewritten
SELECT DISTINCT products.product_id
FROM products
JOIN product_reviews
  ON product_reviews.product_id = products.product_id
 AND product_reviews.rating >= 4;
```

```sql
-- Not applicable: correlation cannot be expressed as a JOIN condition
SELECT *
FROM R
WHERE EXISTS (
  SELECT 1
  FROM S
  WHERE S.x + S.y = R.z
);
```
