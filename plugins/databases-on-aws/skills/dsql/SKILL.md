---
name: dsql
description: "Build with Aurora DSQL — manage schemas, execute queries, handle migrations, diagnose query plans, diagnose cluster performance, load data, and develop applications with a serverless, distributed SQL database. Covers IAM auth, multi-tenant patterns, MySQL-to-DSQL and PostgreSQL-to-DSQL schema conversion, foreign key constraints, OCC retry patterns, ORM migration (Django/EF Core/Hibernate/Rails/SQLAlchemy), DDL operations, query plan explainability, system diagnostics via CloudWatch AAS, SQL compatibility validation, and bulk data loading. Triggers on phrases like: DSQL, Aurora DSQL, distributed SQL database, serverless PostgreSQL-compatible database, migrate to DSQL, DSQL query plan, DSQL EXPLAIN ANALYZE, DSQL ENUM, DSQL foreign key, DSQL OCC retry, DSQL multi-region, DSQL JSONB, DSQL GIN index, load into DSQL, load CSV into DSQL, bulk load DSQL, aurora-dsql-loader, DSQL slow, DSQL performance, DSQL wait events, DSQL AAS."
license: Apache-2.0
metadata:
  tags: aws, aurora, dsql, distributed-sql, distributed, distributed-database, database, serverless, serverless-database, postgresql, postgres, sql, schema, migration, multi-tenant, iam-auth, aurora-dsql, mcp, orm, enum, foreign-key, occ-retry, django, ef-core, dotnet, csharp, hibernate, rails, multi-region, schema-conversion, type-mapping, data-loading, system-diagnostics, wait-events, aas, performance, cloudwatch
---

# Amazon Aurora DSQL Skill

Aurora DSQL is a serverless, PostgreSQL-compatible distributed SQL database. This skill covers direct query execution via MCP tools, schema management, migrations, multi-tenant isolation, IAM auth, and bulk data loading via `aurora-dsql-loader`.

---

## Reference Files

Load these files as needed for detailed guidance:

### Core:

| Reference                                                 | When to Load                                        | Contains                                                                                 |
| --------------------------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [development-guide.md](references/development-guide.md)   | ALWAYS before schema changes or DB operations       | Best practices, DDL rules, transaction limits, foreign key constraints                   |
| [foreign-keys.md](references/foreign-keys.md)             | MUST load for foreign key operations or migrations  | FK syntax, actions, validation, tenant keys                                              |
| [language.md](references/language.md)                     | MUST load for language-specific choices             | Driver selection, DSQL Connectors, connection code                                       |
| [access-control.md](references/access-control.md)         | MUST load for roles, grants, or sensitive data      | Scoped role setup, IAM-to-database role mapping                                          |
| [troubleshooting.md](references/troubleshooting.md)       | SHOULD load for errors or unexpected behavior       | OCC and `23503` errors, FK validation, connection failures, cluster state, DDL rejection |
| [dsql-examples.md](references/dsql-examples.md)           | Load for implementation examples                    | Multi-tenant access, batch operations, identity and sequences, connection pooling        |
| [onboarding.md](references/onboarding.md)                 | User requests "Get started with DSQL"               | Interactive step-by-step guide                                                           |
| [occ-retry-patterns.md](references/occ-retry-patterns.md) | MUST load for OCC retry code or conflict mitigation | Connectors, `40001` retry, non-retryable `23503`, FK read conflicts, idempotent design   |

### MCP:

| Reference                               | When to Load                                                    | Contains                                                           |
| --------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------ |
| [mcp-setup.md](mcp/mcp-setup.md)        | Always for MCP server guidance                                  | Setup instructions, 2 configuration options                        |
| [mcp-tools.md](mcp/mcp-tools.md)        | For MCP tool syntax and examples                                | Tool parameters, [input validation](mcp/tools/input-validation.md) |
| [dsql-lint.md](references/dsql-lint.md) | MUST load before running `dsql_lint` or processing external SQL | Tool reference, fix statuses, unfixable error resolution           |

### DDL Migrations:

