---
name: deploy
description: "Deploy applications to AWS. Triggers on phrases like: deploy to AWS, host on AWS, run this on AWS, AWS architecture, estimate AWS cost, generate infrastructure. Analyzes any codebase and deploys to optimal AWS services."
tags:
  - aws
  - deployment
  - cdk
  - monitoring
  - infrastructure
examples:
  - "Deploy this Flask app to AWS"
  - "Host my React site on AWS"
  - "Estimate AWS costs for this project"
  - "Generate CDK code for this application"
---

# Deploy on AWS

Take any application and deploy it to AWS with minimal user decisions.

## Philosophy

**Minimize cognitive burden.** User has code, wants it on AWS. Pick the most
straightforward services. Don't ask questions with obvious answers.

## Workflow

1. **Analyze** - Scan codebase for framework, database, dependencies
2. **Recommend** - Select AWS services, concisely explain rationale
3. **Estimate** - Show monthly cost before proceeding
4. **Generate** - Write IaC code following CDK best practices (call `cdk_best_practices`
   via `awsiac` MCP) with [security defaults](references/security.md) applied
5. **Validate** - Run synthesis, security scans, and
   [validation script](scripts/validate-stack.sh)
6. **Deploy** - Execute with user confirmation
7. **Monitor** - Set up [monitoring](references/monitoring.md) for deployed resources

## Defaults

See [defaults.md](references/defaults.md) for the complete service selection matrix.

Core principle: Default to **dev-sized** (cost-conscious: small instance sizes, minimal
redundancy, and non-HA/single-AZ defaults) unless user says "production-ready".

## MCP Servers

### awsknowledge

Consult for architecture decisions. Use when choosing between AWS services
or validating that a service fits the use case. Helps answer "what's the
right AWS service for X?"

Key topics: `general` for architecture, `amplify_docs` for static sites/SPAs,
`cdk_docs` and `cdk_constructs` for IaC patterns.

### awspricing

Get cost estimates. **Always present costs before generating IaC** so user
can adjust before committing. See [cost-estimation.md](references/cost-estimation.md)
for query patterns.

### awsiac

Use for IaC generation and validation:

- **Before writing CDK code** — call `cdk_best_practices` for development guidelines
- **For construct usage** — call `search_cdk_documentation` with specific construct names
- **For code examples** — call `search_cdk_samples_and_constructs` with language filter
- **For template validation** — call `validate_cloudformation_template` on synthesized output
- **For compliance checks** — call `check_cloudformation_template_compliance`

### awscdk

CDK-specific guidance and utilities. Use for:

- Construct recommendations and API usage
- CDK pattern suggestions
- Validation of CDK configurations

## CDK Best Practices

Call `cdk_best_practices` via the `awsiac` MCP server before generating CDK code.
In addition to the MCP guidelines, apply these deploy-specific rules:

- **Use language-specific Lambda constructs** — `NodejsFunction` (TypeScript),
  `PythonFunction` (Python) for automatic dependency bundling

## Pre-Deployment Validation

Before deploying, run these checks in order:

1. Build — ensure compilation succeeds
2. Tests — run existing test suite
3. `cdk synth` — validate synthesis (with cdk-nag if configured)
4. Security scan — `checkov` or `cfn-nag` on generated templates
5. Secret detection — scan for hardcoded credentials

Use [validate-stack.sh](scripts/validate-stack.sh) to automate synthesis validation
and template analysis (steps 3). Run `checkov` or `cfn-nag` separately for step 4.

## Error Handling

### MCP Server Unavailable

If awscdk or awsiac MCP servers are unresponsive:

- Inform user: "[server] MCP not responding"
- Continue using inline CDK best practices from this skill
- DO NOT skip cost estimation if awspricing fails — ask user to proceed without estimate

### Validation Failures

If `cdk synth` or validation script fails:

- Show the error output to the user
- Identify and fix the issue in generated code
- Re-run validation before proceeding to deploy
- DO NOT deploy with failing validation

### Deployment Failures

If `cdk deploy` fails:

- Show the CloudFormation error event
- Suggest fix based on error type
- Stack will auto-rollback — no manual cleanup needed

## Post-Deployment Monitoring

After successful deployment, set up monitoring appropriate to the environment:

- **Dev**: Basic error alerting (Lambda errors, Fargate task failures)
- **Production**: Full observability (alarms, dashboards, structured logging)

See [monitoring.md](references/monitoring.md) for CloudWatch alarm patterns by service.

## Principles

- Concisely explain why each service was chosen
- Always show cost estimate before generating code
- Apply [security defaults](references/security.md) automatically (encryption,
  private subnets, least privilege)
- Call `cdk_best_practices` via `awsiac` MCP when generating IaC
- Run IaC security scans (cfn-nag, checkov) before deployment
- Set up [monitoring](references/monitoring.md) after deployment
- Don't ask "Lambda or Fargate?" — just pick the obvious one
- If genuinely ambiguous, then ask

## References

- [Service defaults](references/defaults.md)
- [Security defaults](references/security.md)
- [Cost estimation patterns](references/cost-estimation.md)
- [Monitoring and observability](references/monitoring.md)
- [Validation script](scripts/validate-stack.sh)
