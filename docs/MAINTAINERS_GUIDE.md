# Maintainers Guide

This guide covers workflows, responsibilities, and tooling for repository reviewers, maintainers, and administrators.

## Roles

### Core Teams

| Team                                 | Scope                          | Responsibilities                                             |
| ------------------------------------ | ------------------------------ | ------------------------------------------------------------ |
| `@awslabs/agent-plugins-admins`      | Everything                     | Repo settings, CI/CD, schemas, tooling, CODEOWNERS, releases |
| `@awslabs/agent-plugins-maintainers` | Everything (default reviewers) | PR review, triage, community engagement                      |

Admins own all configuration and infrastructure files explicitly. Both teams are defined in [CODEOWNERS](../.github/CODEOWNERS) on the default `*` pattern.

### Plugin Teams

Each plugin has its own GitHub team that owns its plugin directory. Plugin teams are created with `@awslabs/agent-plugins-writers` as the parent team. Once the parent team accepts the request, the plugin team gains write access to the repository.

**Onboarding a new plugin team:**

1. Create a GitHub team named `agent-plugins-<plugin-name>` (e.g., `agent-plugins-deploy-on-aws`)
2. Set the parent team to `@awslabs/agent-plugins-writers`
3. The contributor adds a CODEOWNERS entry for the plugin directory:

   ```text
   plugins/<plugin-name>     @awslabs/agent-plugins-admins @awslabs/agent-plugins-maintainers  @awslabs/agent-plugins-<plugin-name>
   ```

4. An admin accepts the parent team request

**Current plugin teams:**

| Team                                   | Plugin directory         |
| -------------------------------------- | ------------------------ |
| `@awslabs/agent-plugins-deploy-on-aws` | `plugins/deploy-on-aws/` |

## PR Review Workflow

### Useful Filtered Views

| View                                | Link                                                                                                          |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Open PRs with all checks passing    | [status:success](https://github.com/awslabs/agent-plugins/pulls?q=is%3Apr+is%3Aopen+status%3Asuccess)         |
| Open PRs needing review             | [review:required](https://github.com/awslabs/agent-plugins/pulls?q=is%3Apr+is%3Aopen+review%3Arequired)       |
| Open PRs with failing checks        | [status:failure](https://github.com/awslabs/agent-plugins/pulls?q=is%3Apr+is%3Aopen+status%3Afailure)         |
| PRs blocked from merge              | [label:do-not-merge](https://github.com/awslabs/agent-plugins/pulls?q=is%3Apr+is%3Aopen+label%3Ado-not-merge) |
| Stale PRs                           | [label:stale](https://github.com/awslabs/agent-plugins/pulls?q=is%3Apr+is%3Aopen+label%3Astale)               |
| Backlog PRs (exempt from staleness) | [label:backlog](https://github.com/awslabs/agent-plugins/pulls?q=is%3Apr+is%3Aopen+label%3Abacklog)           |

### Review Criteria

When reviewing a PR, verify:

1. **CI is green** - All required GitHub Actions checks pass (build, lint, security scanners, CodeQL)
2. **PR title** - Follows [conventional commits](https://www.conventionalcommits.org/) format (`fix:`, `feat:`, `chore:`, etc.). Enforced by CI.
3. **Contributor statement** - PR body includes the license contribution acknowledgment. Enforced by CI (exempts `awslabs-mcp` and `dependabot[bot]`).
4. **Design quality** - For plugin changes, use the review checklist in [Design Guidelines](./DESIGN_GUIDELINES.md#review-checklist)
5. **Versioning** - Plugin version changes follow [semantic versioning](https://semver.org/). Breaking changes require a major bump, new features a minor bump, bug fixes a patch bump.
6. **New plugins** - PRs that add a new directory under `plugins/` must also include:
   - A CODEOWNERS entry for the plugin directory (see [Plugin Teams](#plugin-teams))
   - An entry in the marketplace manifest (`.claude-plugin/marketplace.json`)
   - An entry in the plugin listing table in `README.md`
   - The `new-plugin` label on the PR
7. **Security** - No secrets, credentials, or sensitive data in the diff. Security scanners (Bandit, SemGrep, Gitleaks, Checkov, Grype) run in CI.

### Merge Rules

- PRs require passing status checks before merge
- The `do-not-merge` label blocks merging (enforced by the [merge-prevention](../.github/workflows/merge-prevention.yml) workflow)
- The `HALT_MERGES` repository variable can block all merges or allow only a specific PR number:
  - `0` (default) - all merges allowed
  - `-1` - all merges blocked
  - `<PR number>` - only that PR may merge

## Labels

| Label          | Purpose                                |
| -------------- | -------------------------------------- |
| `do-not-merge` | Blocks PR from merging (CI-enforced)   |
| `new-plugin`   | PR adds a new plugin to the repository |
| `backlog`      | Exempts PR/issue from stale automation |
| `stale`        | Auto-applied to inactive PRs/issues    |
| `enhancement`  | Feature request                        |
| `bug`          | Bug report                             |
| `help wanted`  | Good for external contributors         |

## Stale Automation

The [stale workflow](../.github/workflows/stale.yml) runs daily:

| Item          | Stale after      | Closed after       |
| ------------- | ---------------- | ------------------ |
| Pull requests | 14 days inactive | 2 days after stale |
| Issues        | 60 days inactive | 7 days after stale |

Add the `backlog` label to exempt an item from staleness.

## Issue Triage

The repository provides issue templates for:

- **Bug reports** - Structured reproduction steps
- **Feature requests** - Use case and proposed solution
- **Documentation** - Doc improvements or gaps
- **RFCs** - Larger proposals requiring discussion

Triage incoming issues by applying appropriate labels and assigning to the relevant team.

## CI/CD Overview

All workflows are in [`.github/workflows/`](../.github/workflows/):

| Workflow                 | Trigger                    | Purpose                                                           |
| ------------------------ | -------------------------- | ----------------------------------------------------------------- |
| `build.yml`              | PR, push to main           | Full build (`mise run build`: lint + format check + security)     |
| `pull-request-lint.yml`  | PR                         | Conventional commit title validation, contributor statement check |
| `merge-prevention.yml`   | PR, merge queue            | `do-not-merge` label and `HALT_MERGES` enforcement                |
| `security-scanners.yml`  | PR, push to main           | Bandit, SemGrep, Gitleaks, Checkov, Grype                         |
| `codeql.yml`             | PR, push to main, schedule | GitHub CodeQL analysis                                            |
| `dependency-review.yml`  | PR                         | Dependency vulnerability review                                   |
| `scorecard-analysis.yml` | Push to main, schedule     | OpenSSF Scorecard                                                 |
| `stale.yml`              | Daily cron                 | Stale PR/issue management                                         |

## Release Process

Releases follow [semantic versioning](https://semver.org/). Version numbers are tracked in plugin manifests (`plugin.json`).

When preparing a release:

1. Ensure all CI checks pass on `main`
2. Verify plugin manifest versions are updated
3. Run a full build locally: `mise run build`
4. Tag the release following the versioning convention

## Security

- Security vulnerability reports go through [AWS vulnerability reporting](https://aws.amazon.com/security/vulnerability-reporting/), not public GitHub issues
- See [SECURITY.md](../.github/SECURITY.md) for the full policy
- Security scanners run on every PR and push to `main`
- Gitleaks baseline (`.gitleaks-baseline.json`) tracks known false positives - see [Development Guide](./DEVELOPMENT_GUIDE.md#gitleaks---secret-detection) for handling
