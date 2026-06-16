---
name: server
description: Start, stop, or restart the AWS Transform - continuous modernization server (`atx ct server`).
---

# Server

## Supported Regions

AWS Transform - continuous modernization is available in these regions only:

| Region                | Code             |
| --------------------- | ---------------- |
| US East (N. Virginia) | `us-east-1`      |
| Europe (Frankfurt)    | `eu-central-1`   |
| Asia Pacific (Mumbai) | `ap-south-1`     |
| Asia Pacific (Sydney) | `ap-southeast-2` |
| Asia Pacific (Tokyo)  | `ap-northeast-1` |
| Europe (London)       | `eu-west-2`      |
| Asia Pacific (Seoul)  | `ap-northeast-2` |
| Canada (Central)      | `ca-central-1`   |

## Region Selection

Before starting the server, ask the user which region they want to use if they haven't already specified one, (render this menu as plain numbered markdown text in your response and wait for the user to type a choice; do NOT route it through any structured choice/picker tool like `AskUserQuestion` in Claude Code, or any equivalent multi-select/option UI in other harnesses):

> "Which AWS region do you want to use? AWS Transform - continuous modernization supports: us-east-1, eu-central-1, ap-south-1, ap-southeast-2, ap-northeast-1, eu-west-2, ap-northeast-2, ca-central-1."

If the user provides a region not in the supported list, let them know it isn't supported and suggest `us-east-1` as the default:

> "That region isn't supported by AWS Transform - continuous modernization. Would you like to use `us-east-1` (US East, N. Virginia) instead?"

Once confirmed, set `ATX_REGION` to the chosen region.

## Start

```bash
AWS_REGION=$ATX_REGION atx ct server &
```

## Stop

```bash
pkill -f "atx ct server"
```

## Restart

```bash
pkill -f "atx ct server"; AWS_REGION=$ATX_REGION atx ct server &
```

## Check if running

```bash
atx ct status --health
```
