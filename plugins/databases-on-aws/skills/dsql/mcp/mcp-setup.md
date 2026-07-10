## Plugin Default Configuration

The plugin ships with a documentation-only `.mcp.json` at the plugin root (no cluster endpoint, no `--allow-writes`). This means the MCP server provides DSQL documentation search, reading, and recommendations out of the box without requiring any cluster connection.

To enable database operations (queries, schema exploration, DDL, DML), users must update the plugin's `.mcp.json` with their cluster details.

### Default Documentation-Only Config

The plugin's `.mcp.json` is pre-configured as follows:

```json
{
  "mcpServers": {
    "aurora-dsql": {
      "command": "uvx",
      "args": ["awslabs.aurora-dsql-mcp-server@latest"],
      "env": { "FASTMCP_LOG_LEVEL": "ERROR" },
      "disabled": true
    }
  }
}
```

To upgrade to full database operations, add `--cluster_endpoint`, `--region`, `--database_user`, and optionally `--allow-writes` to the args array, and set `"disabled": false`.

---

# MCP Server Setup Instructions

## Prerequisites:

```bash
uv --version
```

**If missing:**

- Install from: [Astral](https://docs.astral.sh/uv/getting-started/installation/)

## General MCP Configuration:

Add the following configuration after checking if the user wants documentation-only functionality
or database operation support too.

### Documentation-Only Configuration

```json
{
  "mcpServers": {
    "aurora-dsql": {
      "command": "uvx",
      "args": [
        "awslabs.aurora-dsql-mcp-server@latest"
      ],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR"
      },
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

### Database Operation Support Configuration

```json
{
  "mcpServers": {
    "aurora-dsql": {
      "command": "uvx",
      "args": [
        "awslabs.aurora-dsql-mcp-server@latest",
        "--cluster_endpoint",
        "[your dsql cluster endpoint, e.g. abcdefghijklmnopqrst234567.dsql.us-east-1.on.aws]",
        "--region",
        "[your dsql cluster region, e.g. us-east-1]",
        "--database_user",
        "[your dsql username, e.g. admin]",
        "--profile",
        "[your aws profile name, eg. default]",
        "--allow-writes"
      ],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR",
        "REGION": "[your dsql cluster region, eg. us-east-1, only when necessary]",
        "AWS_PROFILE": "[your aws profile name, eg. default]"
      },
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

### Optional Arguments and Environment Variables:

The following args and environment variables are not required, but may be required if the user
has custom AWS configurations or would like to allow/disallow the MCP server mutating their database.

- Arg: `--profile` or Env: `"AWS_PROFILE"` only need
  to be configured for non-default values.
- Env: `"REGION"` when the cluster region management is
  distinct from user's primary region in project/application.
- Arg: `--allow-writes` based on how permissive the user wants
  to be for the MCP server. Always ask the user if writes
  should be allowed.

## CloudWatch MCP Server (System Diagnostics — Workflow 12)

Workflow 12 (System Diagnostics) reads Aurora DSQL Active Average Sessions (AAS) telemetry
through the CloudWatch MCP server's PromQL tools. This is a **separate server** from
`aurora-dsql` — it reads CloudWatch metrics, not the database — so it has its own entry in
`.mcp.json`. The plugin ships it disabled because it needs region and credential details the
plugin can't know in advance.

The plugin's `.mcp.json` pre-configures it as:

```json
{
  "mcpServers": {
    "cloudwatch": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR",
        "AWS_REGION": "[your dsql cluster region, e.g. us-east-1 — must be a PromQL-enabled region]",
        "AWS_PROFILE": "[your aws profile name, e.g. default]"
      },
      "disabled": true
    }
  }
}
```

To enable it:

1. Set `AWS_REGION` to the cluster's region and `AWS_PROFILE` to a profile with CloudWatch
   read permissions — `cloudwatch:GetMetricData` and `cloudwatch:ListMetrics` (the actions the
   CloudWatch PromQL query path uses). The server uses the standard AWS credential chain, so
   `--profile` on the command line or `AWS_PROFILE` in `env` both work.
2. Set `"disabled": false`.

**Region matters.** The server must run in the **same region as the DSQL cluster**, and
CloudWatch PromQL is only available in a subset of regions — at the time of writing:
`us-east-1`, `us-west-2`, `eu-west-1`, `ap-southeast-1`, `ap-southeast-2`. If the cluster is
in another region, PromQL-based diagnostics are not available there; verify the current list
in the CloudWatch documentation.

**Restart after enabling.** MCP tools are registered when the session starts. If you enable
the server (or fix its config) mid-session, its tools (`execute_promql_range_query`,
`get_promql_label_values`, `get_metric_data`, …) will **not** become callable until you
restart the coding assistant — even though `claude mcp list` may already show it as
"Connected". A server that shows Connected but whose tools return "No such tool available" is
the classic symptom of this: restart the session to pick them up.

## Coding Assistant - Custom Instructions

Before proceeding, identify which coding assistant you are adding the MCP server to and
navigate to those custom instructions.

1. [Claude Code](platforms/claude-code.md)
2. [Gemini](platforms/gemini.md)
3. [Codex](platforms/codex.md)
4. [Kiro](platforms/kiro.md)

## Additional Documentation

- [MCP Server Setup Guide](https://awslabs.github.io/mcp/servers/aurora-dsql-mcp-server)
- [DSQL MCP User Guide](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/SECTION_aurora-dsql-mcp-server.html)
