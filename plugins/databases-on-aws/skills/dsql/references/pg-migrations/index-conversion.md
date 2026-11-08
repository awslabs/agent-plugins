# Index Conversion for DSQL

Run `dsql_lint(fix=true)` first — it handles most index conversions automatically (ASYNC,
USING gin/gist/brin/hash → btree, CONCURRENTLY removal, INCLUDE preservation, and **stripping**
`ASC`/`DESC` from index keys — DSQL rejects sort direction outright, see
[Index Key Sort Order](#index-key-sort-order)).

This file covers the cases a mechanical fix cannot resolve:

- GIN, GiST, and BRIN indexes — `dsql_lint` strips the `USING` clause, but the resulting btree
  index does not serve the same queries. These need a redesign.
- Operator classes such as `text_pattern_ops` — `dsql_lint` leaves these in place with no
  diagnostic, so strip them by hand. DSQL rejects them with
  `ERROR: 0A000: opclass not supported for index keys`
- Sort direction — `index_sort_direction`; auto-fixed, but the fix changes which `ORDER BY` the
  index serves, and for `ASC` it is reported as neither an error nor a warning. See
  [Index Key Sort Order](#index-key-sort-order). NULLS placement is **not** part of this rule and
  is never stripped — see [NULLS placement is retained](#nulls-placement-is-retained).

Partial indexes (`WHERE`) and expression indexes are **supported** — add `ASYNC` and keep them as
written. No redesign is needed.

Sources:

- [Asynchronous Indexes](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-create-index-async.html)
- [CREATE INDEX syntax support](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/create-index-syntax-support.html)
- [DSQL SQL Dialect Blog](https://aws.amazon.com/blogs/database/dsql-sql-dialect-how-amazon-aurora-dsql-differs-from-single-instance-postgresql/)

## Table of Contents

1. [GIN Index Conversion](#gin-index-conversion)
2. [GiST Index Conversion](#gist-index-conversion)
3. [BRIN Index Conversion](#brin-index-conversion)
4. [Partial Indexes](#partial-indexes)
5. [Expression Indexes](#expression-indexes)
6. [Index Limits](#index-limits)
7. [Index Key Sort Order](#index-key-sort-order)
8. [Monitoring Async Index Status](#monitoring-async-index-status)
9. [Conversion Decision Flowchart](#conversion-decision-flowchart)

---

## GIN Index Conversion

GIN indexes are used for full-text search, JSONB containment, and array operations.
DSQL uses btree indexes exclusively — convert GIN to btree where possible.

### JSONB GIN → Expression Index on Extracted Key

```sql
-- PostgreSQL: GIN index on JSONB column
CREATE INDEX idx_users_prefs ON users USING gin (preferences);
-- Used for: preferences @> '{"theme":"dark"}'

-- DSQL: No equivalent index. JSONB operators work at runtime without index.
-- The query still works, just without index acceleration:
SELECT * FROM users WHERE preferences @> '{"theme":"dark"}';

-- If you need indexed lookup on a specific JSON key, index the extraction expression.
CREATE INDEX ASYNC idx_users_pref_theme ON users ((preferences->>'theme'));
-- Query: SELECT * FROM users WHERE preferences->>'theme' = 'dark';
```

### Array GIN → Join Table

```sql
-- PostgreSQL: GIN index on array column
CREATE INDEX idx_posts_tags ON posts USING gin (tags);
-- Used for: tags @> ARRAY['database']

-- DSQL: Array column types not supported. Normalize tags into a join table for
-- indexed lookup, or store as jsonb if indexed lookup isn't needed.
CREATE TABLE post_tags (
  post_id uuid NOT NULL,
  tag text NOT NULL
);
CREATE INDEX ASYNC idx_post_tags_tag ON post_tags (tag);
CREATE INDEX ASYNC idx_post_tags_post ON post_tags (post_id);
-- Query: SELECT DISTINCT post_id FROM post_tags WHERE tag = 'database';
```

### Full-Text Search GIN → External Service

```sql
-- PostgreSQL: GIN index for full-text search
CREATE INDEX idx_articles_search ON articles USING gin (to_tsvector('english', title || ' ' || body));

-- DSQL: No equivalent. Use OpenSearch/Elasticsearch for full-text search.
-- Store the text in DSQL, index in OpenSearch, query OpenSearch for IDs, then fetch from DSQL.
-- Remove the index entirely from the DSQL schema.
```

### Trigram GIN (pg_trgm) → Application Layer

```sql
-- PostgreSQL: Trigram index for LIKE '%pattern%'
CREATE INDEX idx_users_name_trgm ON users USING gin (name gin_trgm_ops);

-- DSQL: No equivalent. Options:
-- 1. Use prefix matching (LIKE 'pattern%') with a btree index
CREATE INDEX ASYNC idx_users_name ON users (name);
-- 2. Use OpenSearch for fuzzy/substring matching
-- 3. Accept full scan for infrequent LIKE '%pattern%' queries
```

---

## GiST Index Conversion

GiST indexes are used for geometric data, range types, and exclusion constraints.

### Geometric GiST → No Index

```sql
-- PostgreSQL: GiST index on point column
CREATE INDEX idx_locations_coords ON locations USING gist (coords);

-- DSQL: Geometric types are not supported — ERROR: 0A000: datatype point not supported
-- Option 1: Store lat/lng as separate numeric columns, index those
ALTER TABLE locations ADD COLUMN lat double precision;
ALTER TABLE locations ADD COLUMN lng double precision;
CREATE INDEX ASYNC idx_locations_lat ON locations (lat);
CREATE INDEX ASYNC idx_locations_lng ON locations (lng);
-- Bounding box queries: WHERE lat BETWEEN x1 AND x2 AND lng BETWEEN y1 AND y2

-- Option 2: Use a geohash text column for proximity queries
ALTER TABLE locations ADD COLUMN geohash text;
CREATE INDEX ASYNC idx_locations_geohash ON locations (geohash);
-- Prefix matching: WHERE geohash LIKE 'dr5ru%'
```

### Range GiST → Separate Columns

```sql
-- PostgreSQL: GiST index on range type
CREATE INDEX idx_events_during ON events USING gist (during);
-- Used for: during && '[2024-01-01, 2024-02-01)'

-- DSQL: Store range as two columns
CREATE TABLE events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  start_time timestamptz NOT NULL,
  end_time timestamptz NOT NULL
);
CREATE INDEX ASYNC idx_events_start ON events (start_time);
CREATE INDEX ASYNC idx_events_end ON events (end_time);
-- Overlap query: WHERE start_time < '2024-02-01' AND end_time > '2024-01-01'
```

---

## BRIN Index Conversion

BRIN indexes are used for large, naturally-ordered tables (time-series data).

```sql
-- PostgreSQL: BRIN index on timestamp column
CREATE INDEX idx_logs_created ON logs USING brin (created_at);

-- DSQL: Use btree. DSQL's PK-ordered storage provides similar benefits
-- if created_at correlates with PK order.
CREATE INDEX ASYNC idx_logs_created ON logs (created_at);

-- If the table is very large and you need to limit index size,
-- use a composite index with the most selective column first.
-- No ASC/DESC on index keys — see "Index Key Sort Order" below.
CREATE INDEX ASYNC idx_logs_tenant_created ON logs (tenant_id, created_at);
```

---

## Partial Indexes

DSQL supports partial indexes. Keep the WHERE clause — only add `ASYNC`.

```sql
-- PostgreSQL: Partial index
CREATE INDEX idx_orders_pending ON orders (customer_id, created_at)
  WHERE status = 'pending';

-- DSQL: WHERE clause preserved
CREATE INDEX ASYNC idx_orders_pending ON orders (customer_id, created_at)
  WHERE status = 'pending';
```

DSQL uses a partial index only when it can prove the query's WHERE conditions imply the index
predicate. Queries that do not mention `status` will not use the index above.

```sql
-- Eligible to use idx_orders_pending (status = 'pending' implies the predicate)
SELECT * FROM orders WHERE customer_id = $1 AND status = 'pending';

-- Does NOT use it — the predicate is not implied
SELECT * FROM orders WHERE customer_id = $1;
```

---

## Expression Indexes

DSQL supports expression indexes. Keep the expression — only add `ASYNC`.

```sql
-- PostgreSQL: Expression index
CREATE INDEX idx_users_email_lower ON users (lower(email));

-- DSQL: expression preserved
CREATE INDEX ASYNC idx_users_email_lower ON users ((lower(email)));
-- Query: WHERE lower(email) = lower($1)
```

```sql
-- PostgreSQL: Expression index on JSON field
CREATE INDEX idx_users_city ON users ((preferences->>'city'));

-- DSQL: expression preserved
CREATE INDEX ASYNC idx_users_city ON users ((preferences->>'city'));
-- Query: WHERE preferences->>'city' = 'Seattle'
```

All functions and operators in the expression must be IMMUTABLE. Mark user-defined functions
IMMUTABLE, and rebuild the index if the function definition changes.

**If the expression is not IMMUTABLE**, make it immutable rather than replacing the index:

```sql
-- Rejected: extract on timestamptz depends on the session time zone
CREATE INDEX ASYNC idx_orders_year ON orders ((extract(year FROM created_at)));
-- ERROR: 42P17: functions in index expression must be marked IMMUTABLE

-- Pin the time zone
CREATE INDEX ASYNC idx_orders_year
  ON orders ((extract(year FROM created_at AT TIME ZONE 'UTC')));
-- Query: WHERE extract(year FROM created_at AT TIME ZONE 'UTC') = 2024
--        must repeat the pinned expression, or the index is not used
```

A bare `created_at::timestamp` cast does NOT work — it depends on the session time zone too.

Do not reach for a computed column instead: `ALTER TABLE ... ADD COLUMN ... GENERATED` fails with
`ALTER TABLE ADD COLUMN with constraint not supported`, and the generation expression would have
to be IMMUTABLE anyway.

---

## Index Limits

| Limit                 | Value                                 | SQLSTATE | Message when exceeded                                   |
| --------------------- | ------------------------------------- | -------- | ------------------------------------------------------- |
| Max indexes per table | 24, **incl. the PK**                  | `54000`  | `more than 24 indexes per table are not allowed`        |
| Max columns per index | 8                                     | `54011`  | `more than 8 column keys in an index are not supported` |
| Max PK/index key size | ~1,981 bytes observed; docs say 1 KiB | `54000`  | `key size too large`                                    |

For what takes one of the 24 slots, the key-size budget and the rest of the limit set, see
[limits-and-error-codes.md](../limits-and-error-codes.md#exceeded-limits).

**Strategy when approaching 24 index limit:**

- Use composite indexes instead of multiple single-column indexes
- Use INCLUDE columns for covering indexes (avoids storage round-trips)
- Remove indexes for rarely-used query patterns
- Consider if the query can use an existing composite index with a prefix match

---

## Index Key Sort Order

**DSQL rejects `ASC`/`DESC` on index keys** — both of them, with
`ERROR: 0A000: specifying sort order not supported for index keys`. `dsql_lint` reports this as rule
`index_sort_direction` and `fix=true` strips the direction, but **the severity depends on which
direction you wrote**:

| Input             | `fix_result.status`  | `summary`                            |
| ----------------- | -------------------- | ------------------------------------ |
| `created_at DESC` | `fixed_with_warning` | `{errors: 0, warnings: 1, fixed: 0}` |
| `created_at ASC`  | `fixed`              | `{errors: 0, warnings: 0, fixed: 1}` |

So a pipeline that gates on `errors == 0`, or that consumes only `fixed_sql`, proceeds without
surfacing that the statement changed — and for `ASC` even a stricter pipeline gating on
`warnings == 0` proceeds, because `ASC` raises no warning at all. Review every diagnostic rather
than either counter, and see [dsql-lint.md](../dsql-lint.md) for what zero diagnostics does and
does not mean.

```sql
-- PostgreSQL
CREATE INDEX idx_logs_tenant_created ON logs (tenant_id, created_at DESC);

-- DSQL: ERROR: 0A000: specifying sort order not supported for index keys
-- Drop the direction:
CREATE INDEX ASYNC idx_logs_tenant_created ON logs (tenant_id, created_at);
```

**This costs no capability for a uniformly-ordered `ORDER BY`.** The planner reads an index
backwards, so a single direction-free index serves both directions. Against
`(tenant_id, created_at)`, with a projection the index covers:

| `ORDER BY`                        | Plan                                                          |
| --------------------------------- | ------------------------------------------------------------- |
| `tenant_id, created_at`           | `Index Only Scan`                                             |
| `tenant_id DESC, created_at DESC` | `Index Only Scan Backward`                                    |
| `tenant_id, created_at DESC`      | `Incremental Sort` above the scan, `Presorted Key: tenant_id` |
| `tenant_id DESC, created_at`      | `Incremental Sort` above a backward scan                      |

**The projection matters as much as the direction.** The plans above hold for
`SELECT tenant_id, created_at`. A secondary index is not covering, so `SELECT *` adds a `Sort` above
a primary-key scan in _all four_ cases — the ordering is lost to the column lookup, not to the
direction. Use `INCLUDE` to cover the projection, or accept the sort.

The rule is **direction uniformity over a leading prefix** — uniformity alone is not enough. An
`ORDER BY` is served by a scan when its keys are a leading prefix of the index keys _and_ all point
the same way. `ORDER BY created_at` is perfectly uniform and still gets a full `Sort` against
`(tenant_id, created_at)`, because `created_at` is not a prefix. A _mixed_-direction `ORDER BY` over
a prefix keeps the `Incremental Sort`, and no DSQL index can remove it, because index keys carry no
direction to match against. If a mixed ordering is on a hot path, either sort in the application or
store an inverted column (for example a negated numeric, or a computed descending rank) and order on
it uniformly.

### NULLS placement is retained

`NULLS FIRST` / `NULLS LAST` **is** accepted on an index key, and `dsql_lint` keeps it — only
`ASC`/`DESC` are removed. A backward scan flips the NULLS placement along with the direction, so
an index serves exactly two orderings: its own placement ascending, and the opposite placement
descending. A default index (`NULLS LAST`) therefore covers the two default forms:

| Index             | Served by forward scan   | Served by backward scan      |
| ----------------- | ------------------------ | ---------------------------- |
| `(a)`             | `ORDER BY a`             | `ORDER BY a DESC`            |
| `(a NULLS FIRST)` | `ORDER BY a NULLS FIRST` | `ORDER BY a DESC NULLS LAST` |

**Only add `NULLS FIRST` to serve a query that explicitly asks for it.** An index declared
`NULLS FIRST` no longer satisfies the plain `ORDER BY a` or `ORDER BY a DESC` — both fall back to
a `Sort` — so adding one to fix a single query can cost the default ordering on every other.
Nullable columns need no special handling otherwise: the default index covers both directions.

---

## Monitoring Async Index Status

Indexes created with ASYNC are not immediately usable. Monitor:

```sql
-- Check for indexes still being built
SELECT indexrelid::regclass AS index_name, indisvalid AS is_ready
FROM pg_index
WHERE NOT indisvalid;

-- If this returns rows, those indexes are still building.
-- Queries work but won't use the index until indisvalid = true.
```

**Do NOT rely on index performance until `indisvalid = true`.**

---

## Conversion Decision Flowchart

```
Is it a btree index?
├── Yes → CREATE INDEX ASYNC (preserve columns, INCLUDE, WHERE, IMMUTABLE expressions;
│         drop ASC/DESC — a backward scan serves uniformly-descending ORDER BY)
│
├── Is it GIN?
│   ├── For JSONB containment → unindexed at runtime; expression index for key equality
│   ├── For array ops → normalize to join table + btree
│   ├── For FTS → remove (use OpenSearch)
│   └── For trigram → remove or use prefix btree
│
├── Is it GiST?
│   ├── For geometry → separate lat/lng columns + btree
│   ├── For ranges → separate start/end columns + btree
│   └── For exclusion → remove (enforce in application)
│
├── Is it BRIN?
│   └── Convert to btree (DSQL PK-order gives similar benefit)
│
└── Is it CONCURRENTLY?
    └── Remove CONCURRENTLY, use ASYNC
```
