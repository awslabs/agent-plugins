# Limits and Error Codes

Every DSQL limit, rejection and cluster quota with its SQLSTATE and exact message. Load it before
sizing batches, keys or index sets, and to identify a `54000`, `0A000` or `54011` error. Other
errors are in [troubleshooting.md](troubleshooting.md).

**Match on the message rather than the code.** `54000` and `0A000` each cover
more than a dozen of the rows below, so the code alone does not identify which row you are on. This
is a lookup rule for these tables, not a retry rule — classification elsewhere in the skill is
SQLSTATE-based, and `40001` remains the only retryable code (see
[occ-retry-patterns.md](occ-retry-patterns.md)).

**MUST** match a stable prefix, not the whole string, and match it case-insensitively — case varies
even within one family (`Datatype limit …` for `char`/`varchar`, `datatype limit …` for `text`).
`<n>`, `<type>` and `...` in the Message column are values DSQL interpolates at run time, so an
equality test against the cell never matches. If no message matches, **SHOULD** fall back to the
SQLSTATE class and verify the current limit via `awsknowledge` — message text is not a stable
contract.

Values marked **observed** were measured on a single-Region cluster (PostgreSQL 16
compatibility) rather than taken from the documentation. Where an observed value contradicts the
[quotas documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/CHAP_quotas.html),
the row says so. Re-verify before a design decision depends on an exact number.

Run `dsql_lint` to catch unsupported _features_ before execution; use this section for the
_limits_, which are only observable at run time.

## Exceeded Limits

| Limit                               | Value                                                             | SQLSTATE | Message                                                                                                              |
| ----------------------------------- | ----------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------- |
| Row modifications per transaction   | 3,000                                                             | `54000`  | `transaction row limit exceeded`                                                                                     |
| Transaction size                    | 10 MiB, incl. per-row and per-index overhead (see below)          | `54000`  | `transaction size limit 10mb exceeded`, with `DETAIL: Current transaction size <n>mb > 10mb`                         |
| Transaction age                     | 5 minutes                                                         | `54000`  | `transaction age limit of 300s exceeded`, with `DETAIL: Current transaction age <n>s exceeds 300s`                   |
| Query temp space                    | 128 MiB; docs give `53200` and other text                         | `54000`  | `query requires more than allowed temp space of 131072 KB to execute`                                                |
| Extended statistics per table       | 5                                                                 | `54000`  | `more than 5 extended statistics per table are not allowed`                                                          |
| Schemas per database                | 10, excluding `public` and `sys`                                  | `54000`  | `more than 10 schemas not allowed`                                                                                   |
| Indexes per table                   | 24, counting every index — see below                              | `54000`  | `more than 24 indexes per table are not allowed`                                                                     |
| Primary key or index key size       | ~1,981 bytes observed; docs say 1 KiB                             | `54000`  | `key size too large`                                                                                                 |
| Declared key size                   | 2,000 bytes, rejected at DDL time                                 | `54000`  | `key size greater than 2000 bytes not supported`                                                                     |
| Row size                            | 2 MiB                                                             | `54000`  | `maximum row size exceeded`                                                                                          |
| Non-index column size               | 1 MiB; docs give the message below, a per-datatype one was seen   | `54000`  | docs: `maximum column size exceeded`; observed: `datatype limit greater than 1048576 bytes not supported for <type>` |
| View definition size                | 131–524 KiB of SQL text observed, varies by shape; docs say 2 MiB | `54000`  | `view definition too large`                                                                                          |
| `char` declared size                | 4,096 bytes, rejected at DDL time                                 | `54000`  | `Datatype limit greater than 4096 bytes not supported for char`                                                      |
| `varchar` declared size             | 65,535 bytes, rejected at DDL time                                | `54000`  | `Datatype limit greater than 65535 bytes not supported for varchar`                                                  |
| `text` value                        | 1 MiB stored, rejected at write time                              | `54000`  | `datatype limit greater than 1048576 bytes not supported for text`                                                   |
| `bytea` value                       | 1 MiB stored, rejected at write time                              | `54000`  | `datatype limit greater than 1048576 bytes not supported for bytea`                                                  |
| `json` / `jsonb` value              | 1 MiB stored, rejected at write time                              | `54000`  | `datatype limit greater than 1048576 bytes not supported for jsonb`                                                  |
| Columns per index or primary key    | 8                                                                 | `54011`  | `more than 8 column keys in an index are not supported`                                                              |
| Columns per table, no primary key   | 256 accepted, 257 rejected; docs and message both say 255         | `54011`  | `tables can have at most 255 columns`                                                                                |
| Columns per table, with primary key | 256 accepted, 257 rejected; message names an _index_              | `54011`  | `cannot use more than 256 columns in an index`                                                                       |
| Extended-statistics target          | 100                                                               | `22023`  | `statistics target <n> exceeds maximum allowed value of 100`                                                         |
| `numeric` precision                 | 1,000                                                             | `22023`  | `NUMERIC precision <n> must be between 1 and 1000`                                                                   |

