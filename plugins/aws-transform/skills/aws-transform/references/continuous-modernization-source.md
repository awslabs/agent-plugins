---
name: source
description: Add/list/remove source connections (GitHub org, GitLab group/user, Bitbucket workspace, local folder). List, get, update, and delete repos under sources. Filter and label groups of repos for targeted analysis.
---

# Source

## Prerequisites

Check if the server is running with `atx ct status --health`. If any command fails with a connection error, use the `server` skill to start the server.

## Token handling

**Never ask the user to paste or type a token into this chat.** Tokens entered into the chat are visible in the conversation transcript.

When a source requires a token, give the user the exact one-liner to run in their own terminal — fill in the placeholders, then say: "Run this in your terminal, then tell me when it's done."

`read -s` prompts silently in the terminal — the token is pasted directly into the terminal (not into this chat), nothing echoes, and the value is never captured in shell history. `unset TOKEN` clears it from the shell immediately after.

After the user says "done", run `atx ct source list --json` to verify the source was added. If it appears, continue. If not, ask the user to retry.

## Commands

Supported provider types: `github`, `gitlab`, `bitbucket`, `local`

Before adding a source, run `atx ct source list --json` to check whether it already exists. If it does, use `source update` to update the token instead of `source add`.

When adding a source, the agent should inform the customer what PAT scopes are needed and why:

"Your personal access token requires read access to list and scan your repositories for modernization findings, write access to push remediation branches, and pull request (or merge request) creation permissions to deliver the automated fixes for your review."

Then show the specific scopes for their provider:

- **GitHub:**
  - Classic token: `repo` scope
  - Fine-grained token: Read access to metadata (default), Read and Write access to code and pull requests
- **GitLab:** `api` scope (covers project listing, merge request creation, and git push over HTTPS).
- **Bitbucket:** `read:repository:bitbucket`, `read:account`, `write:repository:bitbucket`, `read:pullrequest:bitbucket`, `write:pullrequest:bitbucket`.

```bash
# Add a GitHub org
# The GitHub PAT requires the `repo` scope (classic token), or for fine-grained tokens: Read access to metadata (default), Read and Write access to code and pull requests.
read -s TOKEN && atx ct source add --name <name> --provider github --org <org> --token "$TOKEN"; unset TOKEN

# Add a GitLab group or user (gitlab.com)
# The GitLab PAT requires the `api` scope.
read -s TOKEN && atx ct source add --name <name> --provider gitlab --org <group-or-username> --token "$TOKEN"; unset TOKEN

# Add a GitLab group or user (self-hosted)
# The GitLab PAT requires the `api` scope.
read -s TOKEN && atx ct source add --name <name> --provider gitlab --org <group-or-username> --token "$TOKEN" --url https://gitlab.example.com; unset TOKEN

# Add a Bitbucket workspace (Cloud -- API token with scopes)
# The Bitbucket PAT requires scopes: read:repository:bitbucket, read:account, write:repository:bitbucket, read:pullrequest:bitbucket, write:pullrequest:bitbucket
read -s TOKEN && atx ct source add --name <name> --provider bitbucket --org <workspace> --token "$TOKEN" --email <bitbucket-email> --username <bitbucket-username>; unset TOKEN

# Add a Bitbucket project (Data Center / self-hosted)
# The Bitbucket PAT requires scopes: read:repository:bitbucket, read:account, write:repository:bitbucket, read:pullrequest:bitbucket, write:pullrequest:bitbucket
read -s TOKEN && atx ct source add --name <name> --provider bitbucket --org <project-key> --token "$TOKEN" --url https://bitbucket.example.com; unset TOKEN
```

Add a local folder source (no token required):

```bash
atx ct source add --name <name> --provider local --path <dir>
```

Update token on an existing source (use instead of source add when the source already exists):

```bash
read -s TOKEN && atx ct source update --name <name> --token "$TOKEN"; unset TOKEN
```

```bash
# List sources
atx ct source list

# Remove
atx ct source remove --name <name>
```

After adding a source, run `atx ct discovery scan --source <name>` to discover repos. See [continuous-modernization-discovery](continuous-modernization-discovery.md). Local sources also require `--path` at scan time.

## Provider details

