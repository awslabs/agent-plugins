"""Tests for plugins/databases-on-aws/scripts/loader.sh release asset selection.

Run with pytest: `pytest tools/evals/databases-on-aws/dsql/scripts/test_loader_sh.py`

Stub `uname` and `curl` commands are placed first on PATH. The curl stub serves
a canned GitHub release and records the URL that loader.sh tries to download,
then fails that download so nothing is installed.
"""

import json
import os
import subprocess  # nosec B404
from pathlib import Path

import pytest

LOADER_SH = (
    Path(__file__).resolve().parent.parent.parent.parent.parent.parent
    / "plugins"
    / "databases-on-aws"
    / "scripts"
    / "loader.sh"
)

RELEASES = "https://github.com/aws-samples/aurora-dsql-loader/releases/download"

# Asset names published by aws-samples/aurora-dsql-loader v3.3.0 (musl Linux builds,
# used since v2.0.2) and v2.0.1 (the last release with glibc Linux builds).
V3_3_0_ASSETS = [
    "aurora-dsql-loader-aarch64-apple-darwin.tar.gz",
    "aurora-dsql-loader-aarch64-unknown-linux-musl.tar.gz",
    "aurora-dsql-loader-x86_64-apple-darwin.tar.gz",
    "aurora-dsql-loader-x86_64-pc-windows-msvc.zip",
    "aurora-dsql-loader-x86_64-unknown-linux-musl.tar.gz",
]
V2_0_1_ASSETS = [
    "aurora-dsql-loader-aarch64-apple-darwin.tar.gz",
    "aurora-dsql-loader-aarch64-unknown-linux-gnu.tar.gz",
    "aurora-dsql-loader-x86_64-apple-darwin.tar.gz",
    "aurora-dsql-loader-x86_64-pc-windows-msvc.zip",
    "aurora-dsql-loader-x86_64-unknown-linux-gnu.tar.gz",
]

UNAME_STUB = """#!/bin/sh
case "$1" in
  -m) echo "$STUB_ARCH" ;;
  *) echo "$STUB_OS" ;;
esac
"""

CURL_STUB = """#!/bin/sh
url=""
for arg in "$@"; do
  case "$arg" in
    https://*) url="$arg" ;;
  esac
done
case " $* " in
  *" -o "*)
    echo "$url" >> "$STUB_DOWNLOADS"
    exit 22
    ;;
esac
cat "$STUB_RELEASE_JSON"
"""


def run_install_only(
    tmp_path: Path, os_name: str, arch: str, tag: str, assets: list[str]
):
    stub_bin = tmp_path / "bin"
    stub_bin.mkdir()
    for name, body in (("uname", UNAME_STUB), ("curl", CURL_STUB)):
        stub = stub_bin / name
        stub.write_text(body)
        stub.chmod(0o700)

    release_json = tmp_path / "release.json"
    release_json.write_text(
        json.dumps(
            {
                "tag_name": tag,
                "assets": [
                    {"name": name, "browser_download_url": f"{RELEASES}/{tag}/{name}"}
                    for name in assets
                ],
            }
        )
    )
    downloads = tmp_path / "downloads.txt"

    env = {
        **os.environ,
        "HOME": str(tmp_path),
        "PATH": f"{stub_bin}{os.pathsep}{os.environ['PATH']}",
        "STUB_OS": os_name,
        "STUB_ARCH": arch,
        "STUB_RELEASE_JSON": str(release_json),
        "STUB_DOWNLOADS": str(downloads),
    }
    result = subprocess.run(  # nosec B603 B607
        ["bash", str(LOADER_SH), "--install-only", "--version", tag],
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    urls = downloads.read_text().split() if downloads.exists() else []
    return result, urls


@pytest.mark.parametrize(
    ("os_name", "arch", "tag", "assets", "asset"),
    [
        (
            "Linux",
            "x86_64",
            "v3.3.0",
            V3_3_0_ASSETS,
            "aurora-dsql-loader-x86_64-unknown-linux-musl.tar.gz",
        ),
        (
            "Linux",
            "aarch64",
            "v3.3.0",
            V3_3_0_ASSETS,
            "aurora-dsql-loader-aarch64-unknown-linux-musl.tar.gz",
        ),
        (
            "Linux",
            "x86_64",
            "v2.0.1",
            V2_0_1_ASSETS,
            "aurora-dsql-loader-x86_64-unknown-linux-gnu.tar.gz",
        ),
        (
            "Darwin",
            "arm64",
            "v3.3.0",
            V3_3_0_ASSETS,
            "aurora-dsql-loader-aarch64-apple-darwin.tar.gz",
        ),
    ],
)
def test_install_downloads_the_published_asset_for_the_platform(
    tmp_path: Path, os_name: str, arch: str, tag: str, assets: list[str], asset: str
) -> None:
    _, urls = run_install_only(tmp_path, os_name, arch, tag, assets)

    assert urls == [f"{RELEASES}/{tag}/{asset}"]  # nosec B101


def test_install_reports_a_platform_without_a_published_asset(tmp_path: Path) -> None:
    darwin_only = [name for name in V3_3_0_ASSETS if "apple-darwin" in name]

    result, urls = run_install_only(tmp_path, "Linux", "x86_64", "v3.3.0", darwin_only)

    assert result.returncode == 1  # nosec B101
    assert urls == []  # nosec B101
    assert (  # nosec B101
        "Could not find download URL for platform: x86_64-unknown-linux-musl"
        in result.stderr
    )
