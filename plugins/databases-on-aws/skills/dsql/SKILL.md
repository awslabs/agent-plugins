---
name: dsql
description: "Build with Aurora DSQL — manage schemas, execute queries, handle migrations, diagnose query plans, load data, and develop applications with a serverless, distributed SQL database. Covers IAM auth, multi-tenant patterns, MySQL-to-DSQL migration, PostgreSQL-to-DSQL schema conversion, PL/pgSQL transpilation, FK replacement code generation, OCC retry patterns, ORM migration (Django/Hibernate/Rails), DDL operations, query plan explainability, SQL compatibility validation, and bulk data loading. Triggers on phrases like: DSQL, Aurora DSQL, create DSQL table, DSQL schema, migrate to DSQL, convert to DSQL, PostgreSQL to DSQL, distributed SQL database, serverless PostgreSQL-compatible database, DSQL query plan, DSQL EXPLAIN ANALYZE, why is my DSQL query slow, DSQL ENUM, DSQL foreign key, DSQL PL/pgSQL, DSQL trigger, DSQL OCC retry, DSQL Django, DSQL Hibernate, DSQL Rails, DSQL multi-region, DSQL JSONB, DSQL index async, DSQL GIN index, aurora-dsql-loader, load CSV into DSQL."
license: Apache-2.0
metadata:
  tags: aws, aurora, dsql, distributed-sql, distributed, distributed-database, database, serverless, serverless-database, postgresql, postgres, sql, schema, migration, multi-tenant, iam-auth, aurora-dsql, mcp, orm, plpgsql, trigger, enum, foreign-key, occ-retry, django, hibernate, rails, multi-region, schema-conversion, type-mapping, data-loading
---

# Amazon Aurora DSQL Skill

Aurora DSQL is a serverless, PostgreSQL-compatible distributed SQL database. This skill covers direct query execution via MCP tools, schema management, migrations, multi-tenant isolation, IAM auth, and bulk data loading via `aurora-dsql-loader`.

---

## Reference Files

Load these files as needed for detailed guidance:

### Core:

| Reference                                                 | When to Load                                        | Contains                                                                                   |
| --------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| [development-guide.md](references/development-guide.md)   | ALWAYS before schema changes or DB operations       | Best practices, DDL rules, transaction limits, app-layer referential integrity             |
| [language.md](references/language.md)                     | MUST load for language-specific choices             | Driver selection, DSQL Connectors, connection code                                         |
| [access-control.md](references/access-control.md)         | MUST load for roles, grants, or sensitive data      | Scoped role setup, IAM-to-database role mapping                                            |
| [troubleshooting.md](references/troubleshooting.md)       | SHOULD load for errors or unexpected behavior       | OCC errors, connection failures, cluster state errors, token expiry, DDL rejection causes  |
| [dsql-examples.md](references/dsql-examples.md)           | Load for implementation examples                    | Multi-tenant schema examples, batch operations, FK validation patterns, connection pooling |
| [onboarding.md](references/onboarding.md)                 | User requests "Get started with DSQL"               | Interactive step-by-step guide                                                             |
| [occ-retry-patterns.md](references/occ-retry-patterns.md) | MUST load for OCC retry code or conflict mitigation | DSQL Connectors, manual retry pattern, idempotent design                                   |

### MCP:

| Reference                               | When to Load                                                    | Contains                                                           |
| --------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------ |
| [mcp-setup.md](mcp/mcp-setup.md)        | Always for MCP server guidance                                  | Setup instructions, 2 configuration options                        |
| [mcp-tools.md](mcp/mcp-tools.md)        | For MCP tool syntax and examples                                | Tool parameters, [input validation](mcp/tools/input-validation.md) |
| [dsql-lint.md](references/dsql-lint.md) | MUST load before running `dsql-lint` or processing external SQL | Tool reference, fix statuses, unfixable error resolution           |

### DDL Migrations:

