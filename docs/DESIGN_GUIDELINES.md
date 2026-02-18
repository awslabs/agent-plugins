# Plugin Design Guidelines

This document outlines best practices for authoring plugins, skills, and MCP integrations that work effectively with AI agents.

## Quick Reference: Essential Best Practices

1. **Keep plugins focused** — Do one thing well rather than bundling unrelated features
2. **Document thoroughly** — Include a clear README with usage examples
3. **Use semantic versioning** — Follow [Semantic Versioning](https://semver.org/) for version numbers (Major.Minor.Patch)
4. **Add proper frontmatter** — All skills need `name` and `description` per the [Agent Skills spec](https://agentskills.io/specification)
5. **Test locally first** — Verify your plugin works before submitting (`mise run build`) and load it in an AI assistant that supports the standard
6. **Use descriptive keywords** — Put trigger phrases and 3–7 keywords in the description (and optionally in `metadata`) for discoverability

See detailed sections below for implementation guidance.

## Core Principles

### 1. Minimize Context Usage

**Files should be SHORT and FOCUSED**. Every token counts in an agent's context window.

**Good:**

```
skills/
  deploy/
    SKILL.md              # 200 lines: core workflow
    references/
      defaults.md         # 50 lines: service selections
      cost.md             # 30 lines: estimation rules
      security.md         # 40 lines: security checks
```

**Bad:**

```
skills/
  deploy/
    SKILL.md              # 1000 lines: everything in one file
```

**Why:** Agents can selectively load reference files when needed. A 1000-line file loads all content upfront, wasting context on unused information. Don't dump your whole wiki!

### 2. Write for Agents, Not Humans

Agents need **explicit, unambiguous instructions**. Avoid conversational language, humor, or narrative explanations.

**Good:**

```markdown
## Cost Estimation

REQUIRED: Show cost estimate BEFORE generating IaC code.

Steps:

1. Use awspricing MCP to get hourly rates
2. Calculate monthly cost: hourly_rate × 730
3. Present as table with service breakdown
4. Wait for user confirmation
```

**Bad:**

```markdown
## Cost Estimation

It's really important to make sure users understand the costs!
You should probably check the pricing (maybe use the awspricing
tool?) and show them what it might cost. They'll appreciate
knowing before you deploy anything. 😊
```

**Why:** Agents execute instructions literally. Vague language ("probably", "maybe", "should") creates ambiguity and inconsistent behavior.

### 3. Single Responsibility per Skill

Each skill should do ONE thing well. Split complex workflows into separate skills.

**Good:**

- `deploy` - Full deployment workflow
- `estimate-cost` - Cost analysis only
- `security-review` - Security posture assessment

**Bad:**

- `aws-helper` - Does deployment, costs, security, monitoring, backup, etc.

**Why:** Focused skills trigger more reliably and are easier to maintain and test.

### 4. Keep Plugins Focused

Plugins should have a **clear, cohesive purpose**. Bundle related skills and MCP servers, not unrelated features.

**Good plugin scope:**

- `deploy-on-aws` - AWS deployment workflow (architecture, costing, IaC generation)
- `database-tools` - Database operations (migrations, backups, schema validation)
- `security-scanner` - Security analysis (vulnerability scanning, SAST, dependency checks)

**Bad plugin scope:**

- `developer-toolkit` - AWS deployment + database tools + Git helpers + code formatting + test runner
- `utilities` - Random collection of unrelated skills

**Why:**

- Focused plugins are easier to discover and understand
- Users can install only what they need
- Maintenance and testing are simpler
- Clear value proposition attracts more users

**Rule of thumb:** If your plugin description uses "and" more than once, consider splitting it into multiple plugins.

## Skill Authoring Best Practices

Skill frontmatter must follow the [Agent Skills specification](https://agentskills.io/specification). Only spec-defined fields are guaranteed to work across implementations.

### YAML Frontmatter

**Required fields:** `name`, `description`. **Optional:** `license`, `compatibility`, `metadata`, `allowed-tools` (experimental).

```yaml
---
name: deploy
description: |
  Deploy web applications to AWS with architecture recommendations,
  cost estimates, and generated Infrastructure as Code.
  Triggers when user says: "deploy to AWS", "host on AWS", "publish to AWS",
  or similar deployment intent. Use for Flask, React, static sites, and APIs.
license: Apache-2.0
metadata:
  tags: aws, deployment, infrastructure, iac
---
```

**Key fields (spec-compliant):**

- `name` - **Required.** Skill identifier; 1–64 chars, lowercase letters, numbers, hyphens only; no leading/trailing or consecutive hyphens; must match the skill directory name (e.g. `deploy` for `skills/deploy/SKILL.md`).
- `description` - **Required.** How the agent decides to trigger this skill (max 1024 chars). Include what the skill does and when to use it; add trigger phrases and keywords here so agents match user intent.
- `license` - Optional. License name or reference to a bundled license file.
- `compatibility` - Optional. Environment requirements (max 500 chars), e.g. required tools or network access.
- `metadata` - Optional. Arbitrary key-value map (e.g. `tags`, `version`, `author`) for discovery or tooling; key names should be reasonably unique.
- `allowed-tools` - Optional (experimental). Space-delimited list of pre-approved tools the skill may use.

### Tags & Keywords for Discoverability

The Agent Skills spec does not define a top-level `tags` field. Put **keywords and trigger phrases in the `description`** so agents and tooling can match user intent. Optionally use **`metadata`** (e.g. `metadata.tags`) for marketplace or client-specific discovery if your implementation supports it.

**Best practices:**

- **Be specific in the description** - Mention `lambda`, `fargate`, `ec2`, and use cases so agents and search can match
- **Include trigger phrases** - e.g. "Triggers when user says: deploy to AWS, host on AWS, …"
- **Think like users** - What would someone search for? Include those terms in the description
- **Avoid redundancy** - Don't repeat the skill name unnecessarily
- **Use 3–7 keywords** - In description or in `metadata.tags` (comma- or space-separated string) if supported

**Good (description + optional metadata):**

```yaml
description: "Deploy to AWS with architecture recommendations and IaC. Triggers on: deploy to AWS, host on AWS, run on AWS. Supports Flask, React, static sites, Fargate, Lambda."
metadata:
  tags: aws, deployment, infrastructure, iac, fargate, lambda
```

**Bad:**

```yaml
description: "Deploy to AWS."   # too vague; no trigger phrases or keywords
metadata:
  tags: deploy, cloud, stuff   # redundant or meaningless
```

**Keyword selection checklist:**

- [ ] Description includes cloud provider/platform (if applicable)
- [ ] Description states primary function (deploy, test, monitor, etc.)
- [ ] Description or metadata lists specific technologies/services used
- [ ] Trigger phrases and terms align with how users search or ask
- [ ] Tested by searching marketplace or invoking with those phrases

### Instruction Structure

Use clear hierarchies and action-oriented headers:

```markdown
## Workflow

### Step 1: Analyze

- Detect framework from package.json/requirements.txt/go.mod
- Identify database dependencies
- Check for static assets

### Step 2: Recommend

- Select services (see references/defaults.md)
- Provide 1-sentence rationale per service
- Present as table: Service | Purpose | Rationale

### Step 3: Estimate Cost

- REQUIRED: Use awspricing MCP server
- Show monthly estimate before proceeding
- Wait for user confirmation
```

**Why:** Numbered steps, bullets, and clear headers make instructions scannable for agents.

### Default Behavior vs Options

**Specify defaults clearly**, then provide override syntax:

```markdown
## IaC Generation

Default: CDK TypeScript

Override syntax:

- "use Terraform" → Generate .tf files
- "use CloudFormation" → Generate YAML templates
- "use CDK Python" → Generate Python CDK

When not specified, ALWAYS use CDK TypeScript.
```

**Why:** Agents need explicit guidance on what to do when users don't specify preferences.

### Error Handling

Tell agents **exactly what to do** when things fail:

```markdown
## Error Scenarios

### MCP Server Unavailable

- Inform user: "Cost estimation unavailable (awspricing MCP not responding)"
- Ask: "Proceed without cost estimate?"
- DO NOT continue without user confirmation

### Unsupported Framework

- List detected framework
- State: "No AWS deployment pattern for [framework]"
- Suggest manual configuration or alternative approach
```

**Why:** Prevents agents from making assumptions or hallucinating recovery strategies.

## MCP Server Integration

### When to Use MCP

**Use MCP servers for:**

- External data (pricing, documentation)
- Real-time information
- Complex computations
- Service integrations (AWS APIs, GitHub, etc.)

**Use inline instructions for:**

- Logic and decision-making
- Workflow orchestration
- Output formatting
- User interaction patterns

### MCP Configuration

Keep `.mcp.json` minimal and focused:

```json
{
  "mcpServers": {
    "awspricing": {
      "command": "npx",
      "args": ["-y", "@aws/mcp-server-pricing"],
      "env": {
        "AWS_REGION": "us-east-1"
      }
    }
  }
}
```

**Include:**

- Only servers this plugin needs
- Required environment variables
- Timeout configurations if non-standard

**Exclude:**

- Servers available globally
- Optional nice-to-have integrations

## File Organization

### References Directory

Break instructions into logical reference files:

```
skills/myskill/
  SKILL.md                 # Main workflow (200-300 lines max)
  references/
    defaults.md            # Default selections/configurations
    patterns.md            # Common patterns and templates
    troubleshooting.md     # Error messages and fixes
    examples/
      basic.md             # Simple example
      advanced.md          # Complex example
```

**Reference file best practices:**

- Max 50-100 lines per file
- Single topic per file
- Link from main SKILL.md: "See references/defaults.md for service selection rules"
- Use descriptive filenames

### Progressive Disclosure

Structure content so agents load details **only when needed**:

```markdown
## Database Selection

Default: Aurora Serverless v2 for PostgreSQL/MySQL apps

See references/databases.md for:

- NoSQL alternatives (DynamoDB)
- Data warehouse options (Redshift)
- Caching strategies (ElastiCache)
```

**Why:** Keeps initial context small. Agent loads references/databases.md only when user needs alternatives.

## Testing & Validation

### Local Testing

Before submitting plugins:

```bash
# Validate manifests
mise run lint:manifests

# Check cross-references
mise run lint:cross-refs

# Test skill in isolation
claude --plugin-dir ./plugins/myplugin

# Full integration test
mise run build
```

### Test Cases to Verify

- **Auto-trigger accuracy** - Does description match intended use cases?
- **Reference loading** - Are references loaded when expected?
- **Error handling** - Do failure scenarios behave correctly?
- **Token usage** - Is context consumption reasonable?

### Measuring Context Usage

Use Claude Code with `--verbose` to see token consumption:

```bash
claude --plugin-dir ./plugins/myplugin --verbose
```

**Target:** Skills should use <5000 tokens for initial load (SKILL.md + plugin.json)

## Anti-Patterns

### ❌ Don't: Massive Monolithic Files

```
skills/deploy/SKILL.md    # 2000 lines
```

**Why:** Wastes context on unused content.

### ❌ Don't: Vague Conditional Language

```markdown
You might want to consider using Aurora if the user seems
like they need a database. Or maybe RDS? Use your judgment!
```

**Why:** Creates inconsistent behavior.

### ❌ Don't: Human-Centric Documentation

```markdown
Welcome to the deployment skill! This skill was created to
help developers like you deploy apps to AWS. It's really
cool because...
```

**Why:** Wastes tokens. Agents don't need motivation or backstory.

### ❌ Don't: Implicit Defaults

```markdown
Generate IaC code using the appropriate tool.
```

**Why:** "Appropriate" is ambiguous. Specify: "Default: CDK TypeScript. Override with: 'use Terraform'."

### ❌ Don't: Missing Error Handling

```markdown
Use the awspricing MCP to get cost estimates.
```

**Why:** What if MCP fails? Agent needs explicit instructions.

## Performance Optimization

### Lazy Loading

**Good:**

```markdown
For advanced networking configurations, see references/networking.md
```

**Bad:**

```markdown
[Inline 500 lines of networking configuration that 95% of users won't need]
```

### Caching Guidance

Tell agents when to cache vs re-fetch:

```markdown
## Service Catalog

Cache AWS service list for session duration (changes infrequently).
DO NOT re-fetch on every recommendation.

## Pricing Data

Fetch fresh pricing on each cost estimation (changes frequently).
DO NOT cache across estimates.
```

### Minimize Roundtrips

**Good:**

```markdown
1. Analyze codebase (1 scan)
2. Select services (1 decision)
3. Estimate cost (1 MCP call)
4. Generate IaC (1 generation)
```

**Bad:**

```markdown
1. Scan for framework
2. Scan for dependencies
3. Scan for database
4. Scan for assets
   [...10 more sequential scans...]
```

## Versioning & Compatibility

### Semantic Versioning

Follow semver for plugin versions:

MAJOR (2.0.0) - version when you make incompatible (breaking) changes
MINOR (1.1.0) - version when you add functionality in a backward compatible manner
PATCH (1.0.1) - version when you make backward compatible bug fixes

### Deprecation Strategy

When removing/changing skills:

1. **1 minor version warning:**

   ```markdown
   ## Legacy Syntax (Deprecated)

   "deploy with Lambda" is deprecated. Use "deploy-serverless" skill instead.
   Support ends in v2.0.0.
   ```

2. **Major version removal:**

   ```json
   {
     "version": "2.0.0",
     "changelog": "Removed deprecated 'deploy with Lambda' syntax. Use deploy-serverless skill."
   }
   ```

## Documentation Requirements

### README.md (Plugin Root)

Required sections:

- **Overview** - 1-2 sentence plugin purpose
- **Skills** - List of included skills with descriptions
- **MCP Servers** - Required servers and what they provide
- **Installation** - `claude plugin install` command
- **Examples** - 3-5 concrete usage examples

Keep under 300 lines.

### SKILL.md

Required sections:

- **YAML Frontmatter** - `name` and `description` (required per [Agent Skills spec](https://agentskills.io/specification)); optional: license, compatibility, metadata, allowed-tools
- **Workflow** - Step-by-step execution logic
- **Defaults** - Explicit default behaviors
- **Error Handling** - Failure scenarios and recovery

### Reference Files

Optional but recommended:

- **defaults.md** - Default selections and configurations
- **patterns.md** - Common templates and examples
- **troubleshooting.md** - Error messages and resolutions

## Review Checklist

Before submitting a plugin, verify:

**Plugin Design:**

- [ ] Plugin has clear, focused purpose (not bundling unrelated features)
- [ ] README includes overview, skills list, installation, and usage examples
- [ ] Plugin follows semantic versioning (semver)
- [ ] Tags are descriptive and aid discoverability (3-7 specific keywords)

**Skill Quality:**

- [ ] All SKILL.md files under 300 lines
- [ ] Reference files under 100 lines each
- [ ] All skills have proper YAML frontmatter (name, description; optional metadata/tags per [Agent Skills spec](https://agentskills.io/specification))
- [ ] Skill descriptions clearly state trigger conditions
- [ ] All defaults explicitly specified
- [ ] Error handling documented for MCP failures
- [ ] No vague language ("maybe", "probably", "consider")

**Testing & Validation:**

- [ ] Local testing successful (`claude --plugin-dir ./plugins/myplugin`)
- [ ] All cross-references valid (`mise run lint:cross-refs`)
- [ ] Manifests validate (`mise run lint:manifests`)
- [ ] Full build passes (`mise run build`)
- [ ] Token usage reasonable (<5000 for initial load)

## Additional Resources

- [Agent Skills specification](https://agentskills.io/specification) - Official format for SKILL.md frontmatter and directory structure
- `.claude/docs/skills_docs.md` - Skill authoring technical reference
- `.claude/docs/plugin_reference.md` - Plugin manifest specification
- `../schemas/` - JSON schemas for validation
- `../CLAUDE.md` - Repository-specific instructions
