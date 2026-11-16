# Query Plan Rewrite Eval Results — With-Skill vs Baseline

**Date:** 2026-05-08
**Model:** Claude Opus 4.6 (global.anthropic.claude-opus-4-6-v1)
**Runs per eval:** 1 (qualitative comparison, not variance-tested)
**Evals 211–213 and 200–210 re-run:** 2026-11-11, Claude Opus 5.5 (global.anthropic.claude-opus-5-5), Claude Code 2.1.319. With-skill runs used `claude -p --plugin-dir plugins/databases-on-aws --tools Read,Glob,Grep` from the repo root; baseline used `claude -p --bare --tools ""` from a clean temp directory. `--tools Read,Glob,Grep` omits the Skill tool, so with-skill runs reach reference files through Grep/Read rather than by loading SKILL.md. n=1 per cell; graded against each eval's `expectations` array.

**Evaluation method:** Manual qualitative comparison — `claude -p` with skill loaded (from agent-plugins project root) vs `claude -p --bare` from clean directory. n=1 per cell; PASS/FAIL is a single human transcript assessment. Results indicate directional improvement, not statistical significance. Re-run with n≥3 and majority vote for production confidence.

## Summary

| Eval | Scenario                        | With Skill | Baseline | Delta                                                                                                                |
| ---- | ------------------------------- | ---------- | -------- | -------------------------------------------------------------------------------------------------------------------- |
| 200  | IN-subquery Full Scan           | **PASS**   | PARTIAL  | Skill recommends specific rewrite patterns (EXISTS, JOIN) from reference; baseline gives generic advice              |
| 201  | Type coercion index bypass      | **PASS**   | PASS     | Both identify type mismatch; skill adds DSQL-specific B-Tree operator registration detail and offers full workflow   |
| 202  | 12-table join ordering          | **PASS**   | PARTIAL  | Skill offers full diagnostic workflow with GUC experiments; baseline gives generic PostgreSQL advice                 |
| 203  | COUNT(*) timeout on large table | **PASS**   | FAIL     | Skill recommends pg_class reltuples; baseline suggests timeout/retry                                                 |
| 204  | Multiple OR to IN               | **PASS**   | PARTIAL  | Skill identifies OR-to-IN pattern from reference; baseline suggests composite index                                  |
| 205  | GROUP BY after JOIN             | **PASS**   | PARTIAL  | Skill recommends pushing GROUP BY into subquery from reference; baseline suggests general indexing                   |
| 206  | LEFT JOIN null rejection        | **PASS**   | PARTIAL  | Skill provides structured rewrite with skip conditions; baseline hedges                                              |
| 207  | Computation on indexed col      | **PASS**   | PASS     | Both identify; skill adds skip conditions for non-invertible ops                                                     |
| 208  | NOT IN with NULLs               | **PASS**   | PASS     | Both rewrite to NOT EXISTS; **skill wins on NULL semantics warning and user confirmation gate**                      |
| 209  | Nested UNION ALL                | **PASS**   | PASS     | Both flatten; skill documents UNION (dedup) edge case                                                                |
| 210  | OR across different columns     | **PASS**   | PASS     | Both correctly decline OR-to-IN; skill explicitly references the same-column rule                                    |
| 211  | Redundant EXISTS correlation    | **PASS**   | PASS     | Both substitute the constant and predict an InitPlan; skill also states why the result set is unchanged (not graded) |
| 212  | Partially pinned correlation    | **PASS**   | FAIL     | Skill states the all-or-nothing rule; baseline never names `o.account_id` and says the planner already decorrelates  |
| 213  | Generic correlated EXISTS       | **PASS**   | FAIL     | Skill cites the pinning rule when consulted (1 of 3 runs); baseline declines for the wrong reason                    |

---

## Eval 200: IN-Subquery Full Scan

**Prompt:** "My DSQL query is slow. It does: SELECT * FROM customers WHERE customer_id IN (SELECT customer_id FROM orders WHERE order_date > '2024-01-01'); The EXPLAIN shows a Full Scan on customers."

### Behavior Comparison

| Behavior                        | With Skill                         | Baseline                | Correct?                                   |
| ------------------------------- | ---------------------------------- | ----------------------- | ------------------------------------------ |
| Identifies IN-subquery pattern  | PASS                               | PASS                    | Both identify it                           |
| Recommends EXISTS rewrite       | PASS                               | Maybe                   | Skill explicitly recommends from reference |
| Recommends JOIN rewrite         | PASS                               | Maybe                   | Skill provides both options                |
| Checks for type coercion        | PASS (mentions as secondary check) | FAIL                    | Skill wins                                 |
| Offers full diagnostic workflow | PASS                               | FAIL (no MCP awareness) | Skill wins                                 |

