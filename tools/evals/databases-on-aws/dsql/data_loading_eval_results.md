# Data Loading Eval Results

## Summary

3 functional evals testing DSQL-loader-specific operational knowledge. All **11/11 expectations pass** with skill loaded. Baseline fails on DSQL-specific knowledge in all 3 scenarios.

| Eval | Scenario                    | With-Skill     | Baseline                         | Delta                            |
| ---- | --------------------------- | -------------- | -------------------------------- | -------------------------------- |
| 10   | Loader stuck at 3K rec/s    | **PASS** (4/4) | FAIL — recommends adding workers | Skill prevents harmful advice    |
| 11   | Loader crash, lost manifest | **PASS** (4/4) | FAIL — generic recovery          | Skill gives exact recovery path  |
| 12   | Header row parse error      | **PASS** (3/3) | Partial — guesses flag name      | Skill gives definitive diagnosis |

## Eval 10: Partition-Constrained Fresh Table

**Customer question:** "I'm loading 50M rows into a fresh DSQL table with 8 workers but only getting 3K records/second. Host CPU is 20%. Should I add more workers?"

### With-Skill (PASS 4/4)

- ✅ Identifies partition-constrained fresh table as root cause
- ✅ Explains DSQL auto-splits under sustained write heat
- ✅ Does NOT recommend adding workers (writes serialize on single partition)
- ✅ Suggests pre-pass strategy for future loads

### Baseline (FAIL)

- ❌ Recommends adding workers or increasing batch size (wrong — writes serialize)
- ❌ Does not know DSQL partition warming behavior
- ❌ May suggest network/host investigation (wastes time)

**Value:** Skill prevents confidently wrong advice. 3K rec/s on a fresh table is normal DSQL behavior, not a bug.

## Eval 11: Manifest Lost After Crash

**Customer question:** "Loader crashed on AL2023 after 30M of 100M rows. Resume says manifest not found. How do I recover without re-loading the 30M?"

### With-Skill (PASS 4/4)

- ✅ Identifies /tmp as tmpfs on AL2023 (root cause)
- ✅ Recommends `--on-conflict do-nothing` for recovery
- ✅ States preconditions: unique constraint exists, load is idempotent, source unchanged
- ✅ Recommends `--manifest-dir` on persistent path for prevention

### Baseline (FAIL)

- ❌ Does not know AL2023 uses tmpfs for /tmp
- ❌ Suggests generic approaches (manual row counting, file splitting)
- ❌ Missing the loader's built-in recovery mechanism

**Value:** Skill provides exact recovery procedure with safety preconditions. Baseline gives speculative generic advice.

## Eval 12: Missing --header Flag

**Customer question:** "Getting 'invalid input syntax for type integer: customer_id'. First batch fails but CSV looks fine."

### With-Skill (PASS 3/3)

- ✅ Identifies missing `--header` flag immediately
- ✅ Explains loader defaults to treating every row as data
- ✅ Notes v2.x → v3.x behavioral change for upgrading users

### Baseline (Partial)

- ⚠️ Correctly guesses header issue but uncertain on exact flag name
- ❌ Does not know v2/v3 default change
- ❌ Cannot confirm with authority (educated guess vs documented behavior)

**Value:** Skill transforms a guess into a definitive diagnosis with version migration context.

## Conclusion

The skill teaches DSQL-loader-specific operational knowledge that cannot be inferred from general training data:

1. **Partition warming** — fresh tables absorb a few thousand rec/s regardless of client concurrency
2. **tmpfs defaults** — AL2023 /tmp is tmpfs, manifests lost on crash
3. **Header flag semantics** — v3.x changed default behavior from v2.x
4. **Recovery mechanics** — `--on-conflict do-nothing` as crash recovery with explicit preconditions
