# Rewrite: CTE Late Materialization to Defer Storage Lookups (DSQL-Specific)

When a query combines filtering, ordering, and LIMIT with columns not fully covered by an index, DSQL performs a Storage Lookup for every matching row — including rows discarded by LIMIT. Use a CTE to narrow first using only indexed columns, then join back for remaining columns on only the final rows.

**SHOULD apply when:** The query has a LIMIT that returns far fewer rows than the filter matches, and the EXPLAIN plan shows a Storage Lookup with a high loop count relative to the final row count.

**SHOULD skip when:** The filter is already highly selective (matching close to the LIMIT count), or all projected columns are in the index.

```sql
-- Before: Storage Lookup on every matching row, LIMIT discards most
SELECT customer_id, balance, status, created_at
FROM account
WHERE status = 'active'
ORDER BY created_at DESC
LIMIT 10;

-- After: CTE narrows to 10 rows using indexed columns, then fetches remaining
WITH candidates AS (
    SELECT customer_id, created_at
    FROM account
    WHERE status = 'active'
    ORDER BY created_at DESC
    LIMIT 10
)
SELECT a.customer_id, a.balance, a.status, a.created_at
FROM candidates c
JOIN account a ON a.customer_id = c.customer_id;
```

```sql
-- Not applicable: filter already selective (returns ~10 rows)
SELECT customer_id, balance
FROM account
WHERE customer_id = '4b18a761-5870-4d7c-95ce-0a48eca3fceb'::uuid
LIMIT 10;
```
