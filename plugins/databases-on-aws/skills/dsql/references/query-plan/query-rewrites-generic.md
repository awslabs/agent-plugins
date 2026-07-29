# Query Rewrites — Index

Generic SQL rewrites that SHOULD be recommended when a plan reveals inefficiency traceable to query structure (rather than missing indexes or stale statistics). Load the specific rewrite file that matches the observed pattern.

## Available Rewrites

| Pattern Detected                           | Reference File                                                                          |
| ------------------------------------------ | --------------------------------------------------------------------------------------- |
| Multiple OR on same column                 | [or-to-in.md](query-rewrites/or-to-in.md)                                               |
| LEFT JOIN with null-rejecting WHERE        | [left-join-to-inner.md](query-rewrites/left-join-to-inner.md)                           |
| Filter on join column not propagated       | [propagate-filter.md](query-rewrites/propagate-filter.md)                               |
| Uncorrelated IN-subquery                   | [subquery-unnesting-uncorrelated.md](query-rewrites/subquery-unnesting-uncorrelated.md) |
| Correlated EXISTS subquery                 | [subquery-unnesting-correlated.md](query-rewrites/subquery-unnesting-correlated.md)     |
| Scalar correlated subquery in SELECT       | [subquery-unnesting-scalar.md](query-rewrites/subquery-unnesting-scalar.md)             |
| Computation on indexed column in predicate | [push-computation-to-constant.md](query-rewrites/push-computation-to-constant.md)       |
| GROUP BY after JOIN with dimension columns | [push-group-by-into-subquery.md](query-rewrites/push-group-by-into-subquery.md)         |
| NOT IN with large or nullable subquery     | [not-in-to-not-exists.md](query-rewrites/not-in-to-not-exists.md)                       |
| Nested UNION ALL                           | [flatten-union-all.md](query-rewrites/flatten-union-all.md)                             |
