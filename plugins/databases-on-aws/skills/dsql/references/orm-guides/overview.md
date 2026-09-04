# ORM Migration Quick Reference

Adapter names and key gotchas per framework. This file provides DSQL-specific adapter
names and configuration not available in general documentation.

Before relying on generated foreign keys, **MUST** verify the selected adapter version's release
notes or inspect its generated DDL. When the adapter omits foreign key constraints, generate and lint
the DDL manually to preserve the relationship.

Across adapters, inline foreign keys in `CREATE TABLE` use DSQL foreign-key syntax.
Post-creation foreign keys **MUST** use `ADD CONSTRAINT ... NOT VALID`, followed by
`ALTER TABLE ASYNC ... VALIDATE CONSTRAINT` and terminal job verification.

For existing tables, emit that sequence through the framework's raw-SQL migration mechanism:
`RunSQL` (Django), the generated `.sql` migration file (Drizzle), `migrationBuilder.Sql` (EF Core),
Flyway/Liquibase (Hibernate), `execute` (Rails), or `op.execute` (Alembic/SQLAlchemy). For
tenant-scoped composite FKs, use raw DDL in Django and Rails; Drizzle
(`foreignKey({ columns, foreignColumns })`), EF Core, Hibernate, and SQLAlchemy provide composite
relationship mappings.

## Adapters

| Framework  | Adapter                                 | Install                                                                              |
| ---------- | --------------------------------------- | ------------------------------------------------------------------------------------ |
| Django     | `aurora_dsql_django`                    | `pip install aurora-dsql-django boto3`                                               |
| Drizzle    | `@aws/aurora-dsql-drizzle`              | `npm install @aws/aurora-dsql-drizzle drizzle-orm pg` + `npm install -D drizzle-kit` |
| EF Core    | `Amazon.AuroraDsql.EntityFrameworkCore` | `dotnet add package Amazon.AuroraDsql.EntityFrameworkCore`                           |
| Hibernate  | `aurora-dsql-hibernate-dialect`         | `software.amazon.dsql:aurora-dsql-hibernate-dialect` (Maven)                         |
| Rails      | Standard `pg` gem + `aws-sdk-dsql`      | `gem 'pg'` + `gem 'aws-sdk-dsql'`                                                    |
| SQLAlchemy | `aurora_dsql_sqlalchemy`                | `pip install aurora-dsql-sqlalchemy boto3`                                           |

## Key Gotchas Per Framework

### Django

| Issue             | Fix                                                                             |
| ----------------- | ------------------------------------------------------------------------------- |
| ENGINE            | `'aurora_dsql_django'` (not `django.db.backends.postgresql`)                    |
| CONN_MAX_AGE      | ≤ 1800 (DSQL timeout is 1 hour)                                                 |
| Migrations        | Each DDL in its own migration; `RunSQL("CREATE INDEX ASYNC ...")`               |
| SELECT FOR UPDATE | Use when a write depends on rows read; retain whole-transaction OCC retry       |
| AutoField         | Replace with `UUIDField(primary_key=True, default=uuid.uuid4)`                  |
| ForeignKey        | Keep `ForeignKey`; the DSQL backend creates database constraints for new tables |

### Drizzle (TypeScript)

Requires `drizzle-orm` `^0.45` (0.45.x — the peer range pins the minor), `pg` 8+, Node.js 20+, and
`drizzle-kit` as a dev dependency. The adapter rides `drizzle-orm/node-postgres` over the DSQL
node-postgres connector — there is no custom dialect.

| Issue            | Fix                                                                                                                                                                                                                                                                                                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Setup            | `drizzle({ connection: { host, user, region }, schema })` from `@aws/aurora-dsql-drizzle` — IAM auth and TLS come from the connector, and `region` is optional (inferred from the host). Pass an existing pool with `drizzle({ client: pool, schema })`; `db.$client` exposes it                                                                                     |
| `user`           | REQUIRED — there is no default, so a connection never lands on `admin` by omission. Pass a database role scoped to what the app needs                                                                                                                                                                                                                                |
| OCC retry        | `db.transactionWithRetry(cb)` re-runs the transaction on SQLSTATE `40001`. The callback MUST be idempotent — it re-runs on every attempt. Nested `tx.transaction()` fails fast. Defaults: `maxRetries` 3, `baseDelayMs` 50, `maxDelayMs` 5000                                                                                                                        |
| Retry exhaustion | Throws `AwsDsqlRetryExhaustedError` with the last conflict on `.cause`. Pass overrides in the third argument, after the transaction config: `transactionWithRetry(cb, undefined, { maxRetries: 5, onRetry: (err, attempt, max) => ... })`                                                                                                                            |
| Migrations       | Use `migrate()` from `@aws/aurora-dsql-drizzle`, NOT the stock `drizzle-orm/node-postgres` migrator — the stock one sends every statement in a single transaction. `getMigrationStatus(db, config)` reports applied vs. pending                                                                                                                                      |
| Generate         | `npx aurora-dsql-drizzle generate --out ./drizzle -- --config drizzle.config.ts` runs `drizzle-kit generate`, then rewrites each statement with `dsql-lint`. Review and commit the result — see [dsql-lint.md](../dsql-lint.md)                                                                                                                                      |
| `SERIAL`         | The transform rewrites it as `BIGINT ... GENERATED BY DEFAULT AS IDENTITY (CACHE 1)`. Review the DDL for the wider type, and let the identity column supply values — replace any `nextval()`/`setval()`/`currval()` calls that named the old `SERIAL` sequence                                                                                                       |
| Breakpoints      | Keep Drizzle Kit's `breakpoints: true` (the default). The adapter applies one statement per `--> statement-breakpoint` marker, and `migrate()` stops with `success: false` on any chunk holding more than one statement. Give every hand-added statement its own marker — `transform` neither inserts one nor flags the chunk, so the failure surfaces at apply time |
| Identity columns | Define them in the table definition. The transform lints statements one at a time, so `ALTER COLUMN ... ADD GENERATED ... AS IDENTITY` is reported unfixable — merge it into the `CREATE TABLE` by hand if it is already generated                                                                                                                                   |
| Foreign keys     | The transform adds `NOT VALID` to foreign keys created with `ALTER TABLE`. Add `ALTER TABLE ASYNC ... VALIDATE CONSTRAINT` after it, preceded by its own `--> statement-breakpoint` marker; `migrate()` waits for that job                                                                                                                                           |
| Resume           | A statement and its tracking row are separate commits. If a run dies between them the statement is applied but untracked, and re-running fails "already exists" (`drizzle-kit` omits `IF NOT EXISTS`) — `migrate()` names the statement                                                                                                                              |

