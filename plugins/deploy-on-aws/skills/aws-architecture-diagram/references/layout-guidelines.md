# Layout Guidelines

Spacing, edge routing, overlap prevention, and placement rules for AWS architecture diagrams.

## Spacing and Overlap Prevention

- 180px horizontal / 120px vertical gaps between 120px service group containers
- Group padding: 30px all sides; children start at y=40, x=20 minimum
- ~20px label height below each 48x48 icon; 60px gap between vertical tiers
- Edge labels MUST NOT overlap icons or text — use `y` offset to shift; 30px clearance from arrow endpoints to italic text
- Standalone services 200px+ from top-left corner of Region/VPC groups
- Align all positions to grid multiples of 10

## Complex Diagram Scaling (13+ services)

For diagrams with 13+ services, increase spacing:

- Horizontal: 220px; Vertical: 160px; Page: `pageWidth=1600;pageHeight=1200` minimum
- Route long-distance edges around clusters using explicit waypoints (`<Array as="points"><mxPoint x=... y=.../></Array>`)
- Arrows MUST NOT cross through service containers — use waypoints to route around them
- For non-adjacent service connections, ALWAYS add explicit waypoints to route around intervening containers

## Edge Routing

Study `example-event-driven.drawio` and `example-complex-platform.drawio` for correct edge routing patterns.

**Basic rules:**

- Use `edgeStyle=orthogonalEdgeStyle` for right-angle connectors
- For simple adjacent connections, let draw.io auto-route — do NOT set entry/exit points
- Leave 20px straight segment before target and after source for arrowheads
- Edges leave PERPENDICULAR to the container face and route OUTWARD — first segment MUST move AWAY from the container (exit bottom → go DOWN, exit right → go RIGHT)

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

**Always add `labelBackgroundColor=none`** to every edge label. NEVER use `labelBackgroundColor=#ffffff` — it breaks dark mode adaptive contrast.

Only reroute an edge when the overlap is severe and the reroute is simple and clean. Label zone footprints: 78px icons = ~103px tall (with label), 48px icons = ~68px tall, group labels = 30px at top-left.

For parallel edges sharing a corridor, offset by 20px using explicit waypoints and spread connections across different anchor points.

## Layout Patterns

- **Top-to-bottom (tiered)**: Best for VPC architectures with user -> LB -> compute -> DB flow
- **Left-to-right (pipeline)**: Best for data pipelines and CI/CD
- **Column-based (reference architecture)**: Best for complex multi-service platforms with labeled columns

## Step Badges and Legend

For complex diagrams (7+ services or multiple branching paths):

**On-diagram badges**: Teal `#007CBD` 28x28 rounded rectangles near arrow source ends. Place at **source end** (NOT midpoint). Offset 20px above/left. Min 10px clearance from icons/labels.

**Right sidebar legend**: Panel at `x = diagram_right_edge + 40`, `y=30`. Teal badges (40x38) + bold title + bullet descriptions. All step text MUST use `color: light-dark(...)` for dark mode. Increase `mxGraphModel dx` to accommodate.

**Legend height MUST match diagram**: `legend-outer` height from `y=30` to AWS Cloud bottom + 20px. MUST NOT cover diagram elements. See `xml-templates-structure.md` for XML, `style-guide.md` for rules.

**Auxiliary/monitoring services**: ONLY CloudWatch, CloudTrail, X-Ray, and IAM are auxiliary. No step numbers, no edges. Place inside a dashed, unfilled rectangle (`rounded=0;fillColor=none;dashed=1;verticalAlign=top`) labeled "Auxiliary Services". Must be INSIDE AWS Cloud, in a free corner, not covered by legend. Use correct tint colors (CloudWatch/X-Ray: `#FCE4EC`/`#E7157B`, IAM: `#FFEBEE`/`#DD344C`) — NOT gray. Add italic legend note BELOW step descriptions, ABOVE Line Styles box. **All other services are primary** and MUST have edges and step numbers.

**Decision points**: Maximum 1-2 per diagram. Use `fontStyle=2` (italic) for `[condition]` text on edge labels. Dashed arrows ONLY for failure/fallback paths.

## Service Placement

| Service                                          | Correct Container          |
| ------------------------------------------------ | -------------------------- |
| ALB, NAT Gateway, Bastion                        | Public subnet              |
| EC2, ECS/Fargate, Lambda (VPC), RDS, ElastiCache | Private subnet             |
| Transit Gateway, VPN Gateway                     | VPC level (not in subnet)  |
| Route 53, CloudFront, S3, IAM, CloudWatch        | Outside VPC                |
| Users, On-premises                               | Outside AWS Cloud boundary |

**External actor coordinates**: External actors MUST have coordinates that place them visually OUTSIDE the AWS Cloud group rectangle — at least 40px from the boundary.

## Layout Sizing Reference

| Element                | Width     | Height   |
| ---------------------- | --------- | -------- |
| Service icon           | 78        | 78       |
| Small resource icon    | 48        | 48       |
| Text label             | varies    | 20       |
| VPC group (typical)    | 800-1200  | 500-800  |
| Subnet group (typical) | 350-550   | 400-700  |
| AZ group (typical)     | 380-580   | 420-720  |
| Region group (typical) | 900-1400  | 600-900  |
| AWS Cloud group        | 1000-1500 | 700-1000 |
