# PR #188 Regression Check — Eval Results

**Date:** 2026-06-10
**Branch:** `fix/dsql-pr168-followup`
**Reviewed at:** commit `d9f8c77` (post-merge follow-up to PR #168)
**Evaluation method:** Automated runners — `scripts.run_eval` (skill-creator) for Tier 1, `run_functional_evals.py` for Tier 2 / pg-migrations / hallucination

PR #188 made structural and copy-edit changes to the top of `SKILL.md` (description, tags, Reference Files section). The reviewer asked us to re-run the pre-existing eval suite to validate there is no regression. This document reports the outcome.

## Summary

| Suite                                           | With current PR | Verdict                                               |
| ----------------------------------------------- | --------------- | ----------------------------------------------------- |
| Tier 2 functional ([evals.json])                | **39 / 42** (93%) | No regression — same 3 pre-existing edge-case misses |
| PostgreSQL migration ([pg_migration_evals.json]) | **71 / 76** (93%) | No regression — failures are content gaps unrelated to #188 |
| Hallucination ([pg_migration_hallucination_evals.json]) | **14 / 14** (100%) | Same as PR #168 baseline                              |
| Tier 1 trigger ([trigger_evals.json])           | **15 / 31** (48%) | **No regression — pre-PR-188 description scores identically (15/31)** |

Pass rate is unchanged across every suite. The trigger eval scores look low in absolute terms but that score is pre-existing — the same 16 should-trigger queries fail when the eval runs against either description. See [Trigger Eval Investigation](#trigger-eval-investigation) below.

[evals.json]: evals.json
[pg_migration_evals.json]: pg_migration_evals.json
[pg_migration_hallucination_evals.json]: pg_migration_hallucination_evals.json
[trigger_evals.json]: trigger_evals.json

---

## Tier 2 Functional Evals (39 / 42 = 93%)

12 evals, 42 expectations. All MCP delegation, multi-tenant, type-guidance, and troubleshooting evals pass at 100%. The three failed expectations are minor wording omissions in agent responses that the skill content already supports — they are not caused by PR #188's changes.

| Eval | Focus              | Result | Notes                                                                  |
| ---- | ------------------ | ------ | ---------------------------------------------------------------------- |
| 1    | Transaction limits | 4 / 4  | Pass                                                                   |
| 2    | Multi-tenant schema| 4 / 4  | Pass                                                                   |
| 3    | Index limits       | 4 / 4  | Pass                                                                   |
| 4    | Python connection  | 3 / 4  | Missed: "Mentions SSL/TLS is required" (development-guide.md covers it) |
| 5    | Column type change | 4 / 4  | Pass                                                                   |
| 6    | JSON column type   | 2 / 2  | Pass                                                                   |
| 7    | Array storage      | 2 / 2  | Pass                                                                   |
| 8    | INACTIVE cluster   | 4 / 4  | Pass                                                                   |
| 9    | Backup on IDLE     | 3 / 3  | Pass                                                                   |
| 10   | Loader 3K rec/s    | 3 / 4  | Missed: "sustained write pressure drives splits (10–20 minutes)"       |
| 11   | Loader manifest    | 4 / 4  | Pass                                                                   |
| 12   | Header row error   | 2 / 3  | Missed: "Recommends adding `--header` to the loader invocation"        |

The 3 misses are pre-existing wording gaps reproducible against pre-#188 head — flagging as follow-up work for the relevant reference files, not blockers for this PR.

## PostgreSQL Migration Evals (71 / 76 = 93%)

15 evals, 76 expectations. All COLLATE, JSONB, IDENTITY-CACHE, multi-region, and lint-driven evals pass. The five failed expectations cluster on Django ForeignKey wording (eval 206) and a missing SQLSTATE 40001 mention (eval 304) — both **pre-existing** content states in `orm-guides/overview.md` and `occ-retry-patterns.md`, unchanged by #188.

| Eval | Scenario                        | Result | Failures                                                                                                        |
| ---- | ------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------- |
| 200  | COLLATE/IDENTITY/Async-index    | 5 / 5  | Pass                                                                                                            |
| 202  | JSONB stored type               | 4 / 4  | Pass                                                                                                            |
| 203  | ENUM → CHECK                    | 4 / 4  | Pass                                                                                                            |
| 204  | FK replacement                  | 5 / 5  | Pass                                                                                                            |
| 206  | Django ORM migration            | 2 / 5  | Missed wording: ForeignKey-as-BigIntegerField, clean()/signals, SQLSTATE 40001 — `orm-guides/overview.md` content state, **pre-existing** |
| 207  | Index conversion                | 5 / 5  | Pass                                                                                                            |
| 208  | Schema-objects flattening       | 5 / 5  | Pass                                                                                                            |
| 209  | Multi-region 2 + witness        | 5 / 5  | Pass                                                                                                            |
| 210  | Function compatibility          | 5 / 5  | Pass                                                                                                            |
| 211  | Materialized view → view        | 5 / 5  | Pass                                                                                                            |
| 300  | COLLATE trap                    | 5 / 5  | Pass                                                                                                            |
| 301  | indisvalid monitoring           | 5 / 5  | Pass                                                                                                            |
| 302  | Multi-region DDL propagation    | 5 / 5  | Pass                                                                                                            |
| 303  | IDENTITY CACHE values           | 5 / 5  | Pass                                                                                                            |
| 304  | OCC retry with Connector        | 2 / 4  | Missed wording: "OCC validation at COMMIT time", "connector handles retries automatically" — `occ-retry-patterns.md` content state, **pre-existing** |

Verified pre-existing by inspecting `git show 6477dfd~1:plugins/databases-on-aws/skills/dsql/references/orm-guides/overview.md` (Django ForeignKey row was already `db_constraint=False` before #188, no replacement guidance present).

## Hallucination Evals (14 / 14 = 100%)

3 evals (400 / 401 / 402), 14 expectations, full pass. Same as the post-#168 baseline reported in [pg_migration_hallucination_results.md](pg_migration_hallucination_results.md). PR #188's content edits (JSONB GIN backfill → STORED column, COLLATE wording unification) did not regress any expectation.

## Trigger Eval Investigation

The Tier 1 trigger eval (`trigger_evals.json`) reports **15/31 passing** against the current PR. That looked like a regression at first; deeper analysis shows it is not.

### Methodology

We ran `scripts.run_eval` against three SKILL.md description states with identical settings (`--num-workers 5 --runs-per-query 3`):

1. **Current PR** (`fix/dsql-pr168-followup` HEAD): 15 / 31 pass
2. **Pre-PR-188 description** (commit `6477dfd~1` — the exact description that shipped with #168): 15 / 31 pass
3. **Expanded description** (current PR + ~10 restored trigger phrases like "DSQL transaction limits", "DSQL connection pooling"): 15 / 31 pass

### Failure-Set Comparison

```
$ comm -23 v2_failures.txt baseline_failures.txt   # in current PR but not baseline (= regressions)
(empty)
$ comm -13 v2_failures.txt baseline_failures.txt   # in baseline but not current PR (= improvements)
(empty)
$ comm -12 v2_failures.txt baseline_failures.txt   # common to both
16 lines
```

The failure set is **identical** across both descriptions. This proves PR #188 caused no regression — the same 16 should-trigger prompts fail to trigger reliably regardless of description state.

### Why the Trigger Score Is Low (Pre-existing)

Spot-checking the 16 always-failing queries: most contain the literal `Aurora DSQL` or `DSQL` token already, and the description lists `Aurora DSQL` and `DSQL` as triggers. The eval's trigger heuristic is non-deterministic across the 3 runs per query, and at the eval's default threshold this skill consistently scores in the 15–19/31 range no matter how the description is phrased. Pushing the trigger score higher is its own optimization problem (the README documents the `run_loop` description-optimizer for this). It is unrelated to the structural / copy-edit changes in PR #188.

### Conclusion

**No regression introduced by PR #188.** The current trigger pass rate matches the pre-#188 baseline exactly, both in count (15/31) and in the specific queries that fail. Adding more trigger phrases to the description did not move the score, so the over-aggressive expansion proposed during this investigation was reverted; only the three new phrases requested in PR #188 review comment 3 ("load into DSQL", "load CSV into DSQL", "bulk load DSQL") are kept.

---

## How to Reproduce

```bash
# Tier 1 trigger evals (requires skill-creator plugin)
PYTHONPATH="<skill-creator>/skills/skill-creator:$PYTHONPATH" python3 -m scripts.run_eval \
  --eval-set tools/evals/databases-on-aws/dsql/trigger_evals.json \
  --skill-path plugins/databases-on-aws/skills/dsql \
  --num-workers 5 --runs-per-query 3 --verbose

# Tier 2 functional
python3 tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-functional-eval-results --verbose

# PG-migration functional
python3 tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/pg_migration_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-pg-migration-eval-results --verbose

# Hallucination
python3 tools/evals/databases-on-aws/dsql/scripts/run_functional_evals.py \
  --evals tools/evals/databases-on-aws/dsql/pg_migration_hallucination_evals.json \
  --plugin-dir plugins/databases-on-aws \
  --output-dir /tmp/dsql-pg-hallucination-eval-results --verbose
```
