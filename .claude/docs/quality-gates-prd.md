# PRD: Documentation & Manifest Quality Gates for AWS Agent Plugins

**Repo type:** Agent plugin marketplace
**Primary assets:** SKILL.md files, JSON manifests (plugin.json, marketplace.json, .mcp.json)
**Secondary assets:** Reference documentation (Markdown)
**Owner:** AWS Agent Plugins maintainers
**Status:** Draft

---

## 1) Problem Statement

The `awslabs/agent-plugins` marketplace enables contributors to create and share plugins for AI coding assistants. As the plugin ecosystem grows, the repo needs:

- Consistent formatting for Markdown (especially SKILL.md files) and JSON manifests
- Validation of SKILL.md structure, frontmatter, and length constraints
- Schema validation for JSON manifests (plugin.json, marketplace.json, .mcp.json)
- Quality gates that prevent broken plugins from being merged
- Enforcement of progressive disclosure patterns (SKILL.md length limits)

---

## 2) Goals

1. **Consistency:** Deterministic formatting across all contributors and CI.
2. **Quality gates:** Fail CI on:
   - Invalid YAML frontmatter in SKILL.md files
   - SKILL.md files exceeding length limits (encourage progressive disclosure)
   - Missing required sections in SKILL.md
   - Invalid JSON manifests (schema violations)
   - Malformed MCP configurations
3. **Low friction:** Single `mise run lint` command for local and CI validation.
4. **Progressive disclosure:** Enforce SKILL.md constraints that encourage keeping main skill content concise with supporting files for details.
5. **Extensibility:** Easy to add new constraints as plugin standards evolve.

---

## 3) Non-Goals

- Enforcing prose style (tone, terminology) in v1
- Validating MCP server connectivity or runtime behavior
- Building a plugin documentation site
- Automated code generation from manifests

---

## 4) User Stories

| Actor | Story |
|-------|-------|
| **Plugin contributor** | "I run `mise run lint` and know my plugin meets all requirements before opening a PR." |
| **PR reviewer** | "CI tells me exactly what failed and where, so I can give precise feedback." |
| **Marketplace maintainer** | "I encode plugin requirements in config, not tribal knowledge or PR comments." |
| **Plugin consumer** | "Every plugin in the marketplace has consistent quality and structure." |

---

## 5) Plugin-Specific Constraints

### 5.1 SKILL.md Requirements

Based on Claude Code skill authoring guidelines:

| Constraint | Rationale | Implementation |
|------------|-----------|----------------|
| **Max 500 lines** | Encourages progressive disclosure; main skill should be focused | Custom remark plugin |
| **Max ~8,000 words** | Prevents context bloat; detailed content goes in references/ | Custom remark plugin |
| **Required frontmatter** | Skills must have `name` and `description` | Frontmatter schema validation |
| **Valid frontmatter fields** | Prevent typos in field names | JSON Schema for frontmatter |
| **Required sections** | Consistent structure across plugins | remark structure validation |

#### SKILL.md Frontmatter Schema

```yaml
# Required fields
name: string (kebab-case, max 64 chars)
description: string (required, describes when skill triggers)

# Optional fields
argument-hint: string
disable-model-invocation: boolean
user-invocable: boolean
allowed-tools: string (comma-separated)
model: string
context: "fork" | omit
agent: string (if context: fork)
hooks: object
```

#### SKILL.md Required Sections (Recommended)

- H1 title matching skill name
- Overview/description section
- Usage or workflow section
- At least one of: examples, references, or principles

### 5.2 JSON Manifest Requirements

| File | Required Fields | Validation |
|------|-----------------|------------|
| `marketplace.json` | `name`, `owner.name`, `metadata.pluginRoot`, `plugins[]` | JSON Schema |
| `plugin.json` | `name`, `description` | JSON Schema |
| `.mcp.json` | `mcpServers` object with valid server configs | JSON Schema |

### 5.3 Reference Documentation

