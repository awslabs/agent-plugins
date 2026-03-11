# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx>=0.28,<1"]
# ///
"""Check that HTTPS URLs in markdown files are reachable.

Scans all .md files for HTTPS URLs, checks them with HEAD (fallback GET),
and reports broken or redirected links. Network-dependent — not wired into
the main build pipeline. Run on-demand or in scheduled CI.

Usage:
    uv run tools/validate-urls.py [--strict]

With --strict, 301 permanent redirects and 403 responses also fail.
"""

import asyncio
import os
import re
import sys
from pathlib import Path
from urllib.parse import urldefrag

ROOT = Path(__file__).resolve().parent.parent
IGNORE_FILE = ROOT / ".url-check-ignore"

CONCURRENCY = 10
TIMEOUT = 10.0
RETRIES = 1

# Match HTTPS URLs in markdown (links, raw URLs, angle-bracket URLs)
URL_RE = re.compile(r"https://[^\s)<>\"'`\]]+")

RED = "\033[91m"
YELLOW = "\033[93m"
GREEN = "\033[92m"
DIM = "\033[2m"
BOLD = "\033[1m"
RESET = "\033[0m"


def load_ignore_patterns() -> list[str]:
    """Load URL prefixes/patterns to skip from .url-check-ignore."""
    if not IGNORE_FILE.exists():
        return []
    patterns = []
    for line in IGNORE_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            patterns.append(line)
    return patterns


def should_ignore(url: str, patterns: list[str]) -> bool:
    for pattern in patterns:
        if pattern in url:
            return True
    return False


def collect_urls() -> dict[str, list[tuple[Path, int]]]:
    """Scan all .md files and collect unique URLs with their locations."""
    url_locations: dict[str, list[tuple[Path, int]]] = {}

    for md_file in sorted(ROOT.rglob("*.md")):
        # Skip hidden dirs, node_modules, .git, .tmp
        parts = md_file.relative_to(ROOT).parts
        if any(p.startswith(".") or p == "node_modules" for p in parts):
            continue

        try:
            text = md_file.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue

        for i, line in enumerate(text.splitlines(), 1):
            for match in URL_RE.finditer(line):
                raw_url = match.group(0)
                # Strip trailing punctuation that's likely not part of the URL
                raw_url = raw_url.rstrip(".,;:!?)")
                # Strip fragment
                url, _ = urldefrag(raw_url)
                if url not in url_locations:
                    url_locations[url] = []
                url_locations[url].append((md_file, i))

    return url_locations


async def check_url(
    client: "httpx.AsyncClient",
    url: str,
    semaphore: asyncio.Semaphore,
    gh_token: str | None = None,
    gh_hosts: tuple[str, ...] = (),
) -> tuple[str, int | None, str | None]:
    """Check a single URL. Returns (url, status_code, error_or_note)."""
    import httpx
    from urllib.parse import urlparse

    # Only attach auth header for GitHub domains — never leak tokens to third parties
    req_headers: dict[str, str] = {}
    if gh_token:
        host = urlparse(url).hostname or ""
        if any(host == h or host.endswith("." + h) for h in gh_hosts):
            req_headers["Authorization"] = f"Bearer {gh_token}"

    async with semaphore:
        for attempt in range(1 + RETRIES):
            try:
                # Try HEAD first
                resp = await client.head(url, headers=req_headers, follow_redirects=True, timeout=TIMEOUT)
                if resp.status_code == 405 or resp.status_code >= 500:
                    # Server rejects HEAD or is erroring — try GET
                    resp = await client.get(url, headers=req_headers, follow_redirects=True, timeout=TIMEOUT)

                # Check for permanent redirects in the redirect history
                redirect_note = None
                for r in resp.history:
                    if r.status_code == 301:
                        redirect_note = f"301 → {resp.url}"
                        break

                return (url, resp.status_code, redirect_note)

            except httpx.TimeoutException:
                if attempt < RETRIES:
                    await asyncio.sleep(1)
                    continue
                return (url, None, "timeout")
            except (httpx.ConnectError, httpx.ReadError, httpx.RemoteProtocolError) as e:
                if attempt < RETRIES:
                    await asyncio.sleep(1)
                    continue
                return (url, None, str(type(e).__name__))
            except Exception as e:
                return (url, None, str(e))

    return (url, None, "unreachable")


