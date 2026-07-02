# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Vendor the Semgrep ``r/all`` ruleset locally with tracked exclusions.

Implements RFC #211. Downloads ``r/all`` from the Semgrep registry, diffs each
rule's ``version_id`` against the prior snapshot to derive a human-readable
"last changed" date, drops every rule marked ``excluded`` in ``exclusions.toml``,
and writes three tracked artifacts:

* ``r-all.active.yaml`` — pre-filtered rules; the only file scans load.
* ``rule-state.json``   — ``id -> {version_id, updated}``; the diff baseline.
* ``EXCLUSIONS.md``     — generated human-readable tracking table (goal B).

Design constraints (see RFC #211):

* **Stdlib only.** No YAML library — a naive re-serialize/strip of rule bodies
  was verified to silently break the ruleset (6 findings -> 0). We therefore
  treat the download as text: split it into per-rule blocks and keep every
  retained rule *byte-for-byte* as downloaded, only ever dropping whole blocks.
* **Fail loudly.** A non-YAML, empty, or rule-less download aborts before any
  tracked file is overwritten, so a bad upstream response can never produce a
  broken active ruleset.

Run manually via ``mise run semgrep:update`` (``uv run tools/semgrep/update.py``).
The generated files are script-owned; hand edits are lost on the next run. Only
``exclusions.toml`` is human-edited.
"""

from __future__ import annotations

import json
import re
import sys
import tomllib
import urllib.request
from datetime import date
from pathlib import Path

RULESET_URL = "https://semgrep.dev/c/r/all"
DOWNLOAD_TIMEOUT = 120  # seconds

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

# Tracked outputs (script-owned).
ACTIVE_FILE = HERE / "r-all.active.yaml"
STATE_FILE = HERE / "rule-state.json"
EXCLUSIONS_DOC = HERE / "EXCLUSIONS.md"
# Human-owned source of truth for what is excluded/kept.
EXCLUSIONS_TOML = HERE / "exclusions.toml"
# Transient full download; never committed.
SNAPSHOT_FILE = ROOT / ".tmp" / "r-all.snapshot.yaml"

MISE_TOML = ROOT / "mise.toml"

# A rule block begins at a top-level YAML list marker ("- ") in the "rules:"
# sequence. Most rules lead with "- id:", but a handful lead with "- fix:" or
# "- patterns:" and carry "id:" on a later line, so we split on the marker and
# locate the id within each block rather than assuming id comes first.
RULE_START_RE = re.compile(r"^- ", re.MULTILINE)
# Matches the rule id whether it is the first key ("- id: x") or a later
# 2-space-indented key ("  id: x"). Anchored so nested keys (rule_id, r_id,
# rv_id) never match.
ID_RE = re.compile(r"^(?:- |  )id: (.+)$", re.MULTILINE)
VERSION_ID_RE = re.compile(r"^ +version_id: (\S+)$", re.MULTILINE)
MESSAGE_RE = re.compile(r"^  message: (.+)$", re.MULTILINE)

GENERATED_HEADER = (
    "# GENERATED FILE — DO NOT EDIT BY HAND.\n"
    "# Produced by tools/semgrep/update.py from the Semgrep r/all ruleset.\n"
    "# Excluded rules (see tools/semgrep/exclusions.toml) are physically\n"
    "# removed. Hand edits are lost on the next `mise run semgrep:update`.\n"
)


class UpdateError(RuntimeError):
    """Raised when the update cannot complete safely (fails loudly)."""


def semgrep_version() -> str:
    """Read the pinned Semgrep version from mise.toml (declared source of truth)."""
    try:
        data = tomllib.loads(MISE_TOML.read_text(encoding="utf-8"))
        return str(data["tools"]["pipx:semgrep"])
    except (OSError, KeyError, tomllib.TOMLDecodeError):
        return "unknown"


def download_ruleset() -> str:
    """Download r/all to the transient snapshot path and return its text.

    Fails loudly on a network error, an empty body, or a response that does not
    look like a Semgrep ruleset — never lets a bad download reach the active file.
    """
    print(f"Downloading {RULESET_URL} ...")
    req = urllib.request.Request(RULESET_URL, headers={"Accept": "text/yaml"})
    try:
        # RULESET_URL is a fixed https:// constant, not user input, so there is
        # no file:/custom-scheme risk that B310/S310 warn about.
        with urllib.request.urlopen(req, timeout=DOWNLOAD_TIMEOUT) as resp:  # nosec B310  # noqa: S310
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


def parse_block(block: str) -> tuple[str, str, str]:
    """Extract (rule_id, version_id, description) from a single rule block."""
    id_match = ID_RE.search(block)
    if not id_match:
        raise UpdateError(f"rule block has no id:\n{block[:200]}")
    rule_id = id_match.group(1).strip()

    version_match = VERSION_ID_RE.search(block)
    version_id = version_match.group(1).strip() if version_match else ""

    message_match = MESSAGE_RE.search(block)
    message = message_match.group(1).strip() if message_match else ""
    # Strip a single layer of surrounding YAML quotes and keep the first line.
    message = message.strip("'\"").splitlines()[0] if message else ""
    description = message[:117] + "..." if len(message) > 120 else message

    return rule_id, version_id, description


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise UpdateError(f"could not read {path.name}: {exc}") from exc


def load_exclusions() -> dict[str, dict]:
    """Load the human-maintained exclusions.toml (id -> {status, pr, reason})."""
    if not EXCLUSIONS_TOML.exists():
        print(f"  note: {EXCLUSIONS_TOML.name} not found — treating all rules as new")
        return {}
    try:
        data = tomllib.loads(EXCLUSIONS_TOML.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise UpdateError(f"could not read {EXCLUSIONS_TOML.name}: {exc}") from exc
    return data.get("rules", {})


def render_status(entry: dict | None) -> str:
    """Render the rule-status column from an exclusions.toml entry."""
    if entry is None:
        return "`new`"
    status = entry.get("status", "new")
    pr = entry.get("pr", "TBD")
    if status in ("excluded", "active"):
        return f"`{status}` — PR#{pr}"
    return f"`{status}`"


def render_doc(
    *,
    today: str,
    version: str,
    total: int,
    active: int,
    excluded: int,
    new: int,
    rows: list[tuple[str, str, str, str]],
) -> str:
    """Render EXCLUSIONS.md (goal B) — decided rules plus pending new rules."""
    lines = [
        "# Semgrep vendored-rules tracking",
        "",
        "<!-- GENERATED by tools/semgrep/update.py — do not edit by hand. -->",
        "",
        f"- **Snapshot updated:** {today}",
        f"- **Semgrep version:** {version}",
        f"- **Total rules in snapshot:** {total}",
        f"- **Active:** {active} &nbsp;|&nbsp; **Excluded:** {excluded}"
        f" &nbsp;|&nbsp; **New (awaiting triage):** {new}",
        "",
        "This table lists rules with a recorded human decision (`active`/`excluded`)"
        " plus rules that are new since the last snapshot and await triage. The"
        f" other {total - len(rows)} rules are implicitly active. Edit"
        " `exclusions.toml` to change a decision, then run"
        " `mise run semgrep:update`.",
        "",
        "| rule-id | rule-description | rule-status | rule-updated |",
        "| ------- | ---------------- | ----------- | ------------ |",
    ]
    for rule_id, description, status, updated in rows:
        desc = description.replace("|", "\\|") or "—"
        lines.append(f"| `{rule_id}` | {desc} | {status} | {updated} |")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    try:
        raw = download_ruleset()
        header, blocks = split_rules(raw)

        prior_state = load_json(STATE_FILE)
        exclusions = load_exclusions()
        today = date.today().isoformat()

        # On the first run there is no prior state, so the snapshot *is* the
        # baseline — treat every rule as established, not "new". Flagging all
        # ~3100 rules as new would make EXCLUSIONS.md unreadable (RFC goal B).
        # "New" is a drift signal reserved for rules that appear on later runs.
        is_bootstrap = not prior_state

        new_state: dict[str, dict] = {}
        active_blocks: list[str] = []
        doc_rows: list[tuple[str, str, str, str]] = []
        counts = {"active": 0, "excluded": 0, "new": 0, "changed": 0}
        seen_ids: set[str] = set()

        for block in blocks:
            rule_id, version_id, description = parse_block(block)
            seen_ids.add(rule_id)

            # Derive the "last changed" date from version_id drift.
            prior = prior_state.get(rule_id)
            if prior is None:
                updated = today
            elif prior.get("version_id") != version_id:
                updated = today
                counts["changed"] += 1
            else:
                updated = prior.get("updated", today)
            new_state[rule_id] = {"version_id": version_id, "updated": updated}

            entry = exclusions.get(rule_id)
            is_excluded = entry is not None and entry.get("status") == "excluded"

            if is_excluded:
                counts["excluded"] += 1
            else:
                active_blocks.append(block)
                counts["active"] += 1

            # The doc lists decided rules (any exclusions.toml entry) plus new
            # rules (appeared since the last snapshot and awaiting a decision).
            if entry is not None:
                doc_rows.append((rule_id, description, render_status(entry), updated))
            elif prior is None and not is_bootstrap:
                counts["new"] += 1
                doc_rows.append((rule_id, description, render_status(None), updated))

        removed = sorted(set(prior_state) - seen_ids)

        # Warn about exclusions.toml entries that no longer match any rule.
        stale = sorted(set(exclusions) - seen_ids)

        # Write outputs only after all parsing succeeded.
        active_text = GENERATED_HEADER + header + "".join(active_blocks)
        ACTIVE_FILE.write_text(active_text, encoding="utf-8")
        STATE_FILE.write_text(
            json.dumps(new_state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        doc_rows.sort(key=lambda r: r[0])
        EXCLUSIONS_DOC.write_text(
            render_doc(
                today=today,
                version=semgrep_version(),
                total=len(blocks),
                active=counts["active"],
                excluded=counts["excluded"],
                new=counts["new"],
                rows=doc_rows,
            ),
            encoding="utf-8",
        )
    except UpdateError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(
        f"Wrote {ACTIVE_FILE.relative_to(ROOT)}"
        f" ({counts['active']} active, {counts['excluded']} excluded of {len(blocks)})"
    )
    print(
        f"Summary: {counts['new']} new (need triage),"
        f" {counts['excluded']} excluded,"
        f" {counts['changed']} changed,"
        f" {len(removed)} removed"
    )
    if counts["new"]:
        print(f"  triage the {counts['new']} new rule(s) in {EXCLUSIONS_DOC.name}")
    if removed:
        print(f"  removed upstream: {', '.join(removed)}")
    if stale:
        print(
            f"  warning: exclusions.toml lists {len(stale)} unknown rule(s): {', '.join(stale)}"
        )
    print(
        "Next: run `mise run security:semgrep` to verify the active file scans clean."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
