# Query Rewrites — DSQL-Specific

SQL rewrites that address Aurora DSQL-specific behaviors and optimizer constraints. These SHOULD be recommended when the plan reveals inefficiency unique to DSQL's distributed architecture.

## Available Rewrites

| Pattern Detected                                  | Reference File                                                            |
| ------------------------------------------------- | ------------------------------------------------------------------------- |
| COUNT(*) timeout on large table                   | [reltuples-estimate.md](query-rewrites/reltuples-estimate.md)             |
| Join count exceeds DP threshold                   | [split-large-joins.md](query-rewrites/split-large-joins.md)               |
| Storage Lookup with high loops + LIMIT discarding | [cte-late-materialization.md](query-rewrites/cte-late-materialization.md) |