Reference files in `references/` subdirectories:
- No length limits (detailed content belongs here)
- Proper heading structure (no skipped levels)
- Valid code blocks with language identifiers

---

## 6) Proposed Toolchain

### 6.1 Tool Orchestration: mise

**mise** pins runtimes and installs tools across ecosystems:

```toml
# mise.toml
[tools]
node = "22"
"npm:markdownlint-cli2" = "0.17"
"npm:ajv-cli" = "5"
```

### 6.2 Formatting: dprint

**dprint** formats Markdown and JSON with consistent output:
- Markdown: `textWrap: "maintain"` (preserve line breaks)
- JSON: 2-space indent, LF line endings
- Handles YAML frontmatter in Markdown

### 6.3 Markdown Linting: markdownlint-cli2

**markdownlint-cli2** enforces Markdown style rules:
- Heading structure (no skipped levels)
- Code block language identifiers
- Consistent list markers
- YAML frontmatter recognition

### 6.4 Structure Validation: remark (unified)

**remark** provides AST-based validation for:
- SKILL.md length limits (lines and words)
- Required sections
- Frontmatter schema validation
- Code fence language validation

### 6.5 JSON Schema Validation: ajv-cli

**ajv-cli** validates manifests against JSON Schemas:
- `schemas/marketplace.schema.json`
- `schemas/plugin.schema.json`
- `schemas/mcp.schema.json`

---

## 7) Requirements

### 7.1 Functional Requirements

**FR1. Formatting**
- `fmt` formats Markdown and JSON deterministically
- `fmt:check` verifies formatting without modifying files

**FR2. SKILL.md Validation**
- `lint:skills` validates SKILL.md files:
  - Frontmatter presence and schema
  - Length constraints (500 lines, ~8000 words)
  - Required sections
- `lint:skills:length` reports files exceeding limits with actionable guidance

**FR3. Markdown Lint**
- `lint:md` flags common Markdown violations
- `lint:md:structure` enforces heading hierarchy

**FR4. JSON Manifests**
- `lint:manifests` validates all JSON against schemas
- `lint:manifests:marketplace` validates marketplace.json
- `lint:manifests:plugins` validates plugin.json files
- `lint:manifests:mcp` validates .mcp.json files

### 7.2 Non-Functional Requirements

- **NFR1:** Tools run cross-platform (macOS/Linux via mise)
- **NFR2:** CI completes in under 60 seconds
- **NFR3:** Failures include file paths and line numbers
- **NFR4:** Local experience matches CI exactly

---

## 8) Configuration Files

### 8.1 Directory Structure

```
awslabs-agent-plugins/
├── .github/
│   └── workflows/
│       └── quality.yml           # CI workflow
├── schemas/                       # JSON Schemas
│   ├── marketplace.schema.json
│   ├── plugin.schema.json
│   ├── mcp.schema.json
│   └── skill-frontmatter.schema.json
├── tools/                         # Custom markdownlint rules
│   ├── markdownlint-skill-length.cjs
│   └── markdownlint-frontmatter.cjs
├── mise.toml                      # Tool versions and tasks
├── dprint.json                    # Formatter config
└── .markdownlint-cli2.yaml        # Markdown lint rules + custom rules
```

### 8.2 mise.toml

```toml
min_version = "2024.11.1"

[tools]
node = "22"
"npm:markdownlint-cli2" = "0.17"
"npm:ajv-cli" = "5"

[tasks.fmt]
description = "Format all files"
run = "npx dprint fmt"

[tasks."fmt:check"]
description = "Check formatting (CI)"
run = "npx dprint check"

[tasks.lint]
description = "Run all linters"
depends = ["lint:md", "lint:manifests"]

[tasks."lint:md"]
description = "Lint Markdown files (includes SKILL.md validation)"
run = "markdownlint-cli2 '**/*.md' '#node_modules'"

[tasks."lint:manifests"]
description = "Validate JSON manifests"
run = [
  "ajv validate -s schemas/marketplace.schema.json -d '.claude-plugin/marketplace.json' --all-errors --errors=text",
  "ajv validate -s schemas/plugin.schema.json -d 'plugins/**/.claude-plugin/plugin.json' --all-errors --errors=text",
  "ajv validate -s schemas/mcp.schema.json -d 'plugins/**/.mcp.json' --all-errors --errors=text",
]

[tasks.ci]
description = "Run all CI checks"
depends = ["fmt:check", "lint"]
```

