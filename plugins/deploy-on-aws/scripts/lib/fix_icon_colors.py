#!/usr/bin/env python3
"""Fix incorrect icon fillColor, container colors, and shape names.

Fixes three types of issues:
1. Icon fillColor: resIcon cells with wrong category fill color
2. Container tint/stroke: parent container with wrong category colors
3. Shape renames: broken shape names (e.g., iam → identity_and_access_management)

"""

import argparse
import defusedxml.ElementTree as ET

# Broken shape names → correct shape names
SHAPE_RENAMES: dict[str, str] = {
    "mxgraph.aws4.iam": "mxgraph.aws4.identity_and_access_management",
    "mxgraph.aws4.iot_sensor": "mxgraph.aws4.sensor",
}

# Map resIcon → (container_fillColor, container_strokeColor)
# Container = the 120x120 rounded rect that holds the icon
SHAPE_TO_CONTAINER: dict[str, tuple[str, str]] = {
    # Networking → #EDE7F6 / #8C4FFF
    "mxgraph.aws4.api_gateway": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.cloudfront": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.route_53": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.elastic_load_balancing": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.vpc": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.transit_gateway": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.direct_connect": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.cloud_map": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.nat_gateway": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.internet_gateway": ("#EDE7F6", "#8C4FFF"),
    # Analytics → #EDE7F6 / #8C4FFF
    "mxgraph.aws4.kinesis_data_streams": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.kinesis_data_firehose": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.athena": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.glue": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.quicksight": ("#EDE7F6", "#8C4FFF"),
    # Developer Tools → #EDE7F6 / #8C4FFF
    "mxgraph.aws4.codecommit": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.codepipeline": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.codebuild": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.codedeploy": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.xray": ("#EDE7F6", "#8C4FFF"),
    "mxgraph.aws4.x_ray": ("#EDE7F6", "#8C4FFF"),
    # Compute → #FFF2E8 / #ED7100
    "mxgraph.aws4.lambda": ("#FFF2E8", "#ED7100"),
    "mxgraph.aws4.ec2": ("#FFF2E8", "#ED7100"),
    "mxgraph.aws4.fargate": ("#FFF2E8", "#ED7100"),
    "mxgraph.aws4.app_runner": ("#FFF2E8", "#ED7100"),
    "mxgraph.aws4.ecs": ("#FFF2E8", "#ED7100"),
    # Database → #F5E6F7 / #C925D1
    "mxgraph.aws4.dynamodb": ("#F5E6F7", "#C925D1"),
    "mxgraph.aws4.rds": ("#F5E6F7", "#C925D1"),
    "mxgraph.aws4.aurora": ("#F5E6F7", "#C925D1"),
    "mxgraph.aws4.elasticache": ("#F5E6F7", "#C925D1"),
    "mxgraph.aws4.dynamodb_streams": ("#F5E6F7", "#C925D1"),
    "mxgraph.aws4.dynamodb_stream": ("#F5E6F7", "#C925D1"),
    # Storage → #E8F5E9 / #3F8624
    "mxgraph.aws4.s3": ("#E8F5E9", "#3F8624"),
    "mxgraph.aws4.ebs": ("#E8F5E9", "#3F8624"),
    "mxgraph.aws4.efs": ("#E8F5E9", "#3F8624"),
    # App Integration → #FCE4EC / #E7157B
    "mxgraph.aws4.eventbridge": ("#FCE4EC", "#E7157B"),
    "mxgraph.aws4.sqs": ("#FCE4EC", "#E7157B"),
    "mxgraph.aws4.sns": ("#FCE4EC", "#E7157B"),
    "mxgraph.aws4.step_functions": ("#FCE4EC", "#E7157B"),
    # Security → #FFEBEE / #DD344C
    "mxgraph.aws4.identity_and_access_management": ("#FFEBEE", "#DD344C"),
    "mxgraph.aws4.cognito": ("#FFEBEE", "#DD344C"),
    "mxgraph.aws4.waf": ("#FFEBEE", "#DD344C"),
    "mxgraph.aws4.kms": ("#FFEBEE", "#DD344C"),
    "mxgraph.aws4.secrets_manager": ("#FFEBEE", "#DD344C"),
    "mxgraph.aws4.certificate_manager": ("#FFEBEE", "#DD344C"),
    "mxgraph.aws4.directory_service": ("#FFEBEE", "#DD344C"),
    # AI/ML → #E0F2F1 / #01A88D
    "mxgraph.aws4.sagemaker": ("#E0F2F1", "#01A88D"),
    "mxgraph.aws4.bedrock": ("#E0F2F1", "#01A88D"),
    "mxgraph.aws4.bedrock_agentcore": ("#E0F2F1", "#01A88D"),
    # IoT → #E8F5E9 / #1A9C37
    "mxgraph.aws4.iot_core": ("#E8F5E9", "#1A9C37"),
    "mxgraph.aws4.iot_greengrass": ("#E8F5E9", "#1A9C37"),
    "mxgraph.aws4.sensor": ("#E8F5E9", "#1A9C37"),
    "mxgraph.aws4.iot_sensor": ("#E8F5E9", "#1A9C37"),
    # Management → #FCE4EC / #E7157B
    "mxgraph.aws4.cloudwatch": ("#FCE4EC", "#E7157B"),
    "mxgraph.aws4.cloudtrail": ("#FCE4EC", "#E7157B"),
    "mxgraph.aws4.systems_manager": ("#FCE4EC", "#E7157B"),
}

