# draw.io XML Structure Reference

## File Structure

A `.drawio` file is native mxGraphModel XML. Always generate XML directly.

```xml
<mxfile host="Electron" version="29.6.1">
  <diagram name="Page-1" id="diagram-1">
    <mxGraphModel dx="1200" dy="800" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1100" pageHeight="850" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <!-- Diagram cells go here with parent="1" -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

- The `<mxfile>` and `<diagram>` wrappers are required — never use bare `<mxGraphModel>`
- Cell `id="0"` is the root layer
- Cell `id="1"` is the default parent layer
- All diagram elements use `parent="1"` unless using containers

## Cell Types

### Vertex (Shape/Icon)

```xml
<mxCell id="my-ec2" value="Web Server" style="STYLE_STRING" vertex="1" parent="1">
  <mxGeometry x="100" y="200" width="78" height="78" as="geometry"/>
</mxCell>
```

### Edge (Connector)

```xml
<mxCell id="edge-1" value="" style="EDGE_STYLE" edge="1" source="source-id" target="target-id" parent="1">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

### Group (Container)

Groups MUST have `container=1` in style. Children set `parent` to the group's ID and use **relative coordinates**.

```xml
<mxCell id="vpc-1" value="VPC 10.0.0.0/16" style="GROUP_STYLE;container=1;pointerEvents=0" vertex="1" parent="1">
  <mxGeometry x="50" y="50" width="800" height="600" as="geometry"/>
</mxCell>
<mxCell id="subnet-public" value="Public Subnet" style="SUBNET_STYLE;container=1;pointerEvents=0" vertex="1" parent="vpc-1">
  <mxGeometry x="20" y="40" width="360" height="520" as="geometry"/>
</mxCell>
```

## Container Types

| Type | Style | When to use |
|------|-------|-------------|
| **AWS Group** | `shape=mxgraph.aws4.group;grIcon=...;container=1;pointerEvents=0;` | VPC, subnets, regions, AZs |
| **Swimlane** (titled) | `swimlane;startSize=30;` | Container with visible title bar or connectable container |
| **Group** (invisible) | `group;` | No visual border, no connections |
| **Custom container** | Add `container=1;pointerEvents=0;` to any shape | Any shape as container |

Always add `pointerEvents=0;` to containers that MUST NOT capture connections between children. Only omit it when the container itself needs to be connectable.

For XML examples of each container type, see `xml-templates-structure.md` and `xml-templates-examples.md`. For group style strings, see `group-styles.md`.

```xml
<mxCell id="svc1" value="User Service" style="swimlane;startSize=30;fillColor=#E6F2FF;strokeColor=#147EBA;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="300" height="200" as="geometry"/>
</mxCell>
<mxCell id="api1" value="REST API" style="rounded=1;whiteSpace=wrap;" vertex="1" parent="svc1">
  <mxGeometry x="20" y="40" width="120" height="60" as="geometry"/>
</mxCell>
<mxCell id="db1" value="Database" style="shape=cylinder3;whiteSpace=wrap;" vertex="1" parent="svc1">
  <mxGeometry x="160" y="40" width="120" height="60" as="geometry"/>
</mxCell>
```

### Example: Invisible group

```xml
<mxCell id="grp1" value="" style="group;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="300" height="200" as="geometry"/>
</mxCell>
<mxCell id="c1" value="Component A" style="rounded=1;whiteSpace=wrap;" vertex="1" parent="grp1">
  <mxGeometry x="10" y="10" width="120" height="60" as="geometry"/>
</mxCell>
```

## AWS Group Style Templates

### AWS Cloud

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_aws_cloud;strokeColor=#232F3E;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#16191F;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

### Region

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_region;strokeColor=#00A4A6;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#147EBA;dashed=1;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

### Availability Zone

```
fillColor=none;strokeColor=#147EBA;dashed=1;verticalAlign=top;fontStyle=0;fontColor=#147EBA;whiteSpace=wrap;html=1;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

### VPC

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_vpc2;strokeColor=#8C4FFF;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#AAB7B8;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

### Public Subnet

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_public_subnet;strokeColor=#248814;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#AAB7B8;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

### Private Subnet

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_private_subnet;strokeColor=#147EBA;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#AAB7B8;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

### Security Group

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_security_group;strokeColor=#DD3522;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#DD3522;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

### Auto Scaling Group

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_auto_scaling_group;strokeColor=#ED7100;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#ED7100;dashed=1;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

### Account

```
points=[[0,0],[0.25,0],[0.5,0],[0.75,0],[1,0],[1,0.25],[1,0.5],[1,0.75],[1,1],[0.75,1],[0.5,1],[0.25,1],[0,1],[0,0.75],[0,0.5],[0,0.25]];outlineConnect=0;gradientColor=none;html=1;whiteSpace=wrap;fontSize=12;fontStyle=0;shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_account;strokeColor=#CD2264;fillColor=none;verticalAlign=top;align=left;spacingLeft=30;fontColor=#CD2264;dashed=0;container=1;pointerEvents=0;collapsible=0;recursiveResize=0
```

## Edge Style Templates

### Standard directional (data flow)

```
edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;elbow=vertical;startArrow=none;endFill=1;strokeColor=#545B64;rounded=0
```

### Bidirectional

```
edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;elbow=vertical;startArrow=block;startFill=1;endFill=1;strokeColor=#545B64;rounded=0
```

### Dashed (async/optional)

```
edgeStyle=orthogonalEdgeStyle;html=1;endArrow=block;elbow=vertical;startArrow=none;endFill=1;strokeColor=#545B64;rounded=0;dashed=1
```

### Open arrow (informational/reference)

```
edgeStyle=orthogonalEdgeStyle;html=1;endArrow=open;elbow=vertical;startArrow=none;endFill=0;strokeColor=#545B64;rounded=0
```

## Useful Style Properties

| Property | Values | Use for |
|----------|--------|---------|
| `rounded=1` | 0 or 1 | Rounded corners |
| `whiteSpace=wrap` | wrap | Text wrapping |
| `fillColor=#E6F2FF` | Hex color | Background color |
| `strokeColor=#147EBA` | Hex color | Border color |
| `fontColor=#333333` | Hex color | Text color |
| `shape=cylinder3` | shape name | Database cylinders |
| `ellipse` | style keyword | Circles/ovals |
| `rhombus` | style keyword | Diamonds |
| `container=1` | 0 or 1 | Enable container behavior |
| `pointerEvents=0` | 0 or 1 | Prevent container from capturing child connections |
| `exitX`/`exitY` | 0-1 | Edge exit point on source shape |
| `entryX`/`entryY` | 0-1 | Edge entry point on target shape |
| `jettySize=auto` | auto or px | Port spacing on orthogonal edges |

## Layout Sizing Reference

| Element | Width | Height |
|---------|-------|--------|
| Service icon | 78 | 78 |
| Small resource icon | 48 | 48 |
| Text label | varies | 20 |
| VPC group (typical) | 800-1200 | 500-800 |
| Subnet group (typical) | 350-550 | 400-700 |
| AZ group (typical) | 380-580 | 420-720 |
| Region group (typical) | 900-1400 | 600-900 |
| AWS Cloud group | 1000-1500 | 700-1000 |

## References

- Style reference: https://www.drawio.com/doc/faq/drawio-style-reference.html
- XML Schema (XSD): https://www.drawio.com/assets/mxfile.xsd