- **github**: Scans a GitHub organization or user for repositories. Requires a PAT or GitHub App. During remediation, pushes a branch and creates a Pull Request automatically — this includes **security** remediation, where the Security Agent's diff is applied and opened as a PR (`pr_open`). GitHub is the only provider that gets an auto-opened PR from a security diff; gitlab/bitbucket/local stay diff-only.
- **gitlab**: Scans a GitLab group or user for projects. Requires a PAT with `api` scope. Supports self-hosted instances via `--url` (required for self-hosted; omit for gitlab.com). During remediation, pushes a branch and creates a Merge Request automatically. If `--org` is a user (not a group), falls back to listing the user's projects.
- **bitbucket**: Scans a Bitbucket workspace (Cloud) or project (Data Center) for repositories. Cloud requires an API token with scopes (created at https://id.atlassian.com/manage-profile/security/api-tokens → "Create API token with scopes"). Required scopes: `read:repository:bitbucket`, `write:repository:bitbucket`, `read:pullrequest:bitbucket`, `write:pullrequest:bitbucket`. Also requires `--email` (Bitbucket account email, for API auth) and `--username` (Bitbucket username, for git clone/push). Data Center requires an HTTP Access Token and `--url`. During remediation, pushes a branch and creates a Pull Request automatically.
- **local**: Scans a local directory for packages. The directory path is provided at `source add` time via `--path` and stored on the source. Subsequent `discovery scan --source <name>` calls reuse the stored path automatically; pass `--path <new-dir>` only to override and update the source's stored path. Supports analysis and remediation (remediation leaves changes on a new `atx/<transform>-<timestamp>` branch per run — previous branches are never overwritten, no remote push). **Important:** `--path` must point to a parent directory that _contains_ git repos as subdirectories — not to a repo itself. The scanner looks for child directories with `.git` inside them. If `--path` points directly to a repo (e.g. `/home/user/my-app` which has `.git`), the scan returns 0 repos. Use the parent instead (e.g. `/home/user/repos` which contains `my-app/`, `my-service/`, etc.).

## Repository Commands

```bash
# List all repos (shows slug, language, workflow status, labels)
atx ct repository list

# Filter by source
atx ct repository list --source <name>

# Filter by labels (AND-semantics: all specified labels must be present)
atx ct repository list --labels "team:frontend,priority:high"

# Get a single repo
atx ct repository get --repo "<source>::<slug>" --source <source>

# Set labels on a single repo (replace semantics)
atx ct repository update --source <source> --repo "<source>::<slug>" --labels "team:frontend,priority:high"

# Clear all labels from a single repo
atx ct repository update --source <source> --repo "<source>::<slug>" --labels ""

# Bulk update labels (set-union: merges with existing labels)
atx ct repository update --source <source> --repo "<slug1>,<slug2>" --labels "migration:v2"

# Bulk update all repos under a source (set-union)
atx ct repository update --source <source> --labels "migration:v2"

# Delete a repo
atx ct repository delete --repo "<source>::<slug>" --source <source>
```

## Labels

Labels are user-defined identifiers for organizing and filtering groups of repositories.

**Format:** Unicode letters, digits, `_./:-`. Max 63 chars per label, max 64 per repo. Colons are conventional for key:value grouping (e.g. `team:frontend`, `priority:high`).

**Semantics:**

- `repository list --labels`: AND-filter (only repos with ALL specified labels are returned).
- `repository update` single repo: replace (new labels fully replace existing).
- `repository update` bulk (multiple repos or `--source` only): set-union (new labels merge with existing). Clearing is not supported in bulk mode.

**Validation:** Invalid labels (bad characters, too long, duplicates, >64 count) return an error identifying the offending label and constraint.

## Workflow: Label repos after adding a source for targeted analysis

After adding a source and discovering repos, label a subset to scope analysis or remediation to just those repos:

```bash
# 1. Add source and discover repos
read -s TOKEN && atx ct source add --name my-org --provider github --org acme-corp --token "$TOKEN"; unset TOKEN
atx ct discovery scan --source my-org

# 2. Label the repos you want to analyze together
atx ct repository update --source my-org --repo "my-org::service-a,my-org::service-b" --labels "batch:java-upgrade"

# 3. Verify the label took
atx ct repository list --labels "batch:java-upgrade"

# 4. Use the label to scope analysis or remediation to just that group
```

This lets customers organize large orgs into manageable groups (by team, priority, migration wave, etc.) without creating separate sources.