# Map resIcon shape names to correct icon fillColor
SHAPE_TO_FILL: dict[str, str] = {
    # Developer Tools → #8C4FFF (often confused with Database #C925D1)
    "mxgraph.aws4.codecommit": "#8C4FFF",
    "mxgraph.aws4.codepipeline": "#8C4FFF",
    "mxgraph.aws4.codebuild": "#8C4FFF",
    "mxgraph.aws4.codedeploy": "#8C4FFF",
    "mxgraph.aws4.codestar": "#8C4FFF",
    "mxgraph.aws4.codeartifact": "#8C4FFF",
    "mxgraph.aws4.cloud9": "#8C4FFF",
    "mxgraph.aws4.xray": "#8C4FFF",
    "mxgraph.aws4.x_ray": "#8C4FFF",
    # Networking/Analytics → #8C4FFF
    "mxgraph.aws4.kinesis_data_streams": "#8C4FFF",
    "mxgraph.aws4.kinesis_data_firehose": "#8C4FFF",
    "mxgraph.aws4.athena": "#8C4FFF",
    "mxgraph.aws4.glue": "#8C4FFF",
    "mxgraph.aws4.quicksight": "#8C4FFF",
    "mxgraph.aws4.api_gateway": "#8C4FFF",
    "mxgraph.aws4.cloudfront": "#8C4FFF",
    "mxgraph.aws4.route_53": "#8C4FFF",
    "mxgraph.aws4.vpc": "#8C4FFF",
    "mxgraph.aws4.elastic_load_balancing": "#8C4FFF",
    "mxgraph.aws4.transit_gateway": "#8C4FFF",
    "mxgraph.aws4.direct_connect": "#8C4FFF",
    "mxgraph.aws4.cloud_map": "#8C4FFF",
    # Compute → #ED7100
    "mxgraph.aws4.lambda": "#ED7100",
    "mxgraph.aws4.ec2": "#ED7100",
    "mxgraph.aws4.fargate": "#ED7100",
    "mxgraph.aws4.app_runner": "#ED7100",
    "mxgraph.aws4.ecs": "#ED7100",
    # Database → #C925D1
    "mxgraph.aws4.dynamodb": "#C925D1",
    "mxgraph.aws4.rds": "#C925D1",
    "mxgraph.aws4.aurora": "#C925D1",
    "mxgraph.aws4.elasticache": "#C925D1",
    "mxgraph.aws4.dynamodb_streams": "#C925D1",
    # Storage → #3F8624
    "mxgraph.aws4.s3": "#3F8624",
    "mxgraph.aws4.ebs": "#3F8624",
    "mxgraph.aws4.efs": "#3F8624",
    # App Integration → #E7157B
    "mxgraph.aws4.eventbridge": "#E7157B",
    "mxgraph.aws4.sqs": "#E7157B",
    "mxgraph.aws4.sns": "#E7157B",
    "mxgraph.aws4.step_functions": "#E7157B",
    # Security → #DD344C
    "mxgraph.aws4.identity_and_access_management": "#DD344C",
    "mxgraph.aws4.cognito": "#DD344C",
    "mxgraph.aws4.waf": "#DD344C",
    "mxgraph.aws4.kms": "#DD344C",
    "mxgraph.aws4.secrets_manager": "#DD344C",
    "mxgraph.aws4.certificate_manager": "#DD344C",
    # AI/ML → #01A88D
    "mxgraph.aws4.sagemaker": "#01A88D",
    "mxgraph.aws4.bedrock": "#01A88D",
    "mxgraph.aws4.bedrock_agentcore": "#01A88D",
    # IoT → #1A9C37
    "mxgraph.aws4.iot_core": "#1A9C37",
    "mxgraph.aws4.iot_greengrass": "#1A9C37",
    "mxgraph.aws4.iot_analytics": "#1A9C37",
    "mxgraph.aws4.sensor": "#1A9C37",
    "mxgraph.aws4.iot_sensor": "#1A9C37",
    # Management → #E7157B
    "mxgraph.aws4.cloudwatch": "#E7157B",
    "mxgraph.aws4.cloudtrail": "#E7157B",
    "mxgraph.aws4.systems_manager": "#E7157B",
}


