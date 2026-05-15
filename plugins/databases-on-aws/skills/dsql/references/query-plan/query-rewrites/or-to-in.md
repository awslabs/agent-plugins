# Rewrite: OR to IN

Rewrite multiple OR clauses comparing the same column to different constant values into a single IN clause. This enables more efficient index lookups and reduces redundant OR evaluations.

**SHOULD apply when:** All OR comparisons target the same column using equality (`=`) with constant values.

**SHOULD skip when:** OR clauses compare different columns or involve non-constant expressions.

```sql
-- Original
SELECT *
FROM R
WHERE R.key = c1 OR R.key = c2;

-- Rewritten
SELECT *
FROM R
WHERE R.key IN (c1, c2);
```

```sql
-- Additional example
SELECT name, age
FROM employees
WHERE department_id = 1 OR department_id = 2 OR department_id = 3;

-- Rewritten
SELECT name, age
FROM employees
WHERE department_id IN (1, 2, 3);
```

```sql
-- Not applicable: different columns involved
SELECT name, age
FROM employees
WHERE department_id = 1 OR location_id = 2;
```
