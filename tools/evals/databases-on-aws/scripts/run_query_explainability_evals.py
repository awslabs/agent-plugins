#!/usr/bin/env python3
"""Run functional evaluations for the dsql query-plan-explainability workflow.

Executes each eval prompt via `claude -p` with the plugin loaded,
captures the stream-json transcript (which includes tool calls),
and grades assertions programmatically.

Requires a live Aurora DSQL cluster. The plugin's shipped `.mcp.json` keeps
aurora-dsql disabled by default, so supply a live config at runtime via
`--mcp-config` (e.g. `.tmp/mcp.json` — `.tmp/` is already gitignored).
"""

import argparse
import json
import os
import re
import subprocess  # nosec B404 - eval runner needs subprocess to invoke claude CLI
import sys
import time
from pathlib import Path


def run_prompt(prompt: str, plugin_dir: str, timeout: int = 300, model: str | None = None,
               mcp_config: str | None = None, max_turns: int = 40) -> dict:
    """Run a prompt via claude -p with stream-json output to capture tool calls."""
    cmd = [
        "claude", "-p", prompt,
        "--output-format", "stream-json",
        "--verbose",
        "--plugin-dir", plugin_dir,
        "--max-turns", str(max_turns),
        "--permission-mode", "bypassPermissions",
    ]
    if mcp_config:
        cmd.extend(["--mcp-config", mcp_config])
    if model:
        cmd.extend(["--model", model])

    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}

    start = time.time()
    try:
        result = subprocess.run(  # nosec B603 - cmd is built from trusted literals
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return {
            "result_text": "",
            "messages": [],
            "tool_calls": [],
            "stderr": f"Timeout after {timeout}s",
            "returncode": -1,
            "duration_seconds": timeout,
            "total_cost_usd": 0,
            "usage": {},
            "status": "timeout",
        }
    duration = time.time() - start

    status = "completed"
    if result.returncode != 0:
        status = "error"
        print(f"  WARNING: claude exited with status {result.returncode}", file=sys.stderr)
        if result.stderr:
            print(f"  stderr: {result.stderr[:300]}", file=sys.stderr)

    # Parse stream-json: one JSON object per line
    messages = []
    tool_calls = []
    result_text = ""
    total_cost = 0
    usage = {}
    malformed_lines = 0

    for line in result.stdout.strip().split("\n"):
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            malformed_lines += 1
            if malformed_lines <= 3:
                print(f"  Skipping malformed JSON line: {line[:100]}", file=sys.stderr)
            elif malformed_lines == 4:
                print("  (further malformed-JSON warnings suppressed)", file=sys.stderr)
            continue

        event_type = event.get("type", "")

        if event_type == "assistant":
            msg = event.get("message", {})
            messages.append(msg)
            for block in msg.get("content", []):
                if isinstance(block, dict):
                    if block.get("type") == "tool_use":
                        tool_calls.append({
                            "name": block.get("name", ""),
                            "id": block.get("id", ""),
                            "input": block.get("input", {}),
                        })
                    elif block.get("type") == "text":
                        result_text += block.get("text", "") + "\n"

        elif event_type == "tool_result":
            messages.append(event)

        elif event_type == "result":
            result_text = event.get("result", result_text)
            total_cost = event.get("total_cost_usd", 0)
            usage = event.get("usage", {})

    if malformed_lines > 0:
        print(f"  Total malformed JSON lines skipped: {malformed_lines}", file=sys.stderr)

    return {
        "result_text": result_text,
        "messages": messages,
        "tool_calls": tool_calls,
        "stderr": result.stderr,
        "returncode": result.returncode,
        "duration_seconds": round(duration, 1),
        "total_cost_usd": total_cost,
        "usage": usage,
        "status": status,
        "malformed_lines": malformed_lines,
    }


def build_full_text(run_result: dict) -> str:
    """Build a comprehensive searchable string from all transcript content."""
    text = run_result["result_text"].lower()
    for tc in run_result["tool_calls"]:
        text += " " + json.dumps(tc).lower()
    for msg in run_result["messages"]:
        text += " " + json.dumps(msg).lower()
    return text


def check_tool_called(tool_calls: list, pattern: str) -> tuple[bool, str]:
    """Check if any tool call name matches a pattern."""
    for call in tool_calls:
        if re.search(pattern, call["name"], re.IGNORECASE):
            return True, f"Found tool call: {call['name']}"
    return False, f"No tool call matching '{pattern}' found"


def check_tool_input_contains(tool_calls: list, name_pattern: str, input_pattern: str) -> tuple[bool, str]:
    """Check if a tool call executed the given input_pattern.

    Accepts two execution paths: the MCP path (tool name matches name_pattern) and
    the psql fallback path (Bash tool invoking psql against a DSQL endpoint). For
    Bash, we require the command to look like a psql invocation against a DSQL host
    so we don't falsely credit arbitrary shell commands.
    """
    psql_to_dsql = re.compile(r"psql.*\.dsql\..*\.on\.aws", re.IGNORECASE)
    for call in tool_calls:
        input_str = json.dumps(call["input"]).lower()
        if re.search(name_pattern, call["name"], re.IGNORECASE):
            if re.search(input_pattern, input_str, re.IGNORECASE):
                return True, f"Found {call['name']} with input matching '{input_pattern}'"
        elif call["name"] == "Bash":
            command = call["input"].get("command", "")
            if psql_to_dsql.search(command) and re.search(input_pattern, command, re.IGNORECASE):
                return True, f"Found psql fallback (Bash) with input matching '{input_pattern}'"
    return False, f"No tool call matching '{name_pattern}' (or psql fallback) with input '{input_pattern}'"


def grade_eval(eval_item: dict, run_result: dict) -> dict:
    """Grade a single eval against its expectations.

    Two text variables: ``full_text`` concatenates agent output + tool inputs + messages
    (useful when you want to find evidence anywhere in the transcript), and
    ``output_text`` is only the agent's final response. Non-tool-required assertions
    should prefer ``output_text`` — otherwise a keyword that appears in the prompt or in
    a Read'd reference file gets echoed into the transcript and inflates pass rates.
    """
    full_text = build_full_text(run_result)
    output_text = (run_result.get("result_text") or "").lower()
    tool_calls = run_result["tool_calls"]
    expectations = []

    for expectation_text in eval_item.get("expectations", []):
        passed = False
        evidence = ""
        exp_lower = expectation_text.lower()

        # --- Assertion: Reads all four Workflow 8 references ---
        # Workflow 8 Phase 0 requires loading plan-interpretation, catalog-queries,
        # guc-experiments, and report-format before producing the report.
        if "reads all four" in exp_lower and "reference" in exp_lower:
            required = {
                "plan-interpretation.md",
                "catalog-queries.md",
                "guc-experiments.md",
                "report-format.md",
            }
            loaded = {
                c["input"].get("file_path", "").split("/")[-1]
                for c in tool_calls
                if c["name"] == "Read" and "references/" in c["input"].get("file_path", "")
            }
            missing = required - loaded
            if not missing:
                passed = True
                evidence = "All four Workflow 8 references loaded"
            else:
                evidence = f"Missing reference reads: {sorted(missing)}"

        # --- Assertion: Executes EXPLAIN ANALYZE VERBOSE ---
        # Requires an actual MCP tool call — transcript-text match does not count
        # because the prompt itself often mentions EXPLAIN ANALYZE.
        elif "explain analyze verbose" in exp_lower and ("executes" in exp_lower or "execute" in exp_lower):
            passed, evidence = check_tool_input_contains(
                tool_calls,
                r"(readonly_query|transact|aurora.dsql)",
                r"explain\s+analyze\s+verbose"
            )

        # --- Assertion: Extracts Query ID ---
        elif "query id" in exp_lower and ("extract" in exp_lower or "report" in exp_lower):
            if re.search(r"query.{0,20}(id|identifier).{0,5}[:=]\s*\S+", full_text):
                passed = True
                evidence = "Found Query ID extraction in output"
            elif re.search(r"(query_id|queryid|query identifier)", full_text):
                passed = True
                evidence = "Found query identifier reference"
            else:
                evidence = "No Query ID extraction found"

        # --- Assertion: Identifies estimation errors ---
        # Accept: explicit prose ("estimation error", "diverge", "mismatch"), numeric
        # "est N … actual M" comparisons, table-header layouts ("estimated rows |
        # actual rows"), or ratio annotations like "95% waste" / "Nx error".
        elif "estimation error" in exp_lower or "actual rows diverge" in exp_lower:
            if re.search(r"(estimat|actual).{0,40}(diverge|error|mismatch|underestim|overestim|\dx)", full_text):
                passed = True
                evidence = "Found estimation error analysis"
            elif re.search(r"(est|estimated).{0,10}\d+.{0,20}(actual).{0,10}\d+", full_text):
                passed = True
                evidence = "Found estimated vs actual comparison"
            elif re.search(r"estimated\s+rows\s*\|\s*actual\s+rows", full_text):
                passed = True
                evidence = "Found estimated-vs-actual table header"
            elif re.search(r"(\d+%\s*(waste|error|off)|selectivity\s*\|)", full_text):
                passed = True
                evidence = "Found selectivity/waste quantification"
            else:
                evidence = "No estimation error identification found"

        # --- Assertion: Queries pg_class ---
        # Require an actual MCP tool call. If the expectation covers BOTH pg_class AND
        # pg_stats, require both queries to have been executed.
        elif "pg_class" in exp_lower and ("quer" in exp_lower or "retriev" in exp_lower):
            passed_class, _ = check_tool_input_contains(
                tool_calls, r"(readonly_query|aurora.dsql)", r"pg_class"
            )
            if "pg_stats" in exp_lower:
                passed_stats, _ = check_tool_input_contains(
                    tool_calls, r"(readonly_query|aurora.dsql)", r"pg_stats"
                )
                passed = passed_class and passed_stats
                evidence = (
                    "Queried pg_class and pg_stats via MCP"
                    if passed
                    else f"Missing pg_class={passed_class}, pg_stats={passed_stats}"
                )
            else:
                passed = passed_class
                evidence = (
                    "Queried pg_class via MCP" if passed else "No pg_class tool call found"
                )

        # --- Assertion: Queries pg_stats ---
        elif "pg_stats" in exp_lower and ("quer" in exp_lower or "retriev" in exp_lower):
            passed, evidence = check_tool_input_contains(
                tool_calls,
                r"(readonly_query|aurora.dsql)",
                r"pg_stats"
            )

        # --- Assertion: Retrieves actual row counts via COUNT(*) ---
        elif "count(*)" in exp_lower or "actual row counts" in exp_lower:
            passed, evidence = check_tool_input_contains(
                tool_calls,
                r"(readonly_query|aurora.dsql)",
                r"count\(\*\)"
            )

        # --- Assertion: Identifies correlated predicates ---
        # Accept both terminologies the skill uses: "correlated predicate"
        # (cardinality-theory term) and "redundant predicate" (the skill's own
        # guc-experiments terminology for business-rule-derived predicates).
        # Also accept the underlying-concept phrasings (independence assumption,
        # transitive closure / business rule).
        elif "correlated predicate" in exp_lower:
            if re.search(r"(correlat|redundant).{0,20}predicate", full_text):
                passed = True
                evidence = "Found correlated/redundant predicate analysis"
            elif re.search(r"(independence assumption|selectivit.{0,20}multipl|not independent)", full_text):
                passed = True
                evidence = "Found independence assumption analysis"
            elif re.search(r"(transitive closure|business rule.{0,40}(predicate|optimizer))", full_text):
                passed = True
                evidence = "Found transitive-closure / business-rule analysis"
            else:
                evidence = "No correlated/redundant predicate identification found"

        # --- Assertion: Recommends composite index ---
        elif "composite index" in exp_lower and "recommend" in exp_lower:
            if re.search(r"(composite|compound).{0,20}index", full_text):
                passed = True
                evidence = "Found composite index recommendation"
            elif re.search(r"create index.{0,30}\(.{0,50},.{0,50}\)", full_text):
                passed = True
                evidence = "Found multi-column CREATE INDEX"
            else:
                evidence = "No composite index recommendation found"

        # --- Assertion: Diagnostic report with findings ordered by duration ---
        elif "diagnostic report" in exp_lower and "duration" in exp_lower:
            if re.search(r"finding.{0,5}1", full_text) and re.search(r"(duration|time|ms|seconds)", full_text):
                passed = True
                evidence = "Found numbered findings with duration references"
            else:
                evidence = "No duration-ordered diagnostic report found"

        # --- Assertion: Problem-evidence-recommendation structure ---
        elif "problem" in exp_lower and "evidence" in exp_lower and "recommendation" in exp_lower:
            checks = [
                re.search(r"(what we observed|problem|what was observed)", full_text),
                re.search(r"(why it happened|evidence|root cause)", full_text),
                re.search(r"(recommendation|what to do|action)", full_text),
            ]
            if all(checks):
                passed = True
                evidence = "Found problem-evidence-recommendation structure"
            else:
                evidence = f"Missing report structure elements ({sum(1 for c in checks if c)}/3 found)"

        # --- Assertion: Summary table ---
        elif "summary table" in exp_lower:
            if re.search(r"(summary|\|.{0,5}#.{0,5}\|.{0,20}finding)", full_text):
                passed = True
                evidence = "Found summary table"
            elif re.search(r"\|.{0,20}severity.{0,20}\|", full_text):
                passed = True
                evidence = "Found severity column in table"
            else:
                evidence = "No summary table found"

        # --- Assertion: Preview Only subtitle ---
        elif "preview only" in exp_lower:
            if "preview only" in full_text:
                passed = True
                evidence = "Found 'Preview Only - not for distribution'"
            else:
                evidence = "No 'Preview Only' subtitle found"

        # --- Assertion: Full Scan identification ---
        # Match against the agent's output only — eval-2-style prompts literally include
        # "full scan", so full_text would trivially pass.
        elif "full scan" in exp_lower and ("identif" in exp_lower or "explain" in exp_lower):
            if re.search(r"full scan", output_text):
                passed = True
                evidence = "Found Full Scan identification in agent output"
            elif re.search(r"(seq scan|sequential scan|btree-table)", output_text):
                passed = True
                evidence = "Found scan type identification in agent output"
            else:
                evidence = "No Full Scan identification in agent output"

        # --- Assertion: Queries pg_indexes ---
        elif "pg_indexes" in exp_lower:
            passed, evidence = check_tool_input_contains(
                tool_calls,
                r"(readonly_query|aurora.dsql)",
                r"pg_indexes"
            )

        # --- Assertion: CREATE INDEX ASYNC ---
        elif "create index async" in exp_lower:
            if re.search(r"create index async", full_text):
                passed = True
                evidence = "Found CREATE INDEX ASYNC syntax"
            else:
                evidence = "No CREATE INDEX ASYNC syntax found"

        # --- Assertion: Does NOT execute DDL or DML ---
        # Safe patterns: DML statement is ROLLBACK-wrapped (never commits). An EXPLAIN
        # alone is NOT sufficient — `EXPLAIN ANALYZE INSERT ...` still executes the
        # INSERT. Check both the MCP `transact` path and the psql fallback path.
        elif "does not" in exp_lower and ("ddl" in exp_lower or "dml" in exp_lower):
            dml_pattern = re.compile(
                r"(create table|alter table|drop table|insert into|update .+ set|delete from)",
                re.IGNORECASE,
            )
            has_ddl_dml = False
            for call in tool_calls:
                is_transact = re.search(r"transact", call["name"], re.IGNORECASE)
                is_bash_psql = call["name"] == "Bash" and re.search(
                    r"psql.*\.dsql\..*\.on\.aws", call["input"].get("command", ""), re.IGNORECASE,
                )
                if is_transact:
                    input_str = json.dumps(call["input"]).lower()
                elif is_bash_psql:
                    input_str = call["input"].get("command", "").lower()
                else:
                    continue
                if dml_pattern.search(input_str) and not re.search(r"rollback", input_str):
                    has_ddl_dml = True
                    break
            if not has_ddl_dml:
                passed = True
                evidence = "No DDL/DML execution found (correct)"
            else:
                evidence = "Found DDL/DML execution without ROLLBACK (violation)"

        # --- Assertion: Skips GUC experiments for >30s queries ---
        elif re.search(r"skip.{0,10}guc", exp_lower):
            if re.search(r"(skip|skipped).{0,30}(guc|experiment)", full_text):
                passed = True
                evidence = "Found GUC experiment skip notice"
            elif re.search(r"(exceed|over).{0,20}30.{0,10}(sec|s\b|threshold)", full_text):
                passed = True
                evidence = "Found 30-second threshold reference"
            else:
                evidence = "No GUC experiment skip found"

        # --- Assertion: Provides manual GUC testing SQL ---
        elif re.search(r"manual.{0,10}(guc|testing)", exp_lower):
            if re.search(r"set enable_(hashjoin|nestloop|mergejoin)", full_text):
                passed = True
                evidence = "Found manual GUC testing SQL"
            else:
                evidence = "No manual GUC testing SQL provided"

        # --- Assertion: Does NOT re-run query for redundant predicate testing ---
        elif re.search(r"(does not |not |no ).{0,5}re-?run", exp_lower):
            # Check that no redundant predicate test was executed
            rerun_found = False
            for call in tool_calls:
                input_str = json.dumps(call.get("input", {})).lower()
                if "redundant" in input_str or "added predicate" in input_str:
                    rerun_found = True
                    break
            if not rerun_found:
                passed = True
                evidence = "No redundant predicate re-run found (correct for >30s)"
            else:
                evidence = "Found redundant predicate re-run (should have been skipped)"

        # --- Assertion: Wraps DML in transaction with ROLLBACK ---
        # Require an actual transact call containing ROLLBACK — a prose mention
        # alone is not evidence that the agent actually wrapped the statement.
        elif "rollback" in exp_lower and ("wrap" in exp_lower or "transaction" in exp_lower):
            passed, evidence = check_tool_input_contains(
                tool_calls,
                r"transact",
                r"rollback"
            )

        # --- Assertion: Recognizes DML statement ---
        elif "recognizes" in exp_lower and "dml" in exp_lower:
            # Current policy: DML is rewritten as SELECT (UPDATE/DELETE) or rejected
            # (INSERT / pl-pgsql). Accept evidence of either: rewrite-to-SELECT, or
            # explicit rejection. Legacy "wrap in rollback" phrasing still OK for
            # backwards compatibility with older eval files.
            if re.search(r"(update|delete|dml).{0,80}(rewrit|rewrot|equivalent select|select form|select version)", output_text):
                passed = True
                evidence = "Found DML → SELECT rewrite"
            elif re.search(r"(insert|pl.?pgsql|procedural).{0,60}(reject|refus|cannot|can't|won't|decline)", output_text):
                passed = True
                evidence = "Found DML rejection"
            elif re.search(r"(insert|dml|write|modif).{0,30}(wrap|transaction|read.only|rollback)", full_text):
                passed = True
                evidence = "Found DML recognition and wrapping (legacy)"
            else:
                evidence = "No DML recognition / rewrite / rejection found"

        # --- Assertion: Uses transact tool for DML wrapping ---
        elif "transact tool" in exp_lower:
            passed, evidence = check_tool_called(tool_calls, r"transact")

        # --- Assertion: Does NOT persist INSERT ---
        # Evidence of non-persistence: an actual transact call or psql fallback
        # invocation containing ROLLBACK (prose "rollback" in agent text is not enough).
        elif re.search(r"(does not |not ).{0,10}persist", exp_lower):
            passed, _ = check_tool_input_contains(tool_calls, r"transact", r"rollback")
            evidence = (
                "Found ROLLBACK-wrapped execution (no persistence)"
                if passed
                else "No ROLLBACK-wrapped call found — INSERT may have persisted"
            )

        # --- Assertion: Detects anomalous row count ---
        # Prompt 5 contains "bizarre … Storage Lookup … 5 trillion" — so full_text would
        # always match. Check agent output only.
        elif "anomalous" in exp_lower and ("row count" in exp_lower or "value" in exp_lower):
            if re.search(r"(anomalous|impossible|physically impossible|trillion|bug)", output_text):
                passed = True
                evidence = "Found anomalous value detection in agent output"
            else:
                evidence = "No anomalous value detection in agent output"

        # --- Assertion: Flags as DSQL reporting bug ---
        elif "reporting bug" in exp_lower or "dsql bug" in exp_lower:
            if re.search(r"(reporting bug|dsql bug|potential bug|report.{0,20}(bug|issue))", output_text):
                passed = True
                evidence = "Found DSQL bug identification in agent output"
            else:
                evidence = "No DSQL bug flagging in agent output"

        # --- Assertion: Produces support request template ---
        elif "support request template" in exp_lower or "support template" in exp_lower:
            if re.search(r"support.{0,20}(request|template)", full_text):
                passed = True
                evidence = "Found support request template"
            else:
                evidence = "No support request template found"

        # --- Assertion: Support template does NOT include customer data ---
        # Isolate the support-template section of the report and scan it for values
        # that look like actual customer data leaking from the prompt (e.g. a UUID
        # or tenant-id literal passed in by the user). Presence of metadata words
        # alone is not evidence; absence of prompt-derived literals is.
        elif "not include" in exp_lower and "customer data" in exp_lower:
            template_match = re.search(
                r"(?is)support[^\n]*?(?:request|template).*?(?=\n#|\Z)",
                run_result.get("result_text", ""),
            )
            if not template_match:
                evidence = "No support template to evaluate"
            else:
                template_text = template_match.group(0)
                # Pull UUID-like literals and quoted string literals from the prompt,
                # excluding common schema / keyword words.
                prompt_literals = set(
                    re.findall(
                        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|'[^']{4,}'",
                        eval_item.get("prompt", ""),
                    )
                )
                leaked = [lit for lit in prompt_literals if lit in template_text]
                if leaked:
                    evidence = f"Support template leaks prompt literal(s): {leaked[:3]}"
                else:
                    passed = True
                    evidence = "Support template contains no prompt-derived customer data literals"

        # --- Assertion: Confirms query results are correct ---
        elif "query results are correct" in exp_lower or "results are correct" in exp_lower:
            if re.search(r"(results?.{0,20}correct|correct.{0,20}results?|does not affect.{0,20}(correctness|results))", full_text):
                passed = True
                evidence = "Found confirmation that query results are correct"
            else:
                evidence = "No confirmation of correct query results"

        # --- Assertion: Proceeds with diagnostic analysis ---
        elif "proceeds with diagnostic" in exp_lower:
            if re.search(r"(finding|diagnostic|interpret|analyz)", full_text):
                passed = True
                evidence = "Found diagnostic analysis proceeding"
            else:
                evidence = "No diagnostic analysis found after plan capture"

        # --- Assertion: Identifies most expensive nodes ---
        # Match on the agent's output — tool results carry lots of \d+\s*ms that the agent
        # may have ignored.
        elif "most expensive" in exp_lower or "expensive nodes" in exp_lower:
            if re.search(r"(most expensive|highest.{0,10}(time|duration|cost)|longest.{0,10}running|\d+\s*ms)", output_text):
                passed = True
                evidence = "Found expensive node identification in agent output"
            else:
                evidence = "No expensive node identification in agent output"

        # --- Assertion: Actionable recommendations ---
        # Keywords like "recommend", "analyze" appear in the loaded reference files; use
        # output_text to require the agent actually said something actionable.
        elif "actionable recommendation" in exp_lower:
            if re.search(r"(recommend|suggestion|action|create index|analyze|rewrite)", output_text):
                passed = True
                evidence = "Found actionable recommendations in agent output"
            else:
                evidence = "No actionable recommendations in agent output"

        # --- Assertion: Notes GUC experimentation skipped ---
        elif "notes" in exp_lower and "guc" in exp_lower and "skipped" in exp_lower:
            if re.search(r"(skip|skipped).{0,30}(guc|experiment)", full_text):
                passed = True
                evidence = "Found note about GUC experimentation being skipped"
            else:
                evidence = "No note about skipped GUC experiments"

        # --- Assertion: Includes table statistics in support template ---
        elif "table statistics" in exp_lower and "support template" in exp_lower:
            if re.search(r"(reltuples|relpages|count\(\*\))", full_text) and re.search(r"support", full_text):
                passed = True
                evidence = "Found table statistics in support template context"
            else:
                evidence = "No table statistics in support template"

        # --- Assertion: Explains why existing index was not used ---
        elif "why" in exp_lower and ("index" in exp_lower) and ("not used" in exp_lower or "insufficient" in exp_lower):
            if re.search(r"(index.{0,30}(not|wasn|unable|insufficient)|leading column|composite|filter.{0,20}not.{0,20}index)", full_text):
                passed = True
                evidence = "Found explanation of why index was not used"
            else:
                evidence = "No explanation of unused index found"

        # --- Eval 6 assertion: before/after comparison table with numeric duration delta ---
        elif "before/after" in exp_lower and ("comparison" in exp_lower or "table" in exp_lower):
            report = run_result.get("result_text", "") or ""
            # Find a markdown table with Before / After columns and at least one row carrying ms or s values
            header_re = re.compile(r"\|[^\n]*before[^\n]*after[^\n]*\|", re.IGNORECASE)
            has_header = bool(header_re.search(report))
            duration_re = re.compile(r"\d+(?:\.\d+)?\s*(?:ms|s|sec|seconds)\b", re.IGNORECASE)
            numeric_delta = bool(duration_re.search(report))
            if has_header and numeric_delta:
                passed = True
                evidence = "Before/after table present with numeric duration values"
            elif has_header:
                evidence = "Before/after table header present but no numeric duration values"
            else:
                evidence = "No before/after comparison table found"

        # --- Eval 6 assertion: comments on match vs Expected Impact ---
        elif ("observed improvement" in exp_lower or "expected impact" in exp_lower) \
                and ("matches" in exp_lower or "exceeds" in exp_lower or "falls short" in exp_lower):
            phrases = re.compile(
                r"(matches? (the )?expected|exceed(s|ed) (the )?expected|"
                r"fall(s|ing) short of expected|below expected|under expected|"
                r"as predicted|in line with expected|close to expected)",
                re.IGNORECASE,
            )
            if phrases.search(output_text):
                passed = True
                evidence = "Found explicit match-vs-expected commentary"
            else:
                evidence = "No explicit match-vs-expected commentary found"

        # --- Eval 6 assertion: proposes a next hypothesis if shortfall ---
        elif "next hypothesis" in exp_lower and ("falls short" in exp_lower or "does not declare success" in exp_lower):
            # Vacuously pass if there's no shortfall language at all; only fail if
            # the agent claimed success while results were below target.
            short_signal = re.search(r"(fell short|below expected|less than expected|under-?performed)", output_text)
            success_signal = re.search(r"(success(fully)?|as expected|matches|resolved)", output_text)
            next_hypothesis = re.search(r"(next hypothesis|investigate (further|why)|another possible cause|additional investigation)", output_text)
            if not short_signal:
                passed = True
                evidence = "No shortfall claimed; assertion vacuously satisfied"
            elif next_hypothesis:
                passed = True
                evidence = "Shortfall + next-hypothesis proposal both present"
            elif success_signal:
                evidence = "Shortfall language present but agent also claimed success without investigating"
            else:
                evidence = "Shortfall acknowledged but no next hypothesis proposed"

        # --- Eval 8 assertion: surfaces 'relation does not exist' verbatim ---
        elif "relation" in exp_lower and "does not exist" in exp_lower and "verbatim" in exp_lower:
            # Accept either the literal error text from PG, or the agent quoting it
            # (in a code block or blockquote). Reject if the agent paraphrases
            # without including the actual phrase.
            literal_re = re.compile(
                r"relation\s+[\"'`]?[a-z_][a-z0-9_]*[\"'`]?\s+does\s+not\s+exist",
                re.IGNORECASE,
            )
            if literal_re.search(output_text):
                passed = True
                evidence = "Found 'relation ... does not exist' phrase in output"
            else:
                evidence = "Agent did not surface the PG error phrase verbatim"

        # --- Eval 8 assertion: does NOT produce a fresh Diagnostic Report H1 for an un-EXPLAINable query ---
        elif ("does not produce" in exp_lower or "does NOT produce" in exp_lower) \
                and "diagnostic report" in exp_lower:
            h1_re = re.compile(
                r"^\s*#\s*SQL\s*Query\s*Explainability\s*—\s*Diagnostic\s*Report",
                re.IGNORECASE | re.MULTILINE,
            )
            if not h1_re.search(output_text):
                passed = True
                evidence = "No fresh Diagnostic Report H1 produced (correct for un-EXPLAINable query)"
            else:
                evidence = "Agent produced a Diagnostic Report H1 for a query that could not be EXPLAINed"

        # --- Eval 8 assertion: does NOT fabricate plan/findings/numbers ---
        elif "does not fabricate" in exp_lower or "does NOT fabricate" in exp_lower:
            # Look for signals the agent hallucinated numeric findings despite the failure
            fabrication = re.search(
                r"(actual (time|rows)\s*=?\s*\d+|rows\s*removed\s*by\s*filter\s*=?\s*\d+|"
                r"node duration\s*:?\s*\d+|finding\s+\d+:.{0,80}\d+\s*(ms|s|rows))",
                output_text,
            )
            if not fabrication:
                passed = True
                evidence = "No fabricated plan metrics / findings / row counts"
            else:
                evidence = f"Possible fabrication detected: {fabrication.group(0)[:80]}"

        # --- Eval 8 assertion: asks user to confirm table/schema/cluster ---
        elif "asks the user" in exp_lower and ("table" in exp_lower or "schema" in exp_lower or "cluster" in exp_lower):
            ask_re = re.compile(
                r"(confirm (the )?(table|schema|cluster)|which (table|schema)|did you mean|"
                r"is this the right (table|schema)|share (the|your) (connection|cluster|endpoint)|"
                r"provide (the|your) (table|schema))",
                re.IGNORECASE,
            )
            if ask_re.search(output_text):
                passed = True
                evidence = "Agent asked the user to confirm the table/schema/cluster"
            else:
                evidence = "Agent did not explicitly ask for confirmation"

        # --- Eval 9 assertion: names stale statistics as root cause ---
        elif "stale statistics" in exp_lower and "root cause" in exp_lower:
            stale_re = re.compile(
                r"(stale (stat|reltuples)|out-?of-?date (stat|reltuples)|"
                r"statistics (are )?(stale|out of date|outdated)|"
                r"reltuples (lag|is (out of date|stale))|"
                r"pg_class.*reltuples.*(stale|out of date))",
                re.IGNORECASE,
            )
            if stale_re.search(output_text):
                passed = True
                evidence = "Stale statistics named as root cause"
            else:
                evidence = "Stale statistics not named as root cause"

        # --- Eval 9 assertion: recommends ANALYZE or notes auto-analyze schedule ---
        elif "recommends running analyze" in exp_lower or ("analyze" in exp_lower and "auto" in exp_lower):
            analyze_re = re.compile(
                r"(ANALYZE\s+\w+|run (an )?ANALYZE|auto-?analyz(e|ed|es)|"
                r"DSQL (runs |auto-)analyze|analyze (schedule|on a schedule))",
                re.IGNORECASE,
            )
            if analyze_re.search(output_text):
                passed = True
                evidence = "ANALYZE recommendation or auto-analyze note present"
            else:
                evidence = "No ANALYZE recommendation or auto-analyze note"

        # --- Grader (b): Expected Impact is evidence-grounded ---
        # Passes when the Expected Impact is either (1) a concrete numeric
        # prediction grounded in evidence (e.g., "~50× less read DPU",
        # "4s → ~80ms"), OR (2) an honest admission that the evidence is
        # insufficient with a named missing piece ("cannot predict magnitude
        # without most_common_freqs on this column"). Fails on pure hedging
        # like "should improve performance" without either a number or a
        # named evidence gap — that's the fabrication-inducing failure mode.
        elif (("expected impact" in exp_lower and "concrete numbers" in exp_lower)
              or "grader b" in exp_lower):
            report = run_result.get("result_text", "") or ""
            section_match = re.search(r"(?is)(#+\s*summary.*?)(?=\n#|\Z)", report)
            section = section_match.group(1) if section_match else report
            impact_lines = re.findall(r"(?i)(expected[\s_-]*impact[^\n]*)", section)
            numeric_re = re.compile(
                r"(\d+(?:\.\d+)?\s*x\b|\d+(?:\.\d+)?\s*%|"
                r"\d+(?:\.\d+)?\s*(?:ms|s|sec|seconds|minutes?)\b|\d{3,}\s*(?:rows|row))",
                re.IGNORECASE,
            )
            honest_gap_re = re.compile(
                r"(cannot predict|can't predict|unable to (predict|quantify|estimate)|"
                r"insufficient (evidence|data|stats)|missing (evidence|stats)|"
                r"requires? .{0,60} to (predict|estimate|quantify)|"
                r"need (more )?(evidence|data|stats|samples)|"
                r"qualitative (only|direction|prediction))",
                re.IGNORECASE,
            )
            hedges_re = re.compile(
                r"(should improve|will be faster|significant(ly)? (reduc|improv|faster)|"
                r"substantial(ly)? (reduc|improv)|expected to improve|performance gain)",
                re.IGNORECASE,
            )
            numeric_hits = [ln for ln in impact_lines if numeric_re.search(ln)]
            honest_gap_hits = [ln for ln in impact_lines if honest_gap_re.search(ln)]
            hedge_only = [
                ln for ln in impact_lines
                if hedges_re.search(ln) and not numeric_re.search(ln) and not honest_gap_re.search(ln)
            ]
            if numeric_hits:
                passed = True
                evidence = f"Expected Impact has concrete numeric prediction(s): {numeric_hits[0][:80]}"
            elif honest_gap_hits:
                passed = True
                evidence = f"Expected Impact honestly names evidence gap: {honest_gap_hits[0][:80]}"
            elif hedge_only:
                evidence = f"Expected Impact hedges without number or named gap: {hedge_only[0][:80]}"
            elif impact_lines:
                evidence = "Expected Impact column present but no numeric prediction or evidence-gap acknowledgment"
            else:
                evidence = "No Expected Impact column / section found in the report"

        # --- Grader (c): Addendum appended, not a fresh report ---
        # Phase 5 reassessment MUST append an Addendum section, not restart with
        # a fresh top-level Diagnostic Report H1. Single-turn-aware: checks the
        # current turn's output has Addendum and does NOT open with a fresh H1.
        elif ("addendum" in exp_lower
              and ("appended" in exp_lower or "not a fresh" in exp_lower or "rather than" in exp_lower)):
            report = run_result.get("result_text", "") or ""
            h1_re = re.compile(
                r"^\s*#\s*(?:SQL\s*Query\s*Explainability|Diagnostic\s*Report)",
                re.IGNORECASE | re.MULTILINE,
            )
            addendum_re = re.compile(r"(?im)^\s*#{1,3}\s*addendum\b")
            h1_count = len(h1_re.findall(report))
            has_addendum = bool(addendum_re.search(report))
            if has_addendum and h1_count == 0:
                passed = True
                evidence = "Addendum section present, no fresh report H1 (correct)"
            elif has_addendum and h1_count >= 1:
                evidence = (
                    f"Addendum present but ALSO {h1_count} fresh Diagnostic Report "
                    f"H1(s) — should be appended, not restarted"
                )
            elif not has_addendum:
                evidence = "No Addendum section found — reassessment was not appended"
            else:
                evidence = f"Unexpected state: addendum={has_addendum}, h1_count={h1_count}"

        # --- Grader (d): No hallucinated DSQL-specific semantics ---
        # Guards against fabricated root causes like "DSQL is case-sensitive"
        # when the agent saw get_schema return empty. PostgreSQL auto-lowercases
        # unquoted identifiers; inventing a DSQL-specific quirk is a regression.
        # Matches against output_text only (the prompt may legitimately mention
        # "mixed-case" / "case-sensitive" / etc.).
        elif (("case-sensitive" in exp_lower and "dsql" in exp_lower)
              or "lowercasing" in exp_lower
              or ("invent" in exp_lower and ("quirk" in exp_lower or "dsql-specific" in exp_lower))
              or "grader d" in exp_lower):
            bad_phrases = [
                r"dsql is case[\s-]*sensitive",
                r"case[\s-]*sensitive (for )?identifier",
                r"dsql handles identifiers differently",
                r"dsql does not (auto[\s-]*)?lowercase",
                r"you (must|need to|should) lowercase (the )?(table|column|identifier)",
                r"rename .{0,30}to lowercase",
            ]
            correction_re = re.compile(
                r"(postgres(ql)? (auto[\s-]*)?lowercase|auto[\s-]*lowercased|folded to lowercase)",
                re.IGNORECASE,
            )
            hits = []
            for pat in bad_phrases:
                m = re.search(pat, output_text, re.IGNORECASE)
                if m:
                    hits.append(m.group(0))
            if not hits:
                passed = True
                evidence = "No hallucinated DSQL case-sensitivity claims found"
            elif correction_re.search(output_text):
                passed = True
                evidence = f"Found {len(hits)} case-sensitivity phrase(s) but paired with auto-lowercase correction"
            else:
                evidence = f"Hallucinated DSQL case-sensitivity claim: {hits[0]!r}"

        # --- Fallback: keyword matching ---
        # Matches against result_text only (not the prompt-inclusive full_text), so
        # an agent can't pass by echoing the prompt. Threshold is high (0.8) because
        # this branch handles the long tail of assertions with no dedicated handler.
        else:
            keywords = re.findall(r'\b[a-z_]{3,}\b', exp_lower)
            significant = [k for k in keywords if k not in (
                "the", "and", "for", "that", "with", "from", "this", "not",
                "must", "should", "does", "use", "are", "has", "have", "its",
                "via", "tool", "found", "any",
            )]
            # Local name to avoid shadowing the function-scoped `output_text`.
            fallback_text = run_result.get("result_text", "").lower()
            matches = sum(1 for k in significant if k in fallback_text)
            if significant and matches / len(significant) >= 0.8:
                passed = True
                evidence = f"Matched {matches}/{len(significant)} keywords in agent output"
            else:
                evidence = f"Only matched {matches}/{len(significant)} keywords in agent output"

        expectations.append({
            "text": expectation_text,
            "passed": passed,
            "evidence": evidence,
        })

    passed_count = sum(1 for e in expectations if e["passed"])
    total = len(expectations)

    return {
        "expectations": expectations,
        "summary": {
            "passed": passed_count,
            "failed": total - passed_count,
            "total": total,
            "pass_rate": round(passed_count / total, 2) if total > 0 else 0,
        },
    }


