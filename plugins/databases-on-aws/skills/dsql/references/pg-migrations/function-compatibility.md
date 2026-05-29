# PostgreSQL Function Compatibility in DSQL

Reference for which built-in PostgreSQL functions work in Aurora DSQL, which need
replacements, and what alternatives exist. `dsql-lint` does not check function usage —
use this reference when migrating application code and stored functions.

Sources:

- [Supported SQL Features](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-supported-sql-features.html)
- [Supported Data Types — JSON Functions](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-supported-data-types.html)
- [Migration Guide](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-migration-guide.html)

## Table of Contents

1. [Common Function Replacements](#common-function-replacements)
2. [Fully Supported Functions](#fully-supported-functions)
3. [Partially Supported Functions](#partially-supported-functions)
4. [Not Supported — With Alternatives](#not-supported--with-alternatives)
5. [Maintenance Commands](#maintenance-commands)
6. [Transaction Control](#transaction-control)
7. [Migration Checklist for Function Usage](#migration-checklist-for-function-usage)

---

## Common Function Replacements

These are the most frequently encountered replacements during migration:

| PostgreSQL Function           | DSQL Replacement           | Notes                           |
| ----------------------------- | -------------------------- | ------------------------------- |
| `uuid_generate_v4()`          | `gen_random_uuid()`        | Built-in, no extension needed   |
| `lastval()`                   | `currval('sequence_name')` | Must use explicit sequence name |
| `pg_notify(channel, payload)` | SNS/SQS/EventBridge        | Application-layer messaging     |
| `pg_advisory_lock(id)`        | DynamoDB conditional write | Application-layer locking       |
| `to_tsvector(text)`           | OpenSearch/Elasticsearch   | Application-layer FTS           |
| `COPY FROM/TO`                | Batched INSERT             | Max 3,000 rows per transaction  |

### uuid_generate_v4() → gen_random_uuid()

```sql
-- PostgreSQL (requires uuid-ossp extension)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
INSERT INTO users (id) VALUES (uuid_generate_v4());

-- DSQL (built-in, no extension)
INSERT INTO users (id) VALUES (gen_random_uuid());

-- In DEFAULT clauses:
CREATE TABLE users (id uuid PRIMARY KEY DEFAULT gen_random_uuid());
```

**grep pattern:** `uuid_generate_v4` — replace all occurrences with `gen_random_uuid()`

### lastval() → currval('sequence_name')

```sql
-- PostgreSQL
INSERT INTO orders (customer_id) VALUES (1);
SELECT lastval();  -- returns the last sequence value from any sequence

-- DSQL: lastval() not supported. Use explicit sequence name.
INSERT INTO orders (id, customer_id) VALUES (nextval('orders_id_seq'), 1);
SELECT currval('orders_id_seq');  -- explicit sequence name required
```

**grep pattern:** `lastval()` — replace with `currval('explicit_sequence_name')`

### COPY → Batched INSERT

```sql
-- PostgreSQL
COPY users (id, email, name) FROM '/path/to/data.csv' WITH (FORMAT csv, HEADER);

-- DSQL: COPY not supported. Use batched INSERT (500-1000 rows per transaction).
BEGIN;
INSERT INTO users (id, email, name) VALUES
  ('uuid1', 'a@b.com', 'Alice'),
  ('uuid2', 'c@d.com', 'Bob'),
  -- ... up to 500-1000 rows
  ;
COMMIT;
-- Repeat for next batch
```

---

## Fully Supported Functions

### Aggregate Functions

`COUNT(*)`, `COUNT(col)`, `SUM`, `AVG`, `MIN`, `MAX`, `bool_and`, `bool_or`,
`string_agg`, `array_agg` (runtime), `json_agg`, `jsonb_agg`, `json_object_agg`

### String Functions

`length`, `char_length`, `lower`, `upper`, `trim`, `ltrim`, `rtrim`, `substring`,
`position`, `replace`, `concat`, `concat_ws`, `left`, `right`, `repeat`, `reverse`,
`split_part`, `format`, `encode`, `decode`, `md5`, `regexp_replace`, `regexp_match`

### Numeric Functions

`abs`, `ceil`, `floor`, `round`, `trunc`, `mod`, `power`, `sqrt`, `random`,
`greatest`, `least`

### Date/Time Functions

`now()`, `current_timestamp`, `current_date`, `current_time`, `clock_timestamp()`,
`date_trunc`, `date_part`, `extract`, `age`, `make_interval`, `make_date`,
`to_char`, `to_date`, `to_timestamp`

### JSON Functions (all PostgreSQL 9.16 functions work)

`json_build_object`, `json_build_array`, `jsonb_build_object`, `jsonb_build_array`,
`row_to_json`, `json_extract_path`, `json_extract_path_text`, `json_each`,
`json_array_elements`, `jsonb_set`, `jsonb_strip_nulls`, `json_typeof`,
`json_array_length`, `->`, `->>`, `#>`, `#>>`, `@>`, `?`

### Window Functions

`ROW_NUMBER()`, `RANK()`, `DENSE_RANK()`, `LAG()`, `LEAD()`, `FIRST_VALUE()`,
`LAST_VALUE()`, `NTH_VALUE()`, `NTILE()`, `SUM/AVG/COUNT OVER (...)`

### Conditional & Subquery

`CASE WHEN`, `COALESCE`, `NULLIF`, `GREATEST`, `LEAST`, `EXISTS`, `IN`, `ANY`, `ALL`

### Sequence Functions

`nextval(regclass)` ✅, `currval(regclass)` ✅, `setval(regclass, bigint)` ✅

### Type Casting

`CAST(x AS type)` ✅, `x::type` ✅, `x::jsonb` ✅ (runtime cast)

---

## Partially Supported Functions

### generate_series()

```sql
-- Works for integer and timestamp series
SELECT generate_series(1, 100);  -- ✅
SELECT generate_series('2024-01-01'::timestamp, '2024-12-31'::timestamp, '1 month');  -- ✅

-- LIMITATION: If used in INSERT, results count toward 3,000 row limit
INSERT INTO numbers SELECT generate_series(1, 5000);  -- ❌ exceeds limit
INSERT INTO numbers SELECT generate_series(1, 2000);  -- ✅ under limit
```

### array_agg() / ARRAY constructor

```sql
-- Works at runtime (SELECT)
SELECT array_agg(name) FROM users WHERE org_id = 1;  -- ✅ returns text[]

-- Use json_agg() to persist array results (arrays are runtime-only):
-- Cannot store result in a column — use json_agg() instead
SELECT json_agg(name) FROM users WHERE org_id = 1;  -- ✅ storable as json
```

### unnest()

```sql
-- Works with runtime arrays
SELECT unnest(ARRAY['a','b','c']);  -- ✅
-- Works with json arrays
SELECT json_array_elements_text('["a","b","c"]'::json);  -- ✅
```

---

## Not Supported — With Alternatives

### Full-Text Search

| Function                     | Alternative                  |
| ---------------------------- | ---------------------------- |
| `to_tsvector(config, text)`  | OpenSearch / Elasticsearch   |
| `to_tsquery(config, text)`   | OpenSearch / Elasticsearch   |
| `ts_rank(tsvector, tsquery)` | OpenSearch relevance scoring |
| `plainto_tsquery(text)`      | OpenSearch query parser      |
| `@@` operator                | OpenSearch query             |

### Advisory Locks

| Function                   | Alternative                               |
| -------------------------- | ----------------------------------------- |
| `pg_advisory_lock(id)`     | DynamoDB conditional write or Redis SETNX |
| `pg_advisory_unlock(id)`   | DynamoDB delete or Redis DEL              |
| `pg_try_advisory_lock(id)` | DynamoDB conditional write (non-blocking) |

### Notification

| Function                      | Alternative                      |
| ----------------------------- | -------------------------------- |
| `pg_notify(channel, payload)` | Amazon SNS Publish               |
| `LISTEN channel`              | SQS polling or EventBridge rules |
| `NOTIFY channel`              | SNS Publish                      |

### System/Admin Functions

| Function                        | Notes                                |
| ------------------------------- | ------------------------------------ |
| `pg_table_size(table)`          | Not available (DSQL manages storage) |
| `pg_total_relation_size(table)` | Not available                        |
| `pg_stat_activity`              | Not available                        |
| `pg_cancel_backend(pid)`        | Not available                        |
| `pg_terminate_backend(pid)`     | Not available                        |
| `current_setting(name)`         | Limited (no custom GUCs)             |
| `set_config(name, val, local)`  | Not available                        |

### Large Object Functions

| Function               | Alternative              |
| ---------------------- | ------------------------ |
| `lo_create(oid)`       | Use S3 for large objects |
| `lo_import(path)`      | Upload to S3             |
| `lo_export(oid, path)` | Download from S3         |

---

## Maintenance Commands

| Command         | DSQL Behavior                       |
| --------------- | ----------------------------------- |
| VACUUM          | Not needed — automatic              |
| VACUUM ANALYZE  | Not needed — automatic              |
| ANALYZE (table) | Supported (relation name only)      |
| REINDEX         | Not needed — automatic              |
| CLUSTER         | Not applicable (PK-ordered storage) |

**Migration action:** Remove all VACUUM, REINDEX, and CLUSTER from maintenance scripts/cron jobs.

---

## Transaction Control

| Command                         | DSQL Support                  |
| ------------------------------- | ----------------------------- |
| BEGIN / COMMIT / ROLLBACK       | ✅                            |
| SAVEPOINT                       | ❌ Not supported              |
| RELEASE SAVEPOINT               | ❌ Not supported              |
| ROLLBACK TO SAVEPOINT           | ❌ Not supported              |
| SET TRANSACTION ISOLATION LEVEL | Only REPEATABLE READ accepted |

**Migration action:** Restructure any code using savepoints into separate transactions.

---

## Migration Checklist for Function Usage

1. **grep for `uuid_generate_v4`** → replace with `gen_random_uuid()`
2. **grep for `lastval()`** → replace with `currval('sequence_name')`
3. **grep for `COPY FROM` / `COPY TO`** → replace with batched INSERT
4. **grep for `pg_notify` / `LISTEN` / `NOTIFY`** → replace with SNS/SQS/EventBridge
5. **grep for `pg_advisory_lock`** → replace with DynamoDB/Redis
6. **grep for `to_tsvector` / `@@`** → replace with OpenSearch
7. **grep for `VACUUM` / `REINDEX` / `CLUSTER`** → remove from scripts
8. **grep for `SAVEPOINT`** → restructure into separate transactions
9. **grep for `lo_create` / `lo_import`** → replace with S3
10. **Test ORDER BY** results with C collation — may differ from locale-aware PostgreSQL
