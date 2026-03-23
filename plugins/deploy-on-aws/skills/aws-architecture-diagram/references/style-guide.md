# AWS Reference Architecture Style Guide

Style rules and visual standards. For XML code blocks, see `xml-templates-structure.md` and `xml-templates-examples.md`.

**Primary visual references**: `example-multi-region-active-active.drawio`, `example-event-driven.drawio`, `example-microservices.drawio`, and `example-saas-backend.drawio` demonstrate all patterns below.

## Title + Subtitle Block

Every diagram MUST have a title group: title (30px bold), subtitle (16px), orange separator (`strokeColor=#FF9900`). Title = architecture name, subtitle = what it does. Width MUST span the full diagram. See `xml-templates-structure.md` for XML.

## Dark/Light Adaptive Contrast

| Element                | Property      | Value                                             |
| ---------------------- | ------------- | ------------------------------------------------- |
| AWS Cloud fills        | `fillColor`   | `light-dark(#232F3E0D,#232F3E0D)`                 |
| Region fills           | `fillColor`   | `light-dark(#0C7B7D0D,#0C7B7D0D)`                 |
| VPC fills              | `fillColor`   | `light-dark(#8C4FFF0D,#8C4FFF0D)`                 |
| Public subnet fills    | `fillColor`   | `light-dark(#2488140D,#2488140D)`                 |
| Private subnet fills   | `fillColor`   | `light-dark(#147EBA0D,#147EBA0D)`                 |
| Users container stroke | `strokeColor` | `light-dark(#666666,#D4D4D4)`                     |
| Legend background      | `fillColor`   | `light-dark(#EDF3FF,#305363)`                     |
| Legend step text       | inline CSS    | `color: light-dark(rgb(0,0,0), rgb(255,255,255))` |
| Line Styles box        | `fillColor`   | `light-dark(#F5F5F5,#29393B)`                     |

**Hex+alpha**: `#0C7B7D0D` = teal at ~5% opacity (last two hex digits are alpha). Add `fillStyle=auto;` when using `light-dark()` fills.

## Users Container

Users and external actors MUST be wrapped in a visible container for dark mode. See `xml-templates-structure.md` for XML.

- Container `fillColor=#f5f5f5` provides contrast in dark mode
- `strokeColor=light-dark(#666666,#D4D4D4)` adapts to mode
- Icon `value=""` (empty) since the container carries the label
- Shadow enabled for visual depth

## Right Sidebar Step Legend

Legend panel positioned to the RIGHT of the main diagram. See `xml-templates-structure.md` for XML.

- Position: `x = diagram_right_edge + 40`, same `y` as title group
- Panel width: ~650px, adaptive background `light-dark(#EDF3FF,#305363)`
- Step entries: teal badge (40x38) at left + text block (width ~548) at x=52
- Each step `<span>` MUST include `color: light-dark(rgb(0,0,0), rgb(255,255,255))`
- Badge style: `strokeColor=default;strokeWidth=2;shadow=1;glass=0`
- Stack entries vertically with ~10px gap

## Step Number Badges (On-Diagram)

Small teal `#007CBD` badges (28x28, fontSize=16) placed near arrows. See `xml-templates-structure.md` for XML.

- Place near arrow source end, offset 20px above/left
- Minimum clearance: 10px from any icon, container edge, or edge label
- Style: `strokeColor=default;strokeWidth=2;shadow=1;glass=0`

## Service Group Containers

### Category Tint Colors

| Category             | fillColor (tint) | strokeColor | Example Services                      |
| -------------------- | ---------------- | ----------- | ------------------------------------- |
| Compute              | `#FFF2E8`        | `#ED7100`   | Lambda, EC2, ECS, Fargate             |
| Database             | `#F5E6F7`        | `#C925D1`   | DynamoDB, RDS, Aurora                 |
| Analytics/Networking | `#EDE7F6`        | `#8C4FFF`   | API Gateway, VPC, CloudFront, Kinesis |
| Storage              | `#E8F5E9`        | `#3F8624`   | S3, EBS, EFS                          |
| App Integration      | `#FCE4EC`        | `#E7157B`   | EventBridge, SQS, SNS, Step Functions |
| AI/ML                | `#E0F2F1`        | `#01A88D`   | SageMaker, Bedrock                    |
| Security             | `#FFEBEE`        | `#DD344C`   | IAM, Cognito, WAF, KMS                |
| IoT                  | `#E8F5E9`        | `#1A9C37`   | IoT Core, Greengrass, IoT Analytics   |
| General/Auxiliary    | `#F5F5F5`        | `#666666`   | CloudWatch, auxiliary services        |

Container 120x120, icon 48x48 at (x=36, y=30). See `xml-templates-structure.md` for XML.

## Group Shapes with Adaptive Fills

Region: `light-dark(#0C7B7D0D,#0C7B7D0D)` / `#00A4A6`. VPC: `light-dark(#8C4FFF0D,#8C4FFF0D)` / `#8C4FFF`. Public subnet: `light-dark(#2488140D,#2488140D)` / `#248814`. Private subnet: `light-dark(#147EBA0D,#147EBA0D)` / `#147EBA`. Add `fillStyle=auto;` when using `light-dark()` fills.

## Font Standard

**Default mode**: `fontFamily=Helvetica`. **Sketch mode**: `fontFamily=Comic Sans MS`. Do NOT use Amazon Ember or other fonts.

Font size hierarchy:

- Title: 30px bold | Subtitle: 16px | Group titles: 14px bold | Container labels: 12px bold | Service labels: 10px | Edge labels: 11px | Legend badge: 22px bold (legend) / 16px bold (on-diagram) | Legend text: 14px

## Sketch Mode

Add `sketch=1;curveFitting=1;jiggle=2` to all non-icon elements. Keep `sketch=0` on service icons. See `example-sketch.drawio`.

| Element           | Default             | Sketch                                                                        |
| ----------------- | ------------------- | ----------------------------------------------------------------------------- |
| Font              | Helvetica           | Comic Sans MS                                                                 |
| Container fills   | static tint         | `light-dark(LIGHT_TINT,#000000)`                                              |
| Icon label text   | `fontColor=#232F3E` | `<font style="color: light-dark(rgb(0,0,0), rgb(245,245,245));">`             |
| Users container   | `fillColor=#f5f5f5` | `fillColor=light-dark(#F5F5F5,#000000);fontColor=light-dark(#333333,#FAFAFA)` |
| Badge number text | `fontColor=#FFFFFF` | `<font style="color: light-dark(rgb(0,0,0), rgb(255,255,255));">`             |
| Legend badge      | `fontColor=#FFFFFF` | `fontColor=light-dark(#000000,#121212)`                                       |

## AgentCore Icons

Use `resIcon=mxgraph.aws4.bedrock_agentcore` (NOT `mxgraph.aws4.bedrock`) for Amazon Bedrock AgentCore services. See `example-agentcore.drawio`.