### 8.3 dprint.json

```json
{
  "$schema": "https://dprint.dev/schemas/v0.json",
  "lineWidth": 100,
  "indentWidth": 2,
  "useTabs": false,
  "newLineKind": "lf",
  "markdown": {
    "lineWidth": 100,
    "textWrap": "maintain"
  },
  "json": {
    "indentWidth": 2,
    "lineWidth": 120
  },
  "excludes": [
    "**/node_modules/**",
    "**/.git/**",
    "**/dist/**"
  ],
  "plugins": [
    "https://plugins.dprint.dev/markdown-0.20.0.wasm",
    "https://plugins.dprint.dev/json-0.21.0.wasm"
  ]
}
```

### 8.4 .markdownlint-cli2.yaml

```yaml
# YAML frontmatter pattern
frontMatter: "^---\\n[\\s\\S]*?\\n---\\n"

# Custom rules for SKILL.md validation
customRules:
  - ./tools/markdownlint-skill-length.cjs
  - ./tools/markdownlint-frontmatter.cjs

gitignore: true

globs:
  - "**/*.md"

ignores:
  - "**/node_modules/**"
  - ".claude/docs/**"

config:
  default: true

  # Heading structure
  MD001: true
  MD003:
    style: "atx"

  # Line length - relaxed for documentation
  MD013:
    line_length: 120
    code_block_line_length: 200
    code_blocks: false
    tables: false

  # Allow duplicate headings under different parents
  MD024:
    siblings_only: true

  # Allow specific HTML elements
  MD033:
    allowed_elements:
      - "br"
      - "details"
      - "summary"

  # Disable for YAML frontmatter files
  MD041: false

  # Code blocks must be fenced
  MD046:
    style: "fenced"

  # Files must end with newline
  MD047: true
```

---

## 9) JSON Schemas

### 9.1 schemas/plugin.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://awslabs.github.io/agent-plugins/schemas/plugin.schema.json",
  "title": "Plugin Manifest",
  "description": "Schema for plugin.json files in AWS Agent Plugins",
  "type": "object",
  "required": ["name"],
  "properties": {
    "name": {
      "type": "string",
      "description": "Plugin identifier (kebab-case)",
      "pattern": "^[a-z][a-z0-9-]*$",
      "minLength": 1,
      "maxLength": 64
    },
    "description": {
      "type": "string",
      "description": "Brief plugin description",
      "maxLength": 500
    },
    "version": {
      "type": "string",
      "description": "Semantic version",
      "pattern": "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(-[a-zA-Z0-9.-]+)?$"
    },
    "author": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "email": { "type": "string", "format": "email" }
      }
    },
    "homepage": {
      "type": "string",
      "format": "uri"
    },
    "repository": {
      "type": "string",
      "format": "uri"
    },
    "license": {
      "type": "string",
      "description": "SPDX license identifier"
    },
    "keywords": {
      "type": "array",
      "items": { "type": "string" },
      "uniqueItems": true
    }
  },
  "additionalProperties": true
}
```

### 9.2 schemas/marketplace.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://awslabs.github.io/agent-plugins/schemas/marketplace.schema.json",
  "title": "Marketplace Registry",
  "description": "Schema for marketplace.json registry file",
  "type": "object",
  "required": ["name", "owner", "metadata", "plugins"],
  "properties": {
    "name": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9-]*$"
    },
    "owner": {
      "type": "object",
      "required": ["name"],
      "properties": {
        "name": { "type": "string" },
        "email": { "type": "string", "format": "email" }
      }
    },
    "metadata": {
      "type": "object",
      "required": ["pluginRoot"],
      "properties": {
        "description": { "type": "string" },
        "version": { "type": "string" },
        "pluginRoot": { "type": "string" }
      }
    },
    "plugins": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "source"],
        "properties": {
          "name": {
            "type": "string",
            "pattern": "^[a-z][a-z0-9-]*$"
          },
          "source": {
            "oneOf": [
              { "type": "string" },
              {
                "type": "object",
                "properties": {
                  "github": { "type": "string" },
                  "url": { "type": "string", "format": "uri" }
                }
              }
            ]
          },
          "description": { "type": "string" },
          "version": { "type": "string" },
          "category": { "type": "string" },
          "tags": {
            "type": "array",
            "items": { "type": "string" }
          },
          "keywords": {
            "type": "array",
            "items": { "type": "string" }
          }
        }
      }
    }
  }
}
```

