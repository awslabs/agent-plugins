# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Check SKILL.md line counts and flag extraction candidates.

Complements the SKILL001 markdownlint rule (which enforces hard limits)
by providing detailed diagnostics: per-skill size table, approximate
token counts, and specific code blocks that should be moved to references/.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGINS_DIR = ROOT / "plugins"

IDEAL_MAX = 200
GOOD_MAX = 300
WARNING_MAX = 500
CODE_BLOCK_THRESHOLD = 30  # lines — suggest extraction if a code block exceeds this

RED = "\033[91m"
YELLOW = "\033[93m"
GREEN = "\033[92m"
DIM = "\033[2m"
BOLD = "\033[1m"
RESET = "\033[0m"

FENCE_RE = re.compile(r"^(`{3,})")


def find_extraction_candidates(text: str) -> list[str]:
    """Find code blocks over CODE_BLOCK_THRESHOLD lines as extraction candidates."""
    candidates: list[str] = []
    in_block = False
    block_start = 0
    block_lang = ""
    block_lines = 0
    fence_len = 0

    for i, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        m = FENCE_RE.match(stripped)
        if m and not in_block:
            in_block = True
            fence_len = len(m.group(1))
            block_start = i
            block_lang = stripped[fence_len:].strip() or "unknown"
            block_lines = 0
        elif in_block and m and len(m.group(1)) >= fence_len and stripped == m.group(1):
            in_block = False
            if block_lines > CODE_BLOCK_THRESHOLD:
                candidates.append(
                    f"Code block ({block_lang}) at line {block_start}: {block_lines} lines"
                )
        elif in_block:
            block_lines += 1

    return candidates


def collect_skills() -> list[tuple[str, str, Path]]:
    """Collect all (plugin_name, skill_name, skill_md_path) tuples."""
    skills = []
    for plugin_dir in sorted(PLUGINS_DIR.iterdir()):
        if not plugin_dir.is_dir():
            continue
        skills_dir = plugin_dir / "skills"
        if not skills_dir.is_dir():
            continue
        for skill_dir in sorted(skills_dir.iterdir()):
            if not skill_dir.is_dir():
                continue
            skill_md = skill_dir / "SKILL.md"
            if skill_md.exists():
                skills.append((plugin_dir.name, skill_dir.name, skill_md))
    return skills


def main() -> int:
    skills = collect_skills()

    if not skills:
        print(f"{YELLOW}No skills found{RESET}")
        return 0

    has_errors = False
    results: list[tuple[str, Path, int, int, str]] = []

    for plugin_name, skill_name, skill_md in skills:
        text = skill_md.read_text(encoding="utf-8")
        lines = len(text.splitlines())
        tokens = len(text) // 4  # rough estimate

        if lines > WARNING_MAX:
            level = "error"
            has_errors = True
        elif lines > GOOD_MAX:
            level = "warning"
        elif lines > IDEAL_MAX:
            level = "good"
        else:
            level = "ideal"

        label = f"{plugin_name}/{skill_name}"
        results.append((label, skill_md, lines, tokens, level))

    # Sort by line count descending
    results.sort(key=lambda r: r[2], reverse=True)

    print(f"{BOLD}SKILL.md Size Check{RESET}")
    print(f"Checking {len(results)} skills...\n")

    print(f"  {'Plugin/Skill':<50} {'Lines':>6}  {'~Tokens':>8}  Status")
    print(f"  {'─' * 50} {'─' * 6}  {'─' * 8}  {'─' * 12}")

    for label, _, lines, tokens, level in results:
        if level == "error":
            status = f"{RED}EXTRACT{RESET}"
            color = RED
        elif level == "warning":
            status = f"{YELLOW}REVIEW{RESET}"
            color = YELLOW
        elif level == "good":
            status = f"{DIM}good{RESET}"
            color = ""
        else:
            status = f"{GREEN}ideal{RESET}"
            color = ""

        line_str = f"{color}{lines:>6}{RESET}" if color else f"{lines:>6}"
        print(f"  {label:<50} {line_str}  {tokens:>8}  {status}")

    # Show extraction candidates for oversized skills
    oversized = [
        (label, skill_md)
        for label, skill_md, _, _, level in results
        if level in ("error", "warning")
    ]
    if oversized:
        print(f"\n{BOLD}Extraction candidates:{RESET}")
        for label, skill_md in oversized:
            text = skill_md.read_text(encoding="utf-8")
            candidates = find_extraction_candidates(text)
            if candidates:
                print(f"\n  {YELLOW}{label}{RESET}:")
                for c in candidates:
                    print(f"    → {c}")

    error_count = sum(1 for *_, level in results if level == "error")
    warn_count = sum(1 for *_, level in results if level == "warning")
    print(
        f"\n{BOLD}Summary:{RESET} {len(results)} skills,"
        f" {error_count} over {WARNING_MAX} (error),"
        f" {warn_count} over {GOOD_MAX} (warning)"
    )

    return 1 if has_errors else 0


if __name__ == "__main__":
    sys.exit(main())
