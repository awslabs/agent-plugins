# Rewrite: Replace COUNT(*) with reltuples Estimate (DSQL-Specific)

When a query performs `COUNT(*)` on a large table, rewrite to use the `reltuples` value from `pg_class` for an approximate row count. This is a common workaround for cases where `COUNT(*)` is too slow or times out on large tables.

**SHOULD apply when:** An approximate count is acceptable and the table is large enough that `COUNT(*)` is prohibitively expensive.

**Skip when:** The application requires an exact count.

```sql
-- Original
SELECT COUNT(*) AS exact_count
FROM big_table;

-- Rewritten (DSQL)
SELECT reltuples::bigint AS estimated_count
FROM pg_class
WHERE oid = 'public.big_table'::regclass;
```

```sql
-- Not applicable: exact count required
SELECT COUNT(*) AS exact_count
FROM big_table;
```
