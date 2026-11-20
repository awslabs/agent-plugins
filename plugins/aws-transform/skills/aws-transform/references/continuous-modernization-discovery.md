---
name: discovery
description: Scan/discover repositories from GitHub orgs/users, GitLab groups/users, Bitbucket workspaces/projects, or local folders. Lists repos with language and default branch.
---

# Discovery

## Local sources: path is set at `source add` time

For local sources, the directory path is provided when the source is first added (`atx ct source add --provider local --name <name> --path <dir>`). It's stored on the source and reused automatically by subsequent `discovery scan --source <name>` calls — no `--path` needed at scan time.

**Prerequisite:** The source must have been added with `--path` first. If `discovery scan` errors with `Source "<name>" has no rootPath configured`, this machine doesn't have a local rootPath yet for that source (typically because the source was originally added on another machine — `rootPath` is machine-specific). Resolve by passing `--path <dir>` to the scan command (which sets and stores the rootPath locally), OR by running `atx ct source add --provider local --name <name> --path <dir>` on this machine.

**Override:** Pass `--path <new-dir>` to `discovery scan` ONLY when you want to overwrite the stored path. This silently changes the source's `rootPath`. Confirm with the user before passing `--path` to a previously-registered local source.

**Path must be a parent directory:** The path (whether at `source add` or `discovery scan`) must point to a directory that _contains_ repos as subdirectories — not to a repo itself. Every non-hidden subdirectory is registered as one repo, even one without its own `.git` (the scan warns, and a fresh git repo is initialized on first remediation). Hidden directories are skipped unless they contain `.git`, and bare git repos are skipped. If the path points directly at a single repo, its subfolders (`src`, `docs`, …) are registered as separate repos — point the source at the parent (e.g. `/home/user/repos`, not `/home/user/repos/my-app`) and remove the wrong entries with `atx ct repository delete`. A scan of a folder with no subdirectories finds 0 repos.

**Moved or deleted folders:** A repo registered earlier whose folder no longer exists is kept (with its findings and history) and shown as `(folder missing)` with a warning; its analyses and remediations will fail until the folder is restored or the repo is removed with `atx ct repository delete`.

## Commands

```bash
# Scan a local source (path was set at `source add` time and is reused automatically)
atx ct discovery scan --source <name>

# Override the stored rootPath (overwrites the source's path -- confirm with user first)
atx ct discovery scan --source <name> --path <new-dir>

# Local source only: register just one repo directory instead of every subdirectory
atx ct discovery scan --source <name> --repo <dir-name>

# Scan a GitHub, GitLab, or Bitbucket source (use the bare name from `source add --name`)
atx ct discovery scan --source <name>

# Machine-readable scan result
atx ct discovery scan --source <name> --json

# List the repos a scan registered
atx ct repository list --source <name> --json
```

A scan prints `Found N repos` plus any warnings. If some repositories could not be registered it also prints `N repositories were skipped and not registered` — report that count and the warnings to the user; do not present the scan as complete.

**GitHub rate limits:** A GitHub scan that hits the API rate limit waits for the reset and continues. `ATXCT_GITHUB_RATE_LIMIT_MAX_WAIT_SECONDS` caps a single wait (default 3900 seconds, 65 minutes); past it, or set to `0`, the scan stops and prints the reset time. Re-running a stopped scan continues where it stopped if the scan first started less than a day ago.

**Hosted source added on another machine:** If the scan fails with `Source "<name>" exists in this account but credentials are not configured on this machine`, the token lives only on the machine that added the source. Have the user store it on this machine with the `read -s` one-liner for `atx ct source update --name <name> --token "$TOKEN"` (see the `/source` skill), then re-run the scan.

## After discovery completes

When discovery finds many repos, offer to label a group of repos for targeted analysis: "Want to label a group of repos to focus your analysis? For example, you can label repos by team, priority, or migration wave, then run analysis on just that group." Use the `/source` skill's repository commands to apply labels. This is optional — skip if the user wants to analyze everything.
