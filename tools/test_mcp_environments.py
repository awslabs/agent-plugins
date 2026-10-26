"""Exercise uv's real resolver and cache against a changing local package index."""

import asyncio
import hashlib
import io
import json
import os
import shutil
import subprocess  # nosec B404: tests execute uv with argv, never a shell
import sys
import tempfile
import threading
import zipfile
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
LAUNCHES = [
    ("deploy-on-aws", "awsiac"),
    ("deploy-on-aws", "awspricing"),
    ("codebase-documentor-for-aws", "awsiac"),
    ("aws-serverless", "aws-serverless-mcp"),
    ("aws-transform", "aws-transform-mcp"),
]


def clean_environment():
    keys = (
        "PATH",
        "SYSTEMROOT",
        "TEMP",
        "TMP",
        "TMPDIR",
        "SSL_CERT_FILE",
        "REQUESTS_CA_BUNDLE",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
    )
    return {key: os.environ[key] for key in keys if key in os.environ}


def server_config(plugin, server):
    return json.loads((ROOT / "plugins" / plugin / ".mcp.json").read_text())[
        "mcpServers"
    ][server]


def wheel(name, version, dependency=None):
    """Build inert fixtures without a build backend or external dependencies."""
    normalized = name.replace("-", "_").replace(".", "_")
    info = f"{normalized}-{version}.dist-info"
    content = io.BytesIO()
    with zipfile.ZipFile(content, "w") as archive:
        metadata = f"Metadata-Version: 2.1\nName: {name}\nVersion: {version}\n"
        if dependency:
            metadata += f"Requires-Dist: {dependency}\n"
        archive.writestr(f"{info}/METADATA", metadata)
        archive.writestr(
            f"{info}/WHEEL",
            "Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
        )
        if dependency:
            archive.writestr(
                f"{info}/entry_points.txt",
                f"[console_scripts]\n{name} = cache_probe:main\n",
            )
            archive.writestr(
                "cache_probe.py",
                "import importlib.metadata as m, json, os, sys\n"
                "def main():\n"
                "    print(json.dumps({'prefix': sys.prefix,\n"
                "        'versions': sorted((d.metadata['Name'], d.version) "
                "for d in m.distributions()),\n"
                "        'args': sys.argv[1:],\n"
                "        'profile': os.environ.get('AWS_PROFILE'),\n"
                "        'region': os.environ.get('AWS_REGION')}))\n",
            )
        # RECORD is required for a valid wheel; uv computes the installed files.
        archive.writestr(f"{info}/RECORD", "")
    return f"{normalized}-{version}-py3-none-any.whl", content.getvalue()


@pytest.fixture
def package_index():
    packages, files = {}, {}

    class Handler(BaseHTTPRequestHandler):
        def do_HEAD(self):
            self.do_GET(head_only=True)

        def do_GET(self, head_only=False):
            if self.path.startswith("/files/"):
                body = files[self.path.removeprefix("/files/")]
                content_type = "application/octet-stream"
            else:
                name = self.path.strip("/").split("/")[-1]
                body = json.dumps(
                    {
                        "meta": {"api-version": "1.1"},
                        "name": name,
                        "files": packages.get(name, []),
                    }
                ).encode()
                content_type = "application/vnd.pypi.simple.v1+json"
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if not head_only:
                self.wfile.write(body)

        def log_message(self, *_args):
            pass

    http = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=http.serve_forever, daemon=True)
    thread.start()

    def publish(name, version, uploaded, dependency=None):
        filename, data = wheel(name, version, dependency)
        files[filename] = data
        normalized = name.replace("_", "-").replace(".", "-").lower()
        packages.setdefault(normalized, []).append(
            {
                "filename": filename,
                "url": f"/files/{filename}",
                "hashes": {"sha256": hashlib.sha256(data).hexdigest()},
                "size": len(data),
                "upload-time": uploaded.isoformat(),
                "requires-python": ">=3.10",
                "yanked": False,
            }
        )

    try:
        yield f"http://127.0.0.1:{http.server_port}/simple/", publish
    finally:
        http.shutdown()
        thread.join(timeout=5)
        http.server_close()


