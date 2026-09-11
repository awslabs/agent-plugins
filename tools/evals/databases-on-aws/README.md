# Evaluation Suite for databases-on-aws

Automated evaluation harnesses for the plugin's skills, created using the skill-creator.

> **Note:** Evals live under `tools/evals/`, not inside the plugin directory, so they aren't
> shipped to users when the plugin is installed.

## Directory Structure

Evals are organized by database service. This partial tree highlights the functional corpora,
their recorded results, and runner files:

```
tools/evals/databases-on-aws/
├── README.md                        # This file — top-level index
└── dsql/                            # Aurora DSQL skill evals
    ├── evals.json                   # Tier 2: functional evals (23 prompts, 93 assertions)
    ├── dsql_lint_evals.json         # dsql_lint workflow (4 prompts, 20 assertions)
    ├── pg_migration_evals.json      # PostgreSQL migrations (17 prompts, 90 assertions)
    ├── pg_migration_hallucination_evals.json # Migration hallucinations (3 prompts, 14 assertions)
    ├── trigger_evals.json           # Tier 1: triggering evals (40 test cases)
    ├── safe_query_evals.json        # Tier 3: safe_query enforcement (5 prompts, 24 assertions)
    ├── query_explainability_evals.json  # Workflow 9: query plan diagnostics (9 prompts, 70 assertions)
    ├── query_plan_rewrite_evals.json   # Query rewrites: type coercion, subquery unnesting, etc. (11 prompts, manual)
    ├── data_loading_eval_results.md    # Historical data-loading results
    ├── dsql_lint_eval_results.md       # Historical dsql_lint eval results
    ├── pg_migration_hallucination_results.md # Historical migration-hallucination results
    ├── query_plan_rewrite_eval_results.md  # Manual eval results — with-skill vs baseline comparison
    └── scripts/
        ├── run_functional_evals.py          # Runner for functional eval corpora
        ├── run_query_explainability_evals.py # Runner/grader for Workflow 9
        ├── test_run_functional_evals.py     # Unit tests for the functional runner
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

- 24 should-trigger prompts (Aurora DSQL, distributed SQL, DSQL migrations, query plan explainability, system diagnostics / cluster performance, data loading, etc.)
- 16 should-not-trigger prompts (DynamoDB, Aurora/RDS PostgreSQL with EXPLAIN ANALYZE, Redshift, generic SQL, non-DSQL bulk loading, etc.)

### Tier 2: Functional Evals

Tests simple skill correctness: MCP delegation, DSQL-specific guidance, and reference file routing.
The runner suppresses configured user, project, and local setting sources, restricts MCP
discovery to the supplied config, runs each subject from a private temporary working directory
that contains only its generated transact guard, limits built-in tools to `Skill` and reads
under the DSQL skill subtree, and verifies that the subject
invoked the `databases-on-aws:dsql` skill. It defaults to the plugin's shipped `.mcp.json`;
use `--mcp-config` only with a reviewed, trusted configuration.
The subject intentionally does not use `--bare`: plugin hooks are part of the behavior under
evaluation, remain enabled, and execute if triggered.

```bash
mise exec -- python tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-eval-results \
  --verbose
```

Run a subset by ID (e.g., just the new type / lifecycle evals):

```bash
mise exec -- python tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-eval-results-6-8 \
  --eval-ids 6,7,8 \
  --verbose
