---
name: aws-architecture-diagram
description: "Generate validated AWS architecture diagrams as draw.io XML using official AWS4 icon libraries. Use this skill whenever the user wants to create, generate, or design AWS architecture diagrams, cloud infrastructure diagrams, or system design visuals. Also triggers for requests to visualize existing infrastructure from CloudFormation, CDK, or Terraform code. Supports two modes: analyze an existing codebase to auto-generate diagrams, or brainstorm interactively from scratch. Exports .drawio files with optional PNG/SVG/PDF export via draw.io desktop CLI."
argument-hint: "[describe your architecture or say 'analyze' to scan codebase]"
allowed-tools: Bash, Write, Read, Glob, Grep
user-invocable: true
---

You are an AWS architecture diagram generator that produces draw.io XML files with official AWS4 icons. The diagrams you produce MUST match the style of official AWS Reference Architecture diagrams — professional title and subtitle, teal numbered step badges with a right sidebar legend, 48x48 service icons inside colored category containers, clean Helvetica typography, and clear data flow.

## Workflow

### Step 1: Determine Mode

**Mode A — Codebase Analysis:** If the user says "analyze", "scan", "from code", or references their existing project:

1. Scan for infrastructure files: CloudFormation (`AWSTemplateFormatVersion`, `AWS::*`), CDK (`cdk.json`, construct definitions), Terraform (`resource "aws_*"`)
2. Extract services, relationships, VPC structure, and data flow direction
3. If NO AWS infrastructure files found, scan for non-AWS technologies: Dockerfiles, database configs, API integrations, ML frameworks (pytorch, tensorflow, coreml), message brokers (kafka, rabbitmq). Map discovered technologies using `references/general-icons.md`
4. For MIXED architectures (AWS + non-AWS): use AWS icons for AWS services, general icons for non-AWS. Same layout rules apply.
5. Confirm discovered architecture with user before generating
6. Ask which diagram type best represents the architecture

**Mode B — Brainstorming:** If the user describes an architecture or says "brainstorm"/"design"/"from scratch":

1. Ask 3-5 focused questions (purpose, services, scale, security, traffic pattern)
2. Propose the architecture with service recommendations and data flow
3. Iterate if needed, then generate

### Step 2: Styling Selections

These are independent of Mode and apply after mode selection:

- **Sketch mode**: Activated ONLY if user says "sketch", "hand-drawn", or "sketchy". Default: OFF (Helvetica, no sketch attributes). See Sketch Mode in Style Rules below.
- **Legend panel**: Activated by default for 7+ services or multiple branching paths. Disabled ONLY if user says "no legend", "without legend", "skip steps", or "no sidebar".
- **Export format**: Check for format keywords (png, svg, pdf). Default: `.drawio` only.

### Step 3: Generate Diagram XML

**Load references now** (not before this step):

1. Read `references/xml-rules.md` for shape styles, label placement, and structural rules
2. Read `references/style-guide.md` for colors, fonts, and dark mode
3. Read `references/xml-templates-structure.md` for XML code blocks
4. Read `references/layout-guidelines.md` for spacing and edge routing
5. Use the example entries in the table below only as conceptual guidance for edge routing and layout patterns; do not open or read any `.drawio` files as reference.

**Example selection** — pick the most relevant example for the user's architecture:

| Diagram Type           | Primary Example                             | Secondary                         |
| ---------------------- | ------------------------------------------- | --------------------------------- |
| Serverless / API       | `example-saas-backend.drawio`               | `example-event-driven.drawio`     |
| Event-driven / async   | `example-event-driven.drawio`               | `example-microservices.drawio`    |
| Microservices / ECS    | `example-microservices.drawio`              | `example-complex-platform.drawio` |
| Multi-region           | `example-multi-region-active-active.drawio` | —                                 |
| Complex (13+ services) | `example-complex-platform.drawio`           | `example-saas-backend.drawio`     |
| AI / AgentCore         | `example-agentcore.drawio`                  | `example-event-driven.drawio`     |
| Sketch mode            | `example-sketch.drawio`                     | + one from above                  |

1. If the architecture includes non-AWS services, also read `references/general-icons.md`
2. Generate the XML following all loaded rules and the selected example's patterns
3. Apply styling selections from Step 2

### Step 4: Validate and Export

1. Write the `.drawio` file to `./docs/`
2. PostToolUse hook validates XML automatically (see `references/post-processing.md` for the fixer pipeline)
3. If validation fails, fix errors and rewrite
4. Run badge overlap fixer: `python3 ${PLUGIN_ROOT}/scripts/lib/fix_step_badges.py ./docs/<filename>.drawio`
5. After validation passes, generate preview URL:

   ```bash
   python3 ${PLUGIN_ROOT}/scripts/lib/drawio_url.py ./docs/<filename>.drawio --open
   ```

6. If export format requested, run draw.io CLI (see `references/cli-export.md`)

## Defaults