@pytest.mark.parametrize("plugin,server", LAUNCHES)
def test_launch_reuses_environment_after_transitive_release(
    plugin, server, tmp_path, package_index
):
    config = server_config(plugin, server)
    args = config["args"]
    assert config["command"] == "uvx"  # nosec B101: pytest assertion
    assert args[0] == "--exclude-newer"  # nosec B101: pytest assertion
    cutoff = datetime.fromisoformat(args[1].replace("Z", "+00:00"))
    assert cutoff.tzinfo == timezone.utc  # nosec B101: pytest assertion
    name, version = args[2].split("==")
    assert "@latest" not in " ".join(args)  # nosec B101: pytest assertion
    index, publish = package_index
    publish("cache-dependency", "1.0.0", cutoff - timedelta(days=1))
    publish(name, version, cutoff - timedelta(days=1), "cache-dependency>=1")

    # Keep the test independent of caller credentials, indexes and uv settings.
    env = clean_environment()
    env.update(config.get("env", {}))
    env.update(
        UV_CACHE_DIR=str(tmp_path / "cache"),
        UV_TOOL_DIR=str(tmp_path / "tools"),
        UV_PYTHON_DOWNLOADS="never",
        AWS_PROFILE="fixture-profile",
        AWS_REGION="us-east-1",
        NO_PROXY="127.0.0.1,localhost",
    )
    uv = shutil.which("uv")
    assert uv, "uv is required; run this test through mise run test:python"  # nosec B101: pytest assertion

    def launch(arguments, refresh=False):
        command = [
            uv,
            "tool",
            "run",
            "--no-config",
            "--python",
            sys.executable,
            "--default-index",
            index,
        ]
        if refresh:
            command.append("--refresh")
        result = subprocess.run(  # nosec B603: uv argv from repository fixtures
            [*command, *arguments],
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, result.stderr  # nosec B101: pytest assertion
        return json.loads(result.stdout)

    first = launch(args)
    marker = Path(first["prefix"]) / "pyvenv.cfg"
    identity = (marker.stat().st_ino, marker.stat().st_mtime_ns)
    assert launch(args) == first  # nosec B101: pytest assertion

    # Control: even an exact top-level pin can drift after a dependency release.
    unbounded = launch(args[2:], refresh=True)
    publish("cache-dependency", "2.0.0", cutoff + timedelta(days=1))
    drifted = launch(args[2:], refresh=True)
    assert unbounded["versions"] != drifted["versions"]  # nosec B101: pytest assertion
    assert unbounded["prefix"] != drifted["prefix"]  # nosec B101: pytest assertion

    # Refresh forces resolution against the changed index rather than letting
    # a warm cache hide transitive drift. The cutoff still selects the old set.
    assert launch(args, refresh=True) == first  # nosec B101: pytest assertion
    assert launch(args) == first  # nosec B101: pytest assertion
    assert (marker.stat().st_ino, marker.stat().st_mtime_ns) == identity  # nosec B101: pytest assertion
    assert first["args"] == args[3:]  # nosec B101: pytest assertion
    assert first["profile"] == "fixture-profile"  # nosec B101: pytest assertion
    assert first["region"] == "us-east-1"  # nosec B101: pytest assertion
    assert ["cache-dependency", "1.0.0"] in first["versions"]  # nosec B101: pytest assertion


def test_serverless_keeps_write_access_and_iac_requests_match():
    assert server_config("aws-serverless", "aws-serverless-mcp")["args"][3:] == [  # nosec B101: pytest assertion
        "--allow-write"
    ]
    assert server_config("deploy-on-aws", "awsiac") == server_config(  # nosec B101: pytest assertion
        "codebase-documentor-for-aws", "awsiac"
    )


@pytest.fixture(scope="module")
def real_cache(tmp_path_factory):
    return tmp_path_factory.mktemp("mcp-real")


async def mcp_catalog(command, env):
    """Initialize and enumerate tools, never execute a tool or AWS operation."""
    with tempfile.TemporaryFile() as errors:
        process = await asyncio.create_subprocess_exec(
            *command,
            env=env,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=errors,
        )

        async def send(message):
            process.stdin.write((json.dumps(message) + "\n").encode())
            await process.stdin.drain()

        async def receive(request_id):
            while True:
                line = await asyncio.wait_for(process.stdout.readline(), timeout=60)
                if not line:
                    errors.seek(0)
                    raise AssertionError(errors.read().decode(errors="replace"))
                message = json.loads(line)
                if message.get("id") == request_id:
                    assert "error" not in message, message  # nosec B101: pytest assertion
                    return message["result"]

        try:
            await send(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2025-03-26",
                        "capabilities": {},
                        "clientInfo": {"name": "cache-regression", "version": "1.0"},
                    },
                }
            )
            initialized = await receive(1)
            await send({"jsonrpc": "2.0", "method": "notifications/initialized"})
            tools, cursor, request_id = [], None, 2
            while True:
                await send(
                    {
                        "jsonrpc": "2.0",
                        "id": request_id,
                        "method": "tools/list",
                        "params": {"cursor": cursor} if cursor else {},
                    }
                )
                page = await receive(request_id)
                tools.extend(page["tools"])
                cursor = page.get("nextCursor")
                if not cursor:
                    break
                request_id += 1
            return initialized["serverInfo"], sorted(
                tools, key=lambda tool: tool["name"]
            )
        finally:
            if process.returncode is None:
                process.terminate()
                try:
                    await asyncio.wait_for(process.wait(), timeout=10)
                except TimeoutError:
                    process.kill()
                    await process.wait()


