---
name: bedrock
description: "Your starting point for Amazon Bedrock — ask anything about setup, usage, costs, caching, models, or optimization"
argument-hint: "[what do you need help with?]"
---

# Bedrock — Unified Entry Point

## AWS CLI Profile Gate

Before running ANY command that touches AWS (aws CLI, plugin scripts, boto3), you MUST:

1. **Ask the developer** which AWS CLI profile to use. List available profiles by running `aws configure list-profiles`. **Wait for the developer to confirm** — do not auto-select a profile, even if one is suggested in CLAUDE.md or environment variables. Never read `~/.aws/credentials` directly — it contains secret keys.
2. **Verify** the confirmed profile with `aws sts get-caller-identity --profile <PROFILE>` and show the account ID and ARN.
3. **Pass `--profile <PROFILE>`** to all subsequent AWS CLI commands and plugin scripts for the rest of the session.

Questions that don't require AWS access (docs, architecture, code samples, pricing info) can be answered immediately without a profile.

---

## Script Paths

`${CLAUDE_PLUGIN_ROOT}` in code blocks below is a placeholder — it is NOT a shell variable. Before running any script, resolve it to the actual plugin directory. Find it by checking the path of this command file (visible in the tool call that loaded it). For example, if this file was loaded from `/Users/me/.claude/plugins/cache/agent-plugins-for-aws/bedrock/0.4.1/commands/bedrock.md`, then `${CLAUDE_PLUGIN_ROOT}` = `/Users/me/.claude/plugins/cache/agent-plugins-for-aws/bedrock/0.4.1`.

---

Interpret the developer's natural language request and route to the appropriate capability.

## Knowledge Sources

Use these sources to answer Bedrock questions. Choose the source that best matches the query — you may consult multiple sources or skip sources that aren't relevant.

- **AWS Docs MCP Server** (`mcp__plugin_bedrock_aws-documentation__search_documentation`, `mcp__plugin_bedrock_aws-documentation__read_documentation`) — Official AWS documentation. Best for: API reference, service limits, pricing, IAM permissions, error codes, feature availability.
- **aws-samples prompt caching repo** (https://github.com/aws-samples/amazon-bedrock-samples/tree/main/introduction-to-bedrock/prompt-caching) — Working code samples for Converse API and InvokeModel API prompt caching. Best for: caching implementation, code examples, cache configuration patterns.
- **Bedrock Central** (https://aws-samples.github.io/sample-amazon-bedrock-central/) — Curated getting-started guides, model discovery, workshops, and sample applications. Best for: onboarding, model comparison, architecture patterns, workshop walkthroughs.
- **Plugin reference docs** (`${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/`) — Operational runbooks for the plugin's own scripts. Best for: step-by-step guidance on IAM setup, quota optimization, observability, cost analysis, and cross-region inference.
- **Internet search** — Last resort when other sources don't cover the topic. Always state that the answer came from an internet search.

Always cite the source that provided your answer.

## Routing Table

Match the developer's intent to the appropriate command:

| Intent                                                                                                              | Route To                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| First-time setup, onboarding, getting started                                                                       | `/bedrock-setup`                                                                                                                                                                                                  |
| Check if my Bedrock access works, verify permissions, can I use model X, is model available, model access in region | `/bedrock-validate-model-access`. Also load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/model-access.md` for model availability context                                                                      |
| Set up prompt caching, implement caching                                                                            | `/bedrock-cache`                                                                                                                                                                                                  |
| Cache not working, cache debugging, no cache tokens                                                                 | `/bedrock-cache-debug`                                                                                                                                                                                            |
| Caching concepts: TTL, cache duration, simplified vs explicit, mixed TTL, cachePoint, break-even, thresholds        | Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/prompt-caching.md`. For code samples, also reference https://github.com/aws-samples/amazon-bedrock-samples/tree/main/introduction-to-bedrock/prompt-caching |
| Token usage, how many tokens am I using, CloudWatch metrics                                                         | `/bedrock-usage`                                                                                                                                                                                                  |
| How much am I spending, cost breakdown, billing                                                                     | `/bedrock-costs`                                                                                                                                                                                                  |
| Quota, throttling, max_tokens, rate limits, 429 errors, retry strategy, ThrottlingException                         | `/bedrock-quota`. For retry patterns and error handling code, also load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/quota-optimization.md` (Handling ThrottlingException section)                            |
| Cross-region, higher throughput, failover, region prefix                                                            | Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/cost-optimization.md` (Cross-Region Inference section). For access issues, run `/bedrock-validate-model-access`                                             |
| AWS CLI profile setup, configure profile, which account, multiple accounts                                          | Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/profile-setup.md`                                                                                                                                           |
| IAM permissions, policies, AccessDeniedException                                                                    | Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/iam-permissions.md`                                                                                                                                         |
| Model comparison, which model should I use                                                                          | Search AWS Docs MCP for model information, then load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/model-access.md`                                                                                            |
| Pricing, how much does a model cost                                                                                 | Search AWS Docs MCP for "Amazon Bedrock pricing", link to https://aws.amazon.com/bedrock/pricing/                                                                                                                 |
| Code samples, how to call Bedrock from my app                                                                       | Fetch Bedrock Central for samples; reference https://github.com/aws-samples/amazon-bedrock-samples                                                                                                                |
| Observability, monitoring, dashboards                                                                               | Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/observability.md`                                                                                                                                           |
| Provisioned throughput, dedicated capacity, reserved capacity                                                       | Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/cost-optimization.md` (When Provisioned Throughput Makes Sense section)                                                                                     |
| Cost optimization, reduce costs, save money                                                                         | Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/cost-optimization.md`                                                                                                                                       |

## If No Route Matches

If the request doesn't match any route above:

1. Check if any plugin reference doc in `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/` covers the topic — these contain curated, verified guidance and should take priority over external sources
2. Search the AWS Docs MCP server for the topic
3. Check Bedrock Central for relevant resources
4. Fall back to internet search only if needed
5. Be transparent about which source provided the answer
