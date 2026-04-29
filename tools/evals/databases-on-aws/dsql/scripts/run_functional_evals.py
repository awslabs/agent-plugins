#!/usr/bin/env python3
"""Run functional evaluations for the DSQL skill.

Executes each eval prompt via `claude -p` with the plugin loaded,
captures the stream-json transcript (which includes tool calls),
and grades assertions programmatically.
"""

import argparse
import json
import os
import re
import subprocess  # nosec B404 - eval runner needs subprocess to invoke claude CLI
import sys
import time
from pathlib import Path


def run_prompt(prompt: str, plugin_dir: str, timeout: int = 180, model: str | None = None) -> dict:
    """Run a prompt via claude -p with stream-json output to capture tool calls."""
    cmd = [
        "claude", "-p", prompt,
        "--output-format", "stream-json",
        "--verbose",
        "--plugin-dir", plugin_dir,
        "--max-turns", "10",
    ]
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
        }
    duration = time.time() - start

    if result.returncode != 0:
        print(f"  WARNING: claude exited with status {result.returncode}", file=sys.stderr)
        if result.stderr:
            print(f"  stderr: {result.stderr[:300]}", file=sys.stderr)

    # Parse stream-json: one JSON object per line
    messages = []
    tool_calls = []
    result_text = ""
    total_cost = 0
    usage = {}

    for line in result.stdout.strip().split("\n"):
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            print(f"  Skipping malformed JSON line: {line[:100]}", file=sys.stderr)
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
            # Capture tool results too for full transcript
            messages.append(event)

        elif event_type == "result":
            result_text = event.get("result", result_text)
            total_cost = event.get("total_cost_usd", 0)
            usage = event.get("usage", {})

    return {
        "result_text": result_text,
        "messages": messages,
        "tool_calls": tool_calls,
        "stderr": result.stderr,
        "returncode": result.returncode,
        "duration_seconds": round(duration, 1),
        "total_cost_usd": total_cost,
        "usage": usage,
    }


