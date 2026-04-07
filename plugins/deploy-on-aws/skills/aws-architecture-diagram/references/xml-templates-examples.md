# XML Templates — Examples

Edge, container, and annotation XML snippets. For core structure (title, users, legend), see `xml-templates-structure.md`.

## Edge with Label

```xml
<mxCell id="edge-1" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="api-gw" target="kinesis">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
<mxCell id="edge-1-label" value="query logs" style="edgeLabel;html=1;align=center;verticalAlign=middle;resizable=0;points=[];fontSize=11;fontFamily=Helvetica;" connectable="0" vertex="1" parent="edge-1">
  <mxGeometry relative="1" x="-0.3" y="0" as="geometry">
    <mxPoint as="offset" />
  </mxGeometry>
</mxCell>
```

## Edge with Explicit Waypoints

```xml
<mxCell id="e1" style="edgeStyle=orthogonalEdgeStyle;" edge="1" parent="1" source="a" target="b">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="300" y="150"/>
      <mxPoint x="300" y="250"/>
    </Array>
  </mxGeometry>
</mxCell>
```

## Decision Point Annotations

```xml
<!-- Conditional edge label (italic) -->
<mxCell id="edge-decision-label" value="deploy [if build passes]" style="edgeLabel;html=1;align=center;verticalAlign=middle;resizable=0;points=[];fontSize=11;fontFamily=Helvetica;fontStyle=2;" connectable="0" vertex="1" parent="edge-decision">
  <mxGeometry relative="1" x="-0.3" y="0" as="geometry">
    <mxPoint as="offset" />
  </mxGeometry>
</mxCell>

<!-- Dashed arrow for failure/fallback paths -->
<mxCell id="edge-fallback" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;dashed=1;strokeColor=#999999;" edge="1" parent="1" source="SOURCE" target="FALLBACK_TARGET">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
```

## Swimlane Container

```xml
<mxCell id="svc1" value="User Service" style="swimlane;startSize=30;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="300" height="200" as="geometry"/>
</mxCell>
<mxCell id="api1" value="REST API" style="rounded=1;whiteSpace=wrap;" vertex="1" parent="svc1">
  <mxGeometry x="20" y="40" width="120" height="60" as="geometry"/>
</mxCell>
```

## Invisible Group

```xml
<mxCell id="grp1" value="" style="group;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="300" height="200" as="geometry"/>
</mxCell>
<mxCell id="c1" value="Component A" style="rounded=1;whiteSpace=wrap;" vertex="1" parent="grp1">
  <mxGeometry x="10" y="10" width="120" height="60" as="geometry"/>
</mxCell>
```

## Region with Adaptive Fill

```xml
<mxCell id="region-1" style="...shape=mxgraph.aws4.group;grIcon=mxgraph.aws4.group_region;strokeColor=#00A4A6;fillColor=light-dark(#0C7B7D0D,#0C7B7D0D);fillStyle=auto;..." value="Region: us-east-1" vertex="1" parent="1">
  <mxGeometry x="X" y="Y" width="W" height="H" as="geometry" />
</mxCell>
```
