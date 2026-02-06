# Agent Plugins for AWS

## TL;DR Pitch

AI coding assistants (Claude Code, Cursor, Windsurf) are becoming the primary interface developers use. These tools support **plugins** - bundles of skills, MCP servers, and agent configurations that extend capabilities. Cursor is launching a curated plugin marketplace. AWS should launch our own plugin marketplace to meet developers where they work. This repo is the MVP: `awslabs/agent-plugins` marketplace with a single plugin (`deploy-on-aws`) that lets any developer say "deploy this to AWS" and get architecture recommendations, cost estimates, and working IaC.

**Elevator pitch for leadership:** Plugin marketplaces are the new app stores for AI-assisted development. Cursor is launching theirs. AWS needs presence in this ecosystem - not just as a cloud provider, but as a first-class citizen in developer tooling. This repo delivers that with a single high-value plugin: "deploy to AWS" in natural language.

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
awslabs-agent-plugins/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace registry
├── plugins/
│   └── deploy-on-aws/
│       ├── .claude-plugin/
│       │   └── plugin.json       # Plugin manifest
│       ├── .mcp.json             # MCP server definitions
│       └── skills/
│           └── deploy/
│               ├── SKILL.md      # Main skill (auto-triggers)
│               └── references/
│                   ├── defaults.md
│                   └── cost-estimation.md
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

## Commands

```bash
# Add marketplace
/plugin marketplace add awslabs/agent-plugins

# Install plugin
/plugin install deploy-on-aws@awslabs-agent-plugins

# Test locally
claude --plugin-dir ./plugins/deploy-on-aws
```
