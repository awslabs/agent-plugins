---
name: dsql
description: "Build with Aurora DSQL — manage schemas, execute queries, handle migrations, and develop applications with a serverless, distributed SQL database. Covers IAM auth, multi-tenant patterns, MySQL-to-DSQL migration, and DDL operations. Triggers on phrases like: DSQL, Aurora DSQL, create DSQL table, DSQL schema, migrate to DSQL, distributed SQL database, serverless PostgreSQL-compatible database."
license: Apache-2.0
metadata:
  tags: aws, aurora, dsql, distributed-sql, distributed, distributed-database, database, serverless, serverless-database, postgresql, postgres, sql, schema, migration, multi-tenant, iam-auth, aurora-dsql, mcp
---

# Amazon Aurora DSQL Skill

Aurora DSQL is a serverless, PostgreSQL-compatible distributed SQL database. This skill provides direct database interaction via MCP tools, schema management, migration support, and multi-tenant patterns.

**Key capabilities:**

- Direct query execution via MCP tools
- Schema management with DSQL constraints
- Migration support and safe schema evolution
- Multi-tenant isolation patterns
- IAM-based authentication

---

## Reference Files

Load these files as needed for detailed guidance:

### [development-guide.md](references/development-guide.md)

**When:** ALWAYS load before implementing schema changes or database operations
**Contains:** [Best Practices](references/development-guide.md#best-practices), DDL rules, connection patterns, transaction limits, data type serialization patterns, application-layer referential integrity instructions, security best practices

### MCP:

#### [mcp-setup.md](mcp/mcp-setup.md)

**When:** Always load for guidance using or updating the DSQL MCP server
**Contains:** Instructions for setting up the DSQL MCP server with 2 configuration options as
sampled in [.mcp.json](../../.mcp.json)

1. Documentation-Tools Only
2. Database Operations (requires a cluster endpoint)

#### [mcp-tools.md](mcp/mcp-tools.md)

**When:** Load when you need detailed MCP tool syntax and examples. PREFER MCP tools for ad-hoc queries — execute directly rather than writing scripts.
**Contains:** Tool parameters, detailed examples, usage patterns, [input validation](mcp/tools/input-validation.md)

### [language.md](references/language.md)

**When:** MUST load when making language-specific implementation choices. ALWAYS prefer DSQL Connector when available.
**Contains:** Driver selection, framework patterns, connection code for Python/JS/Go/Java/Rust

### [dsql-examples.md](references/dsql-examples.md)

**When:** Load when looking for specific implementation examples
**Contains:** Code examples, repository patterns, multi-tenant implementations

### [troubleshooting.md](references/troubleshooting.md)

**When:** Load when debugging errors or unexpected behavior. SHOULD always consult for OCC errors, connection failures, or unexpected query results.
**Contains:** Common pitfalls, error messages, solutions

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

---

## MCP Tools Available

The `aurora-dsql` MCP server provides these tools:

**Database Operations:**

1. **readonly_query** - Execute SELECT queries (returns list of dicts)
2. **transact** - Execute DDL/DML statements in transaction (takes list of SQL statements)
3. **get_schema** - Get table structure for a specific table

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

**When to verify:** Before recommending batch sizes, connection pool settings, or schema designs
where hitting a limit would cause failures. No need to verify for general guidance or when
the exact number doesn't affect the user's decision.

**Fallback:** If `awsknowledge` is unavailable, use the defaults above and note to the user
that limits should be verified against [DSQL documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/).

---

## CLI Scripts Available

Bash scripts in [scripts/](../../scripts/) for cluster management (create, delete, list, cluster info), psql connection, and bulk data loading from local/s3 csv/tsv/parquet files.
See [scripts/README.md](../../scripts/README.md) for usage and hook configuration.

---

## Quick Start

### 1. List tables and explore schema

```
Use readonly_query with information_schema to list tables
Use get_schema to understand table structure
```

### 2. Query data

```
Use readonly_query for SELECT queries
Always include tenant_id in WHERE clause for multi-tenant apps
Validate inputs carefully (no parameterized queries available)
```

### 3. Execute schema changes

```
Use transact tool with list of SQL statements
Follow one-DDL-per-transaction rule
Always use CREATE INDEX ASYNC in separate transaction
ALTER COLUMN TYPE, DROP COLUMN, DROP CONSTRAINT are NOT supported directly
  → These require the Table Recreation Pattern (see Workflow 6)
```

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
- MUST store arrays/JSON as TEXT

### Workflow 2: Safe Data Migration

1. Add column using transact: `transact(["ALTER TABLE ... ADD COLUMN ..."])`
2. Populate existing rows with UPDATE in separate transact calls (batched under 3,000 rows)
3. Verify migration with readonly_query using COUNT
4. Create async index for new column using transact if needed

- MUST add column first, populate later
- MUST issue ADD COLUMN with only name and type; apply DEFAULT via separate UPDATE
- MUST batch updates under 3,000 rows in separate transact calls
- MUST issue each ALTER TABLE in its own transaction

### Workflow 3: Application-Layer Referential Integrity

**INSERT:** MUST validate parent exists with readonly_query → throw error if not found → insert child with transact.

**DELETE:** MUST check dependents with readonly_query COUNT → return error if dependents exist → delete with transact if safe.

### Workflow 4: Query with Tenant Isolation

1. ALWAYS include tenant_id in WHERE clause
2. MUST validate and sanitize tenant_id input (no parameterized queries!)
3. MUST use readonly_query with validated tenant_id

- MUST validate ALL inputs before building SQL (SQL injection risk!)
- MUST reject cross-tenant access at application layer
- SHOULD use allowlists or regex validation for tenant IDs

### Workflow 5: Set Up Scoped Database Roles

MUST load [access-control.md](references/access-control.md) for role setup, IAM mapping, and schema permissions.

### Workflow 6: Table Recreation DDL Migration

DSQL does NOT support direct `ALTER COLUMN TYPE`, `DROP COLUMN`, `DROP CONSTRAINT`, or `MODIFY PRIMARY KEY`. These operations require the **Table Recreation Pattern** — creating a new table, copying data, dropping the original, and renaming. This is a destructive workflow that requires user confirmation at each step.

MUST load [ddl-migrations/overview.md](references/ddl-migrations/overview.md) before attempting any of these operations.

### Workflow 7: MySQL to DSQL Schema Migration

MUST load [mysql-migrations/type-mapping.md](references/mysql-migrations/type-mapping.md) for type mappings, feature alternatives, and migration steps.

---

## Error Scenarios

- **MCP server unavailable:** Fall back to CLI scripts ([scripts/](../../scripts/)) or direct psql. Note the limitation to the user.
- **`awsknowledge` returns no results:** Use the default limits in the table above and note that limits should be verified against [DSQL documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/).
- **OCC serialization error:** Retry the transaction. If persistent, check for hot-key contention — see [troubleshooting.md](references/troubleshooting.md).
- **Transaction exceeds limits:** Split into batches under 3,000 rows — see [batched-migration.md](references/ddl-migrations/batched-migration.md).
- **Token expiration mid-operation:** Generate a fresh IAM token and reconnect — see [authentication-guide.md](references/auth/authentication-guide.md).
- See [troubleshooting.md](references/troubleshooting.md) for other issues.

---

## Additional Resources

- [Aurora DSQL Documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/)
- [Code Samples Repository](https://github.com/aws-samples/aurora-dsql-samples)
- [PostgreSQL Compatibility](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility.html)
- [IAM Authentication Guide](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/using-database-and-iam-roles.html)
- [CloudFormation Resource](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-dsql-cluster.html)
