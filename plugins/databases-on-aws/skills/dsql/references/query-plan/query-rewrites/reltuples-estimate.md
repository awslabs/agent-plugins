# Rewrite: Replace COUNT(*) with reltuples Estimate (DSQL-Specific)

When a query performs `COUNT(*)` on a large table, rewrite to use the `reltuples` value from `pg_class` for an approximate row count. This is a common workaround for cases where `COUNT(*)` is too slow or times out on large tables.

**SHOULD apply when:** An approximate count is acceptable and the table is large enough that `COUNT(*)` is prohibitively expensive.

**Staleness warning:** `reltuples` reflects the last `ANALYZE` run. MUST warn the user that the value MAY be stale on write-heavy or recently created tables (DSQL does not populate `pg_stat_user_tables.last_analyze`). A value of `-1` means statistics have never been gathered — treat as "unknown" and recommend running `ANALYZE` first.

**SHOULD skip when:** The application requires an exact count.

```sql
-- Original
SELECT COUNT(*) AS exact_count
FROM big_table;

-- Rewritten (DSQL) — GREATEST guards against -1 (never-analyzed)
SELECT GREATEST(reltuples, 0)::bigint AS estimated_count
FROM pg_class
WHERE oid = 'public.big_table'::regclass;
```

```sql
-- Not applicable: exact count required
SELECT COUNT(*) AS exact_count
FROM big_table;
```
