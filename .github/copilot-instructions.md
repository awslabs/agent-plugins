# GitHub Copilot Custom Instructions for Agent Plugins for AWS

## Project Overview

This repository contains Agent Plugins for AWS that equip AI coding agents with the skills to help architects, deploy, and operate on AWS. The primary plugin is `deploy-on-aws`, which provides recommendations, cost estimates, and Infrastructure as Code generation.

## Technology Stack

- **Language**: Primarily TypeScript/JavaScript
- **Framework**: Claude Code plugins
- **Cloud Platform**: AWS
- **Infrastructure as Code**: CDK and CloudFormation
- **Tools**: MCP Servers (awsknowledge, awspricing, aws-iac-mcp)

## Code Organization

- `/plugins` - Plugin implementations
- `/schemas` - Data schemas and type definitions
- `/tools` - Utility tools and helpers
- `/.github` - GitHub workflows and configuration
- Root files: Configuration for linting (markdownlint, semgrep), security (gitleaks), and formatting (dprint)

## Development Practices

1. **Code Quality**: Uses pre-commit hooks, semgrep for security analysis, and gitleaks for secret detection
2. **Documentation**: Comprehensive guides including DEVELOPMENT_GUIDE.md, CONTRIBUTING.md, TROUBLESHOOTING.md
3. **Testing**: Follow existing test patterns in the codebase
4. **Formatting**: Use dprint for code formatting consistency
5. **Commit Signoff**: Web commit signoff required (git commit -S flag)

## Plugin Development Guidelines

- Follow the workflow pattern: Analyze → Recommend → Estimate → Generate → Deploy
- MCP Servers provide: AWS documentation, pricing data, and IaC best practices
- Skill triggers should be intuitive natural language phrases users would say
- Always include cost estimation and confirmation steps before deployment
- Generate infrastructure code with explanations and best practices

## Important Reminders for Copilot

1. **AWS Best Practices**: Recommend services aligned with AWS Well-Architected Framework
2. **Cost Awareness**: Always estimate and display costs to users
3. **User Confirmation**: Never deploy without explicit user confirmation
4. **Multi-Agent Support**: Currently supports Claude Code; consider extensibility
5. **Security**: Follow AWS security best practices and principle of least privilege
6. **Documentation**: Provide clear explanations for architectural recommendations

## Key Files to Reference

- `README.md` - Project overview and installation instructions
- `DEVELOPMENT_GUIDE.md` - How to create new plugins
- `CONTRIBUTING.md` - Contribution guidelines
- `TROUBLESHOOTING.md` - Common issues and solutions

## License

Apache-2.0 License - Ensure all contributions comply with this license