def main():
    parser = argparse.ArgumentParser(
        description="Run functional evaluations for dsql query-plan-explainability workflow"
    )
    parser.add_argument("--evals", required=True, help="Path to query_explainability_evals.json")
    parser.add_argument("--plugin-dir", required=True, help="Path to the plugin directory")
    parser.add_argument("--output-dir", required=True, help="Directory to save results")
    parser.add_argument("--model", default=None, help="Model to use")
    parser.add_argument("--timeout", type=int, default=300, help="Timeout per prompt in seconds")
    parser.add_argument("--verbose", action="store_true", help="Print progress")
    parser.add_argument("--eval-ids", type=str, default=None,
                        help="Comma-separated eval IDs to run (default: all)")
    parser.add_argument("--mcp-config", type=str, default=None,
                        help="Path to a JSON file with MCP server config (e.g., .claude/.mcp.json) "
                             "to override the plugin's default (disabled) aurora-dsql config")
    parser.add_argument("--max-turns", type=int, default=40,
                        help="Maximum agent turns per eval (default: 40)")
    parser.add_argument("--skip-warmup", action="store_true",
                        help="Skip the throwaway MCP warmup run (not recommended — first "
                             "eval is likely to fail because uvx/boto3 haven't initialized)")
    args = parser.parse_args()

    if args.mcp_config and not Path(args.mcp_config).is_file():
        sys.exit(f"ERROR: --mcp-config path does not exist: {args.mcp_config}")

    evals_path = Path(args.evals)
    if not evals_path.is_file():
        sys.exit(f"ERROR: --evals file not found: {args.evals}")
    try:
        evals_data = json.loads(evals_path.read_text())
    except json.JSONDecodeError as e:
        sys.exit(f"ERROR: --evals file is not valid JSON: {e}")

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Filter evals if specific IDs requested
    evals_to_run = evals_data["evals"]
    if args.eval_ids:
        try:
            ids = [int(x.strip()) for x in args.eval_ids.split(",")]
        except ValueError:
            sys.exit(f"ERROR: --eval-ids must be comma-separated integers, got: {args.eval_ids}")
        evals_to_run = [e for e in evals_to_run if e["id"] in ids]

    # Throwaway uvx warmup: the aurora-dsql MCP server is an stdio process launched
    # via `uvx awslabs.aurora-dsql-mcp-server@latest`. On a cold cache, uvx downloads
    # the package and boto3 initializes the AWS session — this can take long enough
    # that the first eval times out its MCP handshake and the agent reports
    # "MCP server isn't connected". One throwaway invocation warms uvx + the cache
    # so subsequent evals see the MCP immediately.
    if args.mcp_config and not args.skip_warmup:
        print("\n### Throwaway uvx warmup (initializes aurora-dsql MCP server) ###",
              file=sys.stderr)
        warmup = run_prompt(
            "hi", args.plugin_dir, args.timeout, args.model, args.mcp_config, max_turns=1
        )
        warmup_status = warmup.get("status", "completed")
        print(f"  Warmup status: {warmup_status} ({warmup['duration_seconds']}s)",
              file=sys.stderr)
        if warmup_status != "completed":
            # Surface the warmup's stderr tail and retry once. If it still fails, bail —
            # running evals against a cold MCP guarantees false failures on eval 1.
            print(f"  Warmup stderr: {(warmup.get('stderr') or '')[:500]}", file=sys.stderr)
            print("  Retrying warmup once …", file=sys.stderr)
            warmup = run_prompt(
                "hi", args.plugin_dir, args.timeout, args.model, args.mcp_config, max_turns=1
            )
            warmup_status = warmup.get("status", "completed")
            print(f"  Warmup retry status: {warmup_status} ({warmup['duration_seconds']}s)",
                  file=sys.stderr)
            if warmup_status != "completed":
                sys.exit(
                    "ERROR: MCP warmup failed twice — evals would run against a cold MCP and "
                    "report false negatives. Check AWS credentials, uvx availability, and "
                    "the --mcp-config file. Pass --skip-warmup to bypass (not recommended)."
                )
    elif args.skip_warmup:
        print("WARNING: --skip-warmup is set. Eval 1 may fail if uvx/boto3 have not "
              "initialized before the first real eval call.", file=sys.stderr)

    all_results = []

    for eval_item in evals_to_run:
        eval_id = eval_item["id"]
        prompt = eval_item["prompt"]

        if args.verbose:
            print(f"\n{'='*60}", file=sys.stderr)
            print(f"Running eval {eval_id}: {prompt[:80]}...", file=sys.stderr)

        run_result = run_prompt(
            prompt, args.plugin_dir, args.timeout, args.model, args.mcp_config, args.max_turns
        )

        # Save raw transcript
        eval_dir = output_dir / f"eval-{eval_id}"
        eval_dir.mkdir(parents=True, exist_ok=True)
        (eval_dir / "transcript.json").write_text(json.dumps(run_result, indent=2))

        # Grade
        grading = grade_eval(eval_item, run_result)
        (eval_dir / "grading.json").write_text(json.dumps(grading, indent=2))

        # Save timing
        timing = {
            "total_duration_seconds": run_result["duration_seconds"],
            "total_cost_usd": run_result.get("total_cost_usd", 0),
        }
        (eval_dir / "timing.json").write_text(json.dumps(timing, indent=2))

        # Save eval metadata
        metadata = {
            "eval_id": eval_id,
            "eval_name": f"eval-{eval_id}",
            "prompt": prompt,
            "assertions": eval_item.get("expectations", []),
        }
        (eval_dir / "eval_metadata.json").write_text(json.dumps(metadata, indent=2))

        # Diagnostic trace persisted for post-hoc triage
        ref_reads = [
            c["input"].get("file_path", "").split("/")[-1]
            for c in run_result["tool_calls"]
            if c["name"] == "Read" and "references/" in c["input"].get("file_path", "")
        ]
        mcp_calls = [
            c["name"].split("__")[-1]
            for c in run_result["tool_calls"]
            if "aurora-dsql" in c["name"] or "aurora.dsql" in c["name"]
        ]
        diagnostic = {
            "status": run_result.get("status", "completed"),
            "returncode": run_result.get("returncode"),
            "references_loaded": ref_reads,
            "mcp_tool_calls": mcp_calls,
            "malformed_lines": run_result.get("malformed_lines", 0),
            "stderr_tail": (run_result.get("stderr") or "")[:500],
        }
        (eval_dir / "diagnostic.json").write_text(json.dumps(diagnostic, indent=2))

        if args.verbose:
            print(f"  Status: {diagnostic['status']}", file=sys.stderr)
            print(f"  References loaded ({len(ref_reads)}): {', '.join(ref_reads) or 'none'}", file=sys.stderr)
            print(f"  MCP tool calls ({len(mcp_calls)}): {', '.join(mcp_calls) or 'none'}", file=sys.stderr)

            s = grading["summary"]
            print(f"  Result: {s['passed']}/{s['total']} passed ({s['pass_rate']:.0%})", file=sys.stderr)
            for exp in grading["expectations"]:
                status_label = "PASS" if exp["passed"] else "FAIL"
                print(f"    [{status_label}] {exp['text'][:70]}", file=sys.stderr)
                print(f"           {exp['evidence'][:100]}", file=sys.stderr)

        all_results.append({
            "eval_id": eval_id,
            "prompt": prompt,
            "status": diagnostic["status"],
            "grading": grading,
            "duration_seconds": run_result["duration_seconds"],
            "diagnostic": diagnostic,
        })

    # Aggregate summary: only include completed evals in the pass-rate denominator.
    # Timeouts/errors are counted separately so they don't silently drag the overall number down.
    completed = [r for r in all_results if r["status"] == "completed"]
    total_expectations = sum(r["grading"]["summary"]["total"] for r in completed)
    total_passed = sum(r["grading"]["summary"]["passed"] for r in completed)
    timed_out_ids = [r["eval_id"] for r in all_results if r["status"] == "timeout"]
    errored_ids = [r["eval_id"] for r in all_results if r["status"] == "error"]

    malformed_total = sum(
        r.get("diagnostic", {}).get("malformed_lines", 0) for r in all_results
    )
    summary = {
        "skill_name": evals_data["skill_name"],
        "total_evals": len(all_results),
        "completed_evals": len(completed),
        "timed_out_eval_ids": timed_out_ids,
        "errored_eval_ids": errored_ids,
        "total_expectations": total_expectations,
        "total_passed": total_passed,
        "overall_pass_rate": round(total_passed / total_expectations, 2) if total_expectations > 0 else 0,
        "malformed_json_lines_total": malformed_total,
        "results": all_results,
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2))

    if args.verbose:
        print(f"\n{'='*60}", file=sys.stderr)
        print(f"OVERALL: {total_passed}/{total_expectations} expectations passed "
              f"across {len(completed)}/{len(all_results)} completed evals "
              f"({summary['overall_pass_rate']:.0%})", file=sys.stderr)
        if timed_out_ids:
            print(f"  Timed out: eval IDs {timed_out_ids}", file=sys.stderr)
        if errored_ids:
            print(f"  Errored: eval IDs {errored_ids}", file=sys.stderr)

    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
