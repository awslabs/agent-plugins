#!/usr/bin/env python3
"""
Phase 4: Traceability Verification Script

Deterministic verification that all business rules (captured disposition from
traceability.yaml) and requirements (REQ-* from requirements.md) are referenced
in chapters 1-8 of the generated microservice specification files.

The search is restricted to sections 1 through 8 of each specification file -
any content from section 9 onward (including traceability matrices and
appendices) is excluded to avoid false positives.

Produces a self-contained HTML dashboard showing implementation status.

Usage:
    python verify-traceability.py \\
        --inputs-dir inputs/spec \\
        --specs-dir outputs/microservices \\
        --output traceability-dashboard.html
"""

import argparse
import glob
import html
import os
import re
import sys
from collections import defaultdict  # noqa: F401
from datetime import datetime, timezone

import yaml


# ---------------------------------------------------------------------------
# 1. Extraction helpers
# ---------------------------------------------------------------------------

def discover_functions(inputs_dir: str) -> list[str]:
    """Return sorted list of business-function directory names."""
    functions = []
    for entry in sorted(os.listdir(inputs_dir)):
        full = os.path.join(inputs_dir, entry)
        if os.path.isdir(full) and not entry.startswith("."):
            functions.append(entry)
    return functions


def extract_rules(rule_file: str) -> list[dict]:
    """
    Parse traceability.yaml and return rules with disposition
    'captured'.

    Each returned dict has keys:
        rule_id, disposition, program, rule_text_summary, reference
    """
    with open(rule_file, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)

    if not data or "rules" not in data:
        return []

    results = []
    for rule in data["rules"]:
        disposition = rule.get("disposition", "")
        if disposition == "captured":
            results.append({
                "rule_id": rule.get("rule_id", ""),
                "disposition": disposition,
                "program": rule.get("program", ""),
                "rule_text_summary": rule.get("rule_text_summary", ""),
                "reference": rule.get("reference", ""),
            })
    return results


_REQ_PATTERN = re.compile(r"\b(REQ-[A-Z0-9]+-\d+)\b")


def extract_requirements(req_file: str) -> list[dict]:
    """
    Parse requirements.md and return every REQ-* identifier with its
    full requirement description text.

    Each returned dict has keys:
        req_id, text (the full requirement description)
    """
    with open(req_file, "r", encoding="utf-8") as fh:
        content = fh.read()

    # Split into lines for processing
    lines = content.splitlines()

    seen = set()
    results = []
    for i, line in enumerate(lines):
        for match in _REQ_PATTERN.finditer(line):
            req_id = match.group(1)
            if req_id not in seen:
                seen.add(req_id)
                # Capture the full requirement text: the line containing the
                # REQ-* identifier plus any continuation lines that follow
                # (until the next blank line, next REQ-*, or next heading).
                req_lines = [line.strip()]
                for j in range(i + 1, len(lines)):
                    next_line = lines[j].strip()
                    # Stop at blank line, next requirement, or heading
                    if (not next_line
                            or _REQ_PATTERN.search(next_line)
                            or next_line.startswith("#")):
                        break
                    req_lines.append(next_line)
                full_text = " ".join(req_lines)
                results.append({"req_id": req_id, "text": full_text})
    return results


# ---------------------------------------------------------------------------
# 2. Specification scanning
# ---------------------------------------------------------------------------

_APPENDIX_PATTERN = re.compile(
    r"^## (?:Appendix|APPENDIX)",
    re.MULTILINE,
)

_SECTION_9_PATTERN = re.compile(
    r"^## 9\.",
    re.MULTILINE,
)


def _extract_chapters_1_to_8(content: str) -> str:
    """Extract only chapters 1–8 from a specification file.

    Strips everything from the first occurrence of '## 9.' or
    '## Appendix' onward.  This ensures that traceability matrices,
    reference dumps, and appendices do not produce false positives.
    """
    # Find the earliest cut point
    cut_pos = len(content)

    match_s9 = _SECTION_9_PATTERN.search(content)
    if match_s9:
        cut_pos = min(cut_pos, match_s9.start())

    match_app = _APPENDIX_PATTERN.search(content)
    if match_app:
        cut_pos = min(cut_pos, match_app.start())

    return content[:cut_pos]


