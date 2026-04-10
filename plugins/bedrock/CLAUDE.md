# Bedrock Plugin

## Project Overview

Claude Code plugin (`awslabs/agent-plugins` format) for Amazon Bedrock onboarding.
Guides developers through IAM setup, model access, prompt caching, observability, and cost analysis.

## Plugin Format

- `.claude-plugin/plugin.json` — plugin metadata
- `skills/` — SKILL.md files with YAML frontmatter (name, description, argument-hint)
- `commands/` — slash command definitions with YAML frontmatter (name, description)
- `scripts/` — executable scripts referenced via `${CLAUDE_PLUGIN_ROOT}/scripts/`
- `.mcp.json` — MCP server configuration

## Key Conventions

- Scripts use `${CLAUDE_PLUGIN_ROOT}` for portable paths — never hardcode absolute paths
- Default model: Claude Sonnet 4.6 (`us.anthropic.claude-sonnet-4-6`)
- Default region: `us-east-1`
- AWS profile: always ask the developer to confirm — never auto-select
- Reference docs in `skills/bedrock/references/` are loaded on-demand by topic
- Shell scripts must be POSIX-compatible and executable (`chmod +x`)
- Python scripts require Python 3.10+ and boto3 only — no other dependencies

## Testing Changes

1. Run `scripts/validate-bedrock-access.sh us.anthropic.claude-sonnet-4-6 us-east-1 PROFILE` — all 4 checks must pass
2. Run `python3 scripts/validate-prompt-caching.py --model-id us.anthropic.claude-sonnet-4-6 --region us-east-1 --profile PROFILE` — cache write + read confirmed
3. Run `python3 scripts/check-quota-health.py --model-id us.anthropic.claude-sonnet-4-6 --region us-east-1 --profile PROFILE` — quota analysis completes without error
4. Run `python3 scripts/debug-prompt-cache.py --model-id us.anthropic.claude-sonnet-4-6 --region us-east-1 --profile PROFILE` — all 6 diagnostic tests pass
5. Run `python3 scripts/analyze-bedrock-usage.py --model-id us.anthropic.claude-sonnet-4-6 --period 1 --profile PROFILE` — usage report generates
6. Run `python3 scripts/analyze-bedrock-costs.py --period 1 --profile PROFILE` — cost report generates (may show $0 if no traffic)
7. Each validation run costs ~$0.01-0.05 in Bedrock API calls; cache debug costs ~$0.02-0.08

## What Not to Do

- Don't add dependencies beyond boto3 and AWS CLI
- Don't hardcode AWS credentials or account IDs in scripts
- Don't write custom IAM policies in examples — recommend `AmazonBedrockLimitedAccess` managed policy
- Don't run AWS commands without first confirming the profile with the developer
