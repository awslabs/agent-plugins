# Deploy on AWS Plugin

Deploy applications to AWS with architecture recommendations, cost estimates, IaC deployment, and validated architecture diagrams.

## Overview

This plugin provides two skills: infrastructure deployment with cost estimation, and AWS architecture diagram generation as draw.io XML with official AWS4 icons.

## Skills

| Skill                      | Description                                                                                           |
| -------------------------- | ----------------------------------------------------------------------------------------------------- |
| `deploy`                   | Analyze codebases, recommend AWS services, estimate costs, and generate CDK/CloudFormation IaC        |
| `aws-architecture-diagram` | Generate validated draw.io architecture diagrams with AWS4 icons, step legends, and dark mode support |

## MCP Servers

| Server         | Description                                       |
| -------------- | ------------------------------------------------- |
| `awsiac`       | AWS IaC best practices and patterns               |
| `awsknowledge` | Architecture guidance and service recommendations |
| `awspricing`   | Real-time AWS pricing data for cost estimation    |

## Installation

```bash
/plugin marketplace add awslabs/agent-plugins
/plugin install deploy-on-aws@agent-plugins-for-aws
```

## Prerequisites

- Python 3.9+
- `defusedxml` — required for diagram XML validation: `pip3 install defusedxml>=0.7.1`
- AWS CLI with configured credentials (for deployment skills)
- [draw.io desktop](https://www.drawio.com/) (optional, for PNG/SVG/PDF export)

## Examples

- "Deploy my app to AWS"
- "Estimate AWS costs for this project"
- "Generate an architecture diagram for a serverless REST API"
- "Create a sketch-mode diagram of my IoT pipeline"
- "Analyze my codebase and generate an architecture diagram"

## Files

- `skills/deploy/SKILL.md` — Infrastructure deployment workflow
- `skills/aws-architecture-diagram/SKILL.md` — Diagram generation skill
- `skills/aws-architecture-diagram/references/` — Style guides, templates, and example diagrams
- `scripts/validate-drawio.sh` — PostToolUse hook for diagram validation
- `scripts/lib/` — Post-processing pipeline (icon colors, badge placement, legend sizing)
- `scripts/requirements.txt` — Python dependencies

## License

Apache-2.0
