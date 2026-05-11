# Error Scenarios

How to handle common failure conditions during codebase analysis.

## Empty or Non-Existent Directory

- Report: "Directory [path] not found" or "No source code files detected in [path]"
- Ask user to confirm or provide the correct target directory
- Do NOT generate documentation for an empty directory

## No Entry Point Found

- Report: "No clear entry point detected in [directory]"
- List files analyzed and ask user to specify the main entry point

## IaC Not Found

- Inform: "No IaC files detected. Deployment section will be based on code analysis only."
- Ask: "Is your IaC in a different directory?"
- If user provides IaC location: analyze that location for infrastructure context
- If no IaC exists: proceed with code-only analysis, note in Architecture Overview

## Architecture Diagram Skill Not Available

When the `deploy-on-aws` plugin (which provides the `aws-architecture-diagram` skill) is not installed:

- Generate a Mermaid `flowchart TD` architecture overview directly in the Architecture Overview section
- Include all major services, data stores, external dependencies, and infrastructure boundaries
- A simple Mermaid overview is always better than no diagram
- Mermaid sequence/flow diagrams are generated inline regardless of plugin availability

## Existing Documentation at Output Path

- Checked in Step 1 (before autonomous workflow begins)
- If `CODEBASE_ANALYSIS.md` already exists: ask user "Overwrite or write to a different filename?"
- Do NOT proceed to Step 2 without resolving the output path

## MCP Server Unavailable

- Inform: "AWS documentation enrichment unavailable (MCP server not responding)"
- Proceed without AWS-specific enrichment
- Ask: "Continue without AWS service documentation links?"
