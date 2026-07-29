# AWS Transform Agent Plugin

Migrate and modernize codebases to AWS. Covers .NET Framework to .NET 8/10, mainframe COBOL to Java, VMware VMs to EC2, SQL Server/Oracle/MySQL to Aurora, and Java/Python/Node.js language and AWS SDK upgrades, plus custom transformations defined by the user.

## Overview

AWS Transform is AWS's AI-powered code and workload modernization service. This plugin brings its workflow guidance into AI coding agents: assess, plan, transform, and validate — routed through just-in-time authentication and workload-specific steering.

## Skills

| Skill           | Description                                                                                                                                                                                     |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `aws-transform` | Assessment, planning, and execution for .NET, mainframe, VMware, SQL, language/SDK upgrades. Analyze codebases for tech debt, security issues, modernization opportunities, and remediate them. |

## MCP Servers

| Server              | Description                                                                                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `aws-transform-mcp` | [awslabs.aws-transform-mcp-server](https://pypi.org/project/awslabs.aws-transform-mcp-server/) — tools for workspaces, jobs, agents, HITL tasks, and authentication |

## Installation

```bash
/plugin marketplace add awslabs/agent-plugins
/plugin install aws-transform@agent-plugins-for-aws
```

## Prerequisites

- `uv` (required to launch the MCP server via `uvx`):
  - macOS: `brew install uv`
  - Linux: `curl -LsSf https://astral.sh/uv/install.sh | sh`
- AWS credentials for AWS Transform (SigV4) or an IAM Identity Center session
- AWS Transform CLI (`atx`) — only required for custom transformations: `curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash`

## Examples

- "Migrate this .NET Framework app to .NET 8 on AWS"
- "Upgrade this Java 8 project to Java 21"
- "Move these VMware VMs to EC2"
- "Convert this SQL Server database to Aurora PostgreSQL"
- "Modernize this COBOL mainframe code"
- "Upgrade this Python 2 codebase to Python 3"

## License

Apache-2.0
