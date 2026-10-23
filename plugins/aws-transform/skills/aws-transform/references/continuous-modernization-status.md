---
name: status
description: Show AWS Transform - continuous modernization (continuous modernization) system overview — source count, repo count, analysis results, finding totals, remediation progress.
---

# Status

## Commands

```bash
atx ct status [--source <name>]
```

## Errors & empty results

`status` is often the first command a returning user runs, so treat its failures
as onboarding-critical. Never present a failed read as a clean dashboard of
zeros — see the `troubleshooting` skill for the full reference.

| What you see                                | What it means                                                        | What to tell the user                                                                                                      |
| ------------------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| A count shows `unavailable (read failed …)` | That sub-query (repos or findings) failed — it is **not** actually 0 | Surface the warning: credentials may have expired or `AWS_REGION` may not match where resources live. Re-run after fixing. |
| Connection error                            | The CLI can't reach the AWS Transform backend                        | Refresh AWS credentials and confirm `AWS_REGION` matches a supported region; then retry.                                   |
| `AccessDenied` / 403                        | AWS credentials expired or the principal isn't authorized            | Refresh credentials, confirm the role's permissions and `AWS_REGION`, then retry.                                          |
| All counts genuinely 0 on first use         | Nothing set up yet                                                   | Guide them to add a source and run discovery — not an error.                                                               |