### EF Core (.NET)

Requires .NET 8.0+, EF Core 9.0.7+, and `Amazon.AuroraDsql.Npgsql` 1.1.0+.

| Issue          | Fix                                                                                                                                                                                                                                                |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Setup          | `AddDsqlDataSource(host)` then `UseDsql(sp)` in `AddDbContext` (IAM auth via `Amazon.AuroraDsql.Npgsql`)                                                                                                                                           |
| PKs            | `Guid` keys with a store-generated `gen_random_uuid()` default — leave `Id` unset on insert                                                                                                                                                        |
| Auto-increment | `long` keys via `dsql.EnableIdentityColumns()` — `cacheSize: 1` for near-strict ordering, larger (default ≥ 65536) for throughput                                                                                                                  |
| OCC retry      | `DsqlExecutionStrategy` auto-retries `SaveChangesAsync` in implicit transactions. Inside an explicit transaction it does NOT retry — use `ExecuteInTransactionAsync` and call `ChangeTracker.Clear()` first so retries don't replay stale entities |
| FK constraints | Keep relationships and generated foreign keys. Cascades count toward DSQL transaction limits                                                                                                                                                       |
| Isolation      | Requested isolation levels are ignored; `SET TRANSACTION ISOLATION LEVEL`, `SAVEPOINT`, and `LOCK TABLE` are filtered at the ADO.NET layer                                                                                                         |
| Migrations     | dsql-lint rewrites EF Core DDL for DSQL (e.g. `CREATE INDEX` → `CREATE INDEX ASYNC`) and makes it idempotent so failed migrations re-run safely                                                                                                    |

### Hibernate

| Issue          | Fix                                                                                                                                                                                                                                                                                         |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dialect        | Provided by `aurora-dsql-hibernate-dialect` (auto-registered)                                                                                                                                                                                                                               |
| ID generation  | `@GeneratedValue(strategy = GenerationType.UUID)`                                                                                                                                                                                                                                           |
| OCC retry      | Prefer the [aurora-dsql-jdbc-connector](https://github.com/awslabs/aurora-dsql-connectors/tree/main/java/jdbc) — built-in retry for SQLSTATE 40001. For manual `@Retryable`, match on `SQLException` and check `getSQLState() == "40001"` (Hibernate's class-40 mapping varies by version). |
| FK constraints | Keep normal relationship mappings; the DSQL dialect exports foreign key constraints                                                                                                                                                                                                         |
| DDL generation | `hibernate.hbm2ddl.auto = none` — manage DDL manually                                                                                                                                                                                                                                       |

### Rails

| Issue      | Fix                                                                                                                 |
| ---------- | ------------------------------------------------------------------------------------------------------------------- |
| adapter    | `postgresql` (standard pg gem)                                                                                      |
| Auth       | Custom connection handler generating IAM tokens via `aws-sdk-dsql`                                                  |
| Migrations | `disable_ddl_transaction!` in each migration                                                                        |
| PKs        | `id: :uuid` in `create_table`                                                                                       |
| FKs        | Use `add_foreign_key ..., validate: false`, then run `ALTER TABLE ASYNC ... VALIDATE CONSTRAINT` and verify the job |
| Locking    | Use `lock!` / `with_lock` when a decision depends on rows read; retain OCC retry in `ApplicationRecord`             |

### SQLAlchemy

| Issue      | Fix                                                                                |
| ---------- | ---------------------------------------------------------------------------------- |
| ForeignKey | Keep `ForeignKey` and `ForeignKeyConstraint`; the dialect emits inline constraints |

## Additional Resources

- [Migrating from PostgreSQL to Aurora DSQL — framework and ORM compatibility](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-migration-guide.html#dsql-framework-compatibility)
