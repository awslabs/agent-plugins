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

A rule is dropped only when a human lists it explicitly in ``exclusions.toml``
with ``status = "excluded"``. Nothing is excluded implicitly — so a rule that
appears in a future ``r/all`` can never be silently removed; it surfaces as
``new`` for triage. When an excluded rule later disappears upstream, its now-
orphaned ``exclusions.toml`` entry is reported (console + a "Removed upstream"
section in ``EXCLUSIONS.md``) as safe to prune, rather than deleted
automatically.

Run manually via ``mise run semgrep:update`` (``uv run tools/semgrep/update.py``).
The generated files are script-owned; hand edits are lost on the next run. Only
``exclusions.toml`` is human-edited.

This script emits both generated files in exactly the format the repo's dprint
config produces, so ``dprint fmt`` leaves them untouched and neither needs a
dprint exclude (``dprint.json`` is strict JSON with no comments, so the
rationale lives here):

* ``EXCLUSIONS.md`` — ``render_table`` column-pads the markdown table the same
  way the dprint markdown plugin does.
* ``rule-state.json`` — ``json.dumps(indent=2, sort_keys=True)`` matches
  dprint's JSON style.

Both still sit in the pre-commit ``exclude`` because content hooks
(check-added-large-files, detect-private-key, whitespace fixers) would otherwise
act on them; ``r-all.active.yaml`` is excluded in ``.semgrepignore`` (self-match)
and the gitleaks allowlist (it contains secret-detection regexes).
"""

from __future__ import annotations

import json
import re
import sys
import tomllib
import urllib.error
import urllib.parse
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
# The rule's canonical registry source. Anchored on ": " so it never matches the
# adjacent "source-rule-url:" key. A rule with source "https://semgrep.dev/r/None"
# has no published registry entry (see the [auto_exclude] policy).
SOURCE_RE = re.compile(r"^\s+source: (\S+)\s*$", re.MULTILINE)

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


def sanitize_description(text: str) -> str:
    """Render untrusted rule text as inert markdown-table content.

    Escapes HTML angle brackets (so payloads like ``<img src=x onerror=...>``
    become visible text, not markup — MD045/no-alt-text and any rendered XSS),
    backticks (so inline code can't break out), and the pipe that would
    otherwise split a table cell. Newlines are already stripped by the caller.
    """
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("`", "\\`")
        .replace("|", "\\|")
    )


def parse_block(block: str) -> tuple[str, str, str, str]:
    """Extract (rule_id, version_id, description, source) from a rule block."""
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
    message = message[:117] + "..." if len(message) > 120 else message
    # Neutralize rule-supplied text before it lands in EXCLUSIONS.md. Rule
    # messages are untrusted (the r/all feed carries probe rules whose messages
    # are XSS/markup payloads, e.g. "<img src=x onerror=...>"); render them as
    # inert text so they can't inject active markup or break the markdown table.
    description = sanitize_description(message)

    source_match = SOURCE_RE.search(block)
    source = source_match.group(1).strip() if source_match else ""

    return rule_id, version_id, description, source


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise UpdateError(f"could not read {path.name}: {exc}") from exc


def load_toml() -> dict:
    """Load and parse exclusions.toml, or return {} if absent."""
    if not EXCLUSIONS_TOML.exists():
        print(f"  note: {EXCLUSIONS_TOML.name} not found — treating all rules as new")
        return {}
    try:
        return tomllib.loads(EXCLUSIONS_TOML.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise UpdateError(f"could not read {EXCLUSIONS_TOML.name}: {exc}") from exc


def load_exclusions(data: dict) -> dict[str, dict]:
    """Per-rule decisions ([rules."id"] -> {status, pr, reason})."""
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
    removed_rows: list[tuple[str, str, str]],
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
        + f" &nbsp;|&nbsp; **New (awaiting triage):** {new}",
        "",
        "This table lists rules with a recorded decision plus rules new since the"
        + f" last snapshot that await triage. The other {total - len(rows)} rules"
        + " are implicitly active. Edit `exclusions.toml` to change a decision,"
        + " then run `mise run semgrep:update`.",
        "",
        "**rule-status values:**",
        "",
        "- `excluded` — removed from the active ruleset by an explicit"
        + " `[rules.\"id\"]` entry in `exclusions.toml`; the PR# is where that"
        + " decision was made. Every exclusion is listed individually — nothing"
        + " is dropped implicitly, so a new upstream rule can never be silently"
        + " excluded (it appears as `new` for triage instead).",
        "- `active` — present in the ruleset but explicitly recorded in"
        + " `exclusions.toml` (a deliberate keep decision).",
        "- `new` — present in the snapshot with no recorded decision yet; triage"
        + " it into `exclusions.toml`.",
        "",
    ]
    lines.extend(render_table(rows))
    lines.append("")

    if removed_rows:
        lines.extend(
            [
                "## Removed upstream (safe to prune)",
                "",
                "These `exclusions.toml` entries no longer match any rule in the"
                + " current `r/all` snapshot — the rule was removed upstream. The"
                + " entry is harmless but stale; delete it from `exclusions.toml`"
                + " when convenient.",
                "",
                "| rule-id | last-known-status | reason |",
                "| ------- | ----------------- | ------ |",
            ]
        )
        for rule_id, reason, status in sorted(removed_rows):
            safe_reason = sanitize_description(reason) or "—"
            lines.append(f"| `{rule_id}` | {status} | {safe_reason} |")
        lines.append("")

    return "\n".join(lines)


def render_table(rows: list[tuple[str, str, str, str]]) -> list[str]:
    """Render the tracking table with dprint-aligned columns.

    Emits the same column-padded GitHub table that the dprint markdown plugin
    produces (each cell space-padded to the widest cell in its column, delimiter
    dashes matching that width, minimum 3), so ``dprint fmt`` leaves the
    generated file untouched and it needs no formatter exclude. Widths are by
    code-point count, matching dprint for the ASCII-dominant, already-sanitized
    cell values; a rule description with wide glyphs is the only case that could
    drift, and ``sanitize_description`` plus the build's ``fmt:check`` guard it.
    """
    header = ("rule-id", "rule-description", "rule-status", "rule-updated")
    cells = [header] + [
        (f"`{rule_id}`", description or "—", status, updated)
        for rule_id, description, status, updated in rows
    ]
    widths = [max(len(row[c]) for row in cells) for c in range(len(header))]

    def fmt(row: tuple[str, ...]) -> str:
        return "| " + " | ".join(v.ljust(widths[c]) for c, v in enumerate(row)) + " |"

    delimiter = "| " + " | ".join("-" * w for w in widths) + " |"
    return [fmt(header), delimiter, *(fmt(row) for row in cells[1:])]


def main() -> int:
    try:
        raw = download_ruleset()
        header, blocks = split_rules(raw)

        prior_state = load_json(STATE_FILE)
        toml_data = load_toml()
        exclusions = load_exclusions(toml_data)
        today = date.today().isoformat()

        # On the first run there is no prior state, so the snapshot *is* the
        # baseline — treat every rule as established, not "new". Flagging all
        # ~3100 rules as new would make EXCLUSIONS.md unreadable (RFC goal B).
        # "New" is a drift signal reserved for rules that appear on later runs.
        is_bootstrap = not prior_state

        new_state: dict[str, dict] = {}
        active_blocks: list[tuple[str, str]] = []
        doc_rows: list[tuple[str, str, str, str]] = []
        counts = {"active": 0, "excluded": 0, "new": 0, "changed": 0}
        seen_ids: set[str] = set()

        for block in blocks:
            rule_id, version_id, description, _source = parse_block(block)
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

            # A rule is excluded only when a human listed it explicitly in
            # exclusions.toml with status="excluded". Nothing is dropped
            # implicitly, so a new upstream rule can never silently disappear —
            # it surfaces as `new` for triage.
            entry = exclusions.get(rule_id)
            if entry is not None and entry.get("status") == "excluded":
                counts["excluded"] += 1
            else:
                active_blocks.append((rule_id, block))
                counts["active"] += 1

            # The doc lists rules with an explicit decision plus new rules
            # (appeared since the last snapshot and awaiting a decision).
            if entry is not None:
                doc_rows.append((rule_id, description, render_status(entry), updated))
            elif prior is None and not is_bootstrap:
                counts["new"] += 1
                doc_rows.append((rule_id, description, render_status(None), updated))

        removed = sorted(set(prior_state) - seen_ids)

        # exclusions.toml entries that no longer match any rule in the snapshot:
        # the rule was removed upstream, so the entry is safe to prune. Surfaced
        # both in the console and in a doc section (not auto-deleted).
        stale = sorted(set(exclusions) - seen_ids)

        # Write outputs only after all parsing succeeded. Sort active rule blocks
        # by id so the output is deterministic: the registry serves r/all in a
        # nondeterministic order, so without this every regeneration would emit a
        # spurious full-file diff even when no rule actually changed. Sorting
        # makes real drift the only thing that shows up in git.
        active_blocks.sort(key=lambda rb: rb[0])
        active_text = GENERATED_HEADER + header + "".join(b for _, b in active_blocks)
        ACTIVE_FILE.write_text(active_text, encoding="utf-8")
        STATE_FILE.write_text(
            json.dumps(new_state, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        # Collapse rows that share a rule-id to one entry. The r/all feed reuses
        # some ids across duplicate blocks (e.g. the bbp probe rules), which is
        # meaningless in a human tracking table; the active file and rule-state
        # already handle the blocks/keys directly.
        deduped_rows = list({row[0]: row for row in doc_rows}.values())
        deduped_rows.sort(key=lambda r: r[0])
        # Orphaned exclusions: listed in exclusions.toml but gone from the
        # snapshot (removed upstream). Surface them in the doc as safe-to-prune.
        removed_rows = [
            (rule_id, exclusions[rule_id].get("reason", ""), render_status(exclusions[rule_id]))
            for rule_id in stale
        ]
        EXCLUSIONS_DOC.write_text(
            render_doc(
                today=today,
                version=semgrep_version(),
                total=len(blocks),
                active=counts["active"],
                excluded=counts["excluded"],
                new=counts["new"],
                rows=deduped_rows,
                removed_rows=removed_rows,
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
            f"  {len(stale)} exclusions.toml entr(y/ies) no longer match any rule"
            f" (removed upstream, safe to prune): {', '.join(stale)}"
        )
    print(
        "Next: run `mise run security:semgrep` to verify the active file scans clean."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
