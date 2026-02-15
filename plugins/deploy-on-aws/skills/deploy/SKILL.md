---
name: deploy
description: "Deploy applications to AWS. Triggers on phrases like: deploy to AWS, host on AWS, run this on AWS, AWS architecture, estimate AWS cost, generate infrastructure. Analyzes any codebase and deploys to optimal AWS services."
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
4. **Generate** - Write IaC code following [CDK best practices](references/cdk-best-practices.md)
   with [security defaults](references/security.md) applied
5. **Validate** - Run [validation script](scripts/validate-stack.sh) and security scans
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

Consult for IaC best practices. Use when writing CDK/CloudFormation/Terraform
to ensure patterns follow AWS recommendations.

### awscdk

CDK-specific guidance and utilities. Use for:

- Construct recommendations and API usage
- CDK pattern suggestions
- Validation of CDK configurations

## CDK Best Practices

When generating IaC (default: CDK TypeScript), follow these rules:

- **No explicit resource names** — let CDK generate unique names
- **Use grant methods** for IAM — `table.grantReadWriteData(fn)` not raw policies
- **Use language-specific Lambda constructs** — `NodejsFunction`, `PythonFunction`
- **Prefer L2/L3 constructs** over L1 (`CfnXxx`)
- **Add cdk-nag** for automated best-practice validation

See [cdk-best-practices.md](references/cdk-best-practices.md) for patterns and examples.

## Pre-Deployment Validation

Before deploying, run these checks in order:

1. Build — ensure compilation succeeds
2. Tests — run existing test suite
3. `cdk synth` — validate synthesis (with cdk-nag if configured)
4. Security scan — `checkov` or `cfn-nag` on generated templates
5. Secret detection — scan for hardcoded credentials

Use [validate-stack.sh](scripts/validate-stack.sh) to automate checks 3-4.

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
- Follow [CDK best practices](references/cdk-best-practices.md) when generating IaC
- Run IaC security scans (cfn-nag, checkov) before deployment
- Set up [monitoring](references/monitoring.md) after deployment
- Don't ask "Lambda or Fargate?" — just pick the obvious one
- If genuinely ambiguous, then ask

## References

- [Service defaults](references/defaults.md)
- [Security defaults](references/security.md)
- [Cost estimation patterns](references/cost-estimation.md)
- [CDK best practices](references/cdk-best-practices.md)
- [Monitoring and observability](references/monitoring.md)
- [Validation script](scripts/validate-stack.sh)
