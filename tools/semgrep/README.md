# Vendored Semgrep ruleset

This directory pins the Semgrep [`r/all`](https://semgrep.dev/c/r/all)
community ruleset locally (RFC #211), so every scan (pre-commit, GitHub
Actions, `mise`) runs the same reviewed, offline ruleset instead of fetching
`r/all` live.

| File                  | What it is                                                                                |
| --------------------- | ----------------------------------------------------------------------------------------- |
| `rules-vendored.yaml` | Generated; DO NOT EDIT. The only ruleset Semgrep loads — `r/all` minus excluded rules.    |
| `rules-status.toml`   | Humans edit the "state" with a "reason" at any time based on the table below.             |
| `rules-update.py`     | Refreshes `rules-vendored.yaml` from `r/all`; run manually via `mise run semgrep:update`. |

## Updating

```bash
mise run semgrep:update      # re-download r/all, rebuild rules-vendored.yaml
mise run security:semgrep    # verify the result scans clean
```

The updater reports rules in these states:

| State      | Meaning                                                              |
| ---------- | -------------------------------------------------------------------- |
| `excluded` | Removed from the vendored ruleset by a `rules-status.toml` entry.    |
| `active`   | Kept, with the decision explicitly recorded in `rules-status.toml`.  |
| `new`      | Appeared upstream with no `rules-status.toml` entry — triage it.     |
| `orphaned` | A `rules-status.toml` entry whose rule left `r/all` — prune or keep. |

See the `rules-update.py` module docstring for the full design.
