---
name: discovery
description: Scan/discover repositories from GitHub orgs, GitLab group/user, or local folders. Lists repos with language, branch, and workflow info.
---

# Discovery

## Prerequisites

Check if the server is running with `atx ct status --health`. If any command fails with a connection error, use the `server` skill to start the server.

## Local sources: path is set at `source add` time

For local sources, the directory path is provided when the source is first added (`atx ct source add --provider local --name <name> --path <dir>`). It's stored on the source and reused automatically by subsequent `discovery scan --source <name>` calls — no `--path` needed at scan time.

**Prerequisite:** The source must have been added with `--path` first. If `discovery scan` errors with `Source "<name>" has no rootPath configured`, this machine doesn't have a local rootPath yet for that source (typically because the source was originally added on another machine — `rootPath` is machine-specific). Resolve by running `atx ct source add --provider local --name <name> --path <dir>` on this machine, OR by passing `--path <dir>` to the scan command (which will set and store the rootPath locally).

**Override:** Pass `--path <new-dir>` to `discovery scan` ONLY when you want to overwrite the stored path. This silently changes the source's `rootPath`. Confirm with the user before passing `--path` to a previously-registered local source.

**Path must be a parent directory:** The path (whether at `source add` or `discovery scan`) must point to a directory that _contains_ git repos as subdirectories — not to a repo itself. The scanner looks for child directories with `.git`. If the path points directly at a single repo, the scan returns 0 repos silently. If a user reports 0 repos found, verify their path points to the parent (e.g. `/home/user/repos`) not a repo directly (e.g. `/home/user/repos/my-app`).

## Commands

```bash
# Scan a local source (path was set at `source add` time and is reused automatically)
atx ct discovery scan --source <name>

# Override the stored rootPath (overwrites the source's path -- confirm with user first)
atx ct discovery scan --source <name> --path <new-dir>

# Scan a GitHub source (use the bare name from `source add --name`)
atx ct discovery scan --source <name>

# Check scan status
atx ct discovery status --source <name>
```

## After discovery completes

When discovery finds many repos, offer to label a group of repos for targeted analysis: "Want to label a group of repos to focus your analysis? For example, you can label repos by team, priority, or migration wave, then run analysis on just that group." Use the `/source` skill's repository commands to apply labels. This is optional — skip if the user wants to analyze everything.