| Reference                                                                                     | When to Load                                           | Contains                                |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------ | --------------------------------------- |
| [ddl-migrations/overview.md](references/ddl-migrations/overview.md)                           | MUST load for DROP COLUMN, ALTER TYPE, DROP CONSTRAINT | Table recreation pattern, verify & swap |
| [ddl-migrations/column-operations.md](references/ddl-migrations/column-operations.md)         | DROP COLUMN, ALTER TYPE, SET/DROP NOT NULL/DEFAULT     | Column-level migration patterns         |
| [ddl-migrations/constraint-operations.md](references/ddl-migrations/constraint-operations.md) | ADD/DROP CONSTRAINT, MODIFY PRIMARY KEY                | Constraint and structural changes       |
| [ddl-migrations/batched-migration.md](references/ddl-migrations/batched-migration.md)         | Tables exceeding 3,000 rows                            | Batching patterns, progress tracking    |

### MySQL Migrations:

| Reference                                                                           | When to Load                         | Contains                                 |
| ----------------------------------------------------------------------------------- | ------------------------------------ | ---------------------------------------- |
| [mysql-migrations/type-mapping.md](references/mysql-migrations/type-mapping.md)     | MUST load for MySQL → DSQL migration | Data type mappings, feature alternatives |
| [mysql-migrations/ddl-operations.md](references/mysql-migrations/ddl-operations.md) | Translating MySQL DDL to DSQL        | AUTO_INCREMENT, ENUM, SET, FK patterns   |
| [mysql-migrations/full-example.md](references/mysql-migrations/full-example.md)     | Complete MySQL table migration       | End-to-end example with decision summary |

### PostgreSQL Migrations:

| Reference                                                                         | When to Load                                                     | Contains                                           |
| --------------------------------------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------- |
| [pg-migrations/type-mapping.md](references/pg-migrations/type-mapping.md)         | MUST load for PG → DSQL type questions                           | C collation rules, NUMERIC precision, JSON/JSONB   |
| [pg-migrations/fk-replacement.md](references/pg-migrations/fk-replacement.md)     | MUST load for FK validation code generation                      | Tenant-scoped validate_fk_*() template, cascade    |
| [pg-migrations/index-conversion.md](references/pg-migrations/index-conversion.md) | MUST load for unfixable index diagnostics                        | GIN/GiST/BRIN → btree, partial, expression indexes |
| [pg-migrations/schema-objects.md](references/pg-migrations/schema-objects.md)     | MUST load for ENUM, materialized views, extensions, multi-schema | ENUM → CHECK, views, role/IAM mapping              |
| [pg-migrations/multi-region.md](references/pg-migrations/multi-region.md)         | Multi-region, active-active, or HA questions                     | Architecture, geographic partitioning              |

### ORM Guides:

| Reference                                                   | When to Load              | Contains                                                         |
| ----------------------------------------------------------- | ------------------------- | ---------------------------------------------------------------- |
| [orm-guides/overview.md](references/orm-guides/overview.md) | Migrating any ORM to DSQL | Adapter names, key gotchas for Django/Hibernate/Rails/SQLAlchemy |

### Query Plan Explainability:

**When:** Load when debugging errors or unexpected behavior. SHOULD always consult for OCC errors, connection failures, or unexpected query results.
**Contains:** Common pitfalls, error messages, solutions

### [data-loading.md](references/data-loading.md)

**When:** Load when planning or running bulk loads with `aurora-dsql-loader`, or diagnosing slow load times.
**Contains:** Fresh-vs-warm partition behavior, resume/retry mechanics (`--manifest-dir`, `--resume-job-id`), `--on-conflict do-nothing` semantics, schema inference caveats, index-count throughput impact, diagnostic decision tree

### [onboarding.md](references/onboarding.md)

**When:** User explicitly requests to "Get started with DSQL" or similar phrase
**Contains:** Interactive step-by-step guide for new users

### [access-control.md](references/access-control.md)

**When:** MUST load when creating database roles, granting permissions, setting up schemas for applications, or handling sensitive data. ALWAYS use scoped roles for applications — create database roles with `dsql:DbConnect`.
**Contains:** Scoped role setup, IAM-to-database role mapping, schema separation for sensitive data, role design patterns

### DDL Migrations (modular):

#### [ddl-migrations/overview.md](references/ddl-migrations/overview.md)

**When:** MUST load when performing DROP COLUMN, RENAME COLUMN, ALTER COLUMN TYPE, or DROP CONSTRAINT
**Contains:** Table recreation pattern overview, transaction rules, common verify & swap pattern