| Reference                                                                                     | When to Load                                                 | Contains                                               |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------ |
| [ddl-migrations/overview.md](references/ddl-migrations/overview.md)                           | MUST load for ALTER TYPE, SET NOT NULL, MODIFY PRIMARY KEY   | Direct ALTER coverage and last-resort table recreation |
| [ddl-migrations/column-operations.md](references/ddl-migrations/column-operations.md)         | DROP COLUMN, ALTER TYPE, SET/DROP NOT NULL/DEFAULT           | Column-level migration patterns                        |
| [ddl-migrations/constraint-operations.md](references/ddl-migrations/constraint-operations.md) | ADD/DROP CONSTRAINT, VALIDATE CONSTRAINT, MODIFY PRIMARY KEY | Constraint and structural changes                      |
| [ddl-migrations/batched-migration.md](references/ddl-migrations/batched-migration.md)         | Tables exceeding 3,000 rows                                  | Batching patterns, progress tracking                   |

### MySQL Migrations:

| Reference                                                                           | When to Load                         | Contains                                 |
| ----------------------------------------------------------------------------------- | ------------------------------------ | ---------------------------------------- |
| [mysql-migrations/type-mapping.md](references/mysql-migrations/type-mapping.md)     | MUST load for MySQL → DSQL migration | Data type mappings, feature alternatives |
| [mysql-migrations/ddl-operations.md](references/mysql-migrations/ddl-operations.md) | Translating MySQL DDL to DSQL        | AUTO_INCREMENT, ENUM, SET, FK patterns   |
| [mysql-migrations/full-example.md](references/mysql-migrations/full-example.md)     | Complete MySQL table migration       | End-to-end example with decision summary |

### PostgreSQL Migrations:

| Reference                                                                         | When to Load                                                     | Contains                                           |
| --------------------------------------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------- |
| [pg-migrations/type-mapping.md](references/pg-migrations/type-mapping.md)         | MUST load for DSQL NUMERIC or PG type questions                  | C collation rules, NUMERIC(p,s), JSON/JSONB        |
| [pg-migrations/index-conversion.md](references/pg-migrations/index-conversion.md) | MUST load for unfixable index diagnostics                        | GIN/GiST/BRIN → btree, partial, expression indexes |
| [pg-migrations/schema-objects.md](references/pg-migrations/schema-objects.md)     | MUST load for ENUM, materialized views, extensions, multi-schema | ENUM → CHECK, views, role/IAM mapping              |
| [pg-migrations/multi-region.md](references/pg-migrations/multi-region.md)         | Multi-region, active-active, or HA questions                     | Architecture, geographic partitioning              |

### ORM Guides:

| Reference                                                   | When to Load              | Contains                                                                 |
| ----------------------------------------------------------- | ------------------------- | ------------------------------------------------------------------------ |
| [orm-guides/overview.md](references/orm-guides/overview.md) | Migrating any ORM to DSQL | Adapter names, key gotchas for Django/EF Core/Hibernate/Rails/SQLAlchemy |

### Data Loading:

| Reference                                     | When to Load                                             | Contains                                                                                  |
| --------------------------------------------- | -------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| [data-loading.md](references/data-loading.md) | Planning or running bulk loads with `aurora-dsql-loader` | Fresh-vs-warm partitions, resume/retry, `--on-conflict` semantics, throughput diagnostics |

### System Diagnostics:

| Reference                                                                                 | When to Load                                                     | Contains                                                              |
| ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------- |
| [system-diagnostics/workflow.md](references/system-diagnostics/workflow.md)               | MUST load at Workflow 12 entry — cluster performance diagnostics | Prerequisites, 5 diagnostic phases, temporal comparison, handoff      |
| [system-diagnostics/wait-events.md](references/system-diagnostics/wait-events.md)         | ALWAYS load when interpreting AAS results                        | Canonical DSQL wait event descriptions and investigation guidance     |
| [system-diagnostics/promql-patterns.md](references/system-diagnostics/promql-patterns.md) | Load when constructing PromQL queries                            | Reusable query templates for AAS breakdown, top-SQL, temporal compare |