```

**What it checks** (23 eval prompts, 93 assertions total):

| Eval                           | Focus                 | Grader    | Key assertions                                                                                                                      |
| ------------------------------ | --------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 1. Transaction limits          | MCP delegation        | regex     | Calls `awsknowledge`, cites 3,000 row limit, recommends batching                                                                    |
| 2. Multi-tenant schema         | Correctness           | LLM judge | Uses non-null tenant keys, tenant-scoped foreign keys, `CREATE INDEX ASYNC`, separate DDL txns                                      |
| 3. Index limits                | MCP delegation        | regex     | Calls `awsknowledge`, cites 24 index limit, suggests alternatives                                                                   |
| 4. Python connection           | Language routing      | regex     | Recommends DSQL Python Connector, IAM auth, 15-min token expiry, SSL                                                                |
| 5. Column type change          | DDL migration routing | LLM judge | Table Recreation Pattern, dependency gate, batching, user confirmation                                                              |
| 6. JSON column storage         | Type guidance         | LLM judge | Recommends `JSONB` (or `JSON`) as the column type for queryable structured data                                                     |
| 7. Array storage               | Type guidance         | LLM judge | Flags `TEXT[]` / array column as unsupported, recommends storing the array as `JSONB`                                               |
| 8. INACTIVE cluster error      | Troubleshooting       | LLM judge | Identifies INACTIVE state, uses `aws dsql get-cluster` to poll until `ACTIVE`, retries afterwards                                   |
| 9. Backup on IDLE/INACTIVE     | Troubleshooting       | LLM judge | Identifies `FailedPrecondition`, connects to wake cluster to ACTIVE, retries backup                                                 |
| 10. Loader stuck at 3K rec/s   | Data loading          | LLM judge | Identifies partition-constrained fresh table, advises to keep running, does NOT recommend more workers                              |
| 11. Loader crash lost manifest | Data loading          | LLM judge | Identifies /tmp as tmpfs, recommends --on-conflict do-nothing for recovery, --manifest-dir for prevention                           |
| 12. Header row parse error     | Data loading          | LLM judge | Identifies missing --header flag, explains default behavior, recommends fix                                                         |
| 13. EF Core data layer setup   | ORM routing (.NET)    | LLM judge | Recommends Amazon.AuroraDsql.EntityFrameworkCore, Guid keys w/ gen_random_uuid(), foreign key constraints, DsqlExecutionStrategy    |
| 14. .NET / C# support          | Language routing      | LLM judge | Confirms .NET support, recommends Npgsql connector for IAM auth and EF Core adapter                                                 |
| 15. System diagnostics (W12)   | AAS interpretation    | LLM judge | Identifies the shifted wait event vs baseline, rules out load growth, no absolute-AAS claim, defers to Workflow 9                   |
| 16. Wait-event ≠ plan (W12)    | Observe-only boundary | LLM judge | High SequentialScanRead = concurrency not full scan; does NOT claim a full/seq scan or missing/building index; routes to Workflow 9 |
| 17. Shared reference FK        | Multi-tenant design   | LLM judge | Uses an ordinary foreign key to a global/shared parent and keeps authorization separate                                             |
| 18. Add UNIQUE constraint      | Constraint migration  | LLM judge | Async unique index, readiness verification, `UNIQUE USING INDEX`, no table recreation                                               |
| 19. Modify referenced PK       | Constraint migration  | LLM judge | Inbound-FK preflight, retained unique target, approval or abort when relationships would be lost                                    |
| 20. Direct constraint changes  | Constraint migration  | LLM judge | Direct `DROP CONSTRAINT`, CHECK `NOT VALID`, async validation, no table recreation                                                  |
| 21. Direct column options      | Column migration      | LLM judge | Direct `DROP NOT NULL` and default changes, no table recreation                                                                     |
| 22. Drizzle data layer setup   | ORM routing (TS)      | LLM judge | Recommends `@aws/aurora-dsql-drizzle`, required scoped `user`, `transactionWithRetry` with idempotent callback, package `migrate()` |
| 23. Drizzle migration failure  | ORM migrations (TS)   | LLM judge | Identifies stock migrator batching DDL, routes to `migrate()`, `aurora-dsql-drizzle generate`, keeps `breakpoints: true`            |

### Grader modes

Every eval consumed by `run_functional_evals.py` **MUST** declare one of two grading strategies via
`"grader": "regex"` or `"grader": "llm_judge"`. Functional corpora use
`"schema_version": 2`; result artifacts report schema and grading-protocol version `2` because
the stricter grading and incomplete-run semantics are not directly comparable with older runs.

- **Regex / tool-call**: fast, cheap, deterministic. Each accepted assertion maps to a registered rule; the schema rejects assertions without one. Dedicated rules validate exact tool behavior and safety constraints. Compatibility rules retained for legacy corpora use polarity-aware keyword scoring. Limit rules bind values to their subject, such as 3,000 rows per transaction, 24 indexes per table, and 8 columns per index.
- **LLM judge**: runs a tool-free `claude -p` once per expectation with the complete redacted final answer, bounded call and result metadata, a complete tool-name inventory, the user prompt, and the assertion. Answers longer than 18,000 redacted characters are ungraded instead of being truncated. Tool-result bodies are explicitly untrusted and cannot independently satisfy assertions about what the agent presents or explains. The judge returns `{passed, evidence}`. Use it for semantic assertions where paraphrasing, negation, or synonym coverage makes regex brittle, such as "Does NOT recommend X." Each assertion incurs model-dependent cost and latency.

Select the judge independently of the subject via `--judge-model` (defaults to the CLI default)
and bound each judge assertion with `--judge-timeout` (defaults to 60 seconds).
An explicit model argument records the selected string; it does not make a mutable alias
immutable. Reproducible comparisons require immutable model identifiers for `--model` and
`--judge-model`, plus immutable MCP server dependency versions rather than floating tags such
as `latest`. Keep the judge identifier stable when changing the subject.

The runner exits nonzero for assertion failures, turn-limit truncation, missing requested IDs,
invalid eval files, and subject or judge infrastructure errors. `summary.json` reports
`requested_total` and `graded_total` separately and sets `overall_pass_rate` to `null` when
the run is incomplete. Output directories carry a runner ownership marker and an advisory lock
that excludes cooperating runner instances.
After all inputs pass validation, reusing a managed output directory stages a complete
replacement before promoting its `summary.json` and replacing immediate child directories
whose names match `eval-<integer>`, where `<integer>` is one or more decimal digits. Other
entries are preserved. Promotion state is made durable before a `.previous-*` backup becomes
visible. On the next run, validated abandoned preparation directories and internal `.run-*`
work directories are removed,
committed backups are discarded, and an interrupted promotion is rolled back from its
`.previous-*` backup before evaluation continues. Nonempty unmarked directories and concurrent
cooperating runners are rejected. Artifacts record
the subject model,
judge model, subject and judge timeouts, turn limit, selected eval IDs, passed environment
names, explicit
model-selection status, snapshotted input hashes, and separate subject/judge timing and cost.
Before execution, the runner copies the corpus, plugin tree, and MCP config into a private
temporary snapshot; hashes and the corresponding subprocess arguments refer to that snapshot.
A missing CLI
cost field is recorded as `null`, not as zero.

Artifacts use mode `0600` under mode-`0700` directories. `transcript.json` retains a redacted
answer, ordered event timeline, and redacted tool calls/results while omitting the original
stream message objects. Redaction is best effort: use only synthetic eval data, treat
artifacts as potentially sensitive, and review them before publication. Persisted text and
event collections, corpus size and nesting, and subprocess output are bounded. Timeouts,
interruptions, and output-limit failures terminate the tracked subject or judge process tree.
The runner records an infrastructure error for an eval if Linux subreaper tracking or macOS
`kqueue` and `libproc` tracking cannot be initialized or refreshed.

The subject and judge processes receive the fixed runtime, Claude, and AWS environment
allowlist. MCP server commands inherit the subject environment. The judge suppresses
configurable setting sources; administrator-managed policy may still apply. Each eval that
requires an MCP server declares it in `required_mcp_servers`; preflight validates the consumed
MCP fields and requires those servers to be enabled. This does not make configured commands or
URLs trustworthy.
Use only reviewed
`--mcp-config` files and repeat `--pass-env NAME` only for additional variables a trusted
server or judge requires. Explicitly passed values must contain at least four characters and are
treated as secrets during artifact redaction regardless of variable name. The tool allowlist
permits documentation, recommendation, and lint tools when the supplied configuration enables
their MCP servers. Remote MCP URLs must use HTTPS; plaintext HTTP is accepted only with a
literal loopback address. Plugin runtime and hooks remain enabled because they are part of the behavior
under test. A generated `PreToolUse` guard exposes `transact` to the subject but denies every call
before MCP execution, retaining attempted calls in the transcript for ordering and refusal
assertions. Other cluster-bound tools such as `get_schema` and `readonly_query` are unavailable.

### dsql_lint Workflow Evals

Tests that the agent invokes `dsql_lint`, handles its diagnostics, and observes the applicable
pre-execution gates. The transact guard makes attempted calls and ordering observable without
permitting live execution.
The lint tool does not require a live cluster. The plugin's shipped `.mcp.json`
disables the Aurora DSQL server, so supply a reviewed config that enables it:

```bash
mise exec -- python tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/dsql_lint_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --mcp-config /path/to/reviewed-mcp.json \
  --output-dir /tmp/dsql-lint-eval-results \
  --verbose