def load_spec_contents(specs_dir: str) -> dict[str, str]:
    """
    Read all *-specification.md files from specs_dir.
    Returns {filename: content} restricted to chapters 1–8 only.
    """
    specs = {}
    pattern = os.path.join(specs_dir, "*-specification.md")
    for path in sorted(glob.glob(pattern)):
        fname = os.path.basename(path)
        with open(path, "r", encoding="utf-8") as fh:
            specs[fname] = _extract_chapters_1_to_8(fh.read())
    return specs


def find_identifier_in_specs(
    identifier: str, specs: dict[str, str]
) -> list[dict]:
    """Return list of {filename, sections} dicts for specs containing the identifier.

    For each spec file where the identifier is found, determines which
    section heading(s) (## N. ...) contain the match.
    """
    _SECTION_HEADING = re.compile(r"^(## \d+\..+)$", re.MULTILINE)

    found_in = []
    for fname, content in specs.items():
        if identifier not in content:
            continue

        # Determine which section(s) contain the identifier
        # Build a list of (position, heading_text) for all section headings
        headings = []
        for m in _SECTION_HEADING.finditer(content):
            headings.append((m.start(), m.group(1).strip()))

        # Find all positions of the identifier in the content
        sections_found = set()
        start = 0
        while True:
            pos = content.find(identifier, start)
            if pos == -1:
                break
            # Find which section this position belongs to
            section_name = "(before first section)"
            for i, (hpos, htxt) in enumerate(headings):
                if hpos > pos:
                    break
                section_name = htxt
            sections_found.add(section_name)
            start = pos + len(identifier)

        found_in.append({
            "filename": fname,
            "sections": sorted(sections_found),
        })
    return found_in


# ---------------------------------------------------------------------------
# 3. Orchestration
# ---------------------------------------------------------------------------

def run_verification(inputs_dir: str, specs_dir: str) -> dict:
    """
    Main verification logic.  Returns a result dict with structure:

    {
        "generated_at": str,
        "inputs_dir": str,
        "specs_dir": str,
        "spec_files": [str],
        "functions": {
            "<FunctionName>": {
                "rules": [
                    {
                        "rule_id": str,
                        "disposition": str,
                        "program": str,
                        "rule_text_summary": str,
                        "reference": str,
                        "status": "implemented" | "missing",
                        "found_in": [str]
                    }
                ],
                "requirements": [
                    {
                        "req_id": str,
                        "text": str,
                        "status": "implemented" | "missing",
                        "found_in": [str]
                    }
                ]
            }
        },
        "summary": {
            "total_rules": int,
            "implemented_rules": int,
            "missing_rules": int,
            "total_requirements": int,
            "implemented_requirements": int,
            "missing_requirements": int,
            "by_function": {
                "<FunctionName>": {
                    "rules_total": int,
                    "rules_implemented": int,
                    "rules_missing": int,
                    "reqs_total": int,
                    "reqs_implemented": int,
                    "reqs_missing": int,
                }
            }
        }
    }
    """
    specs = load_spec_contents(specs_dir)
    functions = discover_functions(inputs_dir)

    result = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "inputs_dir": inputs_dir,
        "specs_dir": specs_dir,
        "spec_files": sorted(specs.keys()),
        "functions": {},
        "summary": {
            "total_rules": 0,
            "implemented_rules": 0,
            "missing_rules": 0,
            "total_requirements": 0,
            "implemented_requirements": 0,
            "missing_requirements": 0,
            "by_function": {},
        },
    }

    for func_name in functions:
        func_dir = os.path.join(inputs_dir, func_name)
        func_result = {"rules": [], "requirements": []}

        # --- Rules (captured disposition from traceability.yaml) ---
        rule_file = os.path.join(func_dir, "traceability.yaml")
        if os.path.isfile(rule_file):
            rules = extract_rules(rule_file)
            for rule in rules:
                found_in = find_identifier_in_specs(rule["rule_id"], specs)
                rule["status"] = "implemented" if found_in else "missing"
                rule["found_in"] = found_in
                func_result["rules"].append(rule)

        # --- Requirements ---
        req_file = os.path.join(func_dir, "requirements.md")
        if os.path.isfile(req_file):
            reqs = extract_requirements(req_file)
            for req in reqs:
                found_in = find_identifier_in_specs(req["req_id"], specs)
                req["status"] = "implemented" if found_in else "missing"
                req["found_in"] = found_in  # list of {filename, sections}
                func_result["requirements"].append(req)

        result["functions"][func_name] = func_result

        # --- Per-function summary ---
        r_total = len(func_result["rules"])
        r_impl = sum(1 for r in func_result["rules"] if r["status"] == "implemented")
        q_total = len(func_result["requirements"])
        q_impl = sum(1 for r in func_result["requirements"] if r["status"] == "implemented")

        result["summary"]["total_rules"] += r_total
        result["summary"]["implemented_rules"] += r_impl
        result["summary"]["total_requirements"] += q_total
        result["summary"]["implemented_requirements"] += q_impl
        result["summary"]["by_function"][func_name] = {
            "rules_total": r_total,
            "rules_implemented": r_impl,
            "rules_missing": r_total - r_impl,
            "reqs_total": q_total,
            "reqs_implemented": q_impl,
            "reqs_missing": q_total - q_impl,
        }

    result["summary"]["missing_rules"] = (
        result["summary"]["total_rules"] - result["summary"]["implemented_rules"]
    )
    result["summary"]["missing_requirements"] = (
        result["summary"]["total_requirements"]
        - result["summary"]["implemented_requirements"]
    )

    return result