#### [ddl-migrations/column-operations.md](references/ddl-migrations/column-operations.md)

**When:** Load for DROP COLUMN, ALTER COLUMN TYPE, SET/DROP NOT NULL, SET/DROP DEFAULT migrations
**Contains:** Step-by-step migration patterns for column-level changes

#### [ddl-migrations/constraint-operations.md](references/ddl-migrations/constraint-operations.md)

**When:** Load for ADD/DROP CONSTRAINT, MODIFY PRIMARY KEY, column split/merge migrations
**Contains:** Step-by-step migration patterns for constraint and structural changes

#### [ddl-migrations/batched-migration.md](references/ddl-migrations/batched-migration.md)

**When:** Load when migrating tables exceeding 3,000 rows
**Contains:** OFFSET-based and cursor-based batching patterns, progress tracking, error handling

### MySQL Migrations (modular):

#### [mysql-migrations/type-mapping.md](references/mysql-migrations/type-mapping.md)

**When:** MUST load when migrating MySQL schemas to DSQL
**Contains:** MySQL data type mappings, feature alternatives, DDL operation mapping

#### [mysql-migrations/ddl-operations.md](references/mysql-migrations/ddl-operations.md)

**When:** Load when translating MySQL DDL operations to DSQL equivalents
**Contains:** ALTER COLUMN, DROP COLUMN, AUTO_INCREMENT, ENUM, SET, FOREIGN KEY migration patterns

#### [mysql-migrations/full-example.md](references/mysql-migrations/full-example.md)

**When:** Load when migrating a complete MySQL table to DSQL
**Contains:** End-to-end MySQL CREATE TABLE migration example with decision summary

### Query Plan Explainability (modular):

**When:** MUST load all four at Workflow 9 Phase 0 — [query-plan/plan-interpretation.md](references/query-plan/plan-interpretation.md), [query-plan/catalog-queries.md](references/query-plan/catalog-queries.md), [query-plan/guc-experiments.md](references/query-plan/guc-experiments.md), [query-plan/report-format.md](references/query-plan/report-format.md)
**Contains:** DSQL node types + Node Duration math + estimation-error bands, pg_class/pg_stats/pg_indexes SQL + correlated-predicate verification, GUC experiment procedures + 30-second skip protocol, required report structure + element checklist + support request template

### SQL Compatibility Validation:

#### [dsql-lint.md](references/dsql-lint.md)

**When:** MUST load before running `dsql_lint`, processing externally-sourced SQL (pg_dump, ORM migrations, user-pasted DDL), or resolving `fixed_with_warning` / unfixable diagnostics
**Contains:** `dsql_lint` MCP tool reference, fix statuses, ORM integration, unfixable error resolution

---

## MCP Tools Available

The `aurora-dsql` MCP server provides these tools:

**Database Operations:**

1. **readonly_query** - Execute SELECT queries (returns list of dicts)
2. **transact** - Execute DDL/DML statements in transaction (takes list of SQL statements)
3. **get_schema** - Get table structure for a specific table

**SQL Validation:**

1. **dsql_lint** - Validate SQL for DSQL compatibility and optionally auto-fix issues. Use before executing externally-sourced SQL.

**Documentation & Knowledge:**

1. **dsql_search_documentation** - Search Aurora DSQL documentation
2. **dsql_read_documentation** - Read specific documentation pages
3. **dsql_recommend** - Get DSQL best practice recommendations

**Note:** There is no `list_tables` tool. Use `readonly_query` with information_schema.

See [mcp-setup.md](mcp/mcp-setup.md) for detailed setup instructions.
See [mcp-tools.md](mcp/mcp-tools.md) for detailed usage and examples.

### AWS Knowledge MCP (`awsknowledge`)

Consult for verifying DSQL service limits before advising users. The numeric limits below are
defaults that may change — when a user's decision depends on an exact limit, verify it first:

