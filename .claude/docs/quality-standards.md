# Quality Standards & Tooling

This document describes the quality standards and tooling for the AWS Agent Plugins marketplace. All contributions must pass automated quality gates before merge.

## Quick Start

```bash
# Install tools
mise install

# Format all files
mise run fmt

# Run all linters
mise run lint

# Run full CI check locally
mise run ci
```

## Toolchain Overview

| Tool | Purpose | Config File |
|------|---------|-------------|
| **mise** | Tool version manager & task runner | `mise.toml` |
| **dprint** | Format Markdown & JSON | `dprint.json` |
| **markdownlint-cli2** | Lint Markdown style + SKILL.md validation | `.markdownlint-cli2.yaml` |
| **ajv-cli** | Validate JSON against schemas | `schemas/*.schema.json` |
| **Custom rules** | SKILL.md length & frontmatter validation | `tools/*.cjs` |

## SKILL.md Requirements

SKILL.md files are the core of plugin skills. They must follow specific constraints to ensure quality and encourage progressive disclosure.

### Length Limits

| Constraint | Limit | Rationale |
|------------|-------|-----------|
| **Max lines** | 500 | Keeps main skill focused |
| **Max words** | ~8,000 | Prevents context bloat |
| **Recommended lines** | < 300 | Ideal for most skills |
| **Recommended words** | < 5,000 | Allows room for detail |

**Why limits matter:** Claude Code loads SKILL.md content into context when a skill activates. Overly long skills waste context tokens and reduce effectiveness. Move detailed content to `references/` subdirectory.

### Required Frontmatter

Every SKILL.md must have YAML frontmatter with at least:

```yaml
---
name: skill-name
description: >
  When to use this skill. Include trigger phrases and use cases.
  This description helps Claude determine when to auto-invoke the skill.
---
```

### Frontmatter Fields Reference

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | Yes | string | Skill identifier (kebab-case, max 64 chars) |
| `description` | Yes | string | When/why to use this skill (min 20 chars) |
| `argument-hint` | No | string | Hint for expected arguments, e.g., `[filename]` |
| `disable-model-invocation` | No | boolean | Prevent Claude from auto-loading (default: false) |
| `user-invocable` | No | boolean | Show in / menu (default: true) |
| `allowed-tools` | No | string | Comma-separated tools Claude can use |
| `model` | No | string | Model override when skill is active |
| `context` | No | `fork` | Run in forked subagent context |
| `agent` | No | string | Subagent type (requires `context: fork`) |

### Recommended Structure

```markdown
---
name: my-skill
description: >
  When to use this skill. Triggers on: "keyword1", "keyword2".
  Analyzes X and performs Y.
---

# My Skill

Brief overview of what the skill does.

## Workflow

1. **Step one** - What happens first
2. **Step two** - What happens next
3. **Step three** - Final actions

## Principles

Key behaviors and guidelines for the skill.

## References

- See [details.md](references/details.md) for complete documentation
- See [examples.md](references/examples.md) for usage examples
```

### Progressive Disclosure Pattern

Keep SKILL.md concise. Use `references/` subdirectory for:

- Detailed configuration options
- Comprehensive examples
- Domain-specific documentation
- Technical specifications
- Troubleshooting guides

Claude loads reference files on-demand when needed, preserving context for the actual task.

## JSON Manifest Requirements

### plugin.json

Located at `plugins/<plugin-name>/.claude-plugin/plugin.json`:

```json
{
  "name": "plugin-name",
  "description": "Brief description of the plugin",
  "version": "1.0.0",
  "author": {
    "name": "Author Name"
  },
  "license": "Apache-2.0",
  "keywords": ["keyword1", "keyword2"]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Plugin identifier (kebab-case) |
| `description` | Recommended | Brief plugin description |
| `version` | Recommended | Semantic version |
| `author.name` | Recommended | Author or organization name |
| `license` | Recommended | SPDX license identifier |
| `keywords` | Recommended | Discovery tags |

### marketplace.json

Located at `.claude-plugin/marketplace.json`:

```json
{
  "name": "marketplace-name",
  "owner": {
    "name": "Organization Name",
    "email": "contact@example.com"
  },
  "metadata": {
    "description": "Marketplace description",
    "version": "1.0.0",
    "pluginRoot": "./plugins"
  },
  "plugins": [
    {
      "name": "plugin-name",
      "source": "./plugin-name",
      "description": "Plugin description",
      "version": "1.0.0",
      "category": "category",
      "tags": ["tag1", "tag2"],
      "keywords": ["keyword1", "keyword2"]
    }
  ]
}
```

### .mcp.json

Located at `plugins/<plugin-name>/.mcp.json`:

```json
{
  "mcpServers": {
    "server-name": {
      "type": "stdio",
      "command": "uvx",
      "args": ["package-name@latest"],
      "env": {
        "ENV_VAR": "value"
      },
      "timeout": 120000
    },
    "http-server": {
      "type": "http",
      "url": "https://api.example.com/mcp"
    }
  }
}
```

| Server Type | Required Fields | Description |
|-------------|-----------------|-------------|
| `stdio` | `command` | Local process via stdin/stdout |
| `http` | `url` | Remote HTTP endpoint |

## Markdown Style Rules

### Enforced Rules

| Rule | Description |
|------|-------------|
| MD001 | Heading levels increment by one |
| MD003 | ATX-style headings (`#`) |
| MD013 | Line length ≤ 120 (code blocks relaxed) |
| MD024 | No duplicate sibling headings |
| MD033 | Limited HTML elements allowed |
| MD046 | Fenced code blocks |
| MD047 | Files end with newline |

### Code Blocks

Always specify language identifiers:

````markdown
```bash
npm install
```

```json
{"key": "value"}
```

```python
print("hello")
```
````

### Tables

Keep tables readable with proper alignment:

```markdown
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Value    | Value    | Value    |
```

## Running Quality Checks

### Full CI Check

```bash
mise run ci
```

Runs: formatting check, markdown lint, manifest validation, skill validation.

### Individual Checks

```bash
# Format files (modifies files)
mise run fmt

# Check formatting only (CI mode)
mise run fmt:check

# Lint all Markdown
mise run lint:md

# Validate all JSON manifests
mise run lint:manifests

# Validate SKILL.md files
mise run lint:skills
```

### Fixing Issues

**Formatting issues:**
```bash
mise run fmt
```

**Markdown lint issues:**
Most issues are structural. Check the rule ID (e.g., MD013) and fix manually.

**Schema validation issues:**
Review the error message for the invalid field and fix the JSON.

**SKILL.md length issues:**
Move detailed content to `references/` subdirectory.

## CI Pipeline

All PRs must pass the quality gates workflow:

1. **Format check** - Verifies consistent formatting
2. **Markdown lint** - Checks style rules
3. **Manifest validation** - Validates JSON schemas
4. **Skill validation** - Checks SKILL.md constraints

Branch protection requires all checks to pass before merge.

## Adding a New Plugin

1. Create plugin directory: `plugins/<plugin-name>/`
2. Add `.claude-plugin/plugin.json` manifest
3. Add `.mcp.json` if plugin uses MCP servers
4. Create `skills/<skill-name>/SKILL.md`
5. Add detailed docs to `skills/<skill-name>/references/`
6. Update `.claude-plugin/marketplace.json` with plugin entry
7. Run `mise run ci` to verify quality
8. Open PR

## Troubleshooting

### "dprint check failed"

Run `mise run fmt` to auto-fix formatting, then commit changes.

### "SKILL.md exceeds line limit"

Move detailed content to `references/` subdirectory. Keep SKILL.md focused on:
- Core workflow steps
- Key principles
- Links to reference files

### "Invalid frontmatter"

Check YAML syntax and required fields:
- `name` must be kebab-case
- `description` must be at least 20 characters
- No trailing spaces in YAML

### "Schema validation failed"

Review the error message for the specific field. Common issues:
- Missing required field
- Invalid field type
- Pattern mismatch (e.g., non-kebab-case name)

## Related Documentation

- [Skills Documentation](skills_docs.md) - Claude Code skill authoring guide
- [Plugin Overview](plugin_overview.md) - Creating plugins
- [Plugin Reference](plugin_reference.md) - Complete technical reference
- [Quality Gates PRD](quality-gates-prd.md) - Full requirements document