### 9.3 schemas/mcp.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://awslabs.github.io/agent-plugins/schemas/mcp.schema.json",
  "title": "MCP Configuration",
  "description": "Schema for .mcp.json MCP server definitions",
  "type": "object",
  "required": ["mcpServers"],
  "properties": {
    "mcpServers": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "properties": {
          "type": {
            "type": "string",
            "enum": ["stdio", "http"],
            "default": "stdio"
          },
          "command": {
            "type": "string",
            "description": "Command to execute (stdio type)"
          },
          "args": {
            "type": "array",
            "items": { "type": "string" },
            "description": "Command arguments (stdio type)"
          },
          "url": {
            "type": "string",
            "format": "uri",
            "description": "HTTP endpoint (http type)"
          },
          "env": {
            "type": "object",
            "additionalProperties": { "type": "string" },
            "description": "Environment variables"
          },
          "timeout": {
            "type": "integer",
            "minimum": 1000,
            "description": "Timeout in milliseconds"
          },
          "disabled": {
            "type": "boolean",
            "default": false
          }
        },
        "allOf": [
          {
            "if": {
              "properties": { "type": { "const": "stdio" } }
            },
            "then": {
              "required": ["command"]
            }
          },
          {
            "if": {
              "properties": { "type": { "const": "http" } }
            },
            "then": {
              "required": ["url"]
            }
          }
        ]
      }
    }
  }
}
```

### 9.4 schemas/skill-frontmatter.schema.json

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://awslabs.github.io/agent-plugins/schemas/skill-frontmatter.schema.json",
  "title": "SKILL.md Frontmatter",
  "description": "Schema for YAML frontmatter in SKILL.md files",
  "type": "object",
  "required": ["name", "description"],
  "properties": {
    "name": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9-]*$",
      "maxLength": 64,
      "description": "Skill name (kebab-case)"
    },
    "description": {
      "type": "string",
      "minLength": 20,
      "description": "When to use this skill (for auto-triggering)"
    },
    "argument-hint": {
      "type": "string",
      "description": "Hint for expected arguments"
    },
    "disable-model-invocation": {
      "type": "boolean",
      "default": false,
      "description": "Prevent Claude from auto-loading"
    },
    "user-invocable": {
      "type": "boolean",
      "default": true,
      "description": "Show in slash command menu"
    },
    "allowed-tools": {
      "type": "string",
      "description": "Comma-separated list of allowed tools"
    },
    "model": {
      "type": "string",
      "description": "Model to use when skill is active"
    },
    "context": {
      "type": "string",
      "enum": ["fork"],
      "description": "Run in forked subagent context"
    },
    "agent": {
      "type": "string",
      "description": "Subagent type (when context: fork)"
    }
  },
  "additionalProperties": true
}
```

---

## 10) Custom Validation: SKILL.md Length Limits

### 10.1 tools/validate-skill-length.mjs

