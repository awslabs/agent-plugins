# Updating MCP dependencies

The IaC, Pricing, Serverless and Transform launch definitions use exact server
versions and a fixed `uvx --exclude-newer` timestamp. `@latest` forces cache
refreshes at every launch. An exact server version alone still allows its ranged
dependencies to change when a refresh or cache rebuild resolves them again.
The timestamp excludes later releases of **all** dependencies, keeping normal
repeated launches on the same resolved package set and cached environment.

This is a dependency release cutoff, not a cross-platform lockfile. Different
Python versions, platforms or indexes can resolve different packages. Yanked or
removed distributions and explicit user resolver overrides can also affect a
fresh resolution. The fix does not clean previously accumulated environments.
See [uv's tool environment documentation](https://docs.astral.sh/uv/concepts/tools/)
and [the resolver options](https://docs.astral.sh/uv/reference/cli/#uv-tool-run).

To update these servers:

1. Choose published server versions and a UTC cutoff after their release dates.
2. Update the versions and cutoff together in the affected `.mcp.json` files.
   Keep both IaC launch definitions identical.
3. Run `mise run test:python`. The local-index regression publishes a new ranged
   dependency, demonstrates drift with only the top-level pin, and verifies that
   the cutoff preserves versions and the same environment even on refresh.
4. Run `mise run test:mcp-launches` for real-package startup and cache-reuse checks.
   This downloads packages into an isolated temporary cache, initializes MCP and
   lists tools without invoking AWS operations. It needs network access to PyPI.
   Transform needs a writable `~/.aws-transform-mcp` log directory; its test skips
   accounts with an existing persisted Transform session to avoid using it.
5. Run `mise run build` and review dependency/security changes before publishing.

Advance the cutoff when reviewing dependency updates, including security fixes;
ordinary launches intentionally do not adopt newer releases automatically.
Proxy launch definitions are maintained separately in
[PR #274](https://github.com/awslabs/agent-plugins/pull/274).