Several of these behave in ways the limit alone does not convey:

- **The per-value 1 MiB limit is a hard bound on high-entropy data.** For random `text`, `base64`,
  `bytea` and `jsonb`, 1,048,576 bytes is the largest value accepted and 1,048,577 the first
  rejected — nothing fails early. Compressible values go much further. Size against raw byte count;
  compression only ever buys headroom.
- **The 10 MiB transaction limit also counts index writes.** The check runs at `COMMIT` against an
  accounted size that adds a cost per row and per secondary index entry written. The per-entry
  cost grows with the index key plus the primary key: small for `int`, `uuid` or `timestamptz`
  keys, several times the key width for wide `text` keys. A 500-row batch committed at most
  9.93 MiB of raw data with no secondary index, and 9.11 MiB with four on 100-byte `text` keys.
  The row limit is documented as independent of secondary indexes; the size limit is not, and its
  accounting is undocumented. Large compressible values, such as JSON over a few KB, can count
  below their raw size. To size a batch, read the error: `DETAIL: Current transaction size <n>mb >
  10mb` is the exact accounted size, so one over-limit trial on the real schema gives the ratio to
  scale by.
- **The key-size budget is shared, in bytes, by every key column.** One column holds ~1,981 bytes
  and each additional key column costs ~7 more, so an 8-column key gets ~241 bytes each. Bytes,
  not characters — a 4-byte UTF-8 character key holds ~495 characters. A secondary index key also
  carries the table's primary key columns, so a 500-byte primary key leaves ~1,474 bytes for the
  index columns. Separately, DDL rejects a key whose _declared_ sizes sum past 2,000 bytes, leaving
  the primary key out of that sum for a secondary index; a `varchar(2000)` key therefore passes
  `CREATE` and still fails on write above ~1,981 bytes. The quotas page lists the primary key and
  secondary index as two separate 1 KiB budgets; the observed behaviour is a single shared budget.
- **The view-definition limit is a 512 KiB internal budget, not a text length.** How much SQL
  fits depends on the query's structure, so treat **~120 KiB** of definition text as a working
  ceiling and size by trial when a view approaches it.
- **Every index counts toward the 24**: the primary key, the index behind each `UNIQUE`
  constraint, and every `CREATE [UNIQUE] INDEX ASYNC`, including one still building
  (`indisvalid = f`). A table with a primary key and one `UNIQUE` constraint has 22 slots left;
  a table with no primary key has no hidden index and holds 24. Count with
  `SELECT count(*) FROM pg_index WHERE indrelid = 'tbl'::regclass`. `DROP INDEX` frees a slot.
- **`char` and `varchar` limits are enforced on the _declared_ size at DDL time**, so an
  oversized declaration fails at `CREATE TABLE`, not on first write.
- **Dropped columns keep counting.** The documented ceiling is 1,600 _cumulative_ columns including
  dropped ones, so a table churned by repeated `ADD COLUMN`/`DROP COLUMN` during a migration can
  hit `54011` while holding far fewer live columns. Recreate the table rather than continuing to
  churn it, with user approval, following [ddl-migrations/overview.md](ddl-migrations/overview.md).

## Rejections and Constraint Violations

Unsupported-feature list: [PostgreSQL compatibility — unsupported features](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-unsupported-features.html). Index syntax: [CREATE INDEX syntax support](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/create-index-syntax-support.html).

These are not limits — the feature or the value is refused outright.

| Cause                                               | SQLSTATE | Message                                                                           |
| --------------------------------------------------- | -------- | --------------------------------------------------------------------------------- |
| Non-immutable function in an index expression       | `42P17`  | `functions in index expression must be marked IMMUTABLE`                          |
| Non-immutable generated-column expression           | `42P17`  | `generation expression is not immutable`                                          |
| `serial` column type                                | `42704`  | `type "serial" does not exist`                                                    |
| Array column type                                   | `0A000`  | `datatype text[] not supported` — the declared type is echoed back                |
| Sort direction on an index key                      | `0A000`  | `specifying sort order not supported for index keys`                              |
| Operator class on an index key                      | `0A000`  | `opclass not supported for index keys`                                            |
| Index on an unsupported column type                 | `0A000`  | `datatype <type> is not supported in a key`                                       |
| `CREATE INDEX` without `ASYNC`                      | `0A000`  | `unsupported mode. please use CREATE INDEX ASYNC.`                                |
| `CREATE INDEX CONCURRENTLY`                         | `0A000`  | `CONCURRENTLY not supported for CREATE INDEX`                                     |
| `ALTER TABLE ADD COLUMN` with any inline constraint | `0A000`  | `ALTER TABLE ADD COLUMN with constraint not supported`                            |
| `ALTER COLUMN ... SET DATA TYPE`                    | `0A000`  | `unsupported ALTER TABLE ALTER COLUMN ... SET DATA TYPE statement`                |
| `ALTER COLUMN ... SET STATISTICS`, at any value     | `0A000`  | `unsupported ALTER TABLE ALTER COLUMN ... SET STATISTICS statement`               |
| `CREATE PROCEDURE`                                  | `0A000`  | `PROCEDURE is not supported`                                                      |
| `CREATE DATABASE`                                   | `0A000`  | `unsupported statement: Createdb`                                                 |
| Post-creation foreign key without `NOT VALID`       | `0A000`  | `unsupported ALTER TABLE ADD CONSTRAINT statement`                                |
| Synchronous `VALIDATE CONSTRAINT`                   | `0A000`  | `unsupported ALTER TABLE VALIDATE CONSTRAINT statement`                           |
| Foreign key violation — **not retryable**           | `23503`  | `insert or update on table ... violates foreign key constraint ...`               |
| Duplicate against a unique index still building     | `23505`  | `duplicate key value violates unique constraint ...`                              |
| Any statement issued after a failure inside `BEGIN` | `25P02`  | `current transaction is aborted, commands ignored until end of transaction block` |
| Protocol message over 10 MiB                        | **none** | No error reaches the client — see below                                           |

