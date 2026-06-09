# ORM Migration Quick Reference

Adapter names and key gotchas per framework. This file provides DSQL-specific adapter
names and configuration not available in general documentation.

## Adapters

| Framework  | Adapter                            | Install                                              |
| ---------- | ---------------------------------- | ---------------------------------------------------- |
| Django     | `aurora_dsql_django`               | `pip install aurora-dsql-django boto3`               |
| Hibernate  | `aurora-dsql-hibernate`            | `software.amazon.dsql:aurora-dsql-hibernate` (Maven) |
| Rails      | Standard `pg` gem + `aws-sdk-dsql` | `gem 'pg'` + `gem 'aws-sdk-dsql'`                    |
| SQLAlchemy | `aurora_dsql_sqlalchemy`           | `pip install aurora-dsql-sqlalchemy boto3`           |

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

### Hibernate

| Issue          | Fix                                                      |
| -------------- | -------------------------------------------------------- |
| Dialect        | Provided by `aurora-dsql-hibernate` (auto-registered)    |
| ID generation  | `@GeneratedValue(strategy = GenerationType.UUID)`        |
| OCC retry      | Use `@Retryable(value = PessimisticLockException.class)` |
| FK constraints | `@ForeignKey(value = ConstraintMode.NO_CONSTRAINT)`      |
| DDL generation | `hibernate.hbm2ddl.auto = none` — manage DDL manually    |

### Rails

| Issue      | Fix                                                                 |
| ---------- | ------------------------------------------------------------------- |
| adapter    | `postgresql` (standard pg gem)                                      |
| Auth       | Custom connection handler generating IAM tokens via `aws-sdk-dsql`  |
| Migrations | `disable_ddl_transaction!` in each migration                        |
| PKs        | `id: :uuid` in `create_table`                                       |
| FKs        | Remove `add_foreign_key` calls; validate in model callbacks         |
| Locking    | Remove `lock!` / `with_lock` — use OCC retry in `ApplicationRecord` |