@pytest.mark.skipif(
    os.environ.get("MCP_LAUNCH_INTEGRATION") != "1",
    reason="opt-in package downloads: mise run test:mcp-launches",
)
@pytest.mark.parametrize("plugin,server", LAUNCHES)
def test_real_mcp_repeated_launches(plugin, server, real_cache):
    if (
        plugin == "aws-transform"
        and (Path.home() / ".aws-transform-mcp" / "config.json").exists()
    ):
        pytest.skip(
            "Run in a clean account: Transform reads its persisted session at startup"
        )
    config = server_config(plugin, server)
    args = config["args"]
    uv = shutil.which("uv")
    assert uv  # nosec B101: pytest assertion
    env = clean_environment()
    env.update(config.get("env", {}))
    env.update(
        UV_CACHE_DIR=str(real_cache / "cache"),
        UV_TOOL_DIR=str(real_cache / "tools"),
        UV_PYTHON_DOWNLOADS="never",
        AWS_CONFIG_FILE=os.devnull,
        AWS_SHARED_CREDENTIALS_FILE=os.devnull,
        AWS_EC2_METADATA_DISABLED="true",
        AWS_DEFAULT_REGION="us-east-1",
        AWS_REGION="us-east-1",
    )
    # Introspect the same resolved requirement without starting its server.
    probe = [
        uv,
        "tool",
        "run",
        "--no-config",
        "--python",
        sys.executable,
        *args[:2],
        "--from",
        args[2],
        "python",
        "-c",
        "import importlib.metadata as m, json, sys; "
        "print(json.dumps({'prefix':sys.prefix, 'versions':"
        "sorted((d.metadata['Name'],d.version) for d in m.distributions())}))",
    ]

    def snapshot(refresh=False):
        command = [*probe[:3], "--refresh", *probe[3:]] if refresh else probe
        result = subprocess.run(  # nosec B603: uv argv from repository fixtures
            command, env=env, capture_output=True, text=True, timeout=300
        )
        assert result.returncode == 0, result.stderr  # nosec B101: pytest assertion
        return json.loads(result.stdout)

    first = snapshot()
    prefix = Path(first["prefix"])
    marker = prefix / "pyvenv.cfg"
    identity = (marker.stat().st_ino, marker.stat().st_mtime_ns)
    command = [uv, "tool", "run", "--no-config", "--python", sys.executable, *args]
    # Packages are cached now. Prevent outbound HTTP from server startup and
    # avoid using local AWS credentials; listing tools needs neither.
    server_env = dict(
        env,
        UV_OFFLINE="true",
        HTTP_PROXY="http://127.0.0.1:9",
        HTTPS_PROXY="http://127.0.0.1:9",
        ALL_PROXY="http://127.0.0.1:9",
    )
    catalog = asyncio.run(mcp_catalog(command, server_env))
    assert catalog[1], "Server advertised no tools"  # nosec B101: pytest assertion
    environments = set((real_cache / "cache").rglob("pyvenv.cfg"))
    for refresh in (False, True):
        assert snapshot(refresh=refresh) == first  # nosec B101: pytest assertion
        assert asyncio.run(mcp_catalog(command, server_env)) == catalog  # nosec B101: pytest assertion
        assert set((real_cache / "cache").rglob("pyvenv.cfg")) == environments  # nosec B101: pytest assertion
        assert (marker.stat().st_ino, marker.stat().st_mtime_ns) == identity  # nosec B101: pytest assertion
    print(
        f"{plugin}/{server}: {len(first['versions'])} packages, "
        f"{len(catalog[1])} tools, stable identity/versions/catalog over 3 launches"
    )
