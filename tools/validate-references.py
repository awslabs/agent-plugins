# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Detect broken links and orphaned reference files across all plugins.

Walks from each SKILL.md through all referenced markdown files using BFS,
reports broken links (exit 1) and orphaned reference files (warning).
"""

import re
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGINS_DIR = ROOT / "plugins"

# File extensions to track as linkable resources
EXT = r"md|py|ts|js|json|yaml|yml|toml|txt|tsx|jsx|sh|cjs|mjs"
# Patterns for extracting file references from markdown
INLINE_CODE_RE = re.compile(rf"`([^`]+\.(?:{EXT}))`")
MD_LINK_RE = re.compile(rf"\[(?:[^\]]*)\]\(([^)]+\.(?:{EXT}))\)")
# Directory links: [text](../some-skill/) — treated as linking to SKILL.md
MD_DIR_LINK_RE = re.compile(r"\[(?:[^\]]*)\]\((\.\./[^)]+/)\)")
# Plain-text paths containing references/ (catches table cells, prose)
# Negative lookbehind prevents matching partial paths inside markdown link hrefs
# e.g. won't match "references/foo.md" from "../../other-skill/references/foo.md"
PLAIN_REF_RE = re.compile(rf"(?<![`(\[/\w])(?:references/[^\s\"'`<>|]+\.(?:{EXT}))")

RED = "\033[91m"
YELLOW = "\033[93m"
GREEN = "\033[92m"
BOLD = "\033[1m"
RESET = "\033[0m"


def extract_refs(text: str) -> set[str]:
    """Extract all file path references from markdown text."""
    refs: set[str] = set()
    for pattern in (INLINE_CODE_RE, MD_LINK_RE):
        refs.update(pattern.findall(text))
    refs.update(PLAIN_REF_RE.findall(text))
    # Directory links like ../other-skill/ → treat as ../other-skill/SKILL.md
    for dir_ref in MD_DIR_LINK_RE.findall(text):
        refs.add(dir_ref + "SKILL.md")
    return refs


def find_skill_root(source_file: Path) -> Path | None:
    """Find the skill root directory (plugins/X/skills/Y/) for a source file."""
    resolved = source_file.resolve()
    for parent in resolved.parents:
        if parent.parent.name == "skills" and parent.parent.parent.exists():
            # Verify this is under plugins/
            try:
                parent.relative_to(PLUGINS_DIR)
                return parent
            except ValueError:
                pass
    return None


def _is_under_root(resolved: Path) -> bool:
    """Reject candidates that escape the repository root."""
    try:
        resolved.relative_to(ROOT)
        return True
    except ValueError:
        return False


def resolve_ref(ref: str, source_file: Path) -> list[Path]:
    """Resolve a reference path to candidate file paths.

    All candidates are clamped to ROOT — paths that escape the repository
    via symlinks or ../ traversal are silently dropped.
    """
    # Skip URLs, mailto, fragment-only links
    if ref.startswith(("http://", "https://", "mailto:", "#")):
        return []

    candidates: list[Path] = []

    def _add(raw: Path) -> None:
        resolved = raw.resolve()
        if _is_under_root(resolved) and resolved not in candidates:
            candidates.append(resolved)

    # Try relative to the source file's directory
    _add(source_file.parent / ref)
    # Also try relative to the skill root
    skill_root = find_skill_root(source_file)
    if skill_root:
        _add(skill_root / ref)
        # Try relative to the skill's references/ directory
        # Handles convention where files in references/ use short paths like
        # `design-refs/foo.md` meaning `references/design-refs/foo.md`
        _add(skill_root / "references" / ref)
    return candidates


def collect_all_resource_files() -> set[Path]:
    """Collect all files under plugins/*/skills/*/references/."""
    files: set[Path] = set()
    for plugin_dir in PLUGINS_DIR.iterdir():
        if not plugin_dir.is_dir():
            continue
        skills_dir = plugin_dir / "skills"
        if not skills_dir.is_dir():
            continue
        for skill_dir in skills_dir.iterdir():
            if not skill_dir.is_dir():
                continue
            refs_dir = skill_dir / "references"
            if refs_dir.is_dir():
                for f in refs_dir.rglob("*"):
                    if f.is_file() and f.name != ".gitkeep":
                        files.add(f.resolve())
    return files


def collect_entry_points() -> list[Path]:
    """Collect all SKILL.md files as entry points."""
    entries: list[Path] = []
    for plugin_dir in PLUGINS_DIR.iterdir():
        if not plugin_dir.is_dir():
            continue
        skills_dir = plugin_dir / "skills"
        if not skills_dir.is_dir():
            continue
        for skill_dir in skills_dir.iterdir():
            if skill_dir.is_dir():
                skill_md = skill_dir / "SKILL.md"
                if skill_md.exists():
                    entries.append(skill_md)
    return entries


def main() -> int:
    if not PLUGINS_DIR.is_dir():
        print(f"{YELLOW}No plugins/ directory found{RESET}")
        return 0

    all_resources = collect_all_resource_files()
    entry_points = collect_entry_points()

    if not entry_points:
        print(f"{YELLOW}No SKILL.md entry points found{RESET}")
        return 0

    # BFS: track which resource files are reachable
    reachable: set[Path] = set()
    broken_links: list[tuple[Path, str]] = []

    queue: deque[Path] = deque(entry_points)
    visited: set[Path] = set()

    while queue:
        current = queue.popleft()
        resolved = current.resolve()
        if resolved in visited:
            continue
        visited.add(resolved)

        if not current.exists():
            continue

        text = current.read_text(encoding="utf-8")
        refs = extract_refs(text)

        for ref in refs:
            if ref.startswith(("http://", "https://", "mailto:", "#")):
                continue
            # Skip glob patterns
            if "*" in ref or "?" in ref:
                continue

            candidates = resolve_ref(ref, current)
            if not candidates:
                continue

            found_any = any(p.exists() for p in candidates)

            if not found_any:
                # Only report as broken if the path looks like a reference
                ref_lower = ref.lower()
                if any(
                    kw in ref_lower
                    for kw in ("references/", "templates/", "skills/", "phases/")
                ):
                    broken_links.append((current, ref))
                continue

            for candidate in candidates:
                if candidate.exists():
                    reachable.add(candidate)
                    # If it's a markdown file, crawl it too for transitive links
                    if candidate not in visited and candidate.suffix == ".md":
                        queue.append(candidate)

    orphans = all_resources - reachable

    print(f"{BOLD}Reference Integrity Check{RESET}")
    print(
        f"Entry points: {len(entry_points)}, Resource files: {len(all_resources)}\n"
    )

    if broken_links:
        print(f"{RED}Broken links ({len(broken_links)}):{RESET}")
        for source, ref in sorted(broken_links, key=lambda x: (str(x[0]), x[1])):
            rel_source = source.relative_to(ROOT)
            print(f"  {RED}BROKEN{RESET}  {rel_source} -> {ref}")
        print()

    if orphans:
        print(f"{YELLOW}Orphaned files ({len(orphans)}):{RESET}")
        for p in sorted(orphans):
            rel = p.relative_to(ROOT)
            print(f"  {YELLOW}ORPHAN{RESET}  {rel}")
        print()

    if not broken_links and not orphans:
        print(
            f"  {GREEN}All {len(all_resources)} resource files are reachable."
            f" No broken links found.{RESET}\n"
        )

    reachable_count = len(all_resources) - len(orphans)
    print(
        f"{BOLD}Summary:{RESET} {reachable_count}/{len(all_resources)} reachable,"
        f" {len(orphans)} orphaned, {len(broken_links)} broken links"
    )

    return 1 if broken_links else 0


if __name__ == "__main__":
    sys.exit(main())
