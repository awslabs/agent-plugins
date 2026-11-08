# Troubleshooting in DSQL

This file contains common additional errors encountered while working with DSQL and
guidelines for how to solve them.

Before referring to any listed error, use the routing below and consult
[Additional Resources](#additional-resources).

## Table of Contents

1. [Limits and Error Codes](#limits-and-error-codes)
2. [Connection and Authorization](#connection-and-authorization)
3. [Cluster Lifecycle](#cluster-lifecycle)
4. [Foreign Key Addition or Validation Fails](#foreign-key-addition-or-validation-fails)
5. [Incompatibility](#incompatibility)
6. [Protocol Compatibility](#protocol-compatibility)
7. [Additional Resources](#additional-resources)

## Limits and Error Codes

The limit, rejection and quota tables, with each SQLSTATE and exact message, are in
[limits-and-error-codes.md](limits-and-error-codes.md).

## Connection and Authorization

### Error: "FATAL: unable to accept connection, ..."

**Cause:** One of several conditions. `unable to accept connection` is a **shared prefix** — match
it case-insensitively, since the two connection-quota variants capitalise `Unable` and omit the
`FATAL:` prefix — then match the whole line before deciding whether to retry.

`HINT` is a **separate protocol field**, not part of the message line, so read it from the driver's
error object rather than by substring-matching the message: `err.diag.message_hint` (psycopg),
`pgErr.Hint` (Go `pgx`), `err.hint` (node-postgres). psycopg's string rendering happens to include
`HINT:`, so a substring match works there and nowhere else.

| Full message                                                                            | Meaning                                                                 | Retry?                                    |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ----------------------------------------- |
| `FATAL: unable to accept connection, access denied` plus `HINT: Signature expired: ...` | The token is stale                                                      | Once, with a fresh token                  |
| `FATAL: unable to accept connection, access denied` with no `Signature expired` hint    | Wrong credentials, region, or IAM permissions                           | No — regenerating the token will not help |
| `FATAL: unable to accept connection, waking up cluster, please retry later`             | The cluster is `INACTIVE` — see [Cluster Lifecycle](#cluster-lifecycle) | Yes, after polling for `ACTIVE`           |
| `Unable to accept connection, too many open connections.` (`53300`)                     | Cluster connection limit reached (10,000)                               | Yes, after releasing connections          |
| `Unable to accept connection, rate exceeded.` (`53400`)                                 | Connection rate limit reached (100/s sustained)                         | Yes, with backoff — not with a new token  |

The last two rows are from the quotas documentation and are **not verified here**; the first three
were reproduced against a cluster. An agent that matches only on `unable to accept connection`
retries an authorization failure indefinitely, and treats connection-pool exhaustion as an auth
problem.

**When the `Signature expired` hint is present**, the token is stale. Refresh connections within
15 minutes and pick one of:

- Auto-regenerate tokens per connection or query OR
- Use connection pool hooks to refresh before expiration OR
- Implement retry logic with token regeneration

**MUST** retry at most once with a fresh token. The token is a SigV4 pre-signed URL, so if the client
clock is behind by more than the token lifetime every freshly minted token is already outside the
server's window and the hint persists no matter how many you generate. If `Signature expired`
survives a fresh token, **SHOULD** check the host clock (NTP) rather than regenerating again.

For the other rows, regenerating the token does not help — resolve the IAM, region, cluster-state,
or connection-count condition the matched row names.

### Connection Timeouts

**Problem**: Database connections time out after 1 hour.
**Solution**:

- Configure connection pool lifetime < 1 hour
- Implement connection health checks
- Handle disconnection gracefully with retries

### Schema Privileges

**Problem**: Non-admin users get permission denied errors.

**Solution**:

- Admin users must explicitly grant schema access to non-admin users
- Non-admin users must create and use custom schemas (not `public`)
- Link database roles to IAM roles for authentication

### SSL Certificate Verification

**Problem**: SSL verification fails with certificate errors.

**Solution**:

- Ensure system has Amazon Root CA certificates
- Use native TLS libraries (not OpenSSL 1.0.x)
- Set `server_name_indication` to cluster endpoint in SSL config

## Cluster Lifecycle

See [cluster lifecycle](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/cluster-lifecycle.html) for state definitions and behavior.

### Error: "FATAL: unable to accept connection, waking up cluster, please retry later"

The cluster is `INACTIVE` and waking up. Poll `aws dsql get-cluster --identifier <id> --region <region> --query status --output text` until `ACTIVE`, then retry.

### Error: `FailedPrecondition` when backing up an `IDLE` / `INACTIVE` cluster

Connect to the cluster to wake it, then retry the backup.

## Foreign Key Addition or Validation Fails

**Addition failure:** Aurora DSQL rejects `ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY`
without `NOT VALID`. Add the post-creation constraint with `NOT VALID`.

**Validation-job failure:** Inspect `sys.jobs.status` and `sys.jobs.details` first. Repair
referencing rows only when `details` identifies a foreign key violation. For other failures,
address the reported cause before rerunning
`ALTER TABLE ASYNC ... VALIDATE CONSTRAINT`.

For SQLSTATE `40001` during concurrent referenced-row and referencing-row writes, retry the
complete transaction. For transaction-limit errors during cascades, assess per-parent fan-out.
When one parent can exceed transaction limits, use `NO ACTION` or `RESTRICT`, process child rows
in bounded transactions, then change the parent.

### Error: "... violates foreign key constraint"

SQLSTATE `23503` is not retryable. Correct the relationship or apply the intended referential
action; **MUST NOT** route it through the `40001` OCC retry loop.

## Incompatibility

When migrating from PostgreSQL, remember DSQL doesn't support:

- **SERIAL types** — `42704: type "serial" does not exist`. Use
  `GENERATED { ALWAYS | BY DEFAULT } AS IDENTITY` with sequences instead. The message names a
  missing _type_, not an unsupported feature, so it is easy to misread as a typo
- **Extensions** - No PL/pgSQL, PostGIS, pgvector, etc.
- **Triggers** - Implement logic in application layer
- **Temporary tables** - Use regular tables or application-level caching
- **TRUNCATE** - Use `DELETE FROM table` instead
- **Multiple databases** — `0A000: unsupported statement: Createdb`. Single `postgres` database
  per cluster
- **Custom types** - Limited type system support
- **Partitioning** - Manage data distribution in application

See [full list of unsupported features](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-unsupported-features.html),
and [Rejections and Constraint Violations](limits-and-error-codes.md#rejections-and-constraint-violations) for the exact
message each rejection produces.

### Error: "datatype text[] not supported"

**Cause:** Using `TEXT[]` or other array column types. SQLSTATE `0A000`; the rejected type is
echoed back, so `integer[]` reports `datatype integer[] not supported`.
**Solution:** Serialize the array into a single column — DSQL has no array column type. PREFER `JSONB`; MAY use `TEXT` for opaque columns. ASK the user which format fits the access pattern.

- **PREFER `JSONB`** — the application queries inside the value (`@>`/`?`/`?|`/`?&`, `jsonb_array_elements_text`, or indexed JSONB paths); values are normalized on write. Insert: `INSERT INTO t (tags) VALUES ($1::jsonb)` with `JSON.stringify(arr)`. Query: `jsonb_array_elements_text(tags)`.
- **MAY use `TEXT`** — the column is opaque to the database (the app reads the whole value, parses it, and never queries inside). Insert raw: `INSERT INTO t (tags_csv) VALUES ($1)` with `arr.join(',')`.
- **`JSON` is valid** when writes dominate (no parse/sort overhead on write), byte-exact input matters (audit, replay, duplicate keys), or only `->`/`->>` is needed.
- **When migrating:** keep existing `JSON` columns as `JSON`; upgrade to `JSONB` only when JSONB-only operators or indexed paths are needed.

### Error: "unsupported mode. please use CREATE INDEX ASYNC."

**Cause:** Creating an index without the `ASYNC` keyword. `CREATE INDEX CONCURRENTLY` is rejected
separately, with `CONCURRENTLY not supported for CREATE INDEX`. Both are SQLSTATE `0A000`.

**Solution:**

```sql
-- Wrong
CREATE INDEX idx_logs_created_a ON logs (created_at);
CREATE INDEX CONCURRENTLY idx_logs_created_b ON logs (created_at);

-- Correct
CREATE INDEX ASYNC idx_logs_created ON logs (created_at);
```

### Error: "transaction row limit exceeded"

**Cause:** Modifying more than 3,000 rows in a single transaction. SQLSTATE `54000`.
**Solution:**

1. Start from chunks of 500-1000 rows
2. Process each batch separately
3. Add WHERE clause to limit scope

Treat that chunk size as a starting point, not a guarantee. The same transaction is also bounded by
size and age, and every secondary index entry written counts toward the size. On a table carrying
several secondary indexes that overhead decides the chunk size; see
[Exceeded Limits](limits-and-error-codes.md#exceeded-limits) for how to size it.

### Error: "schema has been updated by another transaction (OC001)"

**Cause:** The session's cached schema catalog is older than a catalog change another session
committed — any DDL, `GRANT` or `REVOKE`, concurrent or already finished. Reads are hit as well as
writes. It is SQLSTATE `40001`, the same code as an OCC write conflict, told apart only by the
marker:

| Message                                                  | Marker  | Cause                                       |
| -------------------------------------------------------- | ------- | ------------------------------------------- |
| `change conflicts with another transaction (OC000)`      | `OC000` | Concurrent DML on the same rows             |
| `schema has been updated by another transaction (OC001)` | `OC001` | Any catalog change — DDL, `GRANT`, `REVOKE` |

**Solution:**

1. Retry the transaction in the same `40001` loop — the retry refreshes the catalog cache, so a
   one-shot change clears on the first retry
2. If it recurs across retries, serialize the catalog changes rather than widening the backoff

See [occ-retry-patterns.md](occ-retry-patterns.md) for the mechanism and the retry code.

## Protocol Compatibility

**Problem**: Some PostgreSQL clients send unsupported protocol messages.

**Solution**:

- Use officially tested drivers from [aws-samples/aurora-dsql-samples](https://github.com/aws-samples/aurora-dsql-samples)
- Test client compatibility before production deployment

A protocol message over 10 MiB is a separate failure with no error message at all — the
connection is closed and the client sees only `SSL SYSCALL error: EOF detected`. See
[Rejections and Constraint Violations](limits-and-error-codes.md#rejections-and-constraint-violations).

## Additional Resources

- [Aurora DSQL troubleshooting guide](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/troubleshooting.html#troubleshooting-connections)
- [Aurora DSQL PostgreSQL compatibility](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with.html)