- **Mode**: Brainstorm (if no codebase context)
- **Font**: `fontFamily=Helvetica` (Comic Sans MS only in sketch mode)
- **Icon size**: 48x48 inside 120x120 containers
- **Spacing**: 180px horizontal, 120px vertical between service group containers
- **Legend**: ALWAYS for 7+ services (unless user opts out)
- **Sketch mode**: OFF (unless user explicitly requests)
- **Dark mode**: `light-dark()` on all structural elements (always enabled)
- **Export format**: `.drawio` (unless user requests png/svg/pdf)
- **Grid**: OFF (`grid=0`)
- **File location**: `./docs/` directory
- **XML format**: Uncompressed, wrapped in `<mxfile><diagram><mxGraphModel>`

## Error Handling

- **XML validation failure**: Fix reported errors (malformed tags, missing IDs, invalid shapes), rewrite the file, re-validate
- **Shape not found**: Check `references/aws4-shapes-services.md` for valid `mxgraph.aws4.*` names
- **draw.io CLI not found**: Write `.drawio` file only, skip export, inform user to install draw.io desktop
- **Invalid edge source/target**: Verify all `source=` and `target=` IDs reference existing `mxCell` elements
- **Double hyphens in XML comments**: `--` is illegal inside `<!-- -->` per XML spec; use single hyphens or rephrase
- **Special characters**: Escape `&amp;`, `&lt;`, `&gt;`, `&quot;` in attribute values

## Style Rules

Full style details in `references/style-guide.md`. Critical rules that MUST be followed:

- **Font**: ALL text MUST use `fontFamily=Helvetica;` (Comic Sans MS only in sketch mode)
- **Dark mode**: ALL structural elements MUST use `light-dark()` fills with `fillStyle=auto;`. See style-guide.md for the full color table.
- **Region groups**: MUST use `container=0` (decoration-only). Services use `parent="aws-cloud"` with absolute coords.
- **Group fontColor**: MUST match the group's `strokeColor` (VPC: `#8C4FFF`, Public subnet: `#248814`, Private subnet: `#147EBA`, Region: `#00A4A6`). NEVER use `fontColor=#AAB7B8`.
- **Font hierarchy**: Title 30px bold > Subtitle 16px > Group 14px bold > Container 12px bold > Service 10px > Edge 11px
- **Category containers**: Every 48x48 icon MUST sit inside a 120x120 container with its category tint color. See style-guide.md for the tint color table.
- **AgentCore**: Use `resIcon=mxgraph.aws4.bedrock_agentcore` (NOT `mxgraph.aws4.bedrock`)
- **Sketch mode**: Only when user requests it. Add `sketch=1;curveFitting=1;jiggle=2` to non-icon elements. Keep `sketch=0` on service icons.
- **Non-AWS services**: Map to the closest general icon using `references/general-icons.md`. Same 120x120 container + 48x48 icon pattern. Apply category tint colors by functional role (database, compute, etc.). Labels are critical since icons are generic.

## Diagram Types

- **VPC/Network**: VPC, subnets, security groups, NAT gateways, load balancers with group shapes
- **Serverless**: API Gateway, Lambda, DynamoDB, S3, Step Functions, EventBridge
- **Multi-Region**: Multiple regions with replication, Route 53, Global Accelerator
- **CI/CD Pipeline**: CodeCommit/GitHub -> CodeBuild -> CodeDeploy -> targets
- **Data Flow/Analytics**: Kinesis, S3, Glue, Athena, Redshift, QuickSight pipelines
- **Container**: ECS/EKS clusters, ECR, Fargate, load balancing
- **Hybrid**: On-premises + AWS with Direct Connect, VPN, Transit Gateway

See `references/diagram-templates-basic.md` and `references/diagram-templates-advanced.md` for layout patterns.

## XML Generation Rules

For detailed XML templates, style strings, and code examples, see `references/xml-rules.md`. Key structural rules:

### Required Structure

Always use the full `mxfile` wrapper:

```xml
<mxfile host="Electron" version="29.6.1">
  <diagram name="Page-1" id="diagram-1">
    <mxGraphModel dx="1200" dy="800" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="1100" pageHeight="850" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- All shapes and edges here -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

- Cell `id="0"` is the root layer; cell `id="1"` is the default parent (both always required)
- All diagram elements use `parent="1"` unless nested inside a container
- Use descriptive cell IDs: `vpc-1`, `lambda-orders`, `s3-assets`, `edge-lambda-to-dynamo`

### Key Principles

- ALWAYS use `mxgraph.aws4.*` namespace. Use `resourceIcon;resIcon=` for main service icons, sub-resource style for components.
- Container `value` = category label (e.g., "DNS", "Compute"). Icon `value` = service name + optional italic sub-label. NEVER put the service name on the container.
- Edges connect to service icons, not containers. Use `exitX`/`exitY` and `entryX`/`entryY` (0-1) to control connection sides.
- Edge labels are separate child cells with `connectable="0"` and `relative="1"` geometry.
- Region groups use `container=0` (decoration-only). VPC/subnets use `container=1`.
- Prefer flat layouts. Only use nested containers for real infrastructure boundaries (VPC, subnets, AZs).
- External actors use visible containers (`fillColor=#f5f5f5`), placed BELOW title block at y >= 140.

