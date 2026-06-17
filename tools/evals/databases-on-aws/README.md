# Evaluation Suite for databases-on-aws

Automated evaluation harnesses for the plugin's skills, created using the skill-creator.

> **Note:** Evals live under `tools/evals/`, not inside the plugin directory, so they aren't
> shipped to users when the plugin is installed.

## Directory Structure

Evals are organized by database service. Each subfolder contains the eval definitions, runner
scripts, and unit tests for that database's skill.

```
tools/evals/databases-on-aws/
├── README.md                        # This file — top-level index
└── dsql/                            # Aurora DSQL skill evals
    ├── evals.json                   # Tier 2: functional evals (9 prompts, 31 assertions)
    ├── trigger_evals.json           # Tier 1: triggering evals (31 test cases)
    ├── safe_query_evals.json        # Tier 3: safe_query enforcement (6 prompts, ~30 expectations)
    ├── query_explainability_evals.json  # Workflow 9: query plan diagnostics (9 prompts, 70 assertions)
    ├── query_plan_rewrite_evals.json   # Query rewrites: type coercion, subquery unnesting, etc. (11 prompts, manual)
    ├── query_plan_rewrite_eval_results.md  # Manual eval results — with-skill vs baseline comparison
    └── scripts/
        ├── run_functional_evals.py          # Runner/grader for Tier 2
        ├── run_query_explainability_evals.py # Runner/grader for Workflow 9
        └── test_safe_query.py               # Unit tests for safe_query.py module
```

As additional databases are added to the plugin (e.g., Aurora, DynamoDB, DocumentDB), create a
peer subfolder (e.g., `aurora/`, `dynamodb/`) with the same structure: eval JSON files at the
top level and runner scripts under `scripts/`.

---

## DSQL Skill Evals

### Tier 1: Triggering Evals

Tests whether the skill description triggers correctly for relevant vs irrelevant prompts.

