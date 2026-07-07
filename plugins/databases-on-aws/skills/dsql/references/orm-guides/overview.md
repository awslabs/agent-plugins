# ORM Migration Quick Reference

Adapter names and key gotchas per framework. This file provides DSQL-specific adapter
names and configuration not available in general documentation.

## Adapters

| Framework  | Adapter                                 | Install                                                      |
| ---------- | --------------------------------------- | ------------------------------------------------------------ |
| Django     | `aurora_dsql_django`                    | `pip install aurora-dsql-django boto3`                       |
| EF Core    | `Amazon.AuroraDsql.EntityFrameworkCore` | `dotnet add package Amazon.AuroraDsql.EntityFrameworkCore`   |
| Hibernate  | `aurora-dsql-hibernate-dialect`         | `software.amazon.dsql:aurora-dsql-hibernate-dialect` (Maven) |
| Rails      | Standard `pg` gem + `aws-sdk-dsql`      | `gem 'pg'` + `gem 'aws-sdk-dsql'`                            |
| SQLAlchemy | `aurora_dsql_sqlalchemy`                | `pip install aurora-dsql-sqlalchemy boto3`                   |

## Key Gotchas Per Framework

### Django

| Issue             | Fix                                                               |
| ----------------- | ----------------------------------------------------------------- |
| ENGINE            | `'aurora_dsql_django'` (not `django.db.backends.postgresql`)      |
| CONN_MAX_AGE      | ≤ 1800 (DSQL timeout is 1 hour)                                   |
| Migrations        | Each DDL in its own migration; `RunSQL("CREATE INDEX ASYNC ...")` |
| SELECT FOR UPDATE | Remove — DSQL uses OCC; wrap writes in retry decorator            |
| AutoField         | Replace with `UUIDField(primary_key=True, default=uuid.uuid4)`    |
| ForeignKey        | Add `db_constraint=False`                                         |

### EF Core (.NET)

Requires .NET 8.0+, EF Core 9.0.7+, and `Amazon.AuroraDsql.Npgsql` 1.1.0+.

| Issue          | Fix                                                                                                                                                                                                                                                |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Setup          | `AddDsqlDataSource(host)` then `UseDsql(sp)` in `AddDbContext` (IAM auth via `Amazon.AuroraDsql.Npgsql`)                                                                                                                                           |
| PKs            | `Guid` keys with a store-generated `gen_random_uuid()` default — leave `Id` unset on insert                                                                                                                                                        |
| Auto-increment | `long` keys via `dsql.EnableIdentityColumns()` — `cacheSize: 1` for near-strict ordering, larger (default ≥ 65536) for throughput                                                                                                                  |
| OCC retry      | `DsqlExecutionStrategy` auto-retries `SaveChangesAsync` in implicit transactions. Inside an explicit transaction it does NOT retry — use `ExecuteInTransactionAsync` and call `ChangeTracker.Clear()` first so retries don't replay stale entities |
| FK constraints | Not enforced — navigations/`Include`/joins work, but enforce referential integrity in the application layer                                                                                                                                        |
| Isolation      | Requested isolation levels are ignored; `SET TRANSACTION ISOLATION LEVEL`, `SAVEPOINT`, and `LOCK TABLE` are filtered at the ADO.NET layer                                                                                                         |
| Migrations     | dsql-lint rewrites EF Core DDL for DSQL (e.g. `CREATE INDEX` → `CREATE INDEX ASYNC`) and makes it idempotent so failed migrations re-run safely                                                                                                    |

### Hibernate

| Issue          | Fix                                                                                                                                                                                                                                                                                         |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dialect        | Provided by `aurora-dsql-hibernate-dialect` (auto-registered)                                                                                                                                                                                                                               |
| ID generation  | `@GeneratedValue(strategy = GenerationType.UUID)`                                                                                                                                                                                                                                           |
| OCC retry      | Prefer the [aurora-dsql-jdbc-connector](https://github.com/awslabs/aurora-dsql-connectors/tree/main/java/jdbc) — built-in retry for SQLSTATE 40001. For manual `@Retryable`, match on `SQLException` and check `getSQLState() == "40001"` (Hibernate's class-40 mapping varies by version). |
| FK constraints | `@ForeignKey(value = ConstraintMode.NO_CONSTRAINT)`                                                                                                                                                                                                                                         |
| DDL generation | `hibernate.hbm2ddl.auto = none` — manage DDL manually                                                                                                                                                                                                                                       |

### Rails

| Issue      | Fix                                                                 |
| ---------- | ------------------------------------------------------------------- |
| adapter    | `postgresql` (standard pg gem)                                      |
| Auth       | Custom connection handler generating IAM tokens via `aws-sdk-dsql`  |
| Migrations | `disable_ddl_transaction!` in each migration                        |
| PKs        | `id: :uuid` in `create_table`                                       |
| FKs        | Remove `add_foreign_key` calls; validate in model callbacks         |
| Locking    | Remove `lock!` / `with_lock` — use OCC retry in `ApplicationRecord` |