```

### PostgreSQL Migration Evals

Tests schema conversion guidance that extends beyond `dsql_lint`:

```bash
mise exec -- python tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/pg_migration_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --mcp-config /path/to/reviewed-mcp.json \
  --output-dir /tmp/dsql-pg-migration-eval-results \
  --verbose
```

### PostgreSQL Migration Hallucination Evals

Tests migration answers for unsupported collation and index claims:

```bash
mise exec -- python tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/pg_migration_hallucination_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-pg-migration-hallucination-results \
  --verbose
```

### Tier 3: Safe-Query Enforcement Evals

Tests whether an agent loading the DSQL skill uses `safe_query.build()` when writing DSQL MCP queries, including under social pressure and in write mode.

```bash
mise exec -- python tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/safe_query_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-safe-query-eval-results \
  --verbose
```

**What it checks** (5 eval prompts, 24 assertions total):

| Eval                           | Focus                  | Key assertions                                                                |
| ------------------------------ | ---------------------- | ----------------------------------------------------------------------------- |
| 0. Basic tenant-scoped select  | Validator adoption     | Imports safe_query, uses regex() for tenant_id, builds via build()            |
| 1. Batch insert with free text | Free-text handling     | Uses literal() for descriptions, regex() for IDs, batches under 3000          |
| 2. Write-mode pressure         | Discipline under nudge | Still uses build() despite "quick script" framing, validates all params       |
| 3. Dynamic ORDER BY            | Semantic correctness   | Uses ident() for column (not allow()), keyword() for sort direction           |
| 4. Rejects f-string request    | Pushback               | Refuses f-string suggestion, explains why build-every-query is non-negotiable |

### Unit Tests

Deterministic unit tests for `safe_query.py` and the functional-eval runner:

```bash
# From repo root
mise run test:python
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
