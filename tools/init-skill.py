# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Scaffold a new skill directory with correct SKILL.md template."""

import re
import sys
from pathlib import Path
from string import Template

ROOT = Path(__file__).resolve().parent.parent
PLUGINS_DIR = ROOT / "plugins"
NAME_RE = re.compile(r"^[a-z][a-z0-9-]*$")

SKILL_TEMPLATE = Template("""\
---
name: $name
description: >
  $description
---

# $title

## When to Use

[FILL: Describe the specific scenarios and contexts where this skill applies.]

## Core Concepts

[FILL: Key concepts, terminology, and mental models.]

## Quick Reference

[FILL: The most commonly needed patterns, commands, or code snippets.]

## Anti-Patterns

[FILL: Common mistakes and what to do instead.]

## References

- `references/` — [FILL: Describe what detailed reference material is available.]
""")


def main() -> int:
    if len(sys.argv) < 4:
        print(f"Usage: uv run {sys.argv[0]} <plugin-name> <skill-name> <description>")
        print(
            f"Example: uv run {sys.argv[0]} deploy-on-aws my-skill"
            " 'Brief description. Use when the user asks to...'"
        )
        return 1

    plugin_name = sys.argv[1]
    skill_name = sys.argv[2]
    description = sys.argv[3]

    # Validate plugin exists and is under PLUGINS_DIR (no path traversal)
    plugin_dir = (PLUGINS_DIR / plugin_name).resolve()
    if not plugin_dir.is_relative_to(PLUGINS_DIR.resolve()):
        print(f"Error: plugin name must not contain path traversal: '{plugin_name}'")
        return 1
    if not plugin_dir.is_dir():
        print(f"Error: plugin '{plugin_name}' not found at {plugin_dir}")
        available = sorted(
            d.name for d in PLUGINS_DIR.iterdir() if d.is_dir() and not d.name.startswith(".")
        )
        if available:
            print(f"Available plugins: {', '.join(available)}")
        return 1

    # Validate skill name format
    if not NAME_RE.match(skill_name):
        print(f"Error: '{skill_name}' is not a valid skill name")
        print("Must be kebab-case (lowercase letters, digits, hyphens)")
        return 1

    if len(skill_name) > 64:
        print(f"Error: skill name exceeds 64 characters (current: {len(skill_name)})")
        return 1

    if "--" in skill_name:
        print(f"Error: '{skill_name}' contains consecutive hyphens")
        return 1

    # Check reserved words
    if re.search(r"\b(anthropic|claude)\b", skill_name, re.IGNORECASE):
        print(f"Error: '{skill_name}' contains reserved word")
        return 1

    # Check skill doesn't already exist
    skills_dir = plugin_dir / "skills"
    skill_dir = skills_dir / skill_name
    if skill_dir.exists():
        print(f"Error: skill '{skill_name}' already exists at {skill_dir}")
        return 1

    # Warn about trigger phrase
    if "Use when" not in description and "Use this" not in description:
        print("Warning: description should contain 'Use when' or 'Use this' trigger phrase")

    # Create structure
    title = skill_name.replace("-", " ").title()
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        SKILL_TEMPLATE.safe_substitute(name=skill_name, description=description, title=title),
        encoding="utf-8",
    )
    refs_dir = skill_dir / "references"
    refs_dir.mkdir()
    (refs_dir / ".gitkeep").touch()

    rel_path = skill_dir.relative_to(ROOT)
    print(f"Created skill '{skill_name}' in plugin '{plugin_name}':")
    print(f"  {rel_path}/SKILL.md")
    print(f"  {rel_path}/references/.gitkeep")
    print()
    print("Next steps:")
    print(f"  1. Edit {rel_path}/SKILL.md — fill in the [FILL] sections")
    print(f"  2. Add reference files to {rel_path}/references/")
    print(f"  3. Run: mise run validate")

    return 0


if __name__ == "__main__":
    sys.exit(main())
