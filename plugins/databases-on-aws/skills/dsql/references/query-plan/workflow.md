# Query Plan Explainability — Workflow

Complete workflow for diagnosing DSQL query plan performance issues. Produces a structured Markdown diagnostic report as the deliverable.

## Table of Contents

1. [Trigger Criteria](#trigger-criteria)
2. [Context Disambiguation](#context-disambiguation)
3. [Routing](#routing)
4. [Phase 0: Load Reference Material](#phase-0-load-reference-material)
5. [Phase 1: Capture the Plan](#phase-1-capture-the-plan)
6. [Phase 2: Gather Evidence](#phase-2-gather-evidence)
7. [Phase 3: Experiment (conditional)](#phase-3-experiment-conditional)
8. [Phase 4: Produce the Report, Invite Reassessment](#phase-4-produce-the-report-invite-reassessment)
9. [Safety](#safety)

---

## Trigger Criteria

Enter this workflow if **ANY** of these signals are present:

| Signal                                                | Examples                                                                      |
| ----------------------------------------------------- | ----------------------------------------------------------------------------- |
| User provides SQL + mentions performance/speed/cost   | "this query takes 8 seconds", "too slow", "optimize this", "make this faster" |
| User mentions DPU cost or resource consumption        | "high DPU", "query cost is too high", "read DPU seems excessive"              |
| User asks about a plan choice or scan type            | "why is it doing a full scan?", "why not use the index?"                      |
| User pastes EXPLAIN / EXPLAIN ANALYZE output          | Raw plan text in the message                                                  |
| User references a Query ID and asks about performance | "query abc-123 is slow"                                                       |
| User says "reassess" / "re-run" / "I added the index" | Reassessment re-entry — re-runs Phase 1–2 and appends an Addendum per Phase 4 |

---

## Context Disambiguation

Before entering the workflow, confirm the query targets DSQL:

| Condition                                                                     | Action                                                                                |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Only `aurora-dsql` MCP is connected (no other database MCPs)                  | Proceed — DSQL is the only target                                                     |
| User explicitly mentions DSQL, Aurora DSQL, or a known DSQL cluster           | Proceed                                                                               |
| Conversation already has prior DSQL interaction (earlier queries, schema ops) | Proceed                                                                               |
| Multiple database MCPs are connected and no DSQL signal in the message        | Ask the user which database they mean before proceeding                               |
| No database MCP is connected                                                  | Inform the user that the `aurora-dsql` MCP is required — no MCP means no plan capture |

---

## Routing

| Condition                                                  | Path                                                                                                                                                   |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| User provides SQL but no plan output                       | Full workflow: Phase 0 → 1 → 2 → 3 → 4                                                                                                                 |
| User pastes plan output + asks to fix/optimize             | Full workflow: Phase 0 → 1 (re-capture fresh plan) → 2 → 3 → 4                                                                                         |
| User pastes plan output + asks what it means (educational) | Full workflow: Phase 0 → 1 (re-capture fresh plan) → 2 → 3 → 4. The report is the explanation — do not produce a shorter conversational answer instead |
| Execution time >30s detected at Phase 1                    | Phase 3 skips experiments per guc-experiments.md                                                                                                       |
| User says "reassess" or equivalent                         | Re-run Phase 1–2, append Addendum to existing report                                                                                                   |

---

## Phase 0: Load Reference Material

MUST read these four files before starting — each has content later phases need verbatim (node-type math, exact catalog SQL, the `>30s` skip protocol, required report elements):

1. [plan-interpretation.md](plan-interpretation.md) — node types, duration math, anomalous values
2. [catalog-queries.md](catalog-queries.md) — pg_class / pg_stats / pg_indexes SQL
3. [guc-experiments.md](guc-experiments.md) — GUC procedures and `>30s` skip protocol
4. [report-format.md](report-format.md) — required report structure

SHOULD also load these index files to identify applicable rewrites at Phase 2:

1. [query-rewrites-generic.md](query-rewrites-generic.md) — pattern index (load specific sub-file when a match is found)
2. [query-rewrites-dsql-specific.md](query-rewrites-dsql-specific.md) — DSQL-specific pattern index

---

## Phase 1: Capture the Plan

For queries the user reports as expensive or slow (execution time >30s, high DPU, or timeout), start with plain `EXPLAIN` (without ANALYZE) to see the optimizer's plan without executing the query. Then run `EXPLAIN ANALYZE VERBOSE` to get actual row counts and DPU.

For all other queries, run `readonly_query("EXPLAIN ANALYZE VERBOSE …")` directly on the user's query verbatim (SELECT form) — **ALWAYS** capture a fresh plan from the cluster, even when the user describes the plan or reports an anomaly. **MAY** leverage `get_schema` or `information_schema` for schema sanity checks.

When EXPLAIN errors (`relation does not exist`, `column does not exist`), **MUST** report the error verbatim — **MUST NOT** invent DSQL-specific semantics (e.g., case sensitivity, identifier quoting) as the root cause.

Extract: Query ID, Planning Time, Execution Time, DPU Estimate.

| Statement type                         | Action                                                                                       |
| -------------------------------------- | -------------------------------------------------------------------------------------------- |
| SELECT                                 | Run as-is                                                                                    |
| UPDATE / DELETE                        | Rewrite to equivalent SELECT (same join chain + WHERE) — optimizer picks the same plan shape |
| INSERT, pl/pgsql, DO blocks, functions | **MUST** reject                                                                              |

**MUST NOT** use `transact --allow-writes` for plan capture; it bypasses MCP safety.

---

## Phase 2: Gather Evidence

Using SQL from `catalog-queries.md`, query `pg_class`, `pg_stats`, `pg_indexes`, `COUNT(*)`, `COUNT(DISTINCT)`.

1. Classify estimation errors per `plan-interpretation.md` (2x–5x minor, 5x–50x significant, 50x+ severe).
2. Detect correlated predicates and data skew.
3. When a Full Scan appears despite an apparently usable index, check for **type coercion index bypass**: retrieve indexed column types and compare against predicate literal types using the `pg_amop` query in `catalog-queries.md` (B-Tree Cross-Type Operator Support).
4. Check whether any query rewrite from `query-rewrites-generic.md` or `query-rewrites-dsql-specific.md` applies to the query structure (e.g., OR-to-IN, subquery unnesting, NOT IN to NOT EXISTS, split large joins).

---

## Phase 3: Experiment (conditional)

- **≤30s:** Run GUC experiments per `guc-experiments.md` (default + merge-join-only) plus optional redundant-predicate test.
- **>30s:** Skip experiments, include the manual GUC testing SQL verbatim in the report, and do not re-run for redundant-predicate testing.
- **Anomalous values** (impossible row counts): confirm query results are correct despite the anomalous EXPLAIN, flag as a potential DSQL bug, and produce the Support Request Template from `report-format.md`.

---

## Phase 4: Produce the Report, Invite Reassessment

Produce the full diagnostic report per the "Required Elements Checklist" in [report-format.md](report-format.md) — structure is non-negotiable.

End with the "Next Steps" block from that reference so the user can ask for a reassessment after applying a recommendation.

When the user says "reassess" (or equivalent), re-run Phase 1–2 and **append an "Addendum: After-Change Performance"** to the original report (before/after table, match against expected impact) rather than producing a new report.

If a query rewrite was identified in Phase 2, include it as a recommendation with the original and rewritten SQL side by side.

---

## Safety

Plan capture MUST use `readonly_query` exclusively — it rejects INSERT/UPDATE/DELETE/DDL at the MCP layer. Rewrite DML to SELECT (Phase 1) rather than asking `transact --allow-writes` to run it; write-mode `transact` bypasses all MCP safety checks. **MUST NOT** run arbitrary DDL/DML or pl/pgsql.
