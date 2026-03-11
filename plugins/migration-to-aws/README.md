# GCP-to-AWS Migration Plugin

Migrate workloads from Google Cloud Platform to AWS with a 5-phase guided process.

## Overview

This plugin guides you through migrating GCP infrastructure to AWS by:

1. **Discover** - Scan Terraform files for GCP resources
2. **Clarify** - Answer 8 questions about your migration requirements
3. **Design** - Map GCP services to equivalent AWS services
4. **Estimate** - Calculate monthly costs and ROI
5. **Execute** - Plan your migration timeline and rollback procedures

## Usage

Invoke the skill with migration-related phrases:

- "Migrate my GCP infrastructure to AWS"
- "Move off Google Cloud"
- "Migrate Cloud SQL to RDS"
- "GCP to AWS migration plan"

## Scope (v1.0)

- **Supports**: Terraform-based GCP infrastructure
- **Generates**: AWS architecture design, cost estimates, execution timeline
- **Does not include** (v1.1+): App code scanning, billing data import, CDK code generation

## MCP Servers

The plugin integrates with:

- **awspricing** - Real-time AWS pricing (with fallback to cached data)
- **awsknowledge** - AWS service guidance and best practices

## Files

- `SKILL.md` - Main skill orchestrator
- `references/phases/` - Workflow phase implementations
- `references/design-refs/` - AWS service mapping rubrics
- `references/shared/` - Shared utilities and pricing data

## Architecture

The plugin uses state files (`.migration/[MMDD-HHMM]/`) to track migration progress across invocations:

- `.phase-status.json` - Current phase and status
- `gcp-resource-inventory.json` - Discovered GCP resources
- `clarified.json` - User requirements
- `aws-design.json` - Mapped AWS services
- `estimation.json` - Cost analysis
- `execution.json` - Timeline and risks

## Installation

```bash
/plugin marketplace add awslabs/agent-plugins
/plugin install migration-to-aws@agent-plugins-for-aws
```

## Development

To test locally:

```bash
claude --plugin-dir ./plugins/migration-to-aws
```

## License

Apache-2.0