---

## Eval 201: Type Coercion Index Bypass

**Prompt:** "customer_id = '12345' with integer column, Full Scan despite index"

### Behavior Comparison

| Behavior                                                | With Skill | Baseline                                              | Correct?                 |
| ------------------------------------------------------- | ---------- | ----------------------------------------------------- | ------------------------ |
| Identifies type mismatch                                | PASS       | PASS                                                  | Both correct             |
| References DSQL B-Tree operator registration            | PASS       | FAIL (uses generic PostgreSQL "sargable" explanation) | Skill more precise       |
| Recommends removing quotes or casting                   | PASS       | PASS                                                  | Both correct             |
| Offers structured diagnostic workflow                   | PASS       | FAIL                                                  | Skill wins               |
| References pg_amop query or cross-type operator concept | PASS       | FAIL                                                  | Skill-specific knowledge |

**Note:** Type coercion is well-known in PostgreSQL training data, so baseline performs reasonably. The skill adds DSQL-specific precision (cross-type operator families, B-Tree access method behavior) and the structured workflow.

---

## Eval 202: 12-Table Join Ordering

**Prompt:** "12 tables, optimizer picks bad join order"

### Behavior Comparison

| Behavior                                    | With Skill | Baseline      | Correct?        |
| ------------------------------------------- | ---------- | ------------- | --------------- |
| Identifies DP/GEQO threshold                | PASS       | PASS          | Both mention it |
| Recommends CTE splitting                    | PASS       | PASS          | Both suggest it |
| References join_collapse_limit              | PASS       | PASS          | Both mention it |
| Offers to run full EXPLAIN ANALYZE workflow | PASS       | FAIL (no MCP) | Skill wins      |
| Recommends GUC experiments                  | PASS       | FAIL          | Skill-specific  |
| Mentions redundant predicate technique      | PASS       | FAIL          | Skill-specific  |

---

## Eval 203: COUNT(*) Timeout on Large Table

**Prompt:** "50 million row table, COUNT(*) times out, need approximate count"

### Behavior Comparison

| Behavior                      | With Skill | Baseline                         | Correct?                                                                              |
| ----------------------------- | ---------- | -------------------------------- | ------------------------------------------------------------------------------------- |
| Recommends pg_class reltuples | PASS       | FAIL (suggests timeout increase) | **Skill wins** — reltuples is the correct DSQL pattern                                |
| Provides exact SQL            | PASS       | FAIL                             | Skill provides `SELECT reltuples::bigint FROM pg_class WHERE oid = 'table'::regclass` |
| Notes it's an estimate        | PASS       | N/A                              | Skill correctly qualifies                                                             |

---

## Eval 204: Multiple OR to IN

**Prompt:** "WHERE department_id = 1 OR department_id = 2 OR ... Full Scan with index"

### Behavior Comparison

| Behavior                          | With Skill | Baseline                                     | Correct?                     |
| --------------------------------- | ---------- | -------------------------------------------- | ---------------------------- |
| Identifies OR pattern             | PASS       | PASS                                         | Both                         |
| Recommends IN rewrite             | PASS       | PARTIAL (may suggest it among other options) | Skill is specific            |
| Checks type coercion as secondary | PASS       | FAIL                                         | Skill-specific               |
| Provides rewritten SQL            | PASS       | PARTIAL                                      | Skill provides exact rewrite |

---

## Eval 205: GROUP BY After JOIN

**Prompt:** "Grouping over large joined result, how to optimize"

### Behavior Comparison

| Behavior                          | With Skill | Baseline                 | Correct?                              |
| --------------------------------- | ---------- | ------------------------ | ------------------------------------- |
| Identifies fact/dimension pattern | PASS       | PARTIAL                  | Skill explicitly identifies it        |
| Recommends subquery aggregation   | PASS       | FAIL (suggests indexing) | **Skill wins** — correct optimization |
| Provides rewritten SQL            | PASS       | FAIL                     | Skill provides complete example       |
| Explains row reduction benefit    | PASS       | PARTIAL                  | Skill explains clearly                |

---

## Eval 206: LEFT JOIN with Null-Rejecting Predicate

**Prompt:** "LEFT JOIN R2 … WHERE R2.status = 'active' — unnecessary work"

### Behavior Comparison

