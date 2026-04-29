# Evaluation Suite for databases-on-aws

Automated evaluation harnesses for the plugin's skills, created using the skill-creator.

> **Note:** Evals live under `tools/evals/`, not inside the plugin directory, so they aren't
> shipped to users when the plugin is installed.

## Skills Covered

- **dsql** — Schema management, migrations, MCP delegation, query plan explainability (Workflow 8)

## Tier 1: Triggering Evals

Tests whether the skill description triggers correctly for relevant vs irrelevant prompts.

**Requires:** [skill-creator](https://github.com/anthropics/skills) plugin installed.

```bash
# Install the skill-creator via plugin
/plugin install example-skills@anthropic-agent-skills

# From repo root
PYTHONPATH="<skill-creator-path>:$PYTHONPATH" python -m scripts.run_eval \
  --eval-set tools/evals/databases-on-aws/trigger_evals.json \
  --skill-path plugins/databases-on-aws/skills/dsql \
  --num-workers 5 \
  --runs-per-query 3 \
  --verbose
```

**What it checks:**

- 13 should-trigger prompts (Aurora DSQL, distributed SQL, DSQL migrations, query plan explainability, etc.)
- 13 should-not-trigger prompts (DynamoDB, Aurora/RDS PostgreSQL with EXPLAIN ANALYZE, Redshift, generic SQL, etc.)

## Tier 2: Functional Evals

Tests simple skill correctness: MCP delegation, DSQL-specific guidance, and reference file routing.

```bash
python tools/evals/databases-on-aws/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-eval-results \
  --verbose
```

**What it checks** (5 eval prompts, 20 assertions total):

| Eval                   | Focus                 | Key assertions                                                             |
| ---------------------- | --------------------- | -------------------------------------------------------------------------- |
| 1. Transaction limits  | MCP delegation        | Calls `awsknowledge`, cites 3,000 row limit, recommends batching           |
| 2. Multi-tenant schema | Correctness           | Uses `tenant_id`, `CREATE INDEX ASYNC`, no foreign keys, separate DDL txns |
| 3. Index limits        | MCP delegation        | Calls `awsknowledge`, cites 24 index limit, suggests alternatives          |
| 4. Python connection   | Language routing      | Recommends DSQL Python Connector, IAM auth, 15-min token expiry, SSL       |
| 5. Column type change  | DDL migration routing | Table Recreation Pattern, DROP TABLE warning, batching, user confirmation  |

## Description Optimization

To optimize the skill description for better triggering:

```bash
PYTHONPATH="<skill-creator-path>:$PYTHONPATH" python -m scripts.run_loop \
  --eval-set tools/evals/databases-on-aws/trigger_evals.json \
  --skill-path plugins/databases-on-aws/skills/dsql \
  --model <model-id> \
  --max-iterations 5 \
  --verbose
```

---

## Query Plan Explainability Functional Evals (Workflow 8)

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
python tools/evals/databases-on-aws/scripts/run_query_explainability_evals.py \
  --evals tools/evals/databases-on-aws/query_explainability_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --mcp-config .claude/.mcp.json \
  --output-dir /tmp/dsql-explainability-eval-results \
  --verbose
```

Run a single eval by ID:

```bash
python tools/evals/databases-on-aws/scripts/run_query_explainability_evals.py \
  --evals tools/evals/databases-on-aws/query_explainability_evals.json \
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
