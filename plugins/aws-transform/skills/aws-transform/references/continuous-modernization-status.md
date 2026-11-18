---
name: status
description: Show AWS Transform - continuous modernization (continuous modernization) system overview — source count, repo count, analysis results, finding totals, remediation progress.
---

# Status

## Commands

```bash
atx ct status [--json]
atx ct status --health
```

`status` reports account-wide totals; it takes no `--source` filter. For one source's numbers, use
`atx ct repository list --source <name>` (the repositories in one source); `atx ct source list` shows only each source's name, provider and identifier.

The `Analyses` and `Remediations` lines also break the totals down by status (per-status counts in
`--json`: `analyses_by_status`, `remediations_by_status`). Very large counts show as a floor, for example `≥50000`, not an exact number
(`--json` adds `repos_truncated` / `analyses_truncated` / `findings_truncated` / `remediations_truncated`).

`--health` only checks that the CLI starts and is wired up: it prints `healthy` without calling AWS, so it does
not prove credentials or region are valid. Use plain `atx ct status` for that.

Related discovery commands:

- `atx ct schema` prints every `atx ct` command, option and argument as one line of JSON (pipe it to `jq`). Use it to
  check that a flag exists instead of guessing; it lists only the options `--help` shows.

## Errors & empty results

`status` is often the first command a returning user runs, so treat its failures
as onboarding-critical. Never present a failed read as a clean dashboard of
zeros — see the `troubleshooting` skill for the full reference.

| What you see                                | What it means                                                                                                                                                                                 | What to tell the user                                                                                                      |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| A count shows `unavailable (read failed …)` | That sub-query (repos, analyses, findings or remediations) failed — it is **not** actually 0; the command exits with status 2 and `--json` shows that count as `null` with a `warnings` array | Surface the warning: credentials may have expired or `AWS_REGION` may not match where resources live. Re-run after fixing. |
| Connection error                            | The CLI can't reach the AWS Transform backend                                                                                                                                                 | Refresh AWS credentials and confirm `AWS_REGION` matches a supported region; then retry.                                   |
| `AccessDenied` / 403                        | AWS credentials expired or the principal isn't authorized                                                                                                                                     | Refresh credentials, confirm the role's permissions and `AWS_REGION`, then retry.                                          |
| All counts genuinely 0 on first use         | Nothing set up yet                                                                                                                                                                            | Guide them to add a source and run discovery — not an error.                                                               |
