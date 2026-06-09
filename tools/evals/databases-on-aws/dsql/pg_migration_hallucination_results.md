# Hallucination Eval Results — With-Skill vs Baseline

**Date:** 2026-05-29
**Evaluation method:** Automated LLM-judge grading via `run_functional_evals.py`

## Summary

| Mode                    | Evals | Expectations | Passed | Rate     |
| ----------------------- | ----- | ------------ | ------ | -------- |
| **With Skill**          | 3     | 14           | **14** | **100%** |
| **Baseline (no skill)** | 3     | 14           | 10     | 71%      |

## Per-Eval Comparison

| Eval | Scenario                 | With Skill | Baseline   | Delta                                     |
| ---- | ------------------------ | ---------- | ---------- | ----------------------------------------- |
| 400  | JSONB + GIN index        | 5/5 ✅     | 5/5 ✅     | Both correct                              |
| 401  | COLLATE "C" on columns   | **5/5 ✅** | **1/5 ❌** | **Baseline hallucinates; skill corrects** |
| 402  | Synchronous CREATE INDEX | 4/4 ✅     | 4/4 ✅     | Both correctly convert to ASYNC           |

## Critical Finding: Eval 401 (COLLATE Hallucination)

The baseline agent **actively recommends adding `COLLATE "C"` to every string column** — this produces a DDL error in DSQL (`COLLATE clause not supported`). The skill-guided agent correctly states "do not add COLLATE" and produces valid DDL.

### Baseline Behavior (WRONG — causes DDL failure)

- Says "you should explicitly add COLLATE "C" to your string columns"
- Produces DDL with `name VARCHAR(200) COLLATE "C"` on every column
- This DDL **fails** when executed against DSQL

### With-Skill Behavior (CORRECT)

- Says "No — do not add COLLATE "C" to your columns"
- Explains "DSQL uses C collation database-wide and does not support per-column COLLATE clauses"
- Produces clean DDL without any COLLATE clause
- Warns about ORDER BY byte-value sorting as a consequence

### Why This Matters

A user following the baseline's advice would get a DDL rejection error at execution time. The skill prevents this by placing the COLLATE rule in the always-loaded `development-guide.md`.

### Root Cause

The model's training data contains older DSQL documentation that recommended explicit `COLLATE "C"` on columns. DSQL's behavior changed — per-column COLLATE is now rejected. The skill overrides stale training data with the current correct behavior.

## Detailed Results

### Eval 401 Expectations

| Expectation                                | With Skill | Baseline                           |
| ------------------------------------------ | ---------- | ---------------------------------- |
| States per-column COLLATE is NOT supported | ✅         | ❌ Recommends adding it            |
| Explains C collation is database-wide      | ✅         | ❌ Says to add explicitly          |
| Does NOT recommend adding COLLATE          | ✅         | ❌ Actively recommends it          |
| Mentions byte-value sorting                | ✅         | ✅                                 |
| DDL output has no COLLATE                  | ✅         | ❌ Includes COLLATE on all columns |

## Conclusion

The skill prevents a real hallucination that causes DDL failures in production. Without the skill, the agent gives incorrect guidance based on stale training data. With the skill, the agent gives correct, current guidance.
