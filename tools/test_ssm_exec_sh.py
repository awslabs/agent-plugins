"""Tests for plugins/sagemaker-ai/skills/hyperpod-ssm/scripts/ssm-exec.sh.

Run with pytest: `pytest tools/test_ssm_exec_sh.py`

A stub `aws` command records the --parameters payload of each call. PATH holds
only the stubs and links to the few tools the script needs, so a real `aws` or
`unbuffer` on the machine is never used.
"""

import json
import os
import shutil
import subprocess  # nosec B404 - runs the script under test with stub commands  # nosemgrep: gitlab.bandit.B404
from pathlib import Path

import pytest

SSM_EXEC_SH = (
    Path(__file__).resolve().parent.parent
    / "plugins"
    / "sagemaker-ai"
    / "skills"
    / "hyperpod-ssm"
    / "scripts"
    / "ssm-exec.sh"
)

TARGET = "sagemaker-cluster:abc123def456_workers-i-0123456789abcdef0"

# Commands needed to run ssm-exec.sh (and the aws stub) in --target 'command' mode.
TOOLS = ("bash", "jq", "mktemp", "chmod", "rm", "cat")

AWS_STUB = """#!/bin/sh
prev=""
for arg in "$@"; do
  if [ "$prev" = "--parameters" ]; then
    payload="${arg#file://}"
  fi
  prev="$arg"
done
n=0
while [ -e "$STUB_PAYLOADS/$n.json" ]; do
  n=$((n + 1))
done
cat "$payload" > "$STUB_PAYLOADS/$n.json"
exit "${STUB_AWS_EXIT:-0}"
"""

UNBUFFER_STUB = """#!/bin/sh
exec "$@"
"""

NO_UNBUFFER_WARNING = (
    "Warning: 'unbuffer' (from the 'expect' package) is not installed."
)


@pytest.fixture
def run_ssm_exec(tmp_path: Path):
    tools = {name: shutil.which(name) for name in TOOLS}
    missing = [name for name, path in tools.items() if path is None]
    if missing:
        pytest.skip(f"ssm-exec.sh needs {', '.join(missing)}")

    stub_bin = tmp_path / "bin"
    stub_bin.mkdir()
    for name, path in tools.items():
        (stub_bin / name).symlink_to(path)
    aws = stub_bin / "aws"
    aws.write_text(AWS_STUB)
    aws.chmod(0o700)
    for name in ("tmpdir", "payloads"):
        (tmp_path / name).mkdir()

    def run(*args: str, unbuffer: bool, aws_exit: int = 0):
        stub = stub_bin / "unbuffer"
        stub.unlink(missing_ok=True)
        if unbuffer:
            stub.write_text(UNBUFFER_STUB)
            stub.chmod(0o700)

        env = {
            **os.environ,
            "PATH": str(stub_bin),
            "TMPDIR": str(tmp_path / "tmpdir"),
            "STUB_PAYLOADS": str(tmp_path / "payloads"),
            "STUB_AWS_EXIT": str(aws_exit),
        }
        result = subprocess.run(  # nosec B603 B607
            ["bash", str(SSM_EXEC_SH), "--target", TARGET, *args],
            env=env,
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
        assert (NO_UNBUFFER_WARNING in result.stderr) is not unbuffer  # nosec B101
        return result

    return run


def payloads(tmp_path: Path) -> list:
    files = sorted((tmp_path / "payloads").iterdir(), key=lambda p: int(p.stem))
    return [json.loads(p.read_text()) for p in files]


@pytest.mark.parametrize("unbuffer", [True, False])
def test_repeated_calls_succeed_and_remove_their_temp_file(
    tmp_path: Path, run_ssm_exec, unbuffer: bool
) -> None:
    for call in range(3):
        result = run_ssm_exec("hostname", unbuffer=unbuffer)

        assert result.returncode == 0, result.stderr  # nosec B101
        assert list((tmp_path / "tmpdir").iterdir()) == [], call  # nosec B101

    assert payloads(tmp_path) == [{"command": ["hostname"]}] * 3  # nosec B101


@pytest.mark.parametrize("unbuffer", [True, False])
def test_aws_failure_status_is_returned_and_temp_file_removed(
    tmp_path: Path, run_ssm_exec, unbuffer: bool
) -> None:
    result = run_ssm_exec("hostname", unbuffer=unbuffer, aws_exit=254)

    assert result.returncode == 254  # nosec B101
    assert list((tmp_path / "tmpdir").iterdir()) == []  # nosec B101


def test_call_succeeds_next_to_a_temp_file_left_by_an_older_version(
    tmp_path: Path, run_ssm_exec
) -> None:
    # Older versions left this file behind. BSD mktemp doesn't randomize a
    # template with a suffix, so a suffixed template would collide with it.
    leftover = tmp_path / "tmpdir" / "ssm-cmd-XXXXXXXXXX.json"
    leftover.write_text("{}")

    result = run_ssm_exec("hostname", unbuffer=True)

    assert result.returncode == 0, result.stderr  # nosec B101
    assert list((tmp_path / "tmpdir").iterdir()) == [leftover]  # nosec B101
    assert payloads(tmp_path) == [{"command": ["hostname"]}]  # nosec B101
