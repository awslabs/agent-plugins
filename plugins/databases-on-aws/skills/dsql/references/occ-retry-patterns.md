# OCC Retry Patterns for DSQL

DSQL uses Optimistic Concurrency Control (OCC). Write transactions are validated at
COMMIT time — if another transaction modified the same rows, COMMIT fails with
`SQLSTATE 40001` (serialization failure). Every application MUST implement retry logic.

Concurrent DDL raises the same `40001`, so the code is not on its own enough to tell which
happened. The trailing marker in the message is the discriminator — see
[Retry Strategy](#retry-strategy).

## Table of Contents

1. [Retry Strategy](#retry-strategy)
2. [DSQL Connectors (Preferred)](#dsql-connectors-preferred)
3. [Manual Retry Pattern](#manual-retry-pattern)
4. [Conflict Mitigation](#conflict-mitigation)
5. [Idempotent Transaction Design](#idempotent-transaction-design)

---

## Retry Strategy

```
Max retries: 5 (balances recovery vs infinite-loop risk)
Base delay: 50ms (allows concurrent transaction to commit)
Backoff: exponential with jitter
Formula: delay = min(base * 2^attempt + random(0, base), max_delay)
Max delay: 5000ms (stays under DSQL's 5-minute transaction timeout)
Retryable: SQLSTATE 40001 only (both markers — see below)
Non-retryable: all other errors, including foreign key violation 23503 (raise immediately)
```

`40001` carries two causes, distinguished by the trailing marker in the message. `(OC000)` is a
write conflict and backoff clears it. `(OC001)` is concurrent DDL; backoff clears it only if the
DDL has stopped, so it will keep recurring while another session keeps issuing DDL — serialize the
DDL rather than relying on retries. Both markers **MUST** stay in the retry loop: excluding `OC001`
turns a one-shot DDL collision that the first retry would have cleared into a hard application
error. Capture the marker before each sleep so an exhausted loop records which cause it was
retrying. See
[troubleshooting.md](troubleshooting.md#error-schema-has-been-updated-by-another-transaction-oc001).

An error that arrives as a dropped connection rather than a SQLSTATE — `SSL SYSCALL error: EOF
detected` — leaves the commit outcome **unknown**, because the connection closed without a reply.
Do not feed it to this loop. Reconnect and confirm whether the write landed, or make the write
idempotent by design first; see [Idempotent Transaction Design](#idempotent-transaction-design).

---

## DSQL Connectors (Preferred)

The DSQL Connectors handle OCC retry, IAM token generation, and connection management
automatically. Applications SHOULD use these instead of manual retry logic:

| Language | Driver                         | Connector package                          | Repository                                                                                                                  |
| -------- | ------------------------------ | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| Java     | JDBC                           | `aurora-dsql-jdbc-connector`               | [aurora-dsql-connectors/java/jdbc](https://github.com/awslabs/aurora-dsql-connectors/tree/main/java/jdbc)                   |
| Python   | `psycopg`/`psycopg2`/`asyncpg` | `aurora-dsql-python-connector`             | [aurora-dsql-connectors/python/connector](https://github.com/awslabs/aurora-dsql-connectors/tree/main/python/connector)     |
| Node.js  | `pg`                           | `@aws/aurora-dsql-node-postgres-connector` | [aurora-dsql-connectors/node/node-postgres](https://github.com/awslabs/aurora-dsql-connectors/tree/main/node/node-postgres) |
| Node.js  | `Postgres.js`                  | `@aws/aurora-dsql-postgresjs-connector`    | [aurora-dsql-connectors/node/postgres-js](https://github.com/awslabs/aurora-dsql-connectors/tree/main/node/postgres-js)     |

See [connectivity-tools.md](auth/connectivity-tools.md) for setup details.

When using a DSQL Connector, OCC retry is built in — no manual retry wrapper needed.

---

## Manual Retry Pattern

Use when a DSQL Connector is not available or when custom retry behavior is required:

```python
import logging, time, random, psycopg2
from psycopg2 import errors

log = logging.getLogger(__name__)

def execute_with_retry(conn_params, operation, max_retries=5):
    """Execute a database operation with OCC retry."""
    for attempt in range(max_retries):
        conn = psycopg2.connect(**conn_params)
        conn.autocommit = False
        try:
            with conn.cursor() as cur:
                operation(cur)
            conn.commit()
            return
        except errors.SerializationFailure as error:
            conn.rollback()
            # Both markers are 40001 and both belong in this loop, but they mean
            # different things operationally. Logging the marker is what lets an
            # exhausted loop be diagnosed: OC001 points at concurrent DDL, so
            # tuning row contention will never fix it.
            marker = "OC001" if "OC001" in str(error) else "OC000"
            if attempt < max_retries - 1:
                delay = min(0.05 * (2 ** attempt) + random.uniform(0, 0.05), 5.0)
                log.warning(
                    "40001 (%s) on attempt %d/%d, retrying in %.3fs",
                    marker, attempt + 1, max_retries, delay,
                )
                time.sleep(delay)
            else:
                log.error(
                    "40001 (%s) exhausted %d attempts%s",
                    marker, max_retries,
                    "; serialize the concurrent DDL" if marker == "OC001" else "",
                )
                raise
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()
```

The same pattern applies in any language — catch SQLSTATE 40001, apply exponential backoff
with jitter, retry up to the max, and record the `(OC000)`/`(OC001)` marker so an exhausted loop
can be told apart from row contention. See the [DSQL code samples](https://github.com/aws-samples/aurora-dsql-samples)
for Java, Go, Node.js, and Rust implementations.

---

## Conflict Mitigation

| Scenario                                 | Conflict Risk | Mitigation                                                                   |
| ---------------------------------------- | ------------- | ---------------------------------------------------------------------------- |
| Counter/balance updates                  | High          | Shard counters, use CACHE 65536 sequences (DSQL minimum for high-throughput) |
| Status field updates (same row)          | High          | Keep transactions short                                                      |
| Batch updates overlapping rows           | Medium        | Smaller batches, randomize order                                             |
| Long-running transactions                | Medium        | Break into smaller units — DSQL transaction timeout is 5 min                 |
| Cross-region writes to same rows         | High          | Geographic partitioning                                                      |
| Child writes with referenced-key changes | High          | Keep referenced keys stable; retry only `40001`                              |
| INSERT-only workloads                    | Low           | UUID PKs distribute writes                                                   |

**Key strategies:**

- Keep transactions short — fewer rows, less time = less conflict window
- Use UUID primary keys — random distribution avoids hot spots
- Design idempotent operations — safe to retry without side effects
- Batch writes in small groups (100–500 rows) — reduces conflict surface vs using the full 3,000-row limit

---

## Idempotent Transaction Design

For OCC retry safety, transactions SHOULD be idempotent:

```sql
-- GOOD: Idempotent (safe to retry)
INSERT INTO orders (id, customer_id, total)
VALUES ($1, $2, $3)
ON CONFLICT (id) DO NOTHING;

-- GOOD: Idempotent update (conditional)
UPDATE orders SET status = 'shipped'
WHERE id = $1 AND status = 'processing';

-- BAD: Not idempotent (double-charges on retry)
UPDATE accounts SET balance = balance - 100 WHERE id = $1;

-- GOOD: Idempotent version (use expected value)
UPDATE accounts SET balance = $2
WHERE id = $1 AND balance = $3;
```
