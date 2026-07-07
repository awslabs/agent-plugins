# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Vendor the Semgrep ``r/all`` ruleset locally with tracked exclusions.

Implements RFC #211. Downloads ``r/all`` from the Semgrep registry, drops every
rule marked ``excluded`` in ``rules-status.toml``, and writes the single tracked
artifact scans load:

* ``rules-vendored.yaml`` — pre-filtered rules; the only file semgrep runs.

Design constraints (see RFC #211):

* **Stdlib only.** No YAML library — a naive re-serialize/strip of rule bodies
  was verified to silently break the ruleset (6 findings -> 0). We therefore
  treat the download as text: split it into per-rule blocks and keep every
  retained rule *byte-for-byte* as downloaded, only ever dropping whole blocks.
* **Fail loudly.** A non-YAML, empty, or rule-less download aborts before the
  tracked file is overwritten, so a bad upstream response can never produce a
  broken active ruleset.
* **Deterministic.** Rules are sorted by id before writing, so a regeneration
  with no upstream change yields a byte-identical file (an empty git diff);
  real drift is the only thing that shows up.

Decision model (``rules-status.toml``, human-owned — the script only ever reads
it, so hand-written ``#`` comments are preserved):

* ``status = "excluded"`` — the rule is physically removed from
  ``rules-vendored.yaml``.
* ``status = "active"``   — the rule is kept, and the keep-decision is recorded.

Two states are *derived* each run and reported for human action (never stored):

* ``new``      — a rule in the feed with no ``rules-status.toml`` entry that was
  not in the prior vendored file. Nothing is excluded implicitly, so a new
  upstream rule can never be silently dropped — it is surfaced for triage.
* ``orphaned`` — a ``rules-status.toml`` entry whose rule no longer appears in
  the feed (removed upstream). A human decides whether to prune the entry or
  keep it. Not deleted automatically.

Both derived states are computed statelessly from artifacts already in git — the
prior ``rules-vendored.yaml`` plus ``rules-status.toml`` reconstruct "every id
seen last run" — so no separate state file is needed.

Run manually via ``mise run semgrep:update`` (``uv run
tools/semgrep/rules-update.py``). ``rules-vendored.yaml`` is script-owned; hand
edits are lost on the next run. Only ``rules-status.toml`` is human-edited.
``rules-vendored.yaml`` is excluded in ``.semgrepignore`` (self-match) and the
gitleaks allowlist (it contains secret-detection regexes), and sits in the
pre-commit ``exclude`` (content hooks would otherwise act on it).
"""

from __future__ import annotations

import re
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

RULESET_URL = "https://semgrep.dev/c/r/all"
DOWNLOAD_TIMEOUT = 120  # seconds

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

# Tracked output (script-owned) — the only file scans load.
VENDORED_FILE = HERE / "rules-vendored.yaml"
# Human-owned source of truth for what is excluded/kept.
STATUS_TOML = HERE / "rules-status.toml"
# Transient full download; never committed.
SNAPSHOT_FILE = ROOT / ".tmp" / "r-all.snapshot.yaml"

# A rule block begins at a top-level YAML list marker ("- ") in the "rules:"
# sequence. Most rules lead with "- id:", but a handful lead with "- fix:" or
# "- patterns:" and carry "id:" on a later line, so we split on the marker and
# locate the id within each block rather than assuming id comes first.
RULE_START_RE = re.compile(r"^- ", re.MULTILINE)
# Matches the rule id whether it is the first key ("- id: x") or a later
# 2-space-indented key ("  id: x"). Anchored so nested keys (rule_id, r_id,
# rv_id) never match.
ID_RE = re.compile(r"^(?:- |  )id: (.+)$", re.MULTILINE)

GENERATED_HEADER = (
    "# GENERATED FILE — DO NOT EDIT BY HAND.\n"
    "# Produced by tools/semgrep/rules-update.py from the Semgrep r/all ruleset.\n"
    "# Excluded rules (see tools/semgrep/rules-status.toml) are physically\n"
    "# removed. Hand edits are lost on the next `mise run semgrep:update`.\n"
)


class UpdateError(RuntimeError):
    """Raised when the update cannot complete safely (fails loudly)."""


def _https_only_opener() -> urllib.request.OpenerDirector:
    """Build a urllib opener that can ONLY speak HTTPS.

    The default opener (``urllib.request.urlopen``) installs handlers for
    ``file://`` and ``ftp://``, so a URL that resolved to another scheme could
    read local files (CWE-939, Improper Authorization in Handler for Custom URL
    Scheme). We construct an opener with the HTTPS/redirect/error handlers only —
    no ``FileHandler``/``FTPHandler`` — so non-HTTPS schemes have no handler and
    are physically unreachable, closing the risk by construction rather than by
    trusting the URL to stay constant.
    """
    opener = urllib.request.OpenerDirector()
    for handler in (
        urllib.request.ProxyHandler(),
        urllib.request.HTTPSHandler(),
        urllib.request.HTTPRedirectHandler(),
        urllib.request.HTTPDefaultErrorHandler(),
        urllib.request.HTTPErrorProcessor(),
        urllib.request.UnknownHandler(),
    ):
        opener.add_handler(handler)
    return opener


def download_ruleset() -> str:
    """Download r/all to the transient snapshot path and return its text.

    Fails loudly on a network error, an empty body, or a response that does not
    look like a Semgrep ruleset — never lets a bad download reach the active file.
    """
    print(f"Downloading {RULESET_URL} ...")
    scheme = urllib.parse.urlsplit(RULESET_URL).scheme
    if scheme != "https":
        raise UpdateError(f"ruleset URL must use https, got {scheme!r}")
    opener = _https_only_opener()
    req = urllib.request.Request(RULESET_URL, headers={"Accept": "text/yaml"})
    try:
        with opener.open(req, timeout=DOWNLOAD_TIMEOUT) as resp:
            raw = resp.read().decode("utf-8")
    except (urllib.error.URLError, TimeoutError) as exc:
        raise UpdateError(f"download failed: {exc}") from exc

    if not raw.strip():
        raise UpdateError("download was empty")
    if not raw.lstrip().startswith("rules:"):
        preview = raw.lstrip()[:80].replace("\n", " ")
        raise UpdateError(
            f"download does not look like a ruleset (starts: {preview!r})"
        )

    SNAPSHOT_FILE.parent.mkdir(parents=True, exist_ok=True)
    SNAPSHOT_FILE.write_text(raw, encoding="utf-8")
    print(f"  saved snapshot to {SNAPSHOT_FILE.relative_to(ROOT)} ({len(raw):,} bytes)")
    return raw


def split_rules(raw: str) -> tuple[str, list[str]]:
    """Split the raw ruleset into (header, [rule_block, ...]).

    ``header`` is the leading ``rules:`` line (kept verbatim). Each block is the
    text of one rule including its leading ``- `` marker and trailing newline,
    preserved byte-for-byte so retained rules are identical to the download.

    Assumes a rule's own content never begins a column-0 ``- `` line (e.g. inside
    a ``message``/``fix`` block scalar), since that marker is what delimits rules.
    r/all indents all such nested content, so this holds; if it ever didn't, the
    mis-split block would fail the ``rule_id_of`` id lookup and abort loudly
    rather than silently corrupt the ruleset.
    """
    starts = [m.start() for m in RULE_START_RE.finditer(raw)]
    if not starts:
        raise UpdateError("no rule blocks found in download")
    header = raw[: starts[0]]
    if "rules:" not in header:
        raise UpdateError("could not locate 'rules:' header before first rule")
    bounds = starts + [len(raw)]
    blocks = [raw[bounds[i] : bounds[i + 1]] for i in range(len(starts))]
    return header, blocks


def rule_id_of(block: str) -> str:
    """Extract the canonical rule id from a single rule block."""
    id_match = ID_RE.search(block)
    if not id_match:
        raise UpdateError(f"rule block has no id:\n{block[:200]}")
    return id_match.group(1).strip()


def load_exclusions() -> dict[str, dict]:
    """Load per-rule decisions from rules-status.toml ([rules."id"] -> {...})."""
    if not STATUS_TOML.exists():
        print(f"  note: {STATUS_TOML.name} not found — treating all rules as new")
        return {}
    try:
        data = tomllib.loads(STATUS_TOML.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise UpdateError(f"could not read {STATUS_TOML.name}: {exc}") from exc
    return data.get("rules", {})


def prior_vendored_ids() -> set[str]:
    """Rule ids in the currently-committed vendored file (the prior baseline).

    Together with the excluded ids from rules-status.toml this reconstructs
    "every id seen on the previous run" — used to flag genuinely new rules —
    without needing a separate state file.
    """
    if not VENDORED_FILE.exists():
        return set()
    try:
        text = VENDORED_FILE.read_text(encoding="utf-8")
    except OSError as exc:
        raise UpdateError(f"could not read {VENDORED_FILE.name}: {exc}") from exc
    return {m.group(1).strip() for m in ID_RE.finditer(text)}


def main() -> int:
    try:
        raw = download_ruleset()
        header, blocks = split_rules(raw)
        exclusions = load_exclusions()

        # Reconstruct "ids seen last run" from artifacts already in git: the
        # prior vendored file (kept rules) plus every excluded id in the toml.
        # First run (no vendored file yet) is the bootstrap baseline — treat the
        # whole snapshot as established rather than flagging ~3000 rules as new.
        prior_ids = prior_vendored_ids()
        is_bootstrap = not prior_ids
        baseline_ids = prior_ids | {
            rid for rid, e in exclusions.items() if e.get("status") == "excluded"
        }

        active_blocks: list[tuple[str, str]] = []
        counts = {"active": 0, "excluded": 0}
        seen_ids: set[str] = set()
        new_ids: list[str] = []

        for block in blocks:
            rule_id = rule_id_of(block)
            seen_ids.add(rule_id)

            entry = exclusions.get(rule_id)
            if entry is not None and entry.get("status") == "excluded":
                counts["excluded"] += 1
            else:
                active_blocks.append((rule_id, block))
                counts["active"] += 1

            # `new`: in the feed, no decision recorded, and not seen last run.
            if entry is None and not is_bootstrap and rule_id not in baseline_ids:
                new_ids.append(rule_id)

        # `orphaned`: a recorded decision whose rule is gone from the feed.
        orphaned = sorted(set(exclusions) - seen_ids)
        new_ids = sorted(set(new_ids))

        # Write output only after all parsing succeeded. Sort blocks by id so the
        # output is deterministic: the registry serves r/all in a nondeterministic
        # order, so without this every regeneration would emit a spurious
        # full-file diff even when no rule actually changed. Tie-break on the
        # block text so duplicate ids (r/all reuses some) also order stably,
        # rather than falling back to the download's nondeterministic order.
        active_blocks.sort(key=lambda rb: (rb[0], rb[1]))
        vendored_text = GENERATED_HEADER + header + "".join(b for _, b in active_blocks)
        VENDORED_FILE.write_text(vendored_text, encoding="utf-8")
    except UpdateError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(
        f"Wrote {VENDORED_FILE.relative_to(ROOT)}"
        f" ({counts['active']} active, {counts['excluded']} excluded of {len(blocks)})"
    )
    print(
        f"Summary: {len(new_ids)} new (need triage),"
        f" {counts['excluded']} excluded,"
        f" {len(orphaned)} orphaned (removed upstream)"
    )
    if new_ids:
        print(
            f"  NEW — {len(new_ids)} rule(s) appeared upstream with no decision;"
            f" triage into {STATUS_TOML.name}: {', '.join(new_ids)}"
        )
    if orphaned:
        print(
            f"  ORPHANED — {len(orphaned)} {STATUS_TOML.name} entr(y/ies) no longer"
            f" match any rule (removed upstream); prune or keep: {', '.join(orphaned)}"
        )
    print(
        "Next: run `mise run security:semgrep` to verify the active file scans clean."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
