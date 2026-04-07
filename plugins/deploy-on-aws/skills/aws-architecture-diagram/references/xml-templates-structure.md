# XML Templates — Core Structure

Ready-to-use XML code blocks for diagram scaffolding. For edge and container examples, see `xml-templates-examples.md`.

## Title + Subtitle Block

```xml
<mxCell id="title-group" connectable="0" style="group;fontFamily=Helvetica;" value="" vertex="1" parent="1">
  <mxGeometry height="83" width="1200" x="50" y="30" as="geometry" />
</mxCell>
<!-- Title: 30px bold -->
<mxCell id="title-text" style="text;html=1;resizable=1;points=[];autosize=1;align=left;verticalAlign=top;spacingTop=-4;fontSize=30;fontStyle=1;fontFamily=Helvetica;" value="Architecture Title Here" vertex="1" parent="title-group">
  <mxGeometry height="42" width="800" as="geometry" />
</mxCell>
<!-- Subtitle: 16px regular -->
<mxCell id="subtitle-text" style="text;html=1;resizable=0;points=[];autosize=1;align=left;verticalAlign=top;spacingTop=-4;fontSize=16;fontFamily=Helvetica;" value="One-line description of what the architecture does" vertex="1" parent="title-group">
  <mxGeometry height="25" width="800" x="5" y="40" as="geometry" />
</mxCell>
<!-- Separator: orange/amber stroke -->
<mxCell id="title-separator" style="line;strokeWidth=2;html=1;fontSize=14;strokeColor=#FF9900;fontFamily=Helvetica;" value="" vertex="1" parent="title-group">
  <mxGeometry height="10" width="1190" x="5" y="70" as="geometry" />
</mxCell>
```

## Users Container

```xml
<!-- Users container: light fill + adaptive stroke -->
<mxCell id="users-container" style="fillColor=#f5f5f5;strokeColor=light-dark(#666666,#D4D4D4);rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fontSize=12;fontColor=#333333;fontFamily=Helvetica;container=1;collapsible=0;shadow=1;strokeWidth=1;perimeterSpacing=0;" value="Users" vertex="1" parent="1">
  <mxGeometry x="X" y="Y" height="98" width="107" as="geometry" />
</mxCell>

<!-- Users icon inside (value="" since label is on container) -->
<mxCell id="users-icon" style="sketch=0;points=[[0,0,0],[0.25,0,0],[0.5,0,0],[0.75,0,0],[1,0,0],[0,1,0],[0.25,1,0],[0.5,1,0],[0.75,1,0],[1,1,0],[0,0.25,0],[0,0.5,0],[0,0.75,0],[1,0.25,0],[1,0.5,0],[1,0.75,0]];outlineConnect=0;fontColor=#232F3E;fillColor=#232F3D;strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=12;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.users;fontFamily=Helvetica;" value="" vertex="1" parent="users-container">
  <mxGeometry x="30" y="30" width="48" height="48" as="geometry" />
</mxCell>
```

## Service Group Container

Container `value` = functional category label (e.g., "DNS", "Compute", "Database"). Icon `value` = service name + optional italic sub-label. NEVER put the service name on the container.

```xml
<!-- Service group container: value = category role, NOT service name -->
<mxCell id="svc-group-NAME" style="fillColor=TINT_COLOR;strokeColor=STROKE_COLOR;rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fontSize=12;fontColor=STROKE_COLOR;fontFamily=Helvetica;container=1;collapsible=0;shadow=1;strokeWidth=1.5;" value="Category Label" vertex="1" parent="1">
  <mxGeometry x="X" y="Y" width="120" height="120" as="geometry" />
</mxCell>

<!-- 48x48 service icon: value = service name + optional italic description -->
<mxCell id="svc-NAME" style="sketch=0;points=[[0,0,0],[0.25,0,0],[0.5,0,0],[0.75,0,0],[1,0,0],[0,1,0],[0.25,1,0],[0.5,1,0],[0.75,1,0],[1,1,0],[0,0.25,0],[0,0.5,0],[0,0.75,0],[1,0.25,0],[1,0.5,0],[1,0.75,0]];outlineConnect=0;fontColor=#232F3E;fillColor=CATEGORY_COLOR;strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;fontSize=10;fontStyle=0;aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.SHAPE_NAME;fontFamily=Helvetica;shadow=1;" value="Service Name&lt;div&gt;&lt;i&gt;description&lt;/i&gt;&lt;/div&gt;" vertex="1" parent="svc-group-NAME">
  <mxGeometry x="36" y="30" width="48" height="48" as="geometry" />
</mxCell>
```

