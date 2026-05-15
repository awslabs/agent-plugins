# Rewrite: Push GROUP BY into Subquery

When a query aggregates after joining a fact table to a dimension table, push the GROUP BY into a subquery on the fact table alone. This aggregates fewer rows and joins the smaller result to retrieve dimension columns.

**SHOULD apply when:** The aggregation is on the fact table and additional columns come from a dimension table joined on the grouping key.

**SHOULD skip when:** No additional columns are needed beyond the grouping key.

```sql
-- Original
SELECT c.customer_id,
       c.first_name,
       c.last_name,
       COUNT(*) AS order_count
FROM customers c
JOIN orders o
  ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name;

-- Rewritten
SELECT c.customer_id,
       c.first_name,
       c.last_name,
       agg.order_count
FROM customers c
JOIN (
  SELECT customer_id,
         COUNT(*) AS order_count
  FROM orders
  GROUP BY customer_id
) AS agg
  ON c.customer_id = agg.customer_id;
```

```sql
-- Additional example
SELECT cat.category_name,
       cat.description,
       SUM(t.amount) AS total_amount
FROM categories cat
JOIN transactions t
  ON cat.id = t.category_id
GROUP BY cat.category_name, cat.description;

-- Rewritten
SELECT cat.category_name,
       cat.description,
       agg.total_amount
FROM categories cat
JOIN (
  SELECT category_id,
         SUM(amount) AS total_amount
  FROM transactions
  GROUP BY category_id
) AS agg
  ON cat.id = agg.category_id;
```

```sql
-- Not applicable: no additional columns needed
SELECT department_id,
       SUM(salary) AS total_salary
FROM employees
GROUP BY department_id;
```