def grade_eval(eval_item: dict, run_result: dict) -> dict:
    """Grade a single eval against its expectations."""
    text = run_result["result_text"].lower()
    tool_calls = run_result["tool_calls"]

    # Build a searchable string from ALL content (text + tool inputs + tool results)
    full_text = text
    for tc in tool_calls:
        full_text += " " + json.dumps(tc).lower()
    for msg in run_result["messages"]:
        full_text += " " + json.dumps(msg).lower()

    expectations = []

    for expectation_text in eval_item.get("expectations", []):
        passed = False
        evidence = ""

        exp_lower = expectation_text.lower()

        # --- Assertion: awsknowledge call with topic ---
        if "calls awsknowledge" in exp_lower:
            topic = ""
            if "transaction" in exp_lower:
                topic = "transaction"
            elif "index" in exp_lower:
                topic = "index"
            elif "connection" in exp_lower:
                topic = "connection"
            elif "sequence" in exp_lower or "cache" in exp_lower:
                topic = "sequence"
            elif "auth" in exp_lower or "token" in exp_lower:
                topic = "auth"

            for call in tool_calls:
                name = call["name"].lower()
                if "awsknowledge" in name or "search_documentation" in name:
                    call_str = json.dumps(call["input"]).lower()
                    if topic and topic in call_str:
                        passed = True
                        evidence = f"Found awsknowledge call matching '{topic}': {json.dumps(call['input'])[:200]}"
                        break
                    elif not topic:
                        passed = True
                        evidence = f"Found awsknowledge call: {json.dumps(call['input'])[:200]}"
                        break

            if not passed:
                # Check full text for tool call patterns (sometimes tool names are mangled)
                if re.search(r"(awsknowledge|aws___search_documentation)", full_text):
                    if not topic or topic in full_text:
                        passed = True
                        evidence = f"Found awsknowledge reference in transcript text"

            if not passed:
                evidence = f"No awsknowledge call found{' for topic: ' + topic if topic else ''}"

        # --- Assertion: mentions 3,000 row limit ---
        elif "3,000 row" in exp_lower or "3000 row" in exp_lower:
            if re.search(r"3[,.]?000", full_text):
                passed = True
                evidence = "Found '3,000' or '3000' in response"
            else:
                evidence = "No mention of 3,000 row limit found"

        # --- Assertion: mentions 10 MiB ---
        elif "10 mib" in exp_lower:
            if re.search(r"10\s*mi?b", full_text) or "10mb" in full_text or "10 mb" in full_text:
                passed = True
                evidence = "Found '10 MiB' or equivalent in response"
            else:
                evidence = "No mention of 10 MiB data size limit found"

        # --- Assertion: 24 indexes ---
        elif "24 index" in exp_lower:
            if "24" in full_text and re.search(r"index", full_text):
                passed = True
                evidence = "Found '24' with 'index' context in response"
            else:
                evidence = "No mention of 24 indexes per table limit found"

        # --- Assertion: 8 columns per index ---
        elif "8 columns per index" in exp_lower:
            if "8" in full_text and "column" in full_text and "index" in full_text:
                passed = True
                evidence = "Found '8' with 'column' and 'index' context"
            else:
                evidence = "No mention of 8 columns per index limit found"

        # --- Assertion: 15-minute token expiry ---
        elif "15-minute" in exp_lower or "15 minute" in exp_lower:
            if re.search(r"15[- ]?min", full_text):
                passed = True
                evidence = "Found '15 min' token expiry reference"
            else:
                evidence = "No mention of 15-minute token expiry found"

        # --- Assertion: DSQL Python Connector ---
        elif "dsql python connector" in exp_lower:
            patterns = [
                r"aurora_dsql_psycopg",
                r"aurora_dsql_asyncpg",
                r"dsql[-_\s]?connector",
                r"dsql[-_\s]?python",
            ]
            for pat in patterns:
                if re.search(pat, full_text):
                    passed = True
                    evidence = f"Found DSQL Python Connector reference matching '{pat}'"
                    break
            if not passed:
                evidence = "No DSQL Python Connector (aurora_dsql_psycopg/psycopg2/asyncpg) found"

        # --- Assertion: tenant_id ---
        elif "tenant_id" in exp_lower:
            if "tenant_id" in full_text:
                passed = True
                evidence = "Found 'tenant_id' in response"
            else:
                evidence = "No 'tenant_id' column found"

        # --- Assertion: CREATE INDEX ASYNC ---
        elif "create index async" in exp_lower:
            if "create index async" in full_text:
                passed = True
                evidence = "Found 'CREATE INDEX ASYNC' in response"
            elif "async" in full_text and "index" in full_text:
                passed = True
                evidence = "Found 'async' with 'index' context"
            else:
                evidence = "No 'CREATE INDEX ASYNC' found"

        # --- Assertion: NOT use FOREIGN KEY ---
        elif "not use foreign key" in exp_lower or "does not use foreign key" in exp_lower:
            if "foreign key" in full_text:
                if re.search(r"(don.t|do not|cannot|doesn.t|not support|no foreign|avoid|instead of foreign|aren.t supported|not available)", full_text):
                    passed = True
                    evidence = "Mentions foreign keys but advises against them (correct)"
                else:
                    passed = False
                    evidence = "Mentions foreign keys — may be using them"
            else:
                passed = True
                evidence = "No foreign key usage found (correct for DSQL)"

        # --- Assertion: separate transactions per DDL ---
        elif "separate transaction" in exp_lower or "own separate transaction" in exp_lower:
            if re.search(r"(separate|individual|own|one|single).{0,30}(transaction|transact)", full_text):
                passed = True
                evidence = "Found separate transactions guidance for DDL"
            elif re.search(r"(one ddl|single ddl).{0,20}(per|each)", full_text):
                passed = True
                evidence = "Found one-DDL-per-transaction guidance"
            elif re.search(r"each.{0,20}(ddl|create|alter).{0,20}(own|separate|its own)", full_text):
                passed = True
                evidence = "Found each-DDL-in-own-transaction guidance"
            else:
                evidence = "No clear guidance about separate DDL transactions"

        # --- Assertion: batching strategy ---
        elif "batching strategy" in exp_lower or "recommends a batching" in exp_lower:
            if re.search(r"batch", full_text):
                passed = True
                evidence = "Found batching recommendation"
            else:
                evidence = "No batching strategy found"

        # --- Assertion: Table Recreation Pattern ---
        elif "table recreation pattern" in exp_lower:
            if re.search(r"(table recreation|recreat|create.{0,40}new.{0,40}table.{0,40}(copy|migrat|move)|new table.{0,40}copy)", full_text):
                passed = True
                evidence = "Found Table Recreation Pattern description"
            else:
                evidence = "No Table Recreation Pattern described"

        # --- Assertion: destructive DROP TABLE ---
        elif "destructive" in exp_lower and "drop table" in exp_lower:
            if re.search(r"(drop table|destructive|irreversible|data loss|permanent)", full_text):
                passed = True
                evidence = "Found warning about destructive DROP TABLE"
            else:
                evidence = "No warning about destructive DROP TABLE found"

        # --- Assertion: batching for >3000 rows ---
        elif "batching" in exp_lower and "3,000" in exp_lower:
            if re.search(r"batch", full_text) and re.search(r"3[,.]?000", full_text):
                passed = True
                evidence = "Found batching with 3,000 row threshold"
            else:
                evidence = "No batching with 3,000 row threshold found"

        # --- Assertion: user confirmation ---
        elif "user confirmation" in exp_lower:
            if re.search(r"(confirm|approval|user.{0,30}(confirm|approv|verify)|before proceed|explicit.{0,20}(confirm|approv))", full_text):
                passed = True
                evidence = "Found user confirmation requirement"
            else:
                evidence = "No user confirmation requirement found"

        # --- Assertion: IAM token generation ---
        elif "iam" in exp_lower and "token" in exp_lower:
            if re.search(r"iam", full_text) and re.search(r"token", full_text):
                passed = True
                evidence = "Found IAM token generation reference"
            else:
                evidence = "No IAM token generation reference found"

        # --- Assertion: SSL/TLS ---
        elif "ssl" in exp_lower or "tls" in exp_lower:
            if re.search(r"ssl|tls", full_text):
                passed = True
                evidence = "Found SSL/TLS requirement"
            else:
                evidence = "No SSL/TLS requirement mentioned"

        # --- Assertion: suggests alternatives ---
        elif "suggests alternatives" in exp_lower or "composite index" in exp_lower:
            if re.search(r"(composite|combin|consolidat|reduc|alternative|workaround|fewer|merge)", full_text):
                passed = True
                evidence = "Found alternatives suggestion"
            else:
                evidence = "No alternatives suggested"

        # --- Fallback: keyword search ---
        else:
            keywords = re.findall(r'\b[a-z_]{3,}\b', exp_lower)
            significant = [k for k in keywords if k not in (
                "the", "and", "for", "that", "with", "from", "this", "not",
                "must", "should", "does", "use", "are", "has", "have", "its",
            )]
            matches = sum(1 for k in significant if k in full_text)
            if significant and matches / len(significant) >= 0.6:
                passed = True
                evidence = f"Matched {matches}/{len(significant)} keywords"
            else:
                evidence = f"Only matched {matches}/{len(significant)} keywords"

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
    parser = argparse.ArgumentParser(description="Run functional evaluations for DSQL skill")
    parser.add_argument("--evals", required=True, help="Path to evals.json")
    parser.add_argument("--plugin-dir", required=True, help="Path to the plugin directory")
    parser.add_argument("--output-dir", required=True, help="Directory to save results")
    parser.add_argument("--model", default=None, help="Model to use")
    parser.add_argument("--timeout", type=int, default=180, help="Timeout per prompt in seconds")
    parser.add_argument("--verbose", action="store_true", help="Print progress")
    args = parser.parse_args()

    evals_data = json.loads(Path(args.evals).read_text())
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    all_results = []

    for eval_item in evals_data["evals"]:
        eval_id = eval_item["id"]
        prompt = eval_item["prompt"]

        if args.verbose:
            print(f"\n{'='*60}", file=sys.stderr)
            print(f"Running eval {eval_id}: {prompt[:80]}...", file=sys.stderr)

        run_result = run_prompt(prompt, args.plugin_dir, args.timeout, args.model)

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

        if args.verbose:
            s = grading["summary"]
            print(f"  Result: {s['passed']}/{s['total']} passed ({s['pass_rate']:.0%})", file=sys.stderr)
            for exp in grading["expectations"]:
                status = "PASS" if exp["passed"] else "FAIL"
                print(f"    [{status}] {exp['text'][:70]}", file=sys.stderr)
                print(f"           {exp['evidence'][:100]}", file=sys.stderr)

        all_results.append({
            "eval_id": eval_id,
            "prompt": prompt,
            "grading": grading,
            "duration_seconds": run_result["duration_seconds"],
        })

    # Aggregate summary
    total_expectations = sum(r["grading"]["summary"]["total"] for r in all_results)
    total_passed = sum(r["grading"]["summary"]["passed"] for r in all_results)

    summary = {
        "skill_name": evals_data["skill_name"],
        "total_evals": len(all_results),
        "total_expectations": total_expectations,
        "total_passed": total_passed,
        "overall_pass_rate": round(total_passed / total_expectations, 2) if total_expectations > 0 else 0,
        "results": all_results,
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2))

    if args.verbose:
        print(f"\n{'='*60}", file=sys.stderr)
        print(f"OVERALL: {total_passed}/{total_expectations} expectations passed ({summary['overall_pass_rate']:.0%})", file=sys.stderr)

    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