async def main_async(strict: bool) -> int:
    import httpx

    ignore_patterns = load_ignore_patterns()
    url_locations = collect_urls()

    if not url_locations:
        print(f"{GREEN}No HTTPS URLs found in markdown files.{RESET}")
        return 0

    # Filter out ignored URLs
    urls_to_check = {
        url: locs
        for url, locs in url_locations.items()
        if not should_ignore(url, ignore_patterns)
    }
    ignored_count = len(url_locations) - len(urls_to_check)

    print(f"{BOLD}URL Liveness Check{RESET}")
    print(f"Found {len(url_locations)} unique URLs, checking {len(urls_to_check)}", end="")
    if ignored_count:
        print(f" ({ignored_count} ignored)", end="")
    print("\n")

    # GitHub token for rate limit avoidance — ONLY sent to GitHub domains
    base_headers = {"User-Agent": "agent-plugins-url-checker/1.0"}
    gh_token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    gh_hosts = ("github.com", "api.github.com", "raw.githubusercontent.com")

    semaphore = asyncio.Semaphore(CONCURRENCY)

    async with httpx.AsyncClient(headers=base_headers) as client:
        tasks = [
            check_url(client, url, semaphore, gh_token=gh_token, gh_hosts=gh_hosts)
            for url in sorted(urls_to_check.keys())
        ]
        results = await asyncio.gather(*tasks)

    # Categorize results
    broken: list[tuple[str, int | None, str | None]] = []
    warnings: list[tuple[str, int | None, str | None]] = []
    ok_count = 0

    for url, status, note in results:
        if status is None:
            broken.append((url, status, note))
        elif status >= 400 and status != 403:
            broken.append((url, status, note))
        elif status == 403:
            if strict:
                broken.append((url, status, note))
            else:
                warnings.append((url, status, "403 Forbidden (may be WAF/bot protection)"))
        elif note and note.startswith("301"):
            if strict:
                broken.append((url, status, note))
            else:
                warnings.append((url, status, note))
        else:
            ok_count += 1

    # Report
    if broken:
        print(f"{RED}Broken URLs ({len(broken)}):{RESET}")
        for url, status, note in broken:
            status_str = str(status) if status else note or "error"
            locs = urls_to_check[url]
            first_loc = locs[0]
            rel = first_loc[0].relative_to(ROOT)
            extra = f" (+{len(locs)-1} more)" if len(locs) > 1 else ""
            print(f"  {RED}[{status_str}]{RESET} {url}")
            print(f"         {DIM}{rel}:{first_loc[1]}{extra}{RESET}")
        print()

    if warnings:
        print(f"{YELLOW}Warnings ({len(warnings)}):{RESET}")
        for url, status, note in warnings:
            locs = urls_to_check[url]
            first_loc = locs[0]
            rel = first_loc[0].relative_to(ROOT)
            extra = f" (+{len(locs)-1} more)" if len(locs) > 1 else ""
            print(f"  {YELLOW}[{status}]{RESET} {url}")
            print(f"         {DIM}{note} — {rel}:{first_loc[1]}{extra}{RESET}")
        print()

    print(
        f"{BOLD}Summary:{RESET} {ok_count} ok, {len(warnings)} warnings,"
        f" {len(broken)} broken out of {len(urls_to_check)} checked"
    )

    return 1 if broken else 0


def main() -> int:
    strict = "--strict" in sys.argv
    return asyncio.run(main_async(strict))


if __name__ == "__main__":
    sys.exit(main())