## Legend Panel + Step Entry

```xml
<!-- Legend background panel (adaptive colors) -->
<mxCell id="legend-bg" style="verticalLabelPosition=bottom;verticalAlign=top;html=1;shape=mxgraph.basic.rect;fillColor2=none;strokeWidth=1;size=20;indent=5;fillColor=light-dark(#EDF3FF,#305363);strokeColor=#6c8ebf;" value="" vertex="1" parent="1">
  <mxGeometry height="780" width="650" x="LEGEND_X" y="LEGEND_Y" as="geometry" />
</mxCell>

<!-- Legend step entries container -->
<mxCell id="legend-container" connectable="0" style="group" value="" vertex="1" parent="1">
  <mxGeometry height="780" width="602" x="LEGEND_X+20" y="LEGEND_Y+30" as="geometry" />
</mxCell>

<!-- Step entry group -->
<mxCell id="step-N-legend" connectable="0" style="group;fontFamily=Helvetica;" value="" vertex="1" parent="legend-container">
  <mxGeometry height="80" width="600" x="0" y="STEP_Y_OFFSET" as="geometry" />
</mxCell>

<!-- Teal badge: 40x38, #007CBD, white bold text -->
<mxCell id="step-N-badge-legend" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#007CBD;strokeColor=default;fontColor=#FFFFFF;fontStyle=1;fontSize=22;labelBackgroundColor=none;fontFamily=Helvetica;shadow=1;glass=0;strokeWidth=2;" value="N" vertex="1" parent="step-N-legend">
  <mxGeometry height="38" width="40" y="2" as="geometry" />
</mxCell>

<!-- Step description with adaptive text color -->
<mxCell id="step-N-desc-legend" style="text;html=1;align=left;verticalAlign=top;spacingTop=-4;fontSize=14;labelBackgroundColor=none;whiteSpace=wrap;fontFamily=Helvetica;" value="&lt;div&gt;&lt;b&gt;Step Title&lt;/b&gt;&lt;/div&gt;&lt;div&gt;&lt;span style=&quot;color: light-dark(rgb(0,0,0), rgb(255,255,255));&quot;&gt;&lt;b&gt;&lt;font style=&quot;font-size: 15px;&quot;&gt;-&lt;/font&gt; &lt;/b&gt;Description of what happens&lt;/span&gt;&lt;/div&gt;" vertex="1" parent="step-N-legend">
  <mxGeometry height="80" width="548" x="52" as="geometry" />
</mxCell>
```

## On-Diagram Step Badge

```xml
<mxCell id="step-N" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#007CBD;strokeColor=default;fontColor=#FFFFFF;fontStyle=1;fontSize=16;fontFamily=Helvetica;shadow=1;glass=0;strokeWidth=2;align=center;verticalAlign=middle;labelBackgroundColor=none;" value="N" vertex="1" parent="1">
  <mxGeometry x="BADGE_X" y="BADGE_Y" width="28" height="28" as="geometry" />
</mxCell>
```

## Line Styles Box

```xml
<mxCell id="legend-line-styles-group" style="group;fontFamily=Helvetica;fillColor=light-dark(#F5F5F5,#29393B);strokeColor=#666666;" value="" vertex="1" parent="legend-container">
  <mxGeometry height="133" width="456" as="geometry" />
</mxCell>
```
