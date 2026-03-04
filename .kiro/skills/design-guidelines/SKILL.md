---
name: design-guidelines
description: Plugin design best practices for authoring skills, MCP integrations, and reference files. Use when creating a new plugin, writing SKILL.md files, structuring reference documentation, adding YAML frontmatter, or reviewing plugin design quality. Triggers on "create a plugin", "write a skill", "plugin best practices", or "design guidelines".
---

# Plugin Design Guidelines

## Workflow

### Step 1: Scope the Plugin

- One plugin = one focused purpose
- If the description uses "and" more than once, consider splitting

### Step 2: Create the Structure

- `plugin.json` manifest with name, version, description
- `.mcp.json` for any MCP server integrations
- `skills/<name>/SKILL.md` (≤300 lines) with `references/` for details (≤100 lines each)

### Step 3: Author SKILL.md

- YAML frontmatter: `name` and `description` required
- Include trigger phrases and 3–7 keywords in description
- Write numbered workflow steps with explicit defaults
- Document error handling for every failure scenario (especially MCP)
- No vague language ("maybe", "probably", "consider")

### Step 4: Validate

1. `mise run lint:manifests` — validate JSON manifests
2. `mise run lint:cross-refs` — check cross-references
3. `mise run build` — full build before committing

For anti-patterns, MCP integration, review checklist, and examples, see references/full-guide.md.
