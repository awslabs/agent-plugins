#!/usr/bin/env python3
"""Run the draw.io post-processing and validation pipeline with timeouts."""

import json
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).parent


def _text(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value or ""


def run_step(script_name, file_path, timeout, suppress_stderr=False):
    command = [sys.executable, str(SCRIPT_DIR / script_name), file_path]
    try:
        result = subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL if suppress_stderr else subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        output = _text(exc.stdout)
        timeout_message = f"Timed out after {timeout}s while running {script_name}."
        return f"{output}\n{timeout_message}".strip()
    except OSError as exc:
        return f"Could not run {script_name}: {exc}"
    return _text(result.stdout).strip()


def main():
    if len(sys.argv) != 2:
        print(json.dumps({"systemMessage": "draw.io hook received invalid input."}))
        return 0

    file_path = sys.argv[1]
    post_result = run_step("post_process_drawio.py", file_path, 10)
    validation_result = run_step("validate_drawio.py", file_path, 10)
    validation_passed = "VALIDATION PASSED" in validation_result

    url_result = ""
    if validation_passed:
        url_result = run_step("drawio_url.py", file_path, 5, suppress_stderr=True)

    messages = []
    if post_result and "no changes needed" not in post_result:
        messages.append(f"POST-PROCESSING: {post_result}")
    if validation_result:
        messages.append(validation_result)
    if url_result:
        messages.append(f"PREVIEW URL: {url_result}")

    message = "\n\n".join(messages) or (
        "draw.io XML validation passed. All AWS shapes are valid."
    )
    print(json.dumps({"systemMessage": message}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