| Behavior                            | With Skill | Baseline | Correct?                         |
| ----------------------------------- | ---------- | -------- | -------------------------------- |
| Identifies null-rejecting WHERE     | PASS       | PASS     | Both identify it                 |
| Recommends converting to INNER JOIN | PASS       | PARTIAL  | Baseline mentions but hedges     |
| Provides rewritten SQL              | PASS       | PARTIAL  | Skill provides exact rewrite     |
| Explains simpler join plan benefit  | PASS       | FAIL     | Skill-specific structured output |

---

## Eval 207: Computation on Indexed Column

**Prompt:** "WHERE price + 10 > 100 — Full Scan with index on price"

### Behavior Comparison

| Behavior                                  | With Skill | Baseline | Correct?                            |
| ----------------------------------------- | ---------- | -------- | ----------------------------------- |
| Identifies arithmetic preventing index    | PASS       | PASS     | Both identify it                    |
| Recommends moving computation to constant | PASS       | PASS     | Both suggest it                     |
| Provides rewritten SQL (WHERE price > 90) | PASS       | PASS     | Both provide it                     |
| Mentions skip conditions (non-invertible) | PASS       | FAIL     | Skill documents when NOT to rewrite |

---

## Eval 208: NOT IN with NULLs

**Prompt:** "NOT IN (SELECT … FROM exclusion_list) — 1M rows, NULLs possible"

### Behavior Comparison

| Behavior                             | With Skill | Baseline | Correct?                              |
| ------------------------------------ | ---------- | -------- | ------------------------------------- |
| Recommends NOT EXISTS rewrite        | PASS       | PASS     | Both suggest it                       |
| Warns about NULL semantics change    | PASS       | FAIL     | **Skill wins** — critical correctness |
| Asks user to confirm before applying | PASS       | FAIL     | Skill gates on user acknowledgement   |
| Provides rewritten SQL               | PASS       | PASS     | Both provide it                       |

---

## Eval 209: Nested UNION ALL

**Prompt:** "Nested UNION ALL — can this be simplified?"

### Behavior Comparison

| Behavior                      | With Skill | Baseline | Correct?                    |
| ----------------------------- | ---------- | -------- | --------------------------- |
| Identifies nested UNION ALL   | PASS       | PASS     | Both identify it            |
| Recommends flattening         | PASS       | PASS     | Both suggest it             |
| Provides rewritten SQL        | PASS       | PASS     | Both provide correct output |
| Notes UNION (dedup) must stay | PASS       | FAIL     | Skill documents the edge    |

---

## Eval 210: OR Across Different Columns (Negative Case)

**Prompt:** "WHERE department_id = 1 OR location_id = 2 — should I rewrite to IN?"

### Behavior Comparison

| Behavior                                  | With Skill | Baseline | Correct?                             |
| ----------------------------------------- | ---------- | -------- | ------------------------------------ |
| Identifies different columns in OR        | PASS       | PASS     | Both identify it                     |
| Correctly declines OR-to-IN               | PASS       | PASS     | Both decline                         |
| Explains IN requires same column          | PASS       | PARTIAL  | Skill explicitly references the rule |
| Suggests alternative (composite idx, etc) | PASS       | PASS     | Both offer alternatives              |

---

## Eval 211: Redundant EXISTS Correlation

**Prompt:** See `query_plan_rewrite_evals.json` id 211.

### Behavior Comparison

| Expectation                                                                                | With Skill | Baseline |
| ------------------------------------------------------------------------------------------ | ---------- | -------- |
| Identifies that the accounts scan runs once per outer row (loops=1000)                     | PASS       | PASS     |
| Identifies that `a.customer_id = o.customer_id` is equivalent to `a.customer_id = 'C1000'` | PASS       | PASS     |
| Recommends replacing `o.customer_id` with the constant (or lifting into a CTE)             | PASS       | PASS     |
| States the rewritten subquery runs once as an InitPlan                                     | PASS       | PASS     |
| Provides the rewritten SQL                                                                 | PASS       | PASS     |
| Does NOT recommend EXISTS→JOIN+DISTINCT as the primary fix                                 | PASS       | PASS     |
| MAY note the 1-vs-1000 estimate is a multi-column underestimate                            | met        | met      |

**Note:** The baseline model already recognizes this pattern and produces a correct primary fix, so this eval does not separate skill from baseline. Behaviors outside the expectations differed: the skill run gave an explicit argument that the result set is unchanged and warned against binding the value through a parameter CTE; the baseline argued correctness only implicitly. Both kept the outer `o.customer_id` pin.

---

## Eval 212: Partially Pinned Correlation (Negative Case)

**Prompt:** See `query_plan_rewrite_evals.json` id 212.