# ---------------------------------------------------------------------------
# 4. HTML dashboard generation
# ---------------------------------------------------------------------------

def _pct(num: int, den: int) -> str:
    if den == 0:
        return "N/A"
    return f"{num / den * 100:.1f}%"


def _status_class(status: str) -> str:
    return "implemented" if status == "implemented" else "missing"


def generate_html(result: dict) -> str:
    """Produce a self-contained HTML dashboard string."""
    s = result["summary"]
    gen_time = result["generated_at"]

    rules_pct = _pct(s["implemented_rules"], s["total_rules"])
    reqs_pct = _pct(s["implemented_requirements"], s["total_requirements"])
    overall_total = s["total_rules"] + s["total_requirements"]
    overall_impl = s["implemented_rules"] + s["implemented_requirements"]
    overall_pct = _pct(overall_impl, overall_total)

    # Build per-function rows for summary table
    func_rows = ""
    for func_name in sorted(result["functions"].keys()):
        fs = s["by_function"][func_name]
        r_pct = _pct(fs["rules_implemented"], fs["rules_total"])
        q_pct = _pct(fs["reqs_implemented"], fs["reqs_total"])
        func_rows += f"""
        <tr>
          <td><a href="#{html.escape(func_name)}">{html.escape(func_name)}</a></td>
          <td>{fs["rules_implemented"]}/{fs["rules_total"]} ({r_pct})</td>
          <td>{fs["reqs_implemented"]}/{fs["reqs_total"]} ({q_pct})</td>
        </tr>"""

    # Build per-function detail sections
    detail_sections = ""
    for func_name in sorted(result["functions"].keys()):
        func = result["functions"][func_name]

        # Rules table
        rule_rows = ""
        for rule in func["rules"]:
            sc = _status_class(rule["status"])
            if rule["found_in"]:
                found_parts = []
                for entry in rule["found_in"]:
                    fname = entry["filename"]
                    sections = entry["sections"]
                    sections_str = "; ".join(sections)
                    found_parts.append(
                        f"<strong>{html.escape(fname)}</strong>"
                        f"<br><em>{html.escape(sections_str)}</em>"
                    )
                found_html = "<br>".join(found_parts)
            else:
                found_html = "—"
            rule_rows += f"""
            <tr class="{sc}">
              <td class="mono">{html.escape(rule["rule_id"])}</td>
              <td>{html.escape(rule.get("rule_text_summary", ""))}</td>
              <td>{html.escape(rule.get("program", ""))}</td>
              <td class="status-cell"><span class="badge {sc}">{rule["status"].upper()}</span></td>
              <td class="small">{found_html}</td>
            </tr>"""

        # Requirements table
        req_rows = ""
        for req in func["requirements"]:
            sc = _status_class(req["status"])
            if req["found_in"]:
                found_parts = []
                for entry in req["found_in"]:
                    fname = entry["filename"]
                    sections = entry["sections"]
                    sections_str = "; ".join(sections)
                    found_parts.append(
                        f"<strong>{html.escape(fname)}</strong>"
                        f"<br><em>{html.escape(sections_str)}</em>"
                    )
                found_html = "<br>".join(found_parts)
            else:
                found_html = "—"
            full_text = req["text"]
            req_rows += f"""
            <tr class="{sc}">
              <td class="mono">{html.escape(req["req_id"])}</td>
              <td>{html.escape(full_text)}</td>
              <td class="status-cell"><span class="badge {sc}">{req["status"].upper()}</span></td>
              <td class="small">{found_html}</td>
            </tr>"""

        detail_sections += f"""
    <section id="{html.escape(func_name)}">
      <h2>{html.escape(func_name)}</h2>

      <h3>Business Rules (captured)</h3>
      {"<p class='empty'>No captured rules found for this function.</p>" if not rule_rows else f'''
      <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th style="min-width:130px">Rule ID</th>
            <th>Rule Name</th>
            <th>Program</th>
            <th>Status</th>
            <th style="min-width:200px">Found In (File &amp; Section)</th>
          </tr>
        </thead>
        <tbody>{rule_rows}
        </tbody>
      </table>
      </div>'''}

      <h3>Requirements</h3>
      {"<p class='empty'>No REQ-* identifiers found for this function.</p>" if not req_rows else f'''
      <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th style="min-width:130px">REQ ID</th>
            <th>Requirement Description</th>
            <th>Status</th>
            <th style="min-width:200px">Found In (File &amp; Section)</th>
          </tr>
        </thead>
        <tbody>{req_rows}
        </tbody>
      </table>
      </div>'''}
    </section>
    <hr>"""

    # Spec files list
    spec_list = ""
    for sf in result["spec_files"]:
        spec_list += f"<li>{html.escape(sf)}</li>\n"
    if not spec_list:
        spec_list = "<li><em>No specification files found</em></li>"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Traceability Verification Dashboard</title>
