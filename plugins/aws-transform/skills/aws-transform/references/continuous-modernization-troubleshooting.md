---
name: troubleshooting
description: Consolidated actionable-error reference for AWS Transform continuous modernization. Every common failure mode with what went wrong and the exact next step. Other CM skills link here.
---

# Troubleshooting — Actionable Errors

This is the single reference for the common failure modes of continuous
modernization. **Rule: never surface a bare error and never present an empty
result as success.** For every failure, tell the user (1) what went wrong and
(2) the exact next step. When a command returns nothing, first decide whether it
is genuinely empty or actually a failure (see "Empty results are not success"),
then respond accordingly.

## Fast triage — match the symptom

| Symptom the user sees                                                     | Most likely cause                                                                                                           | What to tell the user + next step                                                                                                                                                                                                  |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `command not found: atx` / `atx: not found`                               | The AWS Transform CLI (`atx`) is not installed or not on PATH                                                               | "The `atx` CLI isn't installed (or isn't on your PATH)." Install it (see the `setup` skill), reopen the shell, and verify with `atx --version`.                                                                                    |
| `atx ct` reports `unknown command 'ct'`                                   | The shell ran an `atx` that lacks the continuous-modernization commands (local resolution, NOT a credential/region problem) | See "`atx ct` reports `unknown command 'ct'`" below — inspect `type -a atx` and pick the smallest PATH correction.                                                                                                                 |
| `atx` runs but behaves oddly / wrong version                              | A different binary named `atx` is shadowing the real one on PATH                                                            | Run `which -a atx` to list all matches. The real AWS Transform CLI must come first; remove or reorder the shadowing entry, then re-verify with `atx --version`.                                                                    |
| Connection error / `ECONNREFUSED` / "Is the server running?"              | The CLI can't reach the AWS Transform backend                                                                               | Refresh AWS credentials and confirm `AWS_REGION` matches a supported region; then retry.                                                                                                                                           |
| `AccessDenied` / `UnauthorizedException` / 403                            | AWS credentials expired, or the IAM principal lacks permission, or wrong region                                             | "Your AWS credentials look invalid, expired, or unauthorized." Refresh them, confirm the calling role has access, and confirm `AWS_REGION` is a supported region. Then retry.                                                      |
| `401` from GitHub/GitLab/Bitbucket                                        | Provider token missing, invalid, or expired                                                                                 | "The provider rejected your token." Re-add the source with a valid PAT: `atx ct source add --name <name> --provider <p> --org <org> --token <PAT>`. The PAT needs the `repo` scope; for SSO orgs, authorize the token for the org. |
| `discovery scan` reports **0 repos**                                      | `--path` points at a repo instead of its parent, wrong org/identifier, or an empty source                                   | "Found 0 repositories under `<source>`." Check the org/identifier is correct; for `--provider local`, `--path` must be the **parent** directory that _contains_ Git repos, not a repo itself.                                      |
| Analysis / findings list is **empty** but shouldn't be                    | Wrong `AWS_REGION` (resources are region-scoped), analysis not run yet, or a read that silently failed                      | "No results found." Confirm `AWS_REGION` matches where your resources live, that an analysis has completed (`atx ct analysis list`), and re-run the read. If a read errored, surface the error — do not report "0".                |
| Security analysis shows **COMPLETED with 0 findings** after an error line | Findings could not be retrieved from the Security Agent                                                                     | This is **not** a clean result. Retry the analysis; if it persists, verify AWS credentials/region and Security Agent access (`atx ct setup security-agent`).                                                                       |
| `error: required option '--type <type>' not specified`                    | A required flag is missing or was transposed                                                                                | Run the command with `--help` to see valid options and values. Note `--type` takes a value, e.g. `--type tech-debt-comprehensive`; don't pass the type as a bare flag like `--rapid-techdebt-analysis`.                            |
| `error: unknown option '--xyz'` with `(Did you mean ...?)`                | A misspelled or wrong flag                                                                                                  | Use the suggested flag, or run the command with `--help` for the full list.                                                                                                                                                        |
| 5xx / `InternalServerException` / throttling                              | Transient backend/infra issue                                                                                               | "The service hit a transient error." Retry shortly; if it persists, capture the Request ID from the message and contact support.                                                                                                   |
| Write to `~/.atxct` fails ("File access is restricted…")                  | Workspace folder access restriction                                                                                         | See "Error writing files to the `~/.atxct` folder" below — find another way to read/write it; there is no alternative location.                                                                                                    |

## Empty results are not success

A command that returns `0 repos`, `0 findings`, or an empty list can mean either
"genuinely nothing" **or** "an underlying call failed." Never present the second
as the first. Before saying "nothing found":

1. **Check credentials** — a plain `atx ct findings list` / `analysis list` /
   `status` can return empty if AWS credentials expired. If unsure, run
   `aws sts get-caller-identity`; if it fails, refresh credentials and retry.
2. **Check region** — resources are region-scoped. Empty results with valid
   credentials often mean `AWS_REGION` doesn't match where the resources live.
3. **Check reachability** — a connection error mid-read can look like empty
   output. Run a real read such as `atx ct analysis list --json` and branch on the
   error: an auth error → refresh AWS credentials; a
   region mismatch → set `AWS_REGION`; a genuinely empty list → treat as empty.
4. **Then, and only then**, report a genuine empty state — with the specific
   thing to check (org name, `--path` parent directory, whether an analysis has
   run yet).

The CLI itself now distinguishes these: `atx ct status` prints
`unavailable (read failed …)` instead of `0` when a sub-query fails, and
`discovery scan` raises a real auth/infra error instead of silently returning 0
repos. Mirror that behavior in what you tell the user.

## `atx ct` reports `unknown command 'ct'`

This means the shell found and ran an executable named `atx`, but the selected executable does not provide the continuous-modernization commands. Treat it as local command resolution, not an AWS credential or region problem.

Inspect what the shell selected and which alternatives are available:

```bash
command -v atx
type -a atx
atx --version
```

If multiple candidates are listed, test paths returned by `type -a atx` directly with `<discovered-path> ct --version`. Do not assume a fixed installation path, reinstall immediately, or modify PATH automatically. Use the evidence to explain which executable won resolution and which candidate, if any, provides `ct`; then guide the user through the smallest appropriate correction for their shell. After a PATH change, start a new shell or clear its command cache (`hash -r` for Bash, `rehash` for Zsh), then retry plain `atx ct --version`. Install the AWS Transform CLI only if no discovered candidate provides `ct`.

## Error writing files to the `~/.atxct` folder

If attempting to read or write files to the user's `~/.atxct` folder fails due to an error similar to "File access is restricted to the open workspace folders", write a script or find another way to read/write to this directory -- there is no substitute/alternative location for files in `~/.atxct` so be sure to find a way to do it.

## Prerequisites checklist (run when anything fails unexpectedly)

- `atx --version` — the CLI is installed and on PATH.
- `atx ct analysis list --json` — the CLI can reach the backend (an auth/region error here points at credentials or `AWS_REGION`, not an empty result).
- `aws sts get-caller-identity` — AWS credentials are present and valid.
- `echo $AWS_REGION` — set, and matches where your resources live.
- For a provider source: the PAT is valid and has the `repo` scope (SSO-authorized if required).
