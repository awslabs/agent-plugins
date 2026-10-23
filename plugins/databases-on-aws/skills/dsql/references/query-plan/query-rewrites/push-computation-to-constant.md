# Rewrite: Push Computation to Constant Side

When a filter predicate applies invertible arithmetic to an indexed column, move the computation to the constant side so the column appears alone and indexes can be used.

**SHOULD apply when:** All operations on the column are mathematically invertible (addition, subtraction, multiplication/division by non-zero constant).

**SHOULD skip when:** The computation involves non-invertible functions (substring, lower/upper, trigonometric functions) or moving the computation changes query semantics (precision loss, integer-division rounding).

```sql
-- Original (amount is NUMERIC)
SELECT * FROM transactions
WHERE amount * 100 / 5 = 2000.00;

-- Rewritten
SELECT * FROM transactions
WHERE amount = 2000.00 * 5 / 100;
```

```sql
-- Additional example
SELECT * FROM orders
WHERE order_id + 5 > 100;

-- Rewritten
SELECT * FROM orders
WHERE order_id > 100 - 5;
```

```sql
-- Not applicable: non-invertible function
SELECT * FROM users
WHERE substring(username, 1, 3) = 'abc';
```
