# Layout Guidelines

Detailed spacing, edge routing, overlap prevention, and placement rules for AWS architecture diagrams.

## Spacing and Overlap Prevention

- 180px horizontal / 120px vertical gaps between 120px service group containers
- Group padding: 30px all sides, children start at y=40, x=20 minimum
- Account for ~20px label height below each 48x48 icon; 60px gap between vertical tiers
- Edge labels MUST NOT overlap service icons or description text — use `y` offset to shift
- 30px clearance between arrow endpoints and italic description text
- Place standalone services 200px+ from top-left corner of Region/VPC groups
- Align all positions to grid multiples of 10

## Complex Diagram Scaling (13+ services)

For diagrams with 13+ services, increase spacing to prevent crowding:

- Horizontal spacing: 220px (up from 180px)
- Vertical spacing: 160px (up from 120px)
- Page size: `pageWidth=1600;pageHeight=1200` minimum
- Route long-distance edges around service clusters using explicit waypoints (`<Array as="points"><mxPoint x=... y=.../></Array>`)
- Arrows MUST NOT cross through service container rectangles — use waypoints to route around them
- For edges connecting services that are NOT horizontally or vertically adjacent, ALWAYS add explicit waypoints to route around intervening containers

## Edge Routing

Study `example-event-driven.drawio` and `example-complex-platform.drawio` for correct edge routing patterns.

**Basic rules:**

- Use `edgeStyle=orthogonalEdgeStyle` for right-angle connectors
- For simple adjacent connections (A directly next to B), let draw.io auto-route — do NOT set entry/exit points
- Leave 20px straight segment before target and after source for arrowheads
- Edges always leave PERPENDICULAR to the container face and route OUTWARD — the first segment after exiting a container MUST move AWAY from the container, never back into it. If an edge exits from the bottom (`exitY=1`), the first segment goes DOWN. If it exits right (`exitX=1`), the first segment goes RIGHT.

**Multiple edges from one service** (CRITICAL):

- When a service has 2+ outgoing edges, each edge MUST exit from a DIFFERENT side or a different point on the same side
- Example: Lambda -> AgentCore (`exitX=0.5;exitY=1` bottom), Lambda -> Step Functions (`exitX=1;exitY=0.5` right), Lambda -> EventBridge (`exitX=1;exitY=0.75` right-lower)
- When 2+ edges enter the same target from the same direction, offset entry points: `entryX=0.25;entryY=0` and `entryX=0.5;entryY=0` (not both at 0.5)

**Waypoints for non-adjacent routing** (CRITICAL):

- When an edge must route AROUND intervening containers, add explicit waypoints using `<Array as="points"><mxPoint x="X" y="Y"/></Array>` inside the edge's `<mxGeometry>`
- Create clean L-shaped (2 waypoints) or U-shaped (3 waypoints) paths
- Route waypoints through clear lanes between container rows/columns
- Example: To route from Lambda (right side) around to DynamoDB (below), exit right then create a vertical lane: `exit=(1,0.25)` -> waypoint at (x_far_right, y_lambda) -> waypoint at (x_far_right, y_dynamo) -> enters DynamoDB from right
- See the edge patterns in `example-event-driven.drawio` for real examples with 2-3 waypoints per edge

## Handling Overlaps

**Always add `labelBackgroundColor=#ffffff`** to every edge label. This prevents labels from blending with crossing edges or nearby icon labels. Include it in the `edgeLabel` style by default — not as an afterthought:

```
labelBackgroundColor=#ffffff
```

Only reroute an edge (via waypoints or different exit/entry points) when the overlap is severe and the reroute is simple and clean — avoid complex rerouting that could make arrows harder to follow. The label zones to be aware of:

- **78px icons**: ~25px label height below the icon (total footprint ~103px tall)
- **48px icons**: ~20px label height below (total footprint ~68px tall)
- **Group labels**: 30px reserved at the top-left of AWS group shapes

For parallel edges sharing a corridor, offset them by 20px using explicit waypoints and spread connections across different anchor points on the node.

## Layout Patterns

- **Top-to-bottom (tiered)**: Best for VPC architectures with user -> LB -> compute -> DB flow
- **Left-to-right (pipeline)**: Best for data pipelines and CI/CD
- **Column-based (reference architecture)**: Best for complex multi-service platforms with labeled columns

## Step Badges and Legend

For complex diagrams (7+ services or multiple branching paths):

**On-diagram badges**: Teal `#007CBD` 28x28 rounded rectangles near arrow source ends. Place at the **source end** of the arrow (NOT midpoint — midpoint is for edge labels). Offset 20px above/left. Minimum 10px clearance from icons and labels.

**Right sidebar legend**: Panel at `x = diagram_right_edge + 40`, same `y` as title group (y=30). Teal badges (40x38) + bold title + bullet descriptions per step. All step text MUST use `color: light-dark(...)` for dark mode. Increase `mxGraphModel dx` to accommodate sidebar.

**Legend height MUST match the diagram**: Set `legend-outer` height to span from `y=30` to the bottom of the AWS Cloud group + 20px padding. The legend panel MUST visually extend the full height of the diagram, never shorter. If the diagram bottom is at y=1170, legend height should be ~1160px.

**Legend MUST NOT cover any diagram elements**: Ensure the legend panel's x position is far enough right that it does not overlap any external actors, service containers, or edges. If there are external actors on the right side (e.g., external APIs), place them to the LEFT of the legend or increase `mxGraphModel dx` to create more space.

See `xml-templates-structure.md` for badge and legend XML. See `style-guide.md` for detailed legend rules.

**Auxiliary/monitoring services**: ONLY CloudWatch, CloudTrail, X-Ray, and IAM are auxiliary. These do NOT get step numbers and do NOT get edges. Place them inside a dedicated **"Auxiliary Services" group** — a dashed, unfilled rectangle (`rounded=0;fillColor=none;dashed=1;verticalAlign=top`) labeled "Auxiliary Services". Placement rules:

- MUST be INSIDE the AWS Cloud boundary (not outside it)
- MUST be in a free corner where it does NOT overlap or interfere with primary services or their edges
- MUST NOT be placed where the legend panel would cover it — if the legend is on the right, place auxiliary at bottom-left
- The dashed box MUST be large enough to contain all auxiliary service containers with padding (at least 20px on all sides)
- Auxiliary service containers MUST use their correct category tint colors (CloudWatch: `#FCE4EC`/`#E7157B`, X-Ray: same, IAM: `#FFEBEE`/`#DD344C`) — NOT gray

In the legend, add an italic note explaining their role BELOW all step descriptions but ABOVE the Line Styles box — as a separate text element, not inside the Line Styles box.

**All other services (App Runner, Cognito, Secrets Manager, etc.) are primary services** that MUST have edges connecting them to the data flow and MUST receive step numbers.

**Decision points**: Maximum 1-2 per diagram. Use `fontStyle=2` (italic) for `[condition]` text on edge labels. Dashed arrows ONLY for failure/fallback paths.

## Service Placement

| Service | Correct Container |
|---------|-------------------|
| ALB, NAT Gateway, Bastion | Public subnet |
| EC2, ECS/Fargate, Lambda (VPC), RDS, ElastiCache | Private subnet |
| Transit Gateway, VPN Gateway | VPC level (not in subnet) |
| Route 53, CloudFront, S3, IAM, CloudWatch | Outside VPC |
| Users, On-premises | Outside AWS Cloud boundary |

**External actor coordinates**: External actors MUST have coordinates that place them visually OUTSIDE the AWS Cloud group rectangle — at least 40px from the boundary.