**Requires:** [skill-creator](https://github.com/anthropics/skills) plugin installed.

```bash
# Install the skill-creator via plugin
/plugin install example-skills@anthropic-agent-skills

# From repo root
PYTHONPATH="<skill-creator-path>:$PYTHONPATH" python -m scripts.run_eval \
  --eval-set tools/evals/databases-on-aws/dsql/trigger_evals.json \
  --skill-path plugins/databases-on-aws/skills/dsql \
  --num-workers 5 \
  --runs-per-query 3 \
  --verbose
```

**What it checks:**

- 16 should-trigger prompts (Aurora DSQL, distributed SQL, DSQL migrations, query plan explainability, data loading, etc.)
- 15 should-not-trigger prompts (DynamoDB, Aurora/RDS PostgreSQL with EXPLAIN ANALYZE, Redshift, generic SQL, non-DSQL bulk loading, etc.)

### Tier 2: Functional Evals

Tests simple skill correctness: MCP delegation, DSQL-specific guidance, and reference file routing.

```bash
python tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-eval-results \
  --verbose
```

Run a subset by ID (e.g., just the new type / lifecycle evals):

```bash
python tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-eval-results \
  --eval-ids 6,7,8 \
  --verbose
```

**What it checks** (12 eval prompts, 42 assertions total):

| Eval                           | Focus                 | Grader    | Key assertions                                                                                            |
| ------------------------------ | --------------------- | --------- | --------------------------------------------------------------------------------------------------------- |
| 1. Transaction limits          | MCP delegation        | regex     | Calls `awsknowledge`, cites 3,000 row limit, recommends batching                                          |
| 2. Multi-tenant schema         | Correctness           | regex     | Uses `tenant_id`, `CREATE INDEX ASYNC`, no foreign keys, separate DDL txns                                |
| 3. Index limits                | MCP delegation        | regex     | Calls `awsknowledge`, cites 24 index limit, suggests alternatives                                         |
| 4. Python connection           | Language routing      | regex     | Recommends DSQL Python Connector, IAM auth, 15-min token expiry, SSL                                      |
| 5. Column type change          | DDL migration routing | regex     | Table Recreation Pattern, DROP TABLE warning, batching, user confirmation                                 |
| 6. JSON column storage         | Type guidance         | LLM judge | Recommends `JSONB` (or `JSON`) as the column type for queryable structured data                           |
| 7. Array storage               | Type guidance         | LLM judge | Flags `TEXT[]` / array column as unsupported, recommends storing the array as `JSONB`                     |
| 8. INACTIVE cluster error      | Troubleshooting       | LLM judge | Identifies INACTIVE state, uses `aws dsql get-cluster` to poll until `ACTIVE`, retries afterwards         |
| 9. Backup on IDLE/INACTIVE     | Troubleshooting       | LLM judge | Identifies `FailedPrecondition`, connects to wake cluster to ACTIVE, retries backup                       |
| 10. Loader stuck at 3K rec/s   | Data loading          | LLM judge | Identifies partition-constrained fresh table, advises to keep running, does NOT recommend more workers    |
| 11. Loader crash lost manifest | Data loading          | LLM judge | Identifies /tmp as tmpfs, recommends --on-conflict do-nothing for recovery, --manifest-dir for prevention |
| 12. Header row parse error     | Data loading          | LLM judge | Identifies missing --header flag, explains default behavior, recommends fix                               |

### Grader modes

The runner supports two grading strategies; each eval declares which via `"llm_judge": true|false` (default `false`):

- **Regex / tool-call** (evals 1-5): fast, cheap, deterministic. Good for verbatim tokens (`tenant_id`, `CREATE INDEX ASYNC`, the `3,000` row limit) and tool-invocation checks (`Calls awsknowledge with topic=X`).
- **LLM judge** (evals 6-9): runs `claude -p` once per expectation with the agent's final text, the user prompt, and the assertion. Returns `{passed, evidence}`. Good for semantic assertions where paraphrasing, negation, or synonym coverage makes regex brittle. Costs ~$0.01–0.05 per expectation; slower than regex. Use for assertions like "Does NOT recommend X" where the agent may phrase the refutation a hundred different ways.

Pin the judge model independently of the subject model via `--judge-model` (defaults to the CLI default). Keep it stable across runs when bumping `--model` so grading stays comparable.

### Tier 3: Safe-Query Enforcement Evals

Tests whether an agent loading the DSQL skill uses `safe_query.build()` when writing DSQL MCP queries, including under social pressure and in write mode.

```bash
python tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/safe_query_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-safe-query-eval-results \
  --verbose
```

**What it checks** (6 eval prompts, ~30 expectations total):

| Eval                           | Focus                  | Key assertions                                                                |
| ------------------------------ | ---------------------- | ----------------------------------------------------------------------------- |
| 0. Basic tenant-scoped select  | Validator adoption     | Imports safe_query, uses regex() for tenant_id, builds via build()            |
| 1. Batch insert with free text | Free-text handling     | Uses literal() for descriptions, regex() for IDs, batches under 3000          |
| 2. Write-mode pressure         | Discipline under nudge | Still uses build() despite "quick script" framing, validates all params       |
| 3. Dynamic ORDER BY            | Semantic correctness   | Uses ident() for column (not allow()), keyword() for sort direction           |
| 4. Rejects f-string request    | Pushback               | Refuses f-string suggestion, explains why build-every-query is non-negotiable |
| 5. Application-layer FK check  | Multi-statement flow   | Two build() calls, validates parent_id UUID, uses literal() for free text     |

### Unit Tests (safe_query module)

Deterministic unit tests for the `safe_query.py` helper module:

```bash
# From repo root
python -m pytest tools/evals/databases-on-aws/dsql/scripts/test_safe_query.py -v

# Or without pytest
python tools/evals/databases-on-aws/dsql/scripts/test_safe_query.py
```

### Description Optimization

To optimize the skill description for better triggering:

```bash
PYTHONPATH="<skill-creator-path>:$PYTHONPATH" python -m scripts.run_loop \
  --eval-set tools/evals/databases-on-aws/dsql/trigger_evals.json \
  --skill-path plugins/databases-on-aws/skills/dsql \
  --model <model-id> \
  --max-iterations 5 \
  --verbose
```

---

### Query Plan Rewrite Evals (manual)

Tests whether the agent recommends correct SQL rewrites for common performance anti-patterns,
including type coercion index bypass, subquery unnesting, OR-to-IN, GROUP BY pushdown, and
DSQL-specific patterns (reltuples estimate, join splitting). Includes one negative case
(OR across different columns — agent should decline).

**Evaluation method:** Manual qualitative comparison (n=1). Run `claude -p` with skill loaded vs
`claude -p --bare` from a clean directory. Results in `query_plan_rewrite_eval_results.md`.
No automated runner script — this suite is manual-only.

**Future direction:** Many of these rewrites are deterministic pattern transformations. A future
iteration SHOULD implement them as a Python SQL converter script that parses and rewrites SQL
directly, with the reference files serving as documentation for the converter's rules. This
would move correctness-critical rewrites out of the LLM and into deterministic code.

**What it checks** (11 eval prompts):

| Eval           | Focus                       | Key assertions                                               |
| -------------- | --------------------------- | ------------------------------------------------------------ |
| 200            | IN-subquery Full Scan       | Recommends EXISTS rewrite, checks type coercion              |
| 201            | Type coercion index bypass  | Identifies string-vs-integer mismatch, references pg_amop    |
| 202            | 12-table join ordering      | Identifies DP threshold, recommends CTE splitting            |
| 203            | COUNT(*) timeout            | Recommends reltuples, warns about staleness                  |
| 204            | Multiple OR to IN           | Recommends IN rewrite, checks type coercion                  |
| 205            | GROUP BY after JOIN         | Recommends subquery aggregation                              |
| 206            | LEFT JOIN null rejection    | Converts to INNER JOIN                                       |
| 207            | Computation on indexed col  | Pushes arithmetic to constant side                           |
| 208            | NOT IN with NULLs           | Recommends NOT EXISTS, warns about NULL semantics difference |
| 209            | Nested UNION ALL            | Flattens to single-level UNION ALL                           |
| 210 (negative) | OR across different columns | Does NOT recommend OR-to-IN                                  |

---

### Query Plan Explainability Functional Evals (Workflow 9)

Tests the full diagnostic workflow: EXPLAIN ANALYZE execution, catalog queries, cardinality checks, report generation.
Triggering is covered by the main `trigger_evals.json` (explainability prompts included there).

**Prerequisite:** Requires a live Aurora DSQL cluster. The plugin's shipped `.mcp.json` has
`aurora-dsql` disabled by default. Supply your own MCP config via `--mcp-config`, pointing to
a JSON file with cluster credentials (e.g., `.claude/.mcp.json`, gitignored).

The cluster also needs the schemas and data the eval prompts reference — see
[Cluster fixtures the evals expect](#cluster-fixtures-the-evals-expect) below. Seeding is
left to the operator so you can use whatever method fits your environment (psycopg + IAM
token, `psql`, CDK migrations, etc.).

The runner fires one throwaway `claude -p "hi"` as a uvx warmup before the real evals
— otherwise the first eval often reports the MCP as "not connected" because `uvx` is
still downloading the package and `boto3` is still initializing the AWS session. Pass
`--skip-warmup` to disable.

```bash
python tools/evals/databases-on-aws/dsql/scripts/run_query_explainability_evals.py \
  --evals tools/evals/databases-on-aws/dsql/query_explainability_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --mcp-config .claude/.mcp.json \
  --output-dir /tmp/dsql-explainability-eval-results \
  --verbose
```

Run a single eval by ID:

```bash
python tools/evals/databases-on-aws/dsql/scripts/run_query_explainability_evals.py \
  --evals tools/evals/databases-on-aws/dsql/query_explainability_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --mcp-config .claude/.mcp.json \
  --output-dir /tmp/dsql-explainability-eval-results \
  --eval-ids 1 \
  --verbose
```

**What it checks** (9 eval prompts, 70 assertions total):

| Eval                                         | Focus                      | Key assertions                                                                                                  |
| -------------------------------------------- | -------------------------- | --------------------------------------------------------------------------------------------------------------- |
| 1. Correlated predicates (3-table join)      | Full workflow              | EXPLAIN ANALYZE, pg_class/pg_stats queries, COUNT(*), correlated predicates, composite index, structured report |
| 2. Full Scan with existing index             | Index analysis             | Full Scan identification, pg_indexes query, composite index recommendation, CREATE INDEX ASYNC                  |
| 3. Long-running query (>30s)                 | Safety gates               | Skips GUC experiments, provides manual testing SQL, no re-run for redundant predicates                          |
| 4. DML statement (UPDATE)                    | DML safety                 | Rewrites UPDATE as equivalent SELECT, runs EXPLAIN via readonly_query, does not modify data                     |
| 5. Anomalous Storage Lookup                  | Bug detection              | Detects impossible row count, flags DSQL bug, support request template, no customer data                        |
| 6. Phase 5 reassessment                      | Outcome loop               | Appends Addendum (not fresh report), before/after table, compares actual vs Expected Impact                     |
| 7. Mixed-case identifiers                    | Anti-hallucination         | Runs EXPLAIN on user's verbatim query, does NOT invent "DSQL is case-sensitive", root cause grounded in plan    |
| 8. Unknown table (`relation does not exist`) | Anti-hallucination         | Surfaces PG error verbatim, does NOT fabricate a diagnostic report, does NOT invent DSQL quirks                 |
| 9. Stale `pg_class.reltuples`                | Stats divergence diagnosis | Queries pg_class AND COUNT(*), identifies divergence, recommends ANALYZE / notes DSQL auto-analyze              |

### Cluster fixtures the evals expect

Each eval's prompt references specific tables. If they don't exist, the agent either
degrades to paste-based analysis (partial pass) or bails out (hard fail). Seed these
tables before running the suite:

| Eval | Schema.Table                                                                 | Shape notes                                                                                                                                                                                                                                                                                           |
| ---- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | `public.user_account`, `public.user_profile`, `public.work_assignment`       | Bi-temporal PK `(user_id, valid_from)`. Seed ~50 rows under the target `tenant_id` plus ~950 decoys across other tenants. All rows share `valid_from = '2000-01-01 00:00:00.000'`. Create ONLY a single-column index on `valid_from` so the composite-index recommendation has a real gap to surface. |
| 2    | `public.orders (order_id, customer_id, status, total, created_at)`           | ~1000 rows. Target customer `customer_id = '12345'` should have many rows, most `status='paid'`, a small number `status='pending'`. Create a single-column index on `customer_id` only — the `AND status = 'pending'` filter should be post-scan.                                                     |
| 3    | `public.{employees, departments, project_assignments, projects, timesheets}` | 5-way join. Seed ~500 employees across 4 departments (one with `location='NYC'`), 4 projects, multiple assignments per employee, and multiple timesheets with `week_start` including `'2024-01-15'`.                                                                                                  |
| 4    | `public.audit_log (event_id, user_id, action, created_at)`                   | Minimal — even an empty table works; the eval tests that the agent rewrites UPDATE as a SELECT for plan capture rather than executing the DML.                                                                                                                                                        |
| 5    | `public.users (id, tenant_id, active, name, email)`                          | ~250 rows; any shape works. The eval is about spotting the anomalous-EXPLAIN report path, not about producing a specific plan.                                                                                                                                                                        |

A reference seed script lives at `.tmp/seed_eval_fixtures.py` (ignored, not shipped). It
uses `psycopg` + an IAM token from `aws dsql generate-db-connect-admin-auth-token` and is
idempotent (`CREATE TABLE IF NOT EXISTS`, `INSERT … ON CONFLICT DO NOTHING`). Feel free to
adapt or replace it — the evals only care that the tables exist with roughly the shape
described above.
