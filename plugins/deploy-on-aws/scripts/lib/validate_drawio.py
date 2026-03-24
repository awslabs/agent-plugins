#!/usr/bin/env python3
"""
validate_drawio.py - Validates draw.io XML files for:
1. XML well-formedness
2. Correct draw.io structure (mxfile > diagram > mxGraphModel > root)
3. Valid AWS4 shape references
4. Edge integrity (source/target reference valid cell IDs)
5. Geometry validation (vertices have mxGeometry)
"""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Load valid AWS4 shapes
SCRIPT_DIR = Path(__file__).parent
shapes_data = json.loads((SCRIPT_DIR / "aws4-shapes.json").read_text())

valid_shapes = set()
for category in shapes_data["categories"].values():
    for shape in category["shapes"]:
        valid_shapes.add(shape)


def validate(file_path):
    errors = []
    warnings = []

    # 1. Read file
    try:
        xml_text = Path(file_path).read_text(encoding="utf-8")
    except Exception as e:
        errors.append(f"Cannot read file: {e}")
        return errors, warnings

    if not xml_text.strip():
        errors.append("File is empty")
        return errors, warnings

    # Parse XML
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as e:
        errors.append(f"XML parse error: {e}")
        return errors, warnings

    # 2. Validate structure - accept both <mxfile> wrapped and bare <mxGraphModel>
    tag = root.tag
    if tag == "mxfile":
        diagrams = root.findall("diagram")
        if not diagrams:
            errors.append("Missing <diagram> element inside <mxfile>.")
            return errors, warnings

        models = root.findall(".//mxGraphModel")
        if not models:
            # Check for compressed content
            for diag in diagrams:
                content = (diag.text or "").strip()
                if content and not content.startswith("<"):
                    name = diag.get("name", str(diagrams.index(diag)))
                    warnings.append(
                        f'Diagram "{name}" appears to be compressed. '
                        "For full validation, use uncompressed XML format."
                    )
            if warnings:
                return errors, warnings
            errors.append("Missing <mxGraphModel> element.")
            return errors, warnings

        diagram_count = len(diagrams)

    elif tag == "mxGraphModel":
        diagram_count = 1
    else:
        errors.append(
            "Missing root element. draw.io files must start with <mxfile> or <mxGraphModel>."
        )
        return errors, warnings

    # 3. Validate cells
    cells = root.iter("mxCell") if tag == "mxGraphModel" else root.findall(".//mxCell")
    cells = list(cells)

    cell_ids = set()
    has_root_cell = False
    has_default_layer = False
    aws_shapes_used = []
    invalid_shapes = []

    for cell in cells:
        cell_id = cell.get("id")
        style = cell.get("style", "")
        is_vertex = cell.get("vertex") == "1"

        if cell_id:
            cell_ids.add(cell_id)
        if cell_id == "0":
            has_root_cell = True
        if cell_id == "1" and cell.get("parent") == "0":
            has_default_layer = True

        # Check AWS4 shapes
        shape_match = re.search(r"shape=mxgraph\.aws4\.(\w+)", style)
        if shape_match:
            shape_name = shape_match.group(1)
            aws_shapes_used.append(shape_name)
            if shape_name not in valid_shapes:
                invalid_shapes.append(shape_name)

        # Check resIcon references
        res_icon_match = re.search(r"resIcon=mxgraph\.aws4\.(\w+)", style)
        if res_icon_match:
            res_icon_name = res_icon_match.group(1)
            if res_icon_name not in valid_shapes:
                invalid_shapes.append(f"resIcon:{res_icon_name}")

        # 5. Geometry validation for vertices
        if is_vertex:
            geometries = cell.findall("mxGeometry")
            if not geometries:
                warnings.append(f'Vertex cell id="{cell_id}" is missing <mxGeometry>.')

    if not has_root_cell:
        errors.append('Missing root cell (mxCell id="0").')
    if not has_default_layer:
        errors.append('Missing default layer cell (mxCell id="1" parent="0").')

    # 4. Edge integrity
    for cell in cells:
        if cell.get("edge") == "1":
            source = cell.get("source")
            target = cell.get("target")
            if source and source not in cell_ids:
                errors.append(
                    f'Edge id="{cell.get("id")}" references non-existent source="{source}".'
                )
            if target and target not in cell_ids:
                errors.append(
                    f'Edge id="{cell.get("id")}" references non-existent target="{target}".'
                )

    # Report invalid AWS shapes
    if invalid_shapes:
        unique_invalid = list(dict.fromkeys(invalid_shapes))
        errors.append(
            f"Invalid AWS4 shape references: {', '.join(unique_invalid)}. "
            "Check the aws4-shapes.json registry for valid shape names."
        )

    # --- AWS Diagram Guideline Compliance Checks (warnings only) ---

    # 1. Background color check
    graph_models = [root] if tag == "mxGraphModel" else root.findall(".//mxGraphModel")
    for model in graph_models:
        bg = model.get("background")
        if bg != "#FFFFFF":
            warnings.append(
                'No white background set on mxGraphModel. '
                'AWS guidelines require background="#FFFFFF" (not transparent).'
            )
            break

    # 2. Font color check
    has_old_font_color = False
    for cell in cells:
        style = cell.get("style", "")
        if cell.get("vertex") == "1" and "fontColor=#232F3E" in style:
            has_old_font_color = True
            break
    if has_old_font_color:
        warnings.append(
            "Some shapes use fontColor=#232F3E. "
            "AWS guidelines recommend #16191F or #000000 for label text."
        )

    # 4. Font size check
    has_small_font = False
    for cell in cells:
        style = cell.get("style", "")
        if cell.get("vertex") == "1":
            fs_match = re.search(r"fontSize=(\d+)", style)
            if fs_match and int(fs_match.group(1)) < 11:
                has_small_font = True
                break
    if has_small_font:
        warnings.append(
            "Some shapes use fontSize below 11px. "
            "AWS guidelines require 12px minimum (11px acceptable for dense layouts)."
        )

    # Summary info
    if aws_shapes_used:
        unique_count = len(set(aws_shapes_used))
        warnings.append(
            f"AWS4 shapes used: {unique_count} unique shapes across {diagram_count} diagram(s)."
        )

    return errors, warnings


def main():
    if len(sys.argv) < 2:
        print("Usage: validate_drawio.py <file.drawio>", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[1]
    errors, warnings = validate(file_path)

    if errors:
        print(f"VALIDATION FAILED for {file_path}:")
        for e in errors:
            print(f"  ERROR: {e}")
    if warnings:
        for w in warnings:
            print(f"  INFO: {w}")
    if not errors:
        print(f"VALIDATION PASSED for {file_path}.")

    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
