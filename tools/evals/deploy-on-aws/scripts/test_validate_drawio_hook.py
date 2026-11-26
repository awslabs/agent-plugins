"""Regression test: the deploy-on-aws draw.io hook must not run code from the user's project.

Claude Code runs PostToolUse hooks with the project as the CWD, and a bare `python3 -c`
puts the CWD first on sys.path, so a json.py planted in a repository ran on every
Edit/Write with no prompt (CWE-426).

Run: pytest tools/evals/deploy-on-aws/scripts/test_validate_drawio_hook.py
 or: python3 tools/evals/deploy-on-aws/scripts/test_validate_drawio_hook.py
"""

import json
import os
import subprocess  # nosec B404 - runs the plugin's own hook script
import tempfile
from pathlib import Path

HOOK = Path(__file__).resolve().parents[4] / "plugins/deploy-on-aws/scripts/validate-drawio.sh"
DIAGRAM = (
    '<mxfile><diagram name="p"><mxGraphModel><root><mxCell id="0"/>'
    '<mxCell id="1" parent="0"/></root></mxGraphModel></diagram></mxfile>\n'
)


def run_hook(project, file_name, pythonpath):
    return subprocess.run(  # nosec B603 B607 - fixed argv, no shell
        ["bash", str(HOOK)],
        input=json.dumps({"tool_input": {"file_path": str(project / file_name)}}),
        cwd=project,
        env={**os.environ, "PYTHONPATH": str(pythonpath)},
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )


def test_hook_ignores_modules_planted_in_project():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        project = root / "project"
        project.mkdir()
        # Modules the hook's inline Python imports; each leaves a marker if executed.
        for name in ("json", "re", "defusedxml"):
            marker = root / f"RAN_{name}"
            (project / f"{name}.py").write_text(f"open({str(marker)!r}, 'w').close()\n")
        (project / "README.md").write_text("hello\n")
        (project / "arch.drawio").write_text(DIAGRAM)
        # Stand-in defusedxml outside the project, reachable only via PYTHONPATH. The
        # dependency probe must still see it (the validators do), and it carries every
        # run through to the final json.dumps call where defusedxml is not installed.
        (root / "site" / "defusedxml").mkdir(parents=True)
        (root / "site" / "defusedxml" / "__init__.py").touch()

        runs = [run_hook(project, f, root / "site") for f in ("README.md", "arch.drawio")]

        ran = sorted(p.name for p in root.glob("RAN_*"))
        assert not ran, f"hook executed modules planted in the project: {ran}"  # nosec B101
        for run in runs:
            assert run.returncode == 0, run.stderr  # nosec B101 - test assertion
        message = json.loads(runs[1].stdout)["systemMessage"]
        assert "Missing required dependency" not in message, message  # nosec B101


if __name__ == "__main__":
    test_hook_ignores_modules_planted_in_project()
    print("PASS")
