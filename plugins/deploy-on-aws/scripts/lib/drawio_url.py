#!/usr/bin/env python3
"""
drawio_url.py - Generate a draw.io URL from a .drawio file

Compresses the XML and encodes it into a URL fragment that
opens directly in app.diagrams.net with the diagram loaded.

Usage: python3 drawio_url.py <file.drawio> [--open]
  --open  Also opens the URL in the default browser
"""

import json
import subprocess  # nosec B404 # nosemgrep: gitlab.bandit.B404 - opens URLs in browser via platform launcher
import sys
import zlib
from base64 import b64encode
from pathlib import Path
from platform import system
from urllib.parse import quote


MAX_FILE_SIZE = 2 * 1024 * 1024  # 2 MB


def generate_url(file_path):
    path = Path(file_path)
    file_size = path.stat().st_size
    if file_size > MAX_FILE_SIZE:
        print(
            f"Error: File too large ({file_size // 1024}KB > {MAX_FILE_SIZE // 1024 // 1024}MB limit)",
            file=sys.stderr,
        )
        sys.exit(1)

    xml = path.read_text(encoding="utf-8").strip()

    if not xml:
        print("Error: File is empty", file=sys.stderr)
        sys.exit(1)

    # 1. URL-encode the XML
    encoded = quote(xml, safe="")

    # 2. Deflate compress (raw deflate, no zlib header)
    # wbits=-15 gives raw deflate like Node's deflateRaw
    compressed = zlib.compress(encoded.encode("utf-8"), level=9)
    # Strip zlib header (first 2 bytes) and checksum (last 4 bytes) for raw deflate
    raw_deflated = compressed[2:-4]

    # 3. Base64 encode
    base64_str = b64encode(raw_deflated).decode("ascii")

    # 4. Build the JSON payload
    payload = json.dumps({"type": "xml", "compressed": True, "data": base64_str})

    # 5. URL-encode the payload and build the full URL
    url = f"https://app.diagrams.net/#create={quote(payload, safe='')}"

    return url


def main():
    args = sys.argv[1:]
    file_path = next((a for a in args if not a.startswith("--")), None)
    should_open = "--open" in args

    if not file_path:
        print("Usage: drawio_url.py <file.drawio> [--open]", file=sys.stderr)
        sys.exit(1)

    url = generate_url(file_path)
    print(url)

    if should_open:
        os_name = system()
        if os_name == "Darwin":
            cmd = "open"
        elif os_name == "Windows":
            cmd = "start"
        else:
            cmd = "xdg-open"
        subprocess.run([cmd, url], check=False)  # nosec B603 - cmd is a hardcoded platform launcher


if __name__ == "__main__":
    main()