| Limit                          | Default       | Verify query                       |
| ------------------------------ | ------------- | ---------------------------------- |
| Max rows per transaction       | 3,000         | `aurora dsql transaction limits`   |
| Max data size per transaction  | 10 MiB        | `aurora dsql transaction limits`   |
| Max transaction duration       | 5 minutes     | `aurora dsql transaction limits`   |
| Max connections per cluster    | 10,000        | `aurora dsql connection limits`    |
| Auth token expiry              | 15 minutes    | `aurora dsql authentication token` |
| Max connection duration        | 60 minutes    | `aurora dsql connection limits`    |
| Max indexes per table          | 24            | `aurora dsql index limits`         |
| Max columns per index          | 8             | `aurora dsql index limits`         |
| IDENTITY/SEQUENCE CACHE values | 1 or >= 65536 | `aurora dsql sequence cache`       |
| Supported column data types    | See docs      | `aurora dsql supported data types` |

**When to verify:** Before recommending batch sizes, connection pool settings, or schema designs where hitting a limit would cause failures; any time the exact number can affect user decision.

**Fallback:** If `awsknowledge` is unavailable, use the defaults above and flag that limits should be verified against [DSQL documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/).

## CLI Scripts Available

Bash scripts in [scripts/](../../scripts/) for cluster management (create, delete, list, cluster info), psql connection, and bulk data loading from local/s3 csv/tsv/parquet files.
See [scripts/README.md](../../scripts/README.md) for usage and hook configuration.

---

## Quick Start

1. **Explore:** Use `readonly_query` with `information_schema` to list tables. Use `get_schema` for table structure.
2. **Query:** Use `readonly_query` for SELECT queries. **MUST** include `tenant_id` in WHERE for multi-tenant apps. **MUST** build SQL with `safe_query.build()`.
3. **Schema changes:** Use `transact` with one DDL per transaction. **MUST** batch DML under 3,000 rows. **MUST** use `CREATE INDEX ASYNC` in a separate call. Use `dsql_lint` to validate first.
4. **Bulk load data:** Use `aurora-dsql-loader` for CSV/TSV/Parquet. Load [data-loading.md](references/data-loading.md) for details. Use `--dry-run` first.

---

## Common Workflows

### Workflow 1: Create Multi-Tenant Schema

1. Create main table with tenant_id column using transact
2. Create async index on tenant_id in separate transact call
3. Create composite indexes for common query patterns (separate transact calls)
4. Verify schema with get_schema

- MUST include tenant_id in all tables
- MUST use `CREATE INDEX ASYNC` exclusively
- MUST issue each DDL in its own transact call: `transact(["CREATE TABLE ..."])`
- MUST serialize arrays as JSONB; expand at query time with `jsonb_array_elements_text(data)`

### Workflow 2: Safe Data Migration

MUST validate every DDL with `dsql-lint(fix=true)` before executing. DML does not require linting.

1. Validate DDL with `dsql-lint(sql=..., fix=true)` — handle diagnostics per [dsql-lint.md](references/dsql-lint.md)
2. Add column: `transact(["ALTER TABLE ... ADD COLUMN ..."])`
3. Populate existing rows with UPDATE (batched under 3,000 rows)
4. Verify with readonly_query COUNT
5. Create index if needed: validate then `transact(["CREATE INDEX ASYNC ..."])`

- MUST add column with only name and type; apply DEFAULT via separate UPDATE
- MUST batch updates under 3,000 rows in separate transact calls

**Recovery:** Resume failed batches by filtering `WHERE new_column IS NULL`.

### Workflow 3: Bulk Data Loading

Use `aurora-dsql-loader` for CSV, TSV, or Parquet loads. MUST load [data-loading.md](references/data-loading.md) before advising on throughput or diagnosing slow loads.

1. Validate with `--dry-run` first
2. Run with `--manifest-dir` on persistent storage (not `/tmp` — tmpfs on AL2023, lost on crash) and `--header` if file has a header row
3. On failure: resume with `--resume-job-id`; for duplicates use `--on-conflict do-nothing`
4. For large tables: create secondary indexes after load using `CREATE INDEX ASYNC`

### Workflow 4: Application-Layer Referential Integrity

**INSERT:** MUST validate parent exists with readonly_query → throw error if not found → insert child with transact.

**DELETE:** MUST check dependents with readonly_query COUNT → return error if dependents exist → delete with transact if safe.

### Workflow 5: Query with Tenant Isolation

