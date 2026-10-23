# Rewrite: Subquery Unnesting — Correlated

When a query contains a correlated EXISTS subquery that the optimizer handles poorly, rewrite it as an explicit JOIN. This MAY expose the subquery to better join optimizations, especially when indexes exist on the join columns.

**SHOULD apply when:** The correlated subquery is inside an EXISTS clause, the correlation is expressible as a JOIN condition (typically equality), and the inner side is unique on the join key (otherwise DISTINCT changes results by collapsing pre-existing duplicates in the outer table).

**SHOULD skip when:** The correlation cannot be expressed as a simple JOIN condition, or the inner side is not unique on the join key and duplicate preservation matters.

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

-- Rewritten (apply only when S.x is unique; otherwise DISTINCT
-- collapses pre-existing duplicates in R)
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

-- Rewritten (product_reviews.product_id is not unique, so
-- DISTINCT is required — verify this is acceptable)
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