<style>
  :root {{
    --green: #22c55e; --green-bg: #f0fdf4; --green-border: #86efac;
    --red: #ef4444; --red-bg: #fef2f2; --red-border: #fca5a5;
    --blue: #3b82f6; --gray: #6b7280; --dark: #1f2937;
    --bg: #f9fafb; --card-bg: #ffffff;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: var(--bg); color: var(--dark); line-height: 1.6;
    padding: 2rem; max-width: 1400px; margin: 0 auto;
  }}
  h1 {{ font-size: 1.8rem; margin-bottom: 0.25rem; }}
  h2 {{ font-size: 1.4rem; margin: 1.5rem 0 0.75rem; color: var(--dark); }}
  h3 {{ font-size: 1.1rem; margin: 1rem 0 0.5rem; color: var(--gray); }}
  .subtitle {{ color: var(--gray); margin-bottom: 1.5rem; font-size: 0.9rem; }}
  .cards {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1rem; margin-bottom: 2rem; }}
  .card {{
    background: var(--card-bg); border-radius: 8px; padding: 1.25rem;
    box-shadow: 0 1px 3px rgba(0,0,0,0.1); border-left: 4px solid var(--blue);
  }}
  .card.green {{ border-left-color: var(--green); }}
  .card.red {{ border-left-color: var(--red); }}
  .card .label {{ font-size: 0.8rem; color: var(--gray); text-transform: uppercase; letter-spacing: 0.05em; }}
  .card .value {{ font-size: 2rem; font-weight: 700; }}
  .card .detail {{ font-size: 0.85rem; color: var(--gray); }}
  table {{ width: 100%; border-collapse: collapse; font-size: 0.85rem; }}
  th {{ background: #f3f4f6; text-align: left; padding: 0.6rem 0.75rem; font-weight: 600; position: sticky; top: 0; }}
  td {{ padding: 0.5rem 0.75rem; border-bottom: 1px solid #e5e7eb; vertical-align: top; }}
  tr.missing {{ background: var(--red-bg); }}
  tr.implemented {{ background: var(--green-bg); }}
  .badge {{
    display: inline-block; padding: 0.15rem 0.5rem; border-radius: 9999px;
    font-size: 0.7rem; font-weight: 600; text-transform: uppercase;
  }}
  .badge.implemented {{ background: var(--green-bg); color: #166534; border: 1px solid var(--green-border); }}
  .badge.missing {{ background: var(--red-bg); color: #991b1b; border: 1px solid var(--red-border); }}
  .mono {{ font-family: "SF Mono", "Fira Code", monospace; font-size: 0.8rem; }}
  .small {{ font-size: 0.75rem; }}
  .status-cell {{ text-align: center; }}
  .table-wrap {{ overflow-x: auto; margin-bottom: 1rem; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }}
  .empty {{ color: var(--gray); font-style: italic; margin-bottom: 1rem; }}
  hr {{ border: none; border-top: 1px solid #e5e7eb; margin: 2rem 0; }}
  section {{ margin-bottom: 1rem; }}
  a {{ color: var(--blue); text-decoration: none; }}
  a:hover {{ text-decoration: underline; }}
  .spec-list {{ list-style: disc; margin-left: 1.5rem; font-size: 0.85rem; color: var(--gray); }}
  .filter-bar {{ margin-bottom: 1rem; display: flex; gap: 0.5rem; flex-wrap: wrap; }}
  .filter-btn {{
    padding: 0.35rem 0.75rem; border-radius: 6px; border: 1px solid #d1d5db;
    background: white; cursor: pointer; font-size: 0.8rem; transition: all 0.15s;
  }}
  .filter-btn:hover {{ background: #f3f4f6; }}
  .filter-btn.active {{ background: var(--blue); color: white; border-color: var(--blue); }}
  .progress-bar {{ height: 8px; background: #e5e7eb; border-radius: 4px; overflow: hidden; margin-top: 0.25rem; }}
  .progress-fill {{ height: 100%; border-radius: 4px; transition: width 0.3s; }}
  .progress-fill.green {{ background: var(--green); }}
  .progress-fill.red {{ background: var(--red); }}
</style>
</head>
<body>

<h1>Traceability Verification Dashboard</h1>
<p class="subtitle">Generated {html.escape(gen_time)} &mdash; Inputs: <code>{html.escape(result["inputs_dir"])}</code> &mdash; Specs: <code>{html.escape(result["specs_dir"])}</code></p>

<!-- Summary Cards -->
<div class="cards">
  <div class="card">
    <div class="label">Business Rules Coverage</div>
    <div class="value">{rules_pct}</div>
    <div class="detail">{s["implemented_rules"]} / {s["total_rules"]} captured rules traced in chapters 1–8</div>
    <div class="progress-bar"><div class="progress-fill {"green" if s["implemented_rules"] == s["total_rules"] else "red"}" style="width:{rules_pct if s["total_rules"] > 0 else "0%"}"></div></div>
  </div>
  <div class="card">
    <div class="label">Requirements Coverage</div>
    <div class="value">{reqs_pct}</div>
    <div class="detail">{s["implemented_requirements"]} / {s["total_requirements"]} requirements traced in chapters 1–8</div>
    <div class="progress-bar"><div class="progress-fill {"green" if s["implemented_requirements"] == s["total_requirements"] else "red"}" style="width:{reqs_pct if s["total_requirements"] > 0 else "0%"}"></div></div>
  </div>
  <div class="card {"green" if s["missing_rules"] + s["missing_requirements"] == 0 else "red"}">
    <div class="label">Total Missing</div>
    <div class="value">{s["missing_rules"] + s["missing_requirements"]}</div>
    <div class="detail">{s["missing_rules"]} rules + {s["missing_requirements"]} requirements not found in chapters 1–8</div>
  </div>
</div>

<!-- Spec Files -->
<details>
  <summary style="cursor:pointer; font-weight:600; margin-bottom:0.5rem;">Specification Files Scanned ({len(result["spec_files"])})</summary>
  <ul class="spec-list">{spec_list}</ul>
</details>
<hr>

<!-- Per-Function Summary -->
<h2>Coverage by Business Function</h2>
<div class="table-wrap">
<table>
  <thead>
    <tr><th>Business Function</th><th>Rules (in chapters 1–8)</th><th>Requirements (in chapters 1–8)</th></tr>
  </thead>
  <tbody>{func_rows}
  </tbody>
</table>
</div>
<hr>

<!-- Filter Bar -->
<div class="filter-bar">
  <button class="filter-btn active" onclick="filterRows('all')">Show All</button>
  <button class="filter-btn" onclick="filterRows('missing')">Missing Only</button>
  <button class="filter-btn" onclick="filterRows('implemented')">Implemented Only</button>
</div>

<!-- Detail Sections -->
{detail_sections}

<script>
function filterRows(filter) {{
  document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
  event.target.classList.add('active');
  document.querySelectorAll('tbody tr').forEach(row => {{
    if (filter === 'all') {{ row.style.display = ''; return; }}
    row.style.display = row.classList.contains(filter) ? '' : 'none';
  }});
}}
</script>

</body>
</html>"""


# ---------------------------------------------------------------------------
# 5. CLI entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Verify traceability of business rules (captured from "
                    "traceability.yaml) and requirements (REQ-* identifiers) "
                    "in chapters 1-8 of microservice specifications."
    )
    parser.add_argument(
        "--inputs-dir",
        default="inputs/spec",
        help="Path to the inputs/spec directory (default: inputs/spec)",
    )
    parser.add_argument(
        "--specs-dir",
        default="outputs/microservices",
        help="Path to the microservice specification files "
             "(default: outputs/microservices)",
    )
    parser.add_argument(
        "--output",
        default="traceability-dashboard.html",
        help="Output HTML dashboard file path "
             "(default: traceability-dashboard.html)",
    )
    args = parser.parse_args()

    # Validate paths
    if not os.path.isdir(args.inputs_dir):
        print(f"ERROR: Inputs directory not found: {args.inputs_dir}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isdir(args.specs_dir):
        print(f"ERROR: Specs directory not found: {args.specs_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Scanning inputs:  {args.inputs_dir}")
    print(f"Scanning specs:   {args.specs_dir}")

    result = run_verification(args.inputs_dir, args.specs_dir)

    # Print summary to stdout
    s = result["summary"]
    print(f"\n{'='*60}")
    print(f"TRACEABILITY VERIFICATION SUMMARY")
    print(f"{'='*60}")
    print(f"Business Rules (captured):           "
          f"{s['implemented_rules']}/{s['total_rules']} "
          f"({_pct(s['implemented_rules'], s['total_rules'])})")
    print(f"Requirements (REQ-*):                "
          f"{s['implemented_requirements']}/{s['total_requirements']} "
          f"({_pct(s['implemented_requirements'], s['total_requirements'])})")
    print(f"{'─'*60}")
    print(f"Scope: Chapters 1–8 of specification files only")
    print(f"{'='*60}")

    missing_rules = s["missing_rules"]
    missing_reqs = s["missing_requirements"]
    if missing_rules + missing_reqs > 0:
        if missing_rules > 0:
            print(f"\n⚠  {missing_rules} business rule(s) NOT found in chapters "
                  f"1–8 of any specification file.")
        if missing_reqs > 0:
            print(f"\n⚠  {missing_reqs} REQ-* identifiers NOT found in chapters "
                  f"1–8 of any specification file.")
    else:
        print(f"\n✅ All business rules and REQ-* identifiers found in "
              f"chapters 1–8 of specification files.")

    # Write HTML dashboard
    dashboard_html = generate_html(result)
    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write(dashboard_html)
    print(f"\nDashboard written to: {args.output}")

    # Exit code: 0 if all rules and requirements traced, 1 if any missing
    sys.exit(0 if s["missing_rules"] + s["missing_requirements"] == 0 else 1)


if __name__ == "__main__":
    main()