1. **MUST** authorize the caller against the tenant — format validation does not establish authorization
2. **MUST** build SQL with [`safe_query.build()`](mcp/tools/safe_query.py) — use `allow()`/`regex()` for
   values (emits `'v'`), `ident()` for table/column names (emits `"v"`).
   See [input-validation.md](mcp/tools/input-validation.md)
3. **MUST** include `tenant_id` in the WHERE clause; reject cross-tenant access at the application layer

### Workflow 6: Set Up Scoped Database Roles

MUST load [access-control.md](references/access-control.md) for role setup, IAM mapping, and schema permissions.

### Workflow 7: Table Recreation DDL Migration

Use the **Table Recreation Pattern** for `ALTER COLUMN TYPE`, `DROP COLUMN`, `DROP CONSTRAINT`, or `MODIFY PRIMARY KEY`. This is a destructive workflow that requires user confirmation at each step. Every generated DDL in the pattern (CREATE new, INSERT ... SELECT, DROP old, RENAME) MUST be validated with `dsql-lint(sql=..., fix=true)` before execution.

MUST load [ddl-migrations/overview.md](references/ddl-migrations/overview.md) before attempting any of these operations.

### Workflow 8: Validate and Migrate to DSQL

MUST load [dsql-lint.md](references/dsql-lint.md) before running `dsql-lint`. Run `dsql-lint(sql=source_sql, fix=true)` to validate and auto-convert. For MySQL-origin SQL, MUST cross-check against [mysql-migrations/type-mapping.md](references/mysql-migrations/type-mapping.md) even when lint returns clean. On `parse_error`, fall back to manual conversion then re-lint.

### Workflow 9: Query Plan Explainability

Explains why the DSQL optimizer chose a particular plan. Triggered by slow queries, high DPU, unexpected Full Scans, or plans the user doesn't understand. **REQUIRES a structured Markdown diagnostic report as the deliverable.**

MUST load all four reference files at Phase 0: [query-plan/plan-interpretation.md](references/query-plan/plan-interpretation.md), [query-plan/catalog-queries.md](references/query-plan/catalog-queries.md), [query-plan/guc-experiments.md](references/query-plan/guc-experiments.md), [query-plan/report-format.md](references/query-plan/report-format.md). The phase procedures (capture plan, gather evidence, experiment, produce report) are defined in those files.

**Safety.** Plan capture uses `readonly_query` exclusively. Rewrite DML to SELECT for plan capture. **MUST NOT** use `transact --allow-writes` for plan capture.

### Workflow 10: Full PostgreSQL → DSQL Schema Migration

MUST load [pg-migrations/type-mapping.md](references/pg-migrations/type-mapping.md) and [pg-migrations/schema-objects.md](references/pg-migrations/schema-objects.md). Run `dsql-lint(fix=true)` first for mechanical fixes, then apply semantic conversions from the pg-migrations references for unfixable diagnostics and patterns the linter cannot handle. Re-lint the final output before deploying.

### Workflow 11: ORM Migration (Django/Hibernate/Rails)

Load [orm-guides/overview.md](references/orm-guides/overview.md) for adapter names and framework-specific gotchas.

## Error Scenarios

- **`awsknowledge` returns no results:** Use the default limits in the table above and note that limits should be verified against [DSQL documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/).
- **`dsql-lint` unavailable or timing out:** See the Error Handling section of [dsql-lint.md](references/dsql-lint.md). Do not silently skip validation — inform the user and require explicit confirmation before proceeding with manual rules from [development-guide.md](references/development-guide.md).
- **OCC serialization error:** Retry the transaction. If persistent, check for hot-key contention — see [troubleshooting.md](references/troubleshooting.md).
- **Transaction exceeds limits:** Split into batches under 3,000 rows — see [batched-migration.md](references/ddl-migrations/batched-migration.md).
- **Token expiration mid-operation:** Generate a fresh IAM token — see [authentication-guide.md](references/auth/authentication-guide.md). See [troubleshooting.md](references/troubleshooting.md) for other issues.

## Additional Resources

- [Aurora DSQL Documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/)
- [Code Samples Repository](https://github.com/aws-samples/aurora-dsql-samples)
