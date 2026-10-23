---
name: source
description: Add/list/remove source connections (GitHub org, GitLab group/user, Bitbucket workspace, local folder). List, get, update, and delete repos under sources. Filter and label groups of repos for targeted analysis.
---

# Source

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
# Add a GitHub org (optional: --tags key=value,key2=value2)
# The GitHub PAT requires the `repo` scope (classic token), or for fine-grained tokens: Read access to metadata (default), Read and Write access to code and pull requests.
read -s TOKEN && atx ct source add --name <name> --provider github --org <org> --token "$TOKEN" [--tags key=value,key2=value2]; unset TOKEN

# Add a GitLab group or user (gitlab.com)
# The GitLab PAT requires the `api` scope.
read -s TOKEN && atx ct source add --name <name> --provider gitlab --org <group-or-username> --token "$TOKEN" [--tags key=value,key2=value2]; unset TOKEN

# Add a GitLab group or user (self-hosted)
# The GitLab PAT requires the `api` scope.
read -s TOKEN && atx ct source add --name <name> --provider gitlab --org <group-or-username> --token "$TOKEN" --url https://gitlab.example.com [--tags key=value,key2=value2]; unset TOKEN

# Add a Bitbucket workspace (Cloud -- API token with scopes)
# The Bitbucket PAT requires scopes: read:repository:bitbucket, read:account, write:repository:bitbucket, read:pullrequest:bitbucket, write:pullrequest:bitbucket
read -s TOKEN && atx ct source add --name <name> --provider bitbucket --org <workspace> --token "$TOKEN" --email <bitbucket-email> --username <bitbucket-username> [--tags key=value,key2=value2]; unset TOKEN

# Add a Bitbucket project (Data Center / self-hosted)
# The Bitbucket PAT requires scopes: read:repository:bitbucket, read:account, write:repository:bitbucket, read:pullrequest:bitbucket, write:pullrequest:bitbucket
read -s TOKEN && atx ct source add --name <name> --provider bitbucket --org <project-key> --token "$TOKEN" --url https://bitbucket.example.com [--tags key=value,key2=value2]; unset TOKEN
```

Add a local folder source (no token required):

```bash
atx ct source add --name <name> --provider local --path <dir> [--tags key=value,key2=value2]
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

## Pagination (nextToken)

Depending on the CLI version, `atx ct source list` and `atx ct repository list` may return only a bounded page — don't assume a fixed response shape. After each call, if the response carries a non-empty `nextToken`, call the command again with `--next-token <token>` (keeping any `--source`/`--labels` filters) and repeat until no `nextToken` remains. Don't treat the first page as the complete set — otherwise sources or repos silently go missing from listings and downstream scoping.

## Labels

**Labels ≠ Tags.** Labels are for client-side repo grouping/filtering. Tags (`--tags`) are IAM resource tags for access control (ABAC). When the user says "tag" in the context of access, isolation, teams, or multi-tenancy, use `--tags key=value` on the create command. When they say "label" or want to filter/organize repos for targeted analysis, use labels via `repository update --labels`.

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

## Tags (resource tagging for access control)

The `--tags` flag attaches IAM resource tags to a source at creation time. Tags enable tag-based access control (ABAC) — scoped IAM policies can restrict which teams see or modify which resources.

```bash
# Add a source with tags (comma-separated key=value pairs)
read -s TOKEN && atx ct source add --name <name> --provider github --org <org> --token "$TOKEN" --tags team=alpha,env=prod; unset TOKEN
```

**Behavior:**

- `--tags key=value,key2=value2` accepts comma-separated pairs in a single flag (e.g. `--tags team=alpha,env=prod`).
- Tags are optional. If omitted, the source is untagged (visible to all roles, no isolation).
- Tags are registered with the backend at creation time (tag-on-create). They cannot be modified via `source add` after creation.
- If `~/.aws/atx/settings.json` defines `applyTags`, those defaults are applied automatically on every create even without explicit `--tags`. An explicit `--tags` override is merged **per key** with the settings defaults: an overridden key takes the `--tags` value, non-overridden default keys are retained, and new keys are added.

**Settings file (`~/.aws/atx/settings.json`):**

```json
{
  "applyTags": [
    { "team": "alpha", "env": "prod" }
  ]
}
```

`applyTags` is an **array of tag maps** (not a single object). Every map in the array is applied on each create operation (`source add`, `analysis run`, `remediation create`) without requiring `--tags` on each command. This keeps tags consistent across the workflow.

- **Multiple maps are legal** and are merged left-to-right into one effective tag set. On a duplicate key across maps, the **last map wins** (it is not an error). For example, `[{ "team": "alpha" }, { "team": "beta", "env": "prod" }]` resolves to `{ "team": "beta", "env": "prod" }`.
- An empty array (`[]`), a missing `applyTags` key, or a missing file all resolve to no default tags (no error).
- The merged result must satisfy AWS tag limits (≤ 50 tags; key 1–128 chars; value 0–256 chars), or the CLI aborts with `INVALID_INPUT` (400).

**Malformed settings:** If the file exists but contains invalid JSON, or `applyTags` is structurally invalid (root not a JSON object, `applyTags` not an array, an element that is not an object, or a non-string tag value), the CLI aborts with `SETTINGS_ERROR` (422) identifying the file path and the parse or schema error. If the file is missing, no tags are applied (no error).
