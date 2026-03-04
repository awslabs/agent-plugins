---
name: design-guidelines
description: Plugin design best practices for authoring skills, MCP integrations, and reference files. Use when creating a new plugin, writing SKILL.md files, structuring reference documentation, adding YAML frontmatter, or reviewing plugin design quality. Triggers on "create a plugin", "write a skill", "plugin best practices", or "design guidelines".
---

# Plugin Design Guidelines

For the full design guidelines, read `docs/DESIGN_GUIDELINES.md` in the repository root.

## Key Principles

1. **Minimize context usage** - Keep SKILL.md under 300 lines, reference files under 100 lines
2. **Write for agents, not humans** - Explicit, unambiguous instructions; no vague language
3. **Single responsibility per skill** - Each skill does one thing well
4. **Keep plugins focused** - Clear, cohesive purpose; don't bundle unrelated features

## YAML Frontmatter (Agent Skills Spec)

Required: `name`, `description`. Optional: `license`, `compatibility`, `metadata`, `allowed-tools`.

- `name`: 1-64 chars, lowercase, hyphens only, must match directory name
- `description`: Max 1024 chars, include trigger phrases and keywords

## File Organization

```
skills/myskill/
  SKILL.md                 # Main workflow (200-300 lines max)
  references/
    defaults.md            # Default selections (50-100 lines max)
    patterns.md            # Common patterns
```

## Review Checklist

- [ ] SKILL.md under 300 lines with proper frontmatter
- [ ] Reference files under 100 lines each
- [ ] Descriptions include trigger conditions
- [ ] All defaults explicitly specified
- [ ] Error handling documented
- [ ] No vague language ("maybe", "probably", "consider")
- [ ] Full build passes (`mise run build`)
