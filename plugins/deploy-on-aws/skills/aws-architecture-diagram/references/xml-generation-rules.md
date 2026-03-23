# XML Generation Rules

Detailed XML templates, style strings, and structural patterns for AWS architecture diagrams.

## AWS4 Shape Styles

ALWAYS use the `mxgraph.aws4.*` namespace. Reference `aws4-shapes.md` for the full list of valid shape names by category.

There are two style patterns. Use the right one — the difference matters for rendering:

**Service icon (resourceIcon)** — Use for ALL main AWS services. Renders the colored square icon with the AWS service logo. The `points` array gives 16 connection anchors:

```
sketch=0;points=[[0,0,0],[0.25,0,0],[0.5,0,0],[0.75,0,0],[1,0,0],[0,1,0],[0.25,1,0],[0.5,1,0],[0.75,1,0],[1,1,0],[0,0.25,0],[0,0.5,0],[0,0.75,0],[1,0.25,0],[1,0.5,0],[1,0.75,0]];outlineConnect=0;fontColor=#16191F;fillColor={CATEGORY_COLOR};strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{shape_name}
```

**Sub-resource icon** — Use for service sub-components (glue_crawlers, ecs_task, etc.). Smaller flat icons without the square background. Use 48x48 size:

```
sketch=0;outlineConnect=0;fontColor=#16191F;gradientColor=none;fillColor={CATEGORY_COLOR};strokeColor=none;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;pointerEvents=1;shape=mxgraph.aws4.{shape_name}
```

## Adding Context to Labels

Add descriptive sub-text to service labels using italic HTML:

```xml
value="AWS Lambda&lt;div&gt;&lt;i&gt;compress queries&lt;/i&gt;&lt;/div&gt;"
```

This renders as "AWS Lambda" with "compress queries" in italics below it.

## Category Fill Colors

| Category                             | fillColor |
| ------------------------------------ | --------- |
| Compute / Containers                 | `#ED7100` |
| Database                             | `#C925D1` |
| Analytics / Networking               | `#8C4FFF` |
| Storage                              | `#3F8624` |
| Application Integration / Management | `#E7157B` |
| Security                             | `#DD344C` |
| AI/ML                                | `#01A88D` |
| General                              | `#232F3D` |

## Font and Typography

Per AWS diagram guidelines:

- **Font**: Amazon Ember (falls back to Helvetica/Arial in draw.io if not installed)
- **Font size**: 12px minimum (use `fontSize=11` only for dense layouts with 40px icons)
- **Font color**: `#16191F` for most labels. `#000000` is also acceptable.
- **Font weight**: Regular (`fontStyle=0`) for most text. Bold (`fontStyle=1`) for emphasis only.
- **Italics** preferred over underlines for secondary text — underlines create visual noise with arrows/lines.

## Group Shapes (VPC, Subnets, Regions, AZs)

Use group shapes to represent architectural boundaries. Reference `xml-structure.md` for all group style templates.

**AWS Cloud group:**

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_aws_cloud;strokeColor=#232F3E;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#16191F;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

**VPC group:**

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_vpc2;strokeColor=#8C4FFF;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#AAB7B8;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

**Public subnet:**

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_public_subnet;strokeColor=#248814;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#AAB7B8;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

**Private subnet:**

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_private_subnet;strokeColor=#147EBA;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#AAB7B8;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

## Edge Styles

**Standard connection** (most common):

```
edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;
```

**Dashed (optional/async):**

```
edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;dashed=1;
```

The `orthogonalLoop=1;jettySize=auto` properties give edges better automatic routing around obstacles. Always include them on orthogonal edges.

## Edge Labels

Edge labels are separate child cells attached to an edge, NOT an attribute on the edge itself. Use `connectable="0"` and `edgeLabel` style with `relative="1"` geometry so the label positions itself along the edge:

```xml
<mxCell id="edge-1" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="api-gw" target="kinesis">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
<mxCell id="edge-1-label" value="query logs" style="edgeLabel;html=1;align=center;verticalAlign=middle;resizable=0;points=[];labelBackgroundColor=#ffffff;" connectable="0" vertex="1" parent="edge-1">
  <mxGeometry relative="1" x="-0.3" y="0" as="geometry">
    <mxPoint as="offset" />
  </mxGeometry>
</mxCell>
```

The `x` value on the geometry controls position along the edge (-1 = source end, 0 = midpoint, 1 = target end). The `y` value offsets perpendicular to the edge.

