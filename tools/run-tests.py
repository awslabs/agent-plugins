# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Discover and run the repository's Python unit tests.

Wired into `mise run test` (and `mise run build`). Finds every `test_*.py`
under `tools/` and `plugins/`, runs each in its own subprocess via `uv run`,
and exits non-zero if any test file fails.

**No test-runner dependency.** By convention each test file is self-contained:
it carries a `# /// script` header, a tiny pytest shim, and an `if __name__ ==
"__main__"` runner (see tools/evals/databases-on-aws/dsql/scripts/test_safe_query.py).
So `uv run <file>` executes it standalone — pytest is optional, not required —
which keeps the build dependency-free. If pytest is later adopted repo-wide,
this runner can be swapped for a single `pytest` invocation.

Run: `mise run test`  (or `uv run tools/run-tests.py`)
"""

from __future__ import annotations

import shutil
import subprocess  # nosec B404 - test runner needs subprocess to invoke `uv run` on each test file
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Directories that hold runnable code + their tests. `.tmp` (worktrees) and
# node_modules are never scanned.
SEARCH_DIRS = ("tools", "plugins")
EXCLUDE_PARTS = {".tmp", "node_modules"}


def discover() -> list[Path]:
    """Return sorted `test_*.py` files under the search dirs, deterministically."""
    found: set[Path] = set()
    for d in SEARCH_DIRS:
        for path in (ROOT / d).rglob("test_*.py"):
            # Compare parts RELATIVE to ROOT: the repo runs from `.tmp/<name>/`
            # worktrees, so the absolute path always contains `.tmp` — excluding
            # on absolute parts would skip every test. Only intra-repo `.tmp`/
            # node_modules segments should be excluded.
            rel_parts = path.relative_to(ROOT).parts
            if EXCLUDE_PARTS.isdisjoint(rel_parts):
                found.add(path)
    return sorted(found)


def main() -> int:
    tests = discover()
    if not tests:
        print("No test_*.py files found under", ", ".join(SEARCH_DIRS))
        return 0

    # Resolve `uv` to an absolute path once (it's the mise-provided tool, always
    # on PATH in dev/CI). Using the resolved path avoids a partial-executable-path
    # concern and fails clearly if `uv` is somehow missing.
    uv = shutil.which("uv")
    if uv is None:
        print("error: `uv` not found on PATH (needed to run tests)", file=sys.stderr)
        return 1

    print(f"Running {len(tests)} test file(s):\n")
    failed: list[Path] = []
    for path in tests:
        rel = path.relative_to(ROOT)
        print(f"━━ {rel} " + "━" * max(0, 60 - len(str(rel))))
        # argv is a fixed shape; uv is an absolute path and only the discovered
        # test path (from our own rglob, not user input) varies.
        result = subprocess.run(  # nosec B603 - fixed argv, resolved uv path, no shell
            [uv, "run", str(path)],
            cwd=ROOT,
            check=False,
        )
        if result.returncode != 0:
            failed.append(rel)
        print()

    total = len(tests)
    if failed:
        print(f"✖ {len(failed)}/{total} test file(s) failed:")
        for rel in failed:
            print(f"    {rel}")
        return 1
    print(f"✓ all {total} test file(s) passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