### Query Plan Explainability:

| Reference                                                                                           | When to Load                                          | Contains                                                                  |
| --------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------- |
| [query-plan/workflow.md](references/query-plan/workflow.md)                                         | MUST load at Workflow 9 entry — gates all other files | Trigger criteria, context disambiguation, routing, phased workflow        |
| [query-plan/plan-interpretation.md](references/query-plan/plan-interpretation.md)                   | MUST load at Workflow 9 Phase 0                       | DSQL node types, Node Duration math, estimation-error bands               |
| [query-plan/catalog-queries.md](references/query-plan/catalog-queries.md)                           | MUST load at Workflow 9 Phase 0                       | `pg_class`/`pg_stats`/`pg_indexes` SQL, correlated-predicate verification |
| [query-plan/guc-experiments.md](references/query-plan/guc-experiments.md)                           | MUST load at Workflow 9 Phase 0                       | GUC experiment procedures, 30-second skip protocol                        |
| [query-plan/report-format.md](references/query-plan/report-format.md)                               | MUST load at Workflow 9 Phase 0                       | Required report structure, element checklist, support request template    |
| [query-plan/query-rewrites-generic.md](references/query-plan/query-rewrites-generic.md)             | SHOULD load at Phase 0; sub-files on-demand           | Index of 10 generic rewrite patterns                                      |
| [query-plan/query-rewrites-dsql-specific.md](references/query-plan/query-rewrites-dsql-specific.md) | SHOULD load at Phase 0; sub-files on-demand           | Index of DSQL-specific rewrite patterns                                   |

---

## Choosing How to Connect: MCP vs CLI/psql

The `aurora-dsql` MCP server binds a **single cluster at startup** (`--cluster_endpoint`), so
using it for another cluster means editing `.mcp.json` and restarting the session.

- **Use the `aurora-dsql` MCP tools (`readonly_query`, `transact`, `get_schema`) ONLY when the
  server already targets the cluster you need.**
- **Otherwise — unconfigured, disabled, or bound to a different cluster — do NOT reconfigure it.**
  Use the CLI + `psql` path instead: [`scripts/psql-connect.sh`](../../scripts/psql-connect.sh)
  `<cluster-id> --region <region> --command "SELECT ..."` (mints an IAM token and runs via `psql`).
- **If you cannot confirm which cluster the MCP targets, confirm first or use the CLI/psql path** —
  running against the wrong cluster is worse than the check.

