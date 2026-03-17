# AWS Amplify Plugin

Build full-stack apps with AWS Amplify Gen 2 using guided, phased workflows.

## Overview

This plugin orchestrates AWS Amplify Gen 2 development through SOP-driven phases:

1. **Backend** - Create auth, data models, storage, and functions in the `amplify/` directory
2. **Sandbox** - Deploy to a sandbox environment for testing
3. **Frontend** - Connect your frontend framework to the Amplify backend
4. **Production** - Deploy to production via CI/CD

Only applicable phases are executed based on your request.

## Skills

| Skill              | Description                                                                                                           |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| `amplify-workflow` | Orchestrates phased Amplify Gen 2 workflows with prerequisite validation, plan confirmation, and SOP-driven execution |

## MCP Servers

| Server    | Description                                                 |
| --------- | ----------------------------------------------------------- |
| `aws-mcp` | AWS documentation and SOP retrieval via `mcp-proxy-for-aws` |

## Installation

```bash
/plugin marketplace add awslabs/agent-plugins
/plugin install aws-amplify@agent-plugins-for-aws
```

## Examples

- "Build me a task management app with Amplify"
- "Add authentication to my Amplify backend"
- "Add a storage bucket for file uploads"
- "Deploy my Amplify app to sandbox"
- "Connect my React frontend to the Amplify backend"

## Prerequisites

- Node.js >= 18
- npm
- AWS CLI with configured credentials

## Files

- `skills/amplify-workflow/SKILL.md` - Main workflow orchestrator
- `skills/amplify-workflow/references/backend.md` - Backend phase instructions
- `skills/amplify-workflow/references/deploy.md` - Sandbox and production deployment
- `skills/amplify-workflow/references/frontend.md` - Frontend integration and testing
- `skills/amplify-workflow/scripts/prereq-check.sh` - Prerequisite validation script

## License

Apache-2.0