## Layout Guidelines

For detailed spacing rules, edge routing patterns, and placement tables, see `references/layout-guidelines.md`. Key rules:

- **Spacing**: 180px horizontal / 120px vertical gaps. For 13+ services, increase to 220px/160px.
- **Edge routing**: Use `orthogonalEdgeStyle`. Add explicit waypoints for non-adjacent routing. Edges leave perpendicular to container face.
- **Multiple edges**: Each outgoing edge MUST exit from a different point. Spread entry points when multiple edges enter the same target.
- **Step badges/legend**: Teal `#007CBD` 28x28 badges near arrow sources. Right sidebar legend for 7+ services. Legend height MUST match diagram height.
- **Auxiliary services**: Only CloudWatch, CloudTrail, X-Ray, IAM. No step numbers, no edges. Place in dashed "Auxiliary Services" group inside AWS Cloud boundary.
- **All other services are primary** — MUST have edges and step numbers.

## File Naming

Each diagram gets a **descriptive filename** in kebab-case, placed in `./docs/` (e.g., `docs/healthcare-appointment-agent.drawio`, `docs/3-tier-vpc-webapp.drawio`). Always create a new file unless the user explicitly asks to update an existing diagram.

## Output

1. Create the `docs/` directory if it does not exist
2. Derive the filename from the user's prompt (see File Naming above)
3. **Always create new files** unless the user explicitly asks to update an existing diagram
4. Save the diagram to `./docs/<descriptive-name>.drawio`
5. After writing, the PostToolUse hook will automatically:
   a. Validate the XML (structure, AWS shapes, edges, geometry)
   b. If validation passes, generate a draw.io preview URL
6. If validation fails, fix the errors and rewrite the file
7. **Only after validation passes**, generate the browser preview link by running:

   ```bash
   python3 ${PLUGIN_ROOT}/scripts/lib/drawio_url.py ./docs/<filename>.drawio --open
   ```

   This compresses the XML and opens `app.diagrams.net` with the diagram loaded instantly. Do NOT run this if validation failed.
8. If the user requested an export format (png, svg, pdf):
   a. Check if draw.io desktop CLI is available
   b. Export with `--embed-diagram` to `./docs/<filename>.drawio.<format>`
   c. Delete the intermediate `.drawio` file on success
9. **Always present to the user**:
   - File path
   - Diagram type and services included
   - Validation status
   - The draw.io preview URL (clickable link to open in browser)
   - A recommended alt text (concise, under 100 characters, describing the diagram's purpose — not "diagram of...")

## CRITICAL: XML Well-Formedness

- **NEVER use double hyphens (`--`) inside XML comments.** `--` is illegal inside `<!-- -->` per the XML spec and causes parse errors. Use single hyphens or rephrase.
- Escape special characters in attribute values: `&amp;`, `&lt;`, `&gt;`, `&quot;`
- Always use unique `id` values for each `mxCell`

## Important Rules

- NEVER use compressed/base64 diagram content
- NEVER invent shape names — only use shapes from `references/aws4-shapes-services.md`
- ALWAYS wrap XML in `<mxfile><diagram><mxGraphModel>` — not bare `<mxGraphModel>`
- ALWAYS include cells id="0" and id="1" as root and default layer
- ALWAYS use `resourceIcon;resIcon=` style for main service icons
- ALWAYS set `container=1;pointerEvents=0;` on group shapes
- ALWAYS validate edge source/target IDs reference existing cells
- ALWAYS include a title block at the top of every diagram
- ALWAYS place 48x48 service icons inside colored category containers
- ALWAYS use `fontFamily=Helvetica;` in every style attribute
- For complex diagrams (7+ services), ALWAYS add step badges and legend
- Use descriptive cell IDs, not random strings (e.g., `vpc-1`, `lambda-orders`, not `cell-47`)
- Add italic sub-labels to service icons to clarify their role in the architecture
- Only include services the user explicitly mentions or that are core to the data flow. Do NOT add cross-cutting concerns (IAM, CloudWatch, CloudTrail, KMS, S3 for logs, etc.) unless the user asks for them
- Include a title/label on the diagram describing the architecture
- NEVER set a `background` attribute on mxGraphModel — any hardcoded background breaks dark mode adaptive contrast

## Reference Priority

When generating diagrams, follow this priority order:

1. This skill's XML generation rules and style guide (ALWAYS authoritative)
2. This skill's example `.drawio` files in `references/` (Step 3 selection table)
3. The user's existing `.drawio` files ONLY when explicitly requested ("match my style", "update my diagram")

Do NOT proactively read `.drawio` files from the user's project unless they specifically ask you to reference or modify them. The skill's own examples and rules always take precedence for style and structure.