The doc-only MCP tools (`dsql_lint`, `dsql_*_documentation`, `dsql_recommend`) need no cluster.
The CloudWatch MCP (Workflow 12) takes `region`/`cluster_id` per call, so one running server can
query clusters in any PromQL-enabled region (pass each cluster's region on the call). Details:
[connectivity-tools.md](references/auth/connectivity-tools.md).

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

0. **Pick a connection path:** confirm the `aurora-dsql` MCP targets your cluster; if not, use the CLI/`psql` path instead — see [Choosing How to Connect](#choosing-how-to-connect-mcp-vs-clipsql). The steps below name MCP tools; the equivalent SQL runs the same way through `psql-connect.sh --command "..."`.
1. **Explore:** Use `readonly_query` with `information_schema` to list tables. Use `get_schema` for table structure.
2. **Query:** Use `readonly_query` for SELECT queries. **MUST** include `tenant_id` in WHERE for multi-tenant apps. **MUST** build SQL with `safe_query.build()`.
3. **Schema changes:** Use `transact` with one DDL per transaction. **MUST** batch DML under 3,000 rows. **MUST** use `CREATE INDEX ASYNC` in a separate call. Use `dsql_lint` to validate first.
4. **Bulk load data:** Use `aurora-dsql-loader` for CSV/TSV/Parquet. Load [data-loading.md](references/data-loading.md) for details. Use `--dry-run` first.

---

## Performance Routing

When the user reports a performance problem, use this table to select the correct workflow:

| User signal                                                                                                             | Route to                                                                           |
| ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| General performance complaint, "cluster is slow", "something changed", latency regression, no specific query identified | **Workflow 12** (System Diagnostics) — observe via CloudWatch first                |
| Specific query or query_id to investigate, "explain this plan", "why is this query slow"                                | **Workflow 9** (Query Plan Explainability) — direct EXPLAIN analysis               |
| OCC conflicts, commit errors, retry storms                                                                              | **Workflow 12** (System Diagnostics) — confirm via CW metrics before investigating |
| Cost optimization, "where is compute time spent"                                                                        | **Workflow 12** (System Diagnostics) — identify top contributors first             |

**Rule:** When in doubt, start with Workflow 12. It identifies specific queries to investigate and routes to Workflow 9 with context.

---

## Common Workflows

### Workflow 1: Create Multi-Tenant Schema

1. Create tenant-owned tables with `tenant_id` using separate `transact` calls
2. Use composite tenant FKs for tenant-owned parents and ordinary FKs for shared parents
3. Create tenant and query-pattern indexes with separate `CREATE INDEX ASYNC` calls
4. Verify with `get_schema`

- MUST issue each DDL in its own transact call: `transact(["CREATE TABLE ..."])`
- MUST serialize arrays into a single-column representation — DSQL has no array column type; PREFER `JSONB` (operators work directly); MAY use `TEXT` when the column is opaque to the database; ASK the user. For `JSONB` arrays, expand at query time with `jsonb_array_elements_text(data)`

### Workflow 2: Safe Data Migration

MUST validate every DDL with `dsql_lint(fix=true)` before executing. DML does not require linting.

1. Validate DDL with `dsql_lint(sql=..., fix=true)` — handle diagnostics per [dsql-lint.md](references/dsql-lint.md)
2. Execute the reviewed `fixed_sql` when present, otherwise the reviewed source statement
3. Add column in its own `transact` call
4. Populate existing rows with UPDATE (batched under 3,000 rows)
5. Verify with readonly_query COUNT
6. Create an index if needed: validate then execute the reviewed DDL in its own `transact` call

- MUST issue each `ALTER TABLE` in its own `transact` call — DSQL rejects multi-DDL transactions with `multiple ddl statements not supported in a transaction`
- MUST add column with only name and type; apply DEFAULT via separate UPDATE
- MUST batch updates under 3,000 rows in separate transact calls

**Recovery:** Resume failed batches by filtering `WHERE new_column IS NULL`.

### Workflow 3: Bulk Data Loading

Use `aurora-dsql-loader` for CSV, TSV, or Parquet loads. MUST load [data-loading.md](references/data-loading.md) before advising on throughput or diagnosing slow loads.

1. Validate with `--dry-run` first
2. Run with `--manifest-dir` on persistent storage (not `/tmp` — tmpfs on AL2023, lost on crash) and `--header` if file has a header row
3. On failure: resume with `--resume-job-id`; for duplicates use `--on-conflict do-nothing`
4. For large tables: create secondary indexes after load using `CREATE INDEX ASYNC`

### Workflow 4: Foreign Key Constraints

**MUST** load and follow [foreign-keys.md](references/foreign-keys.md)
before creating, altering, dropping, or migrating foreign keys.

### Workflow 5: Query with Tenant Isolation

1. **MUST** authorize the caller against the tenant — format validation does not establish authorization
2. **MUST** build SQL with [`safe_query.build()`](mcp/tools/safe_query.py) — use `allow()`/`regex()` for
   values (emits `'v'`), `ident()` for table/column names (emits `"v"`).
   See [input-validation.md](mcp/tools/input-validation.md)
3. **MUST** include `tenant_id` in the WHERE clause; reject cross-tenant access at the application layer

### Workflow 6: Set Up Scoped Database Roles

MUST load [access-control.md](references/access-control.md) for role setup, IAM mapping, and schema permissions.

### Workflow 7: Table Recreation DDL Migration

For `ALTER COLUMN TYPE`, `SET NOT NULL`, or `MODIFY PRIMARY KEY`, **MUST**
load [ddl-migrations/overview.md](references/ddl-migrations/overview.md). Use a direct ALTER form
when supported; otherwise, present a user-approved table-recreation plan.

### Workflow 8: Validate and Migrate to DSQL

MUST load [dsql-lint.md](references/dsql-lint.md) before running `dsql_lint`. Run `dsql_lint(sql=source_sql, fix=true)` to validate and auto-convert. For MySQL-origin SQL, MUST cross-check against [mysql-migrations/type-mapping.md](references/mysql-migrations/type-mapping.md) even when lint returns clean. On `parse_error`, fall back to manual conversion then re-lint.

### Workflow 9: Query Plan Explainability

Explains why the DSQL optimizer chose a particular plan. Triggered by slow queries, high DPU, unexpected Full Scans, or plans the user doesn't understand. **REQUIRES a structured Markdown diagnostic report as the deliverable.**

MUST load [query-plan/workflow.md](references/query-plan/workflow.md) at entry — it defines trigger criteria, context disambiguation, routing, and the full phased workflow (Phase 0–4). Workflow.md specifies which reference files to load at each phase.

**Safety.** Plan capture uses `readonly_query` exclusively. Rewrite DML to SELECT for plan capture. **MUST NOT** use `transact --allow-writes` for plan capture.

### Workflow 10: Full PostgreSQL → DSQL Schema Migration

MUST load [pg-migrations/type-mapping.md](references/pg-migrations/type-mapping.md), [pg-migrations/schema-objects.md](references/pg-migrations/schema-objects.md), and [foreign-keys.md](references/foreign-keys.md). Run `dsql_lint(fix=true)` first for mechanical fixes, preserve foreign-key relationships, translate unsupported source syntax or options, then apply semantic conversions from the pg-migrations references for unfixable diagnostics and patterns the linter cannot handle. Re-lint the final output before deploying.

### Workflow 11: ORM Migration (Django/EF Core/Hibernate/Rails/SQLAlchemy)

Load [orm-guides/overview.md](references/orm-guides/overview.md) for adapter names and framework-specific gotchas.

### Workflow 12: System Diagnostics (CloudWatch AAS)

Diagnose cluster performance by querying `db.active_sessions.avg` via PromQL. Detects temporal anomalies in wait event distribution, identifies regressed queries, and routes to Workflow 9 for per-query investigation.

**Requires:** CloudWatch MCP server (`awslabs.cloudwatch-mcp-server`) enabled and configured with PromQL access in the same region as the cluster — see [mcp/mcp-setup.md](mcp/mcp-setup.md#cloudwatch-mcp-server-system-diagnostics--workflow-12) for enabling it, region requirements, and the session restart needed for its tools to register.

MUST load [system-diagnostics/workflow.md](references/system-diagnostics/workflow.md) at entry — it defines prerequisites, 5 diagnostic phases, temporal baselines, and the routing to Workflow 9 for identified queries.

## Error Scenarios

- **`awsknowledge` returns no results:** Use the default limits in the table above and note that limits should be verified against [DSQL documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/).
- **`dsql_lint` unavailable or timing out:** See the Error Handling section of [dsql-lint.md](references/dsql-lint.md). Do not silently skip validation — inform the user and require explicit confirmation before proceeding with manual rules from [development-guide.md](references/development-guide.md).
- **OCC serialization error:** Retry the transaction. If persistent, check for hot-key contention — see [troubleshooting.md](references/troubleshooting.md).
- **Foreign key violation (`23503`):** Correct the relationship or referential action; **MUST NOT**
  send it through the `40001` retry loop — see [troubleshooting.md](references/troubleshooting.md).
- **Transaction exceeds limits:** Split into batches under 3,000 rows — see [batched-migration.md](references/ddl-migrations/batched-migration.md).
- **Token expiration mid-operation:** Generate a fresh IAM token — see [authentication-guide.md](references/auth/authentication-guide.md). See [troubleshooting.md](references/troubleshooting.md) for other issues.

## Additional Resources

- [Aurora DSQL Documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/)
- [Code Samples Repository](https://github.com/aws-samples/aurora-dsql-samples)