def _replace_style_value(style: str, key: str, new_val: str) -> str:
    """Replace a key=value in a semicolon-delimited style string."""
    parts = []
    found = False
    for part in style.split(";"):
        if part.startswith(f"{key}="):
            parts.append(f"{key}={new_val}")
            found = True
        else:
            parts.append(part)
    if not found:
        parts.append(f"{key}={new_val}")
    return ";".join(parts)


def _extract_color(value: str) -> str | None:
    """Extract a hex color from a style value, unwrapping light-dark() if present.

    Examples:
        '#E7157B' → '#E7157B'
        'light-dark(#DE227B,#DE227B)' → '#DE227B'
        'light-dark(#FCE4EC,#FCE4EC)' → '#FCE4EC'
    """
    if not value:
        return None
    if "light-dark(" in value:
        # Extract first color from light-dark(COLOR1,COLOR2)
        inner = value.split("light-dark(", 1)[1].rstrip(")")
        parts = inner.split(",")
        return parts[0].strip() if parts else None
    if value.startswith("#"):
        return value
    return None


def fix_icon_colors(tree: ET.ElementTree, verbose: bool = False) -> int:
    """Fix icon fillColor, container tint/stroke, and broken shape names.

    1. Rename broken resIcon shapes (e.g., iam → identity_and_access_management)
    2. Fix icon fillColor to match category
    3. Fix parent container fillColor/strokeColor to match category

    Returns total number of cells fixed.
    """
    root_elem = tree.getroot()
    fixed = 0

    # Build a map of cell ID → cell element
    cells: dict[str, ET.Element] = {}
    for cell in root_elem.iter("mxCell"):
        cid = cell.get("id")
        if cid:
            cells[cid] = cell

    for cell in root_elem.iter("mxCell"):
        style = cell.get("style", "")
        if "resIcon=" not in style:
            continue

        # Extract resIcon value
        res_icon = None
        for part in style.split(";"):
            if part.startswith("resIcon="):
                res_icon = part.split("=", 1)[1]
                break

        if res_icon is None:
            continue

        # Step 1: Fix broken shape names
        if res_icon in SHAPE_RENAMES:
            new_icon = SHAPE_RENAMES[res_icon]
            style = style.replace(f"resIcon={res_icon}", f"resIcon={new_icon}")
            cell.set("style", style)
            fixed += 1
            if verbose:
                cid = cell.get("id", "?")
                print(f"  Renamed {cid}: {res_icon} -> {new_icon}")
            res_icon = new_icon

        # Step 2: Fix icon fillColor
        if res_icon in SHAPE_TO_FILL:
            expected_fill = SHAPE_TO_FILL[res_icon]
            current_fill = None
            for part in style.split(";"):
                if part.startswith("fillColor="):
                    current_fill = part.split("=", 1)[1]
                    break

            if current_fill is not None and current_fill.upper() != expected_fill.upper():
                style = _replace_style_value(style, "fillColor", expected_fill)
                cell.set("style", style)
                fixed += 1
                if verbose:
                    cid = cell.get("id", "?")
                    print(f"  Fixed icon {cid}: fillColor {current_fill} -> {expected_fill}")

        # Step 3: Fix parent container tint/stroke/fontColor
        if res_icon in SHAPE_TO_CONTAINER:
            expected_tint, expected_stroke = SHAPE_TO_CONTAINER[res_icon]
            parent_id = cell.get("parent", "")
            parent_cell = cells.get(parent_id)

            if parent_cell is not None and parent_cell.get("vertex") == "1":
                parent_style = parent_cell.get("style", "")

                # Only fix containers (rounded rect with strokeColor)
                if "strokeColor=" not in parent_style:
                    continue

                # Check current container colors
                cur_stroke_raw = None
                cur_fill_raw = None
                cur_font_raw = None
                for part in parent_style.split(";"):
                    if part.startswith("strokeColor="):
                        cur_stroke_raw = part.split("=", 1)[1]
                    elif part.startswith("fillColor="):
                        cur_fill_raw = part.split("=", 1)[1]
                    elif part.startswith("fontColor="):
                        cur_font_raw = part.split("=", 1)[1]

                container_changed = False

                # Fix strokeColor — handle both plain and light-dark() wrapped
                if cur_stroke_raw:
                    cur_stroke = _extract_color(cur_stroke_raw)
                    if cur_stroke and cur_stroke.upper() != expected_stroke.upper():
                        if "light-dark" in cur_stroke_raw:
                            # Replace with light-dark using correct color
                            new_val = f"light-dark({expected_stroke},{expected_stroke})"
                        else:
                            new_val = expected_stroke
                        parent_style = _replace_style_value(parent_style, "strokeColor", new_val)
                        container_changed = True

                # Fix fillColor — handle both plain and light-dark() wrapped
                if cur_fill_raw:
                    cur_fill = _extract_color(cur_fill_raw)
                    if cur_fill and cur_fill.upper() != expected_tint.upper():
                        if "light-dark" in cur_fill_raw:
                            new_val = f"light-dark({expected_tint},{expected_tint})"
                        else:
                            new_val = expected_tint
                        parent_style = _replace_style_value(parent_style, "fillColor", new_val)
                        container_changed = True

                # Fix fontColor to match category stroke color
                if cur_font_raw:
                    cur_font = _extract_color(cur_font_raw)
                    if cur_font and cur_font.upper() != expected_stroke.upper():
                        # Don't touch light-dark font colors (those are for dark mode text)
                        if "light-dark" not in cur_font_raw:
                            parent_style = _replace_style_value(parent_style, "fontColor", expected_stroke)
                            container_changed = True

                if container_changed:
                    parent_cell.set("style", parent_style)
                    fixed += 1
                    if verbose:
                        pid = parent_cell.get("id", "?")
                        print(f"  Fixed container {pid}: fill={expected_tint} stroke={expected_stroke} font={expected_stroke}")

    return fixed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fix AWS service icon fill colors in draw.io files"
    )
    parser.add_argument("file", help="Path to .drawio file")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    tree = ET.parse(args.file)
    fixed = fix_icon_colors(tree, args.verbose)

    if fixed > 0:
        print(f"Icons fixed: {fixed}")
        if not args.dry_run:
            ET.indent(tree, space="  ")
            tree.write(args.file, encoding="unicode", xml_declaration=False)
            print(f"Written: {args.file}")
        else:
            print("(dry run, no changes written)")
    else:
        print("No icon color issues found")


if __name__ == "__main__":
    main()
