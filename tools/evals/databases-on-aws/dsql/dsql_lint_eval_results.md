# dsql_lint Eval Results — With-Skill vs Baseline

**Date:** 2026-05-06
**MCP Server:** awslabs.aurora-dsql-mcp-server (local build, feature/dsql-lint-mcp-tool merged to main)
**dsql-lint version:** 0.1.3
**Model:** Claude Opus 4.6 (subagent execution)

## Summary

| Eval | Scenario                  | With Skill | Baseline        | Delta                                                           |
| ---- | ------------------------- | ---------- | --------------- | --------------------------------------------------------------- |
| 100  | pg_dump PostgreSQL schema | **PASS**   | FAIL (3 errors) | Skill corrects JSON, index, transaction handling                |
| 101  | Django ORM migration      | **PASS**   | FAIL (3 errors) | Skill corrects JSON, index, provides actionable Django guidance |

The skill demonstrably changes agent behavior. The baseline agent hallucinates incorrect
DSQL constraints (JSONB support, synchronous indexes) while the skill-guided agent uses
`dsql_lint` for deterministic validation and produces correct output.

---

## Eval 100: PostgreSQL pg_dump Schema

**Prompt:** "I have this PostgreSQL schema from pg_dump. Can you check if it's compatible
with DSQL and fix any issues?"

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL,
  preferences JSON,
  team_id INT REFERENCES teams(id)
);
CREATE INDEX idx_users_email ON users(email);
```

### Behavior Comparison

| Behavior                | With Skill                                   | Baseline                 | Correct?                                                        |
| ----------------------- | -------------------------------------------- | ------------------------ | --------------------------------------------------------------- |
| Used deterministic tool | ✅ Called `dsql_lint`                        | ❌ Relied on memory      | Skill wins                                                      |
| SERIAL replacement      | BIGINT IDENTITY (CACHE 1)                    | UUID gen_random_uuid()   | Both valid, skill matches dsql-lint output                      |
| JSON handling           | ✅ TEXT                                      | ❌ JSONB                 | **Baseline wrong** — DSQL does not support JSONB as column type |
| Index handling          | ✅ CREATE INDEX ASYNC                        | ❌ "Index is fine as-is" | **Baseline wrong** — DSQL requires ASYNC                        |
| Transaction splitting   | ✅ Explicitly stated one DDL per transaction | ❌ Not mentioned         | **Baseline misses**                                             |
| Foreign key guidance    | ✅ App-layer enforcement                     | ✅ App-layer enforcement | Both correct                                                    |

### With-Skill Output (summary)

- Called `dsql_lint(sql=..., fix=true)`
- Reported 4 diagnostics: serial_type, json_type, foreign_key, index_async
- Presented fixed SQL with IDENTITY, TEXT, removed FK, ASYNC index
- Explained each warning and what the user needs to do at the application layer
- Stated "issue each DDL as a separate transaction"

### Baseline Output (summary)

- Did NOT use any validation tool
- Recommended `JSONB` for the JSON column (incorrect — DSQL rejects JSONB as a column type)
- Said the CREATE INDEX statement "is fine" (incorrect — DSQL requires ASYNC)
- Did not mention transaction splitting
- Recommended UUID for SERIAL (valid but different from dsql-lint's IDENTITY approach)

### Baseline Failures

1. **JSON → JSONB (wrong):** Would cause DDL rejection at execution time
2. **Index "is fine" (wrong):** Synchronous CREATE INDEX is not supported in DSQL
3. **No transaction guidance:** Agent would likely issue both DDL in one transact call

---

## Eval 101: Django ORM Migration (multi-DDL transaction)

**Prompt:** "I'm migrating my Django app to DSQL. Here's the output of
`python manage.py sqlmigrate myapp 0001`:"

```sql
BEGIN;
CREATE TABLE myapp_order (
  id SERIAL PRIMARY KEY,
  customer_id INT REFERENCES myapp_customer(id),
  total DECIMAL(10,2),
  metadata JSON
);
CREATE INDEX myapp_order_customer_idx ON myapp_order(customer_id);
COMMIT;
```

### Behavior Comparison

| Behavior                | With Skill                                 | Baseline                                      | Correct?                |
| ----------------------- | ------------------------------------------ | --------------------------------------------- | ----------------------- |
| Used deterministic tool | ✅ Called `dsql_lint`                      | ❌ Relied on memory                           | Skill wins              |
| SERIAL replacement      | BIGINT IDENTITY                            | UUID                                          | Both valid              |
| JSON handling           | ✅ TEXT                                    | ❌ JSONB                                      | **Baseline wrong**      |
| Index handling          | ✅ CREATE INDEX ASYNC                      | ❌ "Index is okay"                            | **Baseline wrong**      |
| Multi-DDL detection     | ✅ Split into separate BEGIN/COMMIT blocks | ⚠️ Said "remove BEGIN/COMMIT" but didn't split | **Baseline incomplete** |
| Django-specific advice  | ✅ "sqlmigrate → lint → execute fixed SQL" | ⚠️ Generic (custom backend, atomic=False)      | Skill more actionable   |

### With-Skill Output (summary)

- Called `dsql_lint(sql=..., fix=true)`
- Reported 5 issues: serial, foreign_key, json, index_async, multi_ddl_transaction
- Produced fixed SQL with each DDL in its own BEGIN/COMMIT block
- Gave specific Django advice: run sqlmigrate, lint output, execute fixed SQL directly
- Warned about foreign key removal requiring app-layer enforcement

### Baseline Output (summary)

- Did NOT use any validation tool
- Recommended `JSONB` (incorrect)
- Said CREATE INDEX "is okay as-is" (incorrect — needs ASYNC)
- Said "remove BEGIN/COMMIT" but didn't show the correct split pattern
- Gave generic Django advice (custom backend, atomic=False) without a concrete workflow

### Baseline Failures

1. **JSON → JSONB (wrong):** Same error as eval 100
2. **Index "is okay" (wrong):** Same error as eval 100
3. **Incomplete transaction handling:** Told user to remove BEGIN/COMMIT but didn't show
   that each DDL needs its own transaction — user would likely run both DDL bare without
   any transaction isolation

---

## Conclusion

The skill produces measurably better outcomes by:

1. **Eliminating hallucination** — `dsql_lint` provides deterministic validation instead of
   the model guessing at DSQL constraints from training data
2. **Catching the JSON/JSONB error** — the baseline consistently recommends JSONB (which DSQL
   rejects as a column type). This is a real data-loss-risk mistake that would fail at DDL
   execution time.
3. **Enforcing ASYNC indexes** — the baseline misses this requirement entirely
4. **Providing actionable migration workflows** — the skill-guided agent gives concrete steps
   (lint → review → execute) rather than generic advice

The iron law holds: **the agent fails without this skill change** (gets JSON wrong, misses
ASYNC, doesn't split transactions). The skill teaches something the model does not already know.
