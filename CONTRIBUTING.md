# Contributing Guidelines

Thank you for your interest in contributing to Agent Plugins for AWS.

This guide covers everything you need to make your first contribution: how to set up your
environment, how the repository is organized, the conventions we follow, and how to verify your
change before you open a pull request.

## Contents

- [Role Guides](#role-guides)
- [Quick Start](#quick-start)
- [Repository Layout](#repository-layout)
- [RFCs for New Plugins and Major Changes](#rfcs-for-new-plugins-and-major-changes)
- [Reporting Bugs/Feature Requests](#reporting-bugsfeature-requests)
- [Development Workflow](#development-workflow)
- [Build, Lint, and Test Commands](#build-lint-and-test-commands)
- [Adding or Changing a Skill](#adding-or-changing-a-skill)
- [Commit Conventions](#commit-conventions)
- [Contributing via Pull Requests](#contributing-via-pull-requests)
- [Pull Request Requirements](#pull-request-requirements)
- [Finding Contributions to Work On](#finding-contributions-to-work-on)
- [Getting Unstuck](#getting-unstuck)
- [Code of Conduct](#code-of-conduct)
- [Security Issue Notifications](#security-issue-notifications)
- [Licensing](#licensing)

## Role Guides

Depending on your role, please review the appropriate guide for repository-specific instructions:

- [Development Guide](./docs/DEVELOPMENT_GUIDE.md) - For contributors and developers
- [Design Guidelines](./docs/DESIGN_GUIDELINES.md) - Plugin and skill design best practices
- [Maintainers Guide](./docs/MAINTAINERS_GUIDE.md) - For reviewers, maintainers, and admins
- [Administrators Guide](./docs/ADMINISTRATORS_GUIDE.md) - For GitHub repository and AWS account setup
- [Troubleshooting Guide](./docs/TROUBLESHOOTING.md) - Diagnosing plugin and CI problems

**Using Claude Code?** See the [Claude Code Setup](./docs/DEVELOPMENT_GUIDE.md#claude-code-setup) section in the Development Guide for project-specific configuration.

## Quick Start

This project uses [mise](https://mise.jdx.dev) (>= 2026.2.4) to manage tool versions and tasks. You
do not need to install Node, Python, or the security scanners yourself — `mise install` provisions
everything pinned in [`mise.toml`](./mise.toml).

```bash
# 1. Fork the repository on GitHub, then clone your fork
git clone https://github.com/<your-username>/agent-plugins.git
cd agent-plugins

# 2. Install the pinned toolchain (Node, markdownlint, dprint, pre-commit, scanners)
mise install

# 3. Create a branch for your work
git checkout -b my-change

# 4. Make your change, then run the full build before committing
mise run build
```

If `mise` is not yet on your machine, follow the
[mise installation instructions](https://mise.jdx.dev/getting-started.html) first.

## Repository Layout

Knowing where things live makes most contributions straightforward:

| Path                                        | What lives there                                                   |
| :------------------------------------------ | :----------------------------------------------------------------- |
| `plugins/<name>/`                           | One directory per plugin — the bulk of contributions land here     |
| `plugins/<name>/.claude-plugin/plugin.json` | Plugin manifest (name, version, description, keywords)             |
| `plugins/<name>/.mcp.json`                  | MCP server definitions for that plugin                             |
| `plugins/<name>/skills/<skill>/SKILL.md`    | The skill itself, with YAML frontmatter                            |
| `plugins/<name>/skills/<skill>/references/` | Supporting detail extracted out of `SKILL.md`                      |
| `.claude-plugin/marketplace.json`           | Marketplace registry listing every plugin                          |
| `.agents/plugins/marketplace.json`          | Generated Codex marketplace (see below)                            |
| `schemas/`                                  | JSON Schemas that validate the manifests                           |
| `tools/`                                    | Lint, validation, scaffolding, and eval scripts                    |
| `tools/evals/`                              | Eval suites for plugins, kept separate from the plugins themselves |
| `docs/`                                     | Role-specific guides                                               |
| `mise.toml`                                 | Tool versions and every task used locally and in CI                |

Note that `CLAUDE.md` is a symlink to [`AGENTS.md`](./AGENTS.md). Only edit `AGENTS.md`; the change
applies to both automatically.

## RFCs for New Plugins and Major Changes

For **new plugins** or **major changes** to the repository, contributors must first open an [RFC (Request for Comments)](https://github.com/awslabs/agent-plugins/issues) before doing any work. This ensures public visibility and allows maintainers and owners to review the proposal. Once the RFC is approved, you can proceed with your contribution following the steps in [Contributing via Pull Requests](#contributing-via-pull-requests).

Use the **🚧 Request for Comments (RFC)** issue template, which prompts for the summary, use case,
and proposal. Smaller, self-contained fixes and documentation improvements do not need an RFC — open
a regular issue or go straight to a pull request.

## Reporting Bugs/Feature Requests

We welcome you to use the GitHub issue tracker to report bugs or suggest features.

When filing an issue, please check existing open, or recently closed, issues to make sure somebody else hasn't already reported the issue. Please try to include as much information as you can. Details like these are incredibly useful:

- A reproducible test case or series of steps
- The version of our code being used
- Any modifications you've made relevant to the bug
- Anything unusual about your environment or deployment

The repository provides issue templates for bug reports, feature requests, documentation issues, and
RFCs — picking the right one routes your issue to the correct reviewers.

## Development Workflow

1. **Work from the latest `main`.** Fast-forward only; never commit, merge, or rebase `main` locally.

   ```bash
   git pull --ff-only origin main
   ```

2. **Branch for your change.** Keep one logical change per branch so reviews stay small.

3. **Make the change.** Focus on the specific improvement you are contributing and avoid unrelated
   refactoring — it makes review slower and riskier.

4. **Regenerate derived files if you touched manifests.** The Codex marketplace and per-plugin Codex
   manifests are generated from the Claude sources:

   ```bash
   python3 tools/generate_codex_manifests.py
   ```

5. **Format and verify.** Run `mise run fmt` and then `mise run build` (see below). A full build is
   required before you commit, because it generates and validates everything CI will check.

6. **Commit and push**, then open a pull request against `main`.

Optionally, install the pre-commit hooks so formatting and basic checks run automatically:

```bash
mise run pre-commit    # run every hook against all files
```

## Build, Lint, and Test Commands

Always drive the repository through `mise` so you get the same tool versions CI uses. If a command
you need does not exist, add it to `mise.toml` as part of your change.

```bash
mise run build            # Full build: lint + fmt:check + validate + test + security
```

`mise run build` is the gate to clear before committing. It is composed of smaller tasks you can run
individually while iterating:

| Command                    | What it does                                                            |
| :------------------------- | :---------------------------------------------------------------------- |
| `mise run fmt`             | Format all files with dprint                                            |
| `mise run fmt:check`       | Check formatting without writing (what CI runs)                         |
| `mise run lint:md`         | Lint Markdown, including `SKILL.md` frontmatter and length rules        |
| `mise run lint:md:fix`     | Lint Markdown with auto-fix                                             |
| `mise run lint:manifests`  | Validate JSON manifests against the schemas in `schemas/`               |
| `mise run lint:cross-refs` | Validate cross-references between marketplace and plugin manifests      |
| `mise run lint`            | All linters                                                             |
| `mise run validate:refs`   | Detect broken links and orphaned reference files                        |
| `mise run validate:size`   | Check `SKILL.md` sizes and flag extraction candidates                   |
| `mise run validate:urls`   | Check HTTPS URLs return 200 (network-dependent; not part of the build)  |
| `mise run validate`        | All validation checks                                                   |
| `mise run test`            | Unit tests (pytest for Python, npm when a `package.json` defines tests) |
| `mise run security`        | Bandit, Semgrep, Gitleaks, Checkov, Grype, and zizmor scans             |
| `mise run init:skill`      | Scaffold a new skill directory from the standard template               |

See `mise.toml` for the complete task list and pinned tool versions.

### Notes on specific checks

- **Formatting** is owned by dprint (`lineWidth` 100, LF newlines, 2-space indent). Markdown line
  length linting is intentionally disabled, so let dprint settle formatting rather than hand-wrapping.
- **Markdown linting** uses ATX headings, fenced code blocks with backticks, and two custom rules
  that validate `SKILL.md` frontmatter and length.
- **Secret scanning** uses Gitleaks. If it reports a genuine false positive (for example an example
  key in documentation), follow the baseline process in the
  [Development Guide](./docs/DEVELOPMENT_GUIDE.md#gitleaks---secret-detection) rather than deleting
  the check.
- **`mise run security`** downloads vulnerability databases and rulesets, so it is the slowest part
  of the build. Running the narrower `security:*` tasks is useful while iterating.

## Adding or Changing a Skill

Skills are the heart of this repository, and they are **not** slash commands. The agent decides when
to use a skill by matching user intent against the `description` field in the skill's YAML
frontmatter, so that description is the most important line you will write.

To add a skill, scaffold it rather than copying by hand:

```bash
mise run init:skill
```

Then keep these expectations in mind:

- Write the `description` so it reads like the situations a user would describe in their own words.
- Keep `SKILL.md` focused; move depth into `references/` files. `mise run validate:size` flags files
  that have grown past the point where content should be extracted.
- Link every reference file from `SKILL.md`. `mise run validate:refs` fails on broken links and warns
  about orphaned reference files.
- If you add, rename, or re-version a plugin, update `.claude-plugin/marketplace.json` and the
  plugin's `plugin.json`, then regenerate the Codex manifests.
- Eval suites live under `tools/evals/`, separate from the plugins themselves.

[Design Guidelines](./docs/DESIGN_GUIDELINES.md) covers skill authoring, anti-patterns, MCP server
integration, versioning, and the full review checklist in depth. Read it before proposing a new
plugin.

## Commit Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/). A scope naming the affected area is
strongly preferred, because it makes history and release notes readable:

```text
<type>(<scope>): <short description>
```

Allowed types (enforced on pull request titles by CI) are `fix`, `feat`, `build`, `chore`, `ci`,
`docs`, `style`, `refactor`, `perf`, and `test`. The scope is usually a plugin or skill name, or an
area such as `ci`, `build`, `security`, or `docs`. Examples drawn from this repository's history:

```text
feat(elastic-beanstalk): add Beanstalk Cluster mode
fix(dsql): correct partial index, expression index, and function support
docs(dsql): update SELECT FOR UPDATE guidance and evals
ci(security): bump sonarqube-scan-action to v8.2.0 (Node 24)
```

## Contributing via Pull Requests

Contributions via pull requests are much appreciated. Before sending us a pull request, please ensure that:

1. You are working against the latest source on the _main_ branch.
2. You check existing open, and recently merged, pull requests to make sure someone else hasn't addressed the problem already.
3. You open an issue to discuss any significant work - we would hate for your time to be wasted.

To send us a pull request, please:

1. Fork the repository.
2. Modify the source; please focus on the specific change you are contributing.
3. Ensure local tests pass.
4. Commit to your fork using clear commit messages.
5. Send us a pull request, answering any default questions in the pull request interface.
6. Pay attention to any automated CI failures reported in the pull request, and stay involved in the conversation.

GitHub provides additional documentation on [forking a repository](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo) and [creating a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request).

## Pull Request Requirements

Two checks commonly surprise first-time contributors, so it is worth calling them out:

1. **The title must be a valid Conventional Commit.** CI validates the pull request title against the
   allowed types listed in [Commit Conventions](#commit-conventions).

2. **The body must contain the contributor statement** exactly as it appears in the
   [pull request template](./.github/pull_request_template.md):

   > By submitting this pull request, I confirm that you can use, modify, copy, and redistribute this contribution, under the terms of the [project license](https://github.com/awslabs/agent-plugins/blob/main/LICENSE).

   The template includes it already, so the simplest path is to fill the template in rather than
   replacing it. If you use Claude Code, the project-level `attribution.pr` setting appends this
   statement automatically — see the
   [Development Guide](./docs/DEVELOPMENT_GUIDE.md#pr-contributor-statement).

Beyond that: fill in the **Related** and **Changes** sections of the template, keep the pull request
scoped to one logical change, and stay engaged with review feedback. Files are owned via
[`.github/CODEOWNERS`](./.github/CODEOWNERS), so the right reviewers are requested automatically.
Maintainers may apply a `do-not-merge` label while a discussion is unresolved; the
[Maintainers Guide](./docs/MAINTAINERS_GUIDE.md) describes the review workflow from their side.

## Finding Contributions to Work On

Looking at the existing issues is a great way to find something to contribute on. As our projects, by default, use the default GitHub issue labels (enhancement/bug/duplicate/help wanted/invalid/question/wontfix), looking at any 'help wanted' issues is a great place to start.

## Getting Unstuck

- Plugin not loading, skill not triggering, or CI failing in a way you do not recognize? Start with
  the [Troubleshooting Guide](./docs/TROUBLESHOOTING.md).
- Unsure whether your idea needs an RFC? Open a regular issue and ask — it is cheaper than guessing.
- Build failing only on `mise run security`? Check whether the finding is pre-existing on `main`
  before changing your code.

## Code of Conduct

This project has adopted the [Amazon Open Source Code of Conduct](https://aws.github.io/code-of-conduct). For more information see the [Code of Conduct FAQ](https://aws.github.io/code-of-conduct-faq) or contact opensource-codeofconduct@amazon.com with any additional questions or comments.

## Security Issue Notifications

If you discover a potential security issue in this project we ask that you notify AWS/Amazon Security via our [vulnerability reporting page](https://aws.amazon.com/security/vulnerability-reporting/). Please do **not** create a public GitHub issue.

## Licensing

See the [LICENSE](LICENSE) file for our project's licensing. We will ask you to confirm the licensing of your contribution.
