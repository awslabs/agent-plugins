# XML Generation Rules

Structural patterns and constraints for AWS architecture diagram XML.

## AWS4 Shape Styles

ALWAYS use the `mxgraph.aws4.*` namespace. Reference `aws4-shapes-services.md` and `aws4-shapes-resources.md` for valid shape names.

There are two style patterns — the difference matters for rendering:

**Service icon (resourceIcon)** — Main AWS services. Renders the colored square icon. The `points` array gives 16 connection anchors:

```
sketch=0;points=[[0,0,0],[0.25,0,0],[0.5,0,0],[0.75,0,0],[1,0,0],[0,1,0],[0.25,1,0],[0.5,1,0],[0.75,1,0],[1,1,0],[0,0.25,0],[0,0.5,0],[0,0.75,0],[1,0.25,0],[1,0.5,0],[1,0.75,0]];outlineConnect=0;fontColor=#16191F;fillColor={CATEGORY_COLOR};strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{shape_name}
```

**Sub-resource icon** — Service sub-components (glue_crawlers, ecs_task, etc.). Smaller flat icons, 48x48:

```
sketch=0;outlineConnect=0;fontColor=#16191F;gradientColor=none;fillColor={CATEGORY_COLOR};strokeColor=none;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;pointerEvents=1;shape=mxgraph.aws4.{shape_name}
```

## Adding Context to Labels

Add descriptive sub-text using italic HTML:

```xml
value="AWS Lambda&lt;div&gt;&lt;i&gt;compress queries&lt;/i&gt;&lt;/div&gt;"
```

## Label Placement (CRITICAL)

- **Container `value`** = functional category label (e.g., "DNS", "Compute", "Database", "Auth") — NOT the service name
- **Icon `value`** = service name + optional italic sub-label with `verticalLabelPosition=bottom;verticalAlign=top`
- NEVER put the service name on the container. NEVER put the category label on the icon.

## Edge Labels

Edge labels are separate child cells attached to an edge, NOT an attribute on the edge itself. Use `connectable="0"` and `edgeLabel` style with `relative="1"` geometry:

```xml
<mxCell id="edge-1" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="api-gw" target="kinesis">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
<mxCell id="edge-1-label" value="query logs" style="edgeLabel;html=1;align=center;verticalAlign=middle;resizable=0;points=[];labelBackgroundColor=none;" connectable="0" vertex="1" parent="edge-1">
  <mxGeometry relative="1" x="-0.3" y="0" as="geometry">
    <mxPoint as="offset" />
  </mxGeometry>
</mxCell>
```

The `x` value controls position along the edge (-1 = source, 0 = midpoint, 1 = target). The `y` value offsets perpendicular to the edge.

## Edges

- **Always connect edges to service icons**, not to container/group shapes. Target the icon cell ID.
- Use `exitX`/`exitY` and `entryX`/`entryY` (0-1) to control connection sides. Spread connections across different sides.
- **Leave room for arrowheads**: At least 20px straight segment before target and after source.
- Add explicit **waypoints** (`<Array as="points"><mxPoint x="X" y="Y"/></Array>`) when edges would overlap.
- Align all nodes to a grid (multiples of 10).

## Groups and Containers

- Set `parent="containerId"` on children; children use **relative coordinates**
- Add `container=1;pointerEvents=0;` to group styles — **EXCEPT Region groups which MUST use `container=0`**
- **Region groups are decoration-only**: Services positioned visually inside the region rectangle still have `parent="aws-cloud"` or `parent="1"` with absolute coordinates. This prevents nesting depth from breaking edge auto-routing.
- Full group style strings: `group-styles.md`

## When to Use Containers vs Flat Layout

**Prefer flat layouts for most diagrams.** Place all service icons as direct children of the AWS Cloud group with text cells for section labels. This produces the cleanest edge routing.

**Only use nested containers for real infrastructure boundaries:** VPC, subnets, AZs, regions, security groups, Step Functions workflows, ECS clusters.

**Do NOT use swimlane containers just to visually group columns** (e.g., "Authentication", "Data Layer"). This causes cross-container edge routing problems and coordinate confusion. Instead use a text cell label above each column:

```xml
<mxCell id="col-auth" value="&lt;b&gt;Authentication&lt;/b&gt;" style="text;html=1;whiteSpace=wrap;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;fontSize=12;fontStyle=1;fontColor=#DD344C;" vertex="1" parent="aws-cloud">
  <mxGeometry x="60" y="40" width="160" height="20" as="geometry" />
</mxCell>
```

## External Actors

Users/clients MUST be in a visible container (`fillColor=#f5f5f5`) with adaptive stroke. Icon `value=""`, label on the container. Edges connect to the container, not the icon. NEVER use `shape=actor`. See `xml-templates-structure.md`.

**Placement rule**: External actors MUST be placed BELOW the title block (y >= 140). Vertically align with the top of the AWS Cloud group so the edge to the first service runs horizontally.

**Clear path rule**: Do NOT place any service container between external actors and their first target. Place auth/security services BELOW or ABOVE the main entry flow, not in line with it.