## Label Placement (Mandatory)

- **Container `value`** = functional category label (e.g., "DNS", "Compute", "Database", "Auth") — NOT the service name
- **Icon `value`** = service name + optional italic sub-label with `verticalLabelPosition=bottom;verticalAlign=top`
- NEVER put the service name on the container. NEVER put the category label on the icon.

## Edges

- **Always connect edges to service icons**, not to container/group shapes. Target the icon cell ID, not the container ID.
- Use `exitX`/`exitY` and `entryX`/`entryY` (values 0-1) to control connection sides. Spread connections across different sides.
- **Leave room for arrowheads**: At least 20px straight segment before target and after source.
- Add explicit **waypoints** (`<Array as="points"><mxPoint x="X" y="Y"/></Array>`) when edges would overlap.
- Align all nodes to a grid (multiples of 10)

## Groups and Containers

- Set `parent="containerId"` on children; children use **relative coordinates**
- Add `container=1;pointerEvents=0;` to group styles — **EXCEPT Region groups which MUST use `container=0`**
- **Region groups are decoration-only**: Use `container=0;pointerEvents=0;` on Region. Services positioned visually inside the region rectangle still have `parent="aws-cloud"` or `parent="1"` with absolute coordinates. This prevents nesting depth from breaking edge auto-routing.
- All group shapes MUST use `light-dark()` fills (see Style Rules)
- Full group style strings: `group-styles.md`
- Container type reference: `xml-structure.md`

## When to Use Containers vs Flat Layout

**Prefer flat layouts for most diagrams.** Place all service icons as direct children of the AWS Cloud group, and use text cells for section/column labels. This produces the cleanest edge routing because all icons share the same coordinate space.

**Only use nested containers when they represent real infrastructure boundaries:**

- VPC, subnets, AZs, regions, security groups — these are real containment
- Step Functions workflows, ECS clusters — service-level grouping with a clear boundary

**Do NOT use swimlane containers just to visually group columns** (e.g., "Authentication", "Data Layer", "API Layer"). This causes:

- Cross-container edge routing problems (edges between different containers produce messy orthogonal paths)
- Oversized containers with wasted space
- Coordinate confusion between parent frames

Instead, use a text cell label above each column of icons:

```xml
<mxCell id="col-auth" value="&lt;b&gt;Authentication&lt;/b&gt;" style="text;html=1;whiteSpace=wrap;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;fontSize=12;fontStyle=1;fontColor=#DD344C;" vertex="1" parent="aws-cloud">
  <mxGeometry x="60" y="40" width="160" height="20" as="geometry" />
</mxCell>
```

## External Actors

Users/clients MUST be in a visible container (`fillColor=#f5f5f5`) with adaptive stroke. Icon `value=""`, label on the container. Edges connect to the container, not the icon. NEVER use `shape=actor`. See `xml-templates-structure.md`.
Set `parent="containerId"` on child cells. Children use **relative coordinates** within the container.

## Container Types

| Type                       | Style                                                                                | When to use                                                           |
| -------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------- |
| **AWS Group**              | `shape=mxgraph.aws4.group;grIcon=...;container=1;pointerEvents=0;`                   | VPC, subnets, regions, AZs                                            |
| **Service workflow group** | `shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_aws_step_functions_workflow;...` | Step Functions workflows, ECS clusters, or any service-level grouping |
| **Swimlane** (titled)      | `swimlane;startSize=30;`                                                             | Only when the container itself needs connections (rare)               |
| **Group** (invisible)      | `group;`                                                                             | No visual border needed, container has no connections                 |
| **Custom container**       | Add `container=1;pointerEvents=0;` to any shape style                                | Any shape acting as a container without its own connections           |

**Step Functions workflow group** (useful for showing multi-step pipelines):

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_aws_step_functions_workflow;strokeColor=#CD2264;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#CD2264;dashed=0
```

**Placement rule**: External actors MUST be placed BELOW the title block. The title group occupies y=30 to y~120. Place external actors at **y >= 140**. NEVER place any diagram element overlapping the title area. Vertically, align external actors with the top of the AWS Cloud group so the edge to the first service runs horizontally.

**Clear path rule**: Do NOT place any service container between external actors and their first target (usually API Gateway). If Users is at the left and API Gateway is inside AWS Cloud, ensure no other service (like Cognito, WAF) is positioned in the direct horizontal path between them. Place auth/security services BELOW or ABOVE the main entry flow, not in line with it.
