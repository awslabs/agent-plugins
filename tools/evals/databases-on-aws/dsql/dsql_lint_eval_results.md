# dsql_lint Eval Results — With-Skill vs Baseline

**Date:** 2026-05-08
**MCP Server:** awslabs.aurora-dsql-mcp-server (local build from `feature/dsql-lint-mcp-tool` branch; upstream mirror PR not yet merged)
**dsql-lint version:** 0.1.4
**Evaluation method:** Manual behavioral comparison — subagent run with skill loaded vs. subagent run without skill. Automated grading for these evals is not yet wired into `run_functional_evals.py`; PASS/FAIL is a human assessment of transcripts against the expectations in `dsql_lint_evals.json`.

## Summary

| Eval | Scenario                  | With Skill | Baseline        | Delta                                                           |
| ---- | ------------------------- | ---------- | --------------- | --------------------------------------------------------------- |
| 100  | pg_dump PostgreSQL schema | **PASS**   | FAIL (3 errors) | Skill corrects JSON, index, transaction handling                |
| 101  | Django ORM migration      | **PASS**   | FAIL (3 errors) | Skill corrects JSON, index, provides actionable Django guidance |
| 102  | Clean DSQL-compatible SQL | **PASS**   | N/A             | Tool correctly reports no issues; agent does not execute        |
| 103  | MySQL unsupported syntax  | **PASS**   | N/A             | Tool returns parse error; agent falls back to mysql-migrations  |

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

| Behavior                | With Skill                            | Baseline                   | Correct?                                                        |
| ----------------------- | ------------------------------------- | -------------------------- | --------------------------------------------------------------- |
| Used deterministic tool | PASS Called `dsql_lint`               | FAIL Relied on memory      | Skill wins                                                      |
| SERIAL replacement      | BIGINT IDENTITY (CACHE 1)             | UUID gen_random_uuid()     | Both valid, skill matches `dsql_lint` output                    |
| JSON handling           | PASS TEXT                             | FAIL JSONB                 | **Baseline wrong** — DSQL does not support JSONB as column type |
| Index handling          | PASS CREATE INDEX ASYNC               | FAIL "Index is fine as-is" | **Baseline wrong** — DSQL requires ASYNC                        |
| Transaction splitting   | PASS Explicitly stated one DDL per tx | FAIL Not mentioned         | **Baseline misses**                                             |
| Foreign key guidance    | PASS App-layer enforcement            | PASS App-layer enforcement | Both correct                                                    |

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
- Recommended UUID for SERIAL (valid but different from `dsql_lint`'s IDENTITY approach)

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

| Behavior                | With Skill                               | Baseline                                        | Correct?                |
| ----------------------- | ---------------------------------------- | ----------------------------------------------- | ----------------------- |
| Used deterministic tool | PASS Called `dsql_lint`                  | FAIL Relied on memory                           | Skill wins              |
| SERIAL replacement      | BIGINT IDENTITY                          | UUID                                            | Both valid              |
| JSON handling           | PASS TEXT                                | FAIL JSONB                                      | **Baseline wrong**      |
| Index handling          | PASS CREATE INDEX ASYNC                  | FAIL "Index is okay"                            | **Baseline wrong**      |
| Multi-DDL detection     | PASS Split into separate BEGIN/COMMIT    | PARTIAL Said "remove BEGIN/COMMIT" but no split | **Baseline incomplete** |
| Django-specific advice  | PASS "sqlmigrate → lint → execute fixed" | PARTIAL Generic (custom backend, atomic=False)  | Skill more actionable   |

### With-Skill Output (summary)

- Called `dsql_lint(sql=..., fix=true)`
- Reported 5 diagnostics: `serial_type`, `foreign_key`, `json_type`, `index_async`, `multi_ddl_transaction`
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

## Eval 102: Clean DSQL-Compatible SQL

**Prompt:** "Validate this SQL for DSQL compatibility but don't execute it yet: …" (UUID PK with `gen_random_uuid()`, TEXT payload, `CREATE INDEX ASYNC`).

**Baseline:** Not run — this eval tests that the agent calls `dsql_lint` even when no compatibility issues are expected, and does not execute when the user said "don't execute." Baseline behavior is not a meaningful comparison for this expectation (either a baseline agent would also decline to execute, or it would over-modify compatible SQL — both are failure modes the skill change addresses by deferring to the deterministic tool).

### With-Skill Output (summary)

- Called `dsql_lint(sql=..., fix=false)` (validation-only mode appropriate for "don't execute")
- Tool returned `diagnostics: []`, `summary: { errors: 0, warnings: 0, fixed: 0 }`
- Agent reported to user that SQL is DSQL-compatible with no changes needed
- Agent did NOT call `transact` (honored the "don't execute" instruction)

### Verdict

PASS on all four expectations in `dsql_lint_evals.json` eval 102. The skill's "user said don't execute" handling works as documented in [Workflow: Validate & Migrate SQL to DSQL](../../../plugins/databases-on-aws/skills/dsql/references/dsql-lint.md).

---

## Eval 103: MySQL Unsupported Syntax (`parse_error` fallback)

**Prompt:** MySQL `CREATE TABLE` with `AUTO_INCREMENT`, `SET(...)` column, `ENGINE=InnoDB`, `PARTITION BY HASH(id)`, and explicit `FOREIGN KEY`.

**Baseline:** Not run. Goal of this eval is to verify the `parse_error` fallback path — a baseline agent with no skill would hallucinate DSQL-compatible transformations without ever invoking the tool, so the signal (did the agent correctly fall back to `mysql-migrations/type-mapping.md`?) does not translate to a baseline comparison.

### With-Skill Output (summary)

- Called `dsql_lint(sql=..., fix=true)`
- Tool returned a single `parse_error` diagnostic at `AUTO_INCREMENT` (the PostgreSQL parser short-circuits on the first unsupported token; `AUTO_INCREMENT` and `PARTITION BY` reliably trigger `parse_error`, while `ENGINE=` clauses and `SET(...)` column types can pass silently through the PostgreSQL parser)
- Agent recognized `parse_error` rule and followed the Error Handling guidance in [dsql-lint.md](../../../plugins/databases-on-aws/skills/dsql/references/dsql-lint.md) to load [mysql-migrations/type-mapping.md](../../../plugins/databases-on-aws/skills/dsql/references/mysql-migrations/type-mapping.md)
- Agent proposed manual conversion (`INT AUTO_INCREMENT` → `BIGINT GENERATED ALWAYS AS IDENTITY`; `SET(...)` → TEXT with app-layer validation; omit `ENGINE=` and `PARTITION BY`) and offered to re-run `dsql_lint` on the converted SQL

### Verdict

PASS on the expectations in `dsql_lint_evals.json` eval 103. Agents MUST cross-check MySQL-origin SQL against `mysql-migrations/type-mapping.md` even when `dsql_lint` returns clean — `ENGINE=` and `SET(...)` pass silently.

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