These mislead in practice:

- **`25P02` masks the real error.** It is the code an agent sees most often, because anything
  that keeps issuing statements after a failure inside a transaction block gets it in place of
  the original cause. Read the _first_ error in the transaction, not the last.
- **An oversized protocol message closes the connection with no error message.** The client sees
  only `SSL SYSCALL error: EOF detected`, which is indistinguishable from a transient network
  fault, so a naive retry resends the same oversized statement forever. Treat an EOF on the first
  statement after a large one as a size problem, not a network one. Note the AWS documentation
  lists `08P01` / `FATAL: invalid message length` for this case; that error is not delivered. If
  you _do_ see `08P01: invalid message length`, that is this case and the behaviour has changed — trust the error.

**Any EOF on a statement that could have committed — `COMMIT`, or any write in autocommit mode —
leaves the commit outcome unknown**, whatever the cause, because the
connection closed before the server replied. This applies to the oversized-message case above and
equally to an EOF the agent classifies as a network fault — the size discriminator tells you why the
connection dropped, not whether the write landed. Before resending, an agent **MUST** reconnect and
confirm whether the write committed. Designing the write to be idempotent removes the need for that
check, but only if it was already idempotent — it is not something that can be applied after the
EOF arrives, and a bare retry of a non-idempotent write such as
`UPDATE accounts SET balance = balance - 100` double-applies it. See
[occ-retry-patterns.md](occ-retry-patterns.md#idempotent-transaction-design).

**If the outcome cannot be confirmed, an agent MUST NOT retry.** A blind
`balance = balance - 100` has no observable trace that distinguishes "applied once" from "not
applied", so there is nothing to query. **MUST** report the unresolved write to the user with the
transaction's identifying values and stop; a duplicated debit is worse than a reported gap. Avoid the situation rather than resolve it: write a
correlation id the transaction itself records, so the question becomes answerable next time.

The threshold is the _protocol message_ size, which a client does not see directly: a batched or
parameterised multi-row insert can exceed it well below 10 MiB of visible data. If you cannot
measure it, reduce the batch size until the EOF stops — after confirming, as above, that the
previous attempt did not commit.

## Cluster Quotas

From the [Aurora DSQL quotas documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/CHAP_quotas.html).
Unlike the tables above, these are **not verified here** — they need provisioned resources to
exercise, so treat the values as documented rather than observed.

| Quota                                          | Value                          | SQLSTATE | Message when exceeded                                     |
| ---------------------------------------------- | ------------------------------ | -------- | --------------------------------------------------------- |
| Tables per database                            | 1,000                          | `54000`  | `creating more than 1000 tables not allowed`              |
| Views per database                             | 5,000                          | `54000`  | `creating more than 5000 views not allowed`               |
| Sequences per database                         | 5,000                          | `54000`  | `creating more than 5000 sequences is not allowed`        |
| Single-Region clusters per account, per Region | 20 (increasable)               | API      | `You have reached the cluster limit.`                     |
| Multi-Region clusters per account, per Region  | 5 (increasable)                | API      | `You have reached the cluster limit.`                     |
| Storage per cluster                            | 10 TiB, increasable to 256 TiB | `53100`  | `Current cluster size exceeds cluster size limit.`        |
| Connections per cluster                        | 10,000                         | `53300`  | `Unable to accept connection, too many open connections.` |
| New connections per second                     | 100 sustained, 1,000 burst     | `53400`  | `Unable to accept connection, rate exceeded.`             |
| Concurrent restore jobs                        | 4                              | —        | No error code documented                                  |
| CDC streams per cluster                        | 5                              | API      | `You have reached the stream limit.`                      |

The cluster-count and CDC rows surface as the control-plane API error
`ServiceQuotaExceededException: 402`, not a SQLSTATE, so they never reach a SQL client.