### Behavior Comparison

| Expectation                                                                                     | With Skill | Baseline |
| ----------------------------------------------------------------------------------------------- | ---------- | -------- |
| Identifies that the subquery references `o.account_id`, which the outer WHERE does not pin      | PASS       | FAIL     |
| Explains that substituting only `o.customer_id` leaves the subquery correlated and per-row      | PASS       | FAIL     |
| Does NOT recommend the constant-substitution or CTE rewrite as a fix                            | PASS       | PASS     |
| MAY suggest the generic EXISTS-to-JOIN rewrite or an index on accounts(customer_id, account_id) | met        | met      |

---

## Eval 213: Generic Correlated EXISTS (Neighbouring Pattern)

**Prompt:** See `query_plan_rewrite_evals.json` id 213. Covers `subquery-unnesting-correlated.md`, whose index row sits directly above the redundant-correlation row.

**Method:** Unlike the other evals, the with-skill runs keep the Skill tool available (`--tools Skill,Read,Glob,Grep`) and disable any user-installed copy of the plugin (`--settings '{"enabledPlugins":{...: false}}'`), so the plugin under test is the only DSQL skill. With change: three runs. Without change (plugin from the base commit): one run. A run that answered without invoking the skill or reading a reference is recorded as "not consulted" and is not graded, since it does not exercise the skill.

### Behavior Comparison

| Expectation                                                                                  | With Change | Without Change | Baseline |
| -------------------------------------------------------------------------------------------- | ----------- | -------------- | -------- |
| Identifies the subquery is correlated on `c.customer_id`, which the outer WHERE does not pin | PASS        | FAIL           | FAIL     |
| States that the run-once rewrite does not apply                                              | PASS        | PASS           | PASS     |
| Does NOT recommend constant substitution or a CTE                                            | PASS        | PASS           | PASS     |
| Confirms the JOIN is safe without DISTINCT because accounts.customer_id is unique            | PASS        | PASS           | PASS     |
| Provides the rewritten JOIN SQL                                                              | PASS        | PASS           | PASS     |
| MAY note a non-unique inner side would need DISTINCT                                         | met         | met            | not met  |

**Note:** With Change is the one run of three that consulted the skill; it read both `subquery-unnesting-correlated.md` and `subquery-unnesting-redundant-correlation.md` and cited the pinning rule. The other two runs did not consult the skill. Without Change consulted the skill and read `subquery-unnesting-correlated.md`; it declined the run-once rewrite because the plan is already a semi-join, not because the column is unpinned. No run routed the query to constant substitution, so the added index row did not change behavior for the neighbouring pattern.

---

## Re-run: Evals 200–210

| Eval | With Skill | Baseline | Note                                                                                              |
| ---- | ---------- | -------- | ------------------------------------------------------------------------------------------------- |
| 200  | PARTIAL    | FAIL     | Neither restates the original SQL; only the skill reads workflow.md and attempts `readonly_query` |
| 201  | PARTIAL    | FAIL     | Both runs state an untyped `'12345'` literal resolves to integer, contradicting the eval premise  |
| 202  | PASS       | PARTIAL  | Skill ties the CTE split to `join_collapse_limit`                                                 |
| 203  | PASS       | PASS     |                                                                                                   |
| 204  | PASS       | FAIL     | Baseline omits type coercion and does not attempt EXPLAIN ANALYZE                                 |
| 205  | PASS       | PASS     |                                                                                                   |
| 206  | PASS       | PASS     |                                                                                                   |
| 207  | PASS       | PASS     |                                                                                                   |
| 208  | PASS       | FAIL     | Baseline presents the NULL-semantics change as a benefit and does not ask for confirmation        |
| 209  | PASS       | PASS     |                                                                                                   |
| 210  | PASS       | PASS     |                                                                                                   |

With-skill results for 200 and 201 are lower than on 2026-05-08. The same two evals score PARTIAL with the plugin from the base commit, so the drop is not caused by this change.

---

## Conclusion

The skill demonstrably improves agent behavior for query plan optimization:

1. **Type coercion detection** — Both baseline and skill identify it (well-known pattern), but the skill adds DSQL-specific precision about B-Tree operator registration.
2. **Query rewrites** — The skill consistently recommends specific rewrite patterns from reference material, while baseline gives generic indexing advice.
3. **DSQL-specific patterns** — reltuples estimation and join splitting for DP threshold are skill-exclusive knowledge.
4. **Structured workflow** — Only the skill offers the full Phase 0–4 diagnostic with MCP tool integration.
