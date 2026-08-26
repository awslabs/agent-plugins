# Flyway on Aurora DSQL

Use Flyway's upstream Aurora DSQL community module for new projects after a compatible release is
published. Keep the AWS adapter available to existing users and migrate it as a dependency swap,
not as a schema rewrite.

The AWS adapter is deprecated and maintenance-only. Limit changes to critical security and
compatibility fixes; direct new feature development to the upstream module.

## Choose an Adapter

| Situation                                     | Guidance                                                                                         |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| New project                                   | Use a published `org.flywaydb:flyway-database-dsql` release compatible with the Flyway runtime.  |
| Existing AWS adapter user                     | Continue using `software.amazon.dsql:aurora-dsql-flyway-support`, or plan the tested swap below. |
| Upstream artifact unavailable or incompatible | Stay on the AWS adapter. Do not use an unreleased commit or snapshot as production guidance.     |

A merged pull request is not an installable release. Verify that the exact upstream artifact
version resolves from the user's configured Maven repository and check its declared Flyway
compatibility before recommending it.

## Migrate an Existing Installation

1. Test the change outside production.
2. Record the current Flyway, PostgreSQL module, DSQL JDBC connector, and adapter versions.
3. Remove `software.amazon.dsql:aurora-dsql-flyway-support`.
4. Add a published `org.flywaydb:flyway-database-dsql` version compatible with the Flyway runtime.
5. Keep the existing DSQL JDBC URL, migration files, schema-history table, and `flyway.dsql.*`
   configuration. Keep the Aurora DSQL JDBC connector on the runtime classpath when using
   `jdbc:aws-dsql:postgresql://`.
6. Run `flyway info` and `flyway validate`.
7. Run `flyway migrate` only after the existing history and pending migrations look correct.

MUST NOT load both adapters together. Both register Aurora DSQL database support in Flyway, so
classpath coexistence is not a supported migration strategy.

Before `flyway migrate`, rollback is a dependency-only change. After new migrations execute,
recover using the application's normal database migration procedure; changing the adapter back
does not undo applied SQL.

## DSQL Migration Rules

The adapter choice does not change DSQL migration constraints:

- Keep one DDL statement per migration transaction; use a script configuration with
  `executeInTransaction=false` only when each statement may commit independently.
- Use `CREATE INDEX ASYNC`.
- Use `flyway.dsql.occMaxRetries`, `flyway.dsql.occMaxRetryDelaySeconds`, and
  `flyway.dsql.awaitAsyncIndexes` only after checking the selected release's documentation.
- Use `baselineOnMigrate=true` instead of the standalone `flyway baseline` command.
