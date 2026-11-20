# Rewrite: Subquery Unnesting — Redundant Correlation

When every outer column that a correlated EXISTS subquery references is pinned to a constant or parameter by the outer `WHERE`, the subquery returns the same answer for every outer row. The optimizer derives the constant into the inner scan's `Index Cond` through equivalence classes, but the EXISTS was already pulled up into a semi-join, so the inner scan still runs once per outer row. The cost is highest when the optimizer also underestimates the outer row count, typically because the outer `WHERE` has several predicates on correlated columns. The rewrite removes the outer reference before pull-up, so the EXISTS becomes an `InitPlan` that runs once, regardless of the outer estimate.

This differs from the generic correlated-EXISTS rewrite (`subquery-unnesting-correlated.md`). There, the correlation carries per-row information and the rewrite converts it to a JOIN. Here, the correlation carries no information and the rewrite removes it. No JOIN is introduced, so no `DISTINCT` is needed.

**SHOULD apply when:** Every column the subquery references from the outer query is pinned by the outer `WHERE` to a constant or parameter with plain equality, AND `EXPLAIN ANALYZE` shows the subquery's logical scan node with `loops = N` where N is the number of outer rows.

**SHOULD skip when:** The subquery references any outer column the outer `WHERE` does not pin to a constant or parameter. Substituting only the pinned columns does not help; the subquery stays correlated through the remaining column and still runs per row. An `IN` list, range, or `OR` branch does not pin a column. The correlation columns have different types or collations; `=` can then resolve differently in the two places and change the result.

## How to confirm the problem

Run `EXPLAIN ANALYZE`. The problem is present when the inner logical scan node (`Index Only Scan`, `Index Scan`, or `Full Scan`) shows `loops = N`:

```
Nested Loop Semi Join  (rows=1) (actual rows=1000 loops=1)
  ->  Index Only Scan using orders_crd on orders o  (rows=1) (actual rows=1000 loops=1)
  ->  Index Only Scan using accounts_pkey on accounts a  (rows=1) (actual rows=1 loops=1000)   <-- here
        Index Cond: (a.customer_id = 'C1000'::text)
        -> Storage Scan on accounts_pkey  (rows=1 loops=1) (actual rows=1 loops=1)
            -> B-Tree Scan on accounts_pkey  (rows=1 loops=1) (actual rows=1 loops=1)
```

Check `loops` on the logical scan node, not on a node above it and not on its DSQL `Storage Scan` / `B-Tree Scan` children, which report `loops=1` even when the parent ran N times. If a `Materialize` node sits between the join and the scan, and the scan shows `loops = 1`, the subquery ran once and the rescans are in-memory replays. That case is already cheap and this rewrite gains little.

`Materialize` is absent when the optimizer estimates the outer side at about one row, so the problem appears together with a low outer estimate. Compare the outer scan's estimated rows to its actual rows; a large gap (here 1 vs 1000) confirms it.

## Original

```sql
-- customer_id, region_id, and order_date are correlated in the data, so the
-- optimizer estimates 1 row for orders when the true count is 1000.
-- o.customer_id is pinned to $1, so the EXISTS gives the same answer per row.
SELECT o.order_id
FROM   orders o
WHERE  o.customer_id = $1
  AND  o.region_id   = $2
  AND  o.order_date >= $3
  AND  EXISTS (SELECT 1
               FROM   accounts a
               WHERE  a.customer_id = o.customer_id);
```

## Option A — Substitute the constant (preferred)

Replace the outer column reference inside the subquery with the same constant the outer `WHERE` uses.

```sql
SELECT o.order_id
FROM   orders o
WHERE  o.customer_id = $1
  AND  o.region_id   = $2
  AND  o.order_date >= $3
  AND  EXISTS (SELECT 1
               FROM   accounts
               WHERE  customer_id = $1);
```

Expected plan:

```
Result
  One-Time Filter: $0
  InitPlan 1 (returns $0)
    -> Index Only Scan on accounts_pkey      (actual rows=1    loops=1)
  -> Index Only Scan on orders o             (actual rows=1000 loops=1)
```

If the query has another join on the same pinned column, DSQL cannot use a batched nested loop for it after the rewrite, so that join's plan changes. Compare its node type and the total execution time before and after.

## Option B — Lift into a CTE

Use when a named, one-time existence check reads more clearly than Option A.

```sql
WITH account_exists AS MATERIALIZED (
  SELECT 1 FROM accounts WHERE customer_id = $1
)
SELECT o.order_id
FROM   orders o
WHERE  o.customer_id = $1
  AND  o.region_id   = $2
  AND  o.order_date >= $3
  AND  EXISTS (SELECT 1 FROM account_exists);
```

The plan evaluates `CTE account_exists` once and reads it through `InitPlan 2 (returns $1)`, which filters the outer scan the same way as in Option A. `MATERIALIZED` is optional: without it the optimizer inlines the single-reference CTE and produces exactly Option A's plan. Keep it to make the one-time evaluation explicit.

## Correctness

The outer `WHERE` keeps only rows where `o.customer_id = $1`. Inside the subquery, `a.customer_id = o.customer_id` and `a.customer_id = $1` are the same test as long as `=` behaves the same for both columns. That holds when the columns have the same type, or types whose `=` agrees (such as `int` and `bigint`). It fails when a cast between them changes the value or the comparison (such as `char(n)` and `text`, where `char` ignores trailing blanks and `text` does not). NULL does not affect this since a row with a NULL `o.customer_id` fails the outer `WHERE`, and a NULL `$1` returns no rows in either form.
