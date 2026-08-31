# Flyway on Aurora DSQL

Always use Flyway's official Aurora DSQL community module,
`org.flywaydb:flyway-database-dsql`, with a release compatible with the Flyway runtime.

MUST NOT select or recommend `software.amazon.dsql:aurora-dsql-flyway-support`. It is deprecated.
When an existing installation uses it, direct the user to migrate to the official module through
the tested dependency swap below.

Verify that the selected official module version resolves from the user's configured artifact
repository and check its declared Flyway compatibility. Do not use an unreleased commit or
snapshot, and do not change production dependencies until the official replacement is available
in the user's environment.

## Migrate an Existing Installation

1. Test the change outside production.
2. Record the current Flyway, PostgreSQL module, DSQL JDBC connector, and adapter versions.
3. Replace `software.amazon.dsql:aurora-dsql-flyway-support` with a published
   `org.flywaydb:flyway-database-dsql` version compatible with the Flyway runtime.
4. Keep the existing DSQL JDBC URL, migration files, schema-history table, and `flyway.dsql.*`
   configuration. Keep the Aurora DSQL JDBC connector on the runtime classpath when using
   `jdbc:aws-dsql:postgresql://`.
5. Run `flyway info` and `flyway validate`.
6. Run `flyway migrate` only after the existing history and pending migrations look correct.

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
