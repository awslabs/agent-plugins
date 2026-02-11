# Agent Plugins for AWS

## TL;DR Pitch

This repository supports **plugins** - bundles of skills, MCP servers, and agent configurations that extend capabilities. This repo is the MVP: `awslabs/agent-plugins` marketplace with a single plugin (`deploy-on-aws`) that lets any developer say "deploy this to AWS" and get architecture recommendations, cost estimates, and working IaC.

## Core Concepts

### Plugins vs Skills vs MCP Servers

| Concept         | What It Is                                                                         | Example                                   |
| --------------- | ---------------------------------------------------------------------------------- | ----------------------------------------- |
| **Plugin**      | A distributable bundle (skills + MCP servers + agents)                             | `deploy-on-aws`                           |
| **Skill**       | Instructions that auto-trigger based on user intent (YAML frontmatter description) | "deploy to AWS" triggers the deploy skill |
| **MCP Server**  | External tool integration via Model Context Protocol                               | `awspricing` for cost estimates           |
| **Marketplace** | Registry of plugins users can install                                              | `awslabs/agent-plugins`                   |

### Key Design Decision: Skills Auto-Trigger

Skills are **NOT** slash commands. The agent determines when to use a skill based on the `description` field in YAML frontmatter. If user says "host this on AWS", the agent matches that intent to the deploy skill's description and invokes it.

## Directory Structure

```
agent-plugins/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace registry
├── .github/
│   ├── workflows/                # CI (build, lint, security, etc.)
│   ├── ISSUE_TEMPLATE/
│   └── ...
├── docs/                         # Role-specific guides
│   ├── DESIGN_GUIDELINES.md      # Plugin design best practices
│   ├── DEVELOPMENT_GUIDE.md      # Contributor setup and workflow
│   ├── MAINTAINERS_GUIDE.md      # Reviewer/maintainer processes
│   └── TROUBLESHOOTING.md        # Plugin troubleshooting
├── plugins/
│   └── deploy-on-aws/
│       ├── .claude-plugin/
│       │   └── plugin.json       # Plugin manifest
│       ├── .mcp.json             # MCP server definitions
│       └── skills/
│           └── deploy/
│               ├── SKILL.md     # Main skill (auto-triggers)
│               └── references/
│                   ├── defaults.md
│                   ├── cost-estimation.md
│                   └── security.md
├── schemas/                      # JSON schemas for manifests
│   ├── marketplace.schema.json
│   ├── plugin.schema.json
│   ├── mcp.schema.json
│   └── skill-frontmatter.schema.json
├── tools/                        # Lint/validation scripts
│   ├── validate-cross-refs.cjs
│   └── ...
├── mise.toml                     # Tool versions and tasks
├── dprint.json
├── .markdownlint-cli2.yaml
├── .pre-commit-config.yaml
└── README.md
```

## MCP Servers (deploy-on-aws)

| Server         | Type  | Purpose                                           |
| -------------- | ----- | ------------------------------------------------- |
| `awsknowledge` | HTTP  | AWS documentation, architecture guidance          |
| `awspricing`   | stdio | Real-time cost estimates                          |
| `awsiac`       | stdio | IaC best practices (CDK/CloudFormation/Terraform) |

## Workflow: Deploy Skill

1. **Analyze** - Scan codebase for framework, database, dependencies
2. **Recommend** - Select AWS services with concise rationale
3. **Estimate** - Show monthly cost before proceeding (always!)
4. **Generate** - Write IaC code (CDK by default)
5. **Deploy** - Execute with user confirmation

## Default Service Selections

- Web frameworks → Fargate + ALB (not Lambda - cold starts break WSGI frameworks)
- Static sites/SPAs → Amplify Hosting (not S3+CloudFront - too much config)
- Databases → Aurora Serverless v2 (scales to near-zero in dev)
- IaC → CDK TypeScript (most expressive, best IDE support)

Default to **dev sizing** unless user says "production".

## Reference Documentation

See `.claude/docs/` for Claude Code plugin system reference:

- `plugin_overview.md` - Creating plugins
- `plugin_marketplace_distribution.md` - Marketplace distribution
- `plugin_reference.md` - Complete technical reference
- `skills_docs.md` - Skill authoring guide

## Development commands (mise)

The project uses [mise](https://mise.jdx.dev) for tool versions and tasks. Ensure mise is installed, then from the repo root:

```bash
# Install tools (Node, markdownlint, pre-commit, security scanners, etc.)
mise install

# Run common tasks
mise run pre-commit    # Pre-commit hooks on all files
mise run fmt           # Format with dprint
mise run fmt:check     # Check formatting (CI)
mise run lint:md       # Lint Markdown (incl. SKILL.md)
mise run lint:md:fix   # Lint Markdown with auto-fix
mise run lint:manifests   # Validate JSON manifests (marketplace, plugin, MCP)
mise run lint:cross-refs  # Validate cross-references between manifests
mise run lint          # All linters
mise run security      # All security scans (Bandit, SemGrep, Gitleaks, Checkov, Grype)
mise run build         # Full build: lint + fmt:check + security
```

See `mise.toml` for the full task list and tool versions.

## Plugin commands (Claude)

Project-level plugin settings are in `.claude/settings.json` (`enabledPlugins`).
Contributors must first add the marketplace before these take effect.

```bash
# Add marketplace
/plugin marketplace add awslabs/agent-plugins

# Install plugin
/plugin install deploy-on-aws@agent-plugins-for-aws

# Test locally
claude --plugin-dir ./plugins/deploy-on-aws
```

## Git Worktree Workflow

ALWAYS use git worktrees for new work. The main worktree stays on its current branch and is never switched. Each piece of work gets its own worktree under `.tmp/`, branching off the current branch. This enables multiple agents to work in parallel without conflicts.

```bash
# Create a worktree for new work (branches off current branch)
git worktree add .tmp/<short-name> -b <branch-name>

# Create a worktree for an existing branch
git worktree add .tmp/<short-name> <branch-name>

# List worktrees
git worktree list

# Remove a worktree after the branch is merged
git worktree remove .tmp/<short-name>
```

All worktrees live under `.tmp/` (already in `.gitignore`).

## Boundaries

- ALWAYS use `git worktree add .tmp/<name>` for new work. NEVER switch branches in the main worktree.
- ALWAYS Use mise commands to interact with the codebase. If a command is not available, add it.
- NEVER add new dependencies without asking first.
- ALWAYS run a full build when done with a task, this is to ensure all required files are generated before commit.
- ALWAYS Ask first before modifying existing files in a major way.