```javascript
#!/usr/bin/env node
/**
 * Validates SKILL.md files for length constraints.
 * Encourages progressive disclosure per Claude Code guidelines.
 */

import { readFile } from 'fs/promises';
import { glob } from 'glob';

const MAX_LINES = 500;
const MAX_WORDS = 8000;
const WARNING_LINES = 300;
const WARNING_WORDS = 5000;

async function validateSkillLength() {
  const files = await glob('plugins/**/SKILL.md');
  let hasErrors = false;
  let hasWarnings = false;

  for (const file of files) {
    const content = await readFile(file, 'utf-8');

    // Remove frontmatter for content analysis
    const contentWithoutFrontmatter = content.replace(/^---[\s\S]*?---\n/, '');

    const lines = content.split('\n').length;
    const words = contentWithoutFrontmatter.split(/\s+/).filter(Boolean).length;

    if (lines > MAX_LINES) {
      console.error(`ERROR: ${file}`);
      console.error(`  Line count: ${lines} (max: ${MAX_LINES})`);
      console.error(`  Tip: Move detailed content to references/ subdirectory`);
      hasErrors = true;
    } else if (lines > WARNING_LINES) {
      console.warn(`WARNING: ${file}`);
      console.warn(`  Line count: ${lines} (recommended: <${WARNING_LINES})`);
      hasWarnings = true;
    }

    if (words > MAX_WORDS) {
      console.error(`ERROR: ${file}`);
      console.error(`  Word count: ${words} (max: ${MAX_WORDS})`);
      console.error(`  Tip: Keep SKILL.md focused; use references/ for details`);
      hasErrors = true;
    } else if (words > WARNING_WORDS) {
      console.warn(`WARNING: ${file}`);
      console.warn(`  Word count: ${words} (recommended: <${WARNING_WORDS})`);
      hasWarnings = true;
    }
  }

  if (hasErrors) {
    console.error('\nSKILL.md length validation failed.');
    console.error('See: https://docs.anthropic.com/en/docs/claude-code/skills');
    process.exit(1);
  }

  if (hasWarnings) {
    console.warn('\nConsider reducing SKILL.md size for better progressive disclosure.');
  }

  console.log(`Validated ${files.length} SKILL.md file(s)`);
}

validateSkillLength().catch(console.error);
```

---

## 11) CI/CD Workflow

### 11.1 .github/workflows/quality.yml

```yaml
name: Quality Gates

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup mise
        uses: jdx/mise-action@v2
        with:
          cache: true

      - name: Check formatting
        run: mise run fmt:check

      - name: Lint Markdown
        run: mise run lint:md

      - name: Validate manifests
        run: mise run lint:manifests

      - name: Validate SKILL.md files
        run: mise run lint:skills
```

---

## 12) Rollout Plan

### Phase 1: Foundation
1. Add `mise.toml` with tool versions
2. Add `dprint.json` for formatting
3. Add `.markdownlint-cli2.yaml` for Markdown rules
4. Run initial format/lint pass on existing files

### Phase 2: Schema Validation
1. Create `schemas/` directory with JSON Schemas
2. Add ajv-cli validation tasks
3. Validate existing manifests, fix any issues

### Phase 3: SKILL.md Validation
1. Add `tools/validate-skill-length.mjs`
2. Add remark configuration for structure validation
3. Document SKILL.md best practices in CONTRIBUTING.md

### Phase 4: CI Integration
1. Add `.github/workflows/quality.yml`
2. Enable branch protection requiring CI pass
3. Update CONTRIBUTING.md with contributor workflow

---

## 13) Open Questions

1. **Frontmatter strictness:** Should we require `version` in SKILL.md frontmatter?
2. **MCP validation depth:** Should we validate MCP server package names exist on npm/PyPI?
3. **Reference file limits:** Should reference files in `references/` have any size limits?
4. **Deprecation policy:** How do we handle deprecated skills/plugins in the marketplace?

---

## 14) Success Metrics

| Metric | Target |
|--------|--------|
| CI pass rate on first PR attempt | > 80% |
| Time from PR to merge (quality issues) | < 24 hours |
| Plugin quality complaints | Near zero |
| Contributor satisfaction (DX) | Positive feedback |
