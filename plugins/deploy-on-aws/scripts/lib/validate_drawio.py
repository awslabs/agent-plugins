#!/usr/bin/env python3
"""
validate_drawio.py - Validates draw.io XML files for:
1. XML well-formedness
2. Correct draw.io structure (mxfile > diagram > mxGraphModel > root)
3. Valid AWS4 shape references
4. Edge integrity (source/target reference valid cell IDs)
5. Geometry validation (vertices have mxGeometry)
"""

import io
import json
import os
import re
import sys
import defusedxml.ElementTree as ET
from pathlib import Path

MAX_FILE_SIZE = 2 * 1024 * 1024  # 2 MB
MAX_XML_DEPTH = 50
MAX_XML_ELEMENTS = 50_000

# Load valid AWS4 shapes
SCRIPT_DIR = Path(__file__).parent
shapes_data = json.loads((SCRIPT_DIR / "aws4-shapes.json").read_text())

valid_shapes = set()
for category in shapes_data["categories"].values():
    for shape in category["shapes"]:
        valid_shapes.add(shape)


def _sanitize_attr(value: str, max_len: int = 80) -> str:
    """Sanitize an XML attribute value for safe inclusion in error messages.

    Strips non-printable characters, collapses whitespace, truncates, and
    restricts to safe characters to prevent prompt injection through crafted
    draw.io attributes that flow into agent systemMessage context.
    """
    if not value:
        return "(empty)"
    sanitized = re.sub(r"[\x00-\x1f\x7f-\x9f]", "", value)
    sanitized = re.sub(r"\s+", " ", sanitized).strip()
    sanitized = re.sub(r"[^\w\-.:# ]", "_", sanitized)
    if len(sanitized) > max_len:
        sanitized = sanitized[:max_len] + "...(truncated)"
    return sanitized


def _check_xml_limits(xml_text: str) -> str | None:
    """Pre-flight check for element depth and count using streaming parse.

    Uses iterparse to process elements one at a time without building the
    full tree in memory, avoiding C-stack overflow on deeply nested files.
    Returns an error message string, or None if within limits.
    """
    depth = 0
    count = 0
    for event, _ in ET.iterparse(
        io.BytesIO(xml_text.encode("utf-8")), events=("start", "end")
    ):
        if event == "start":
            depth += 1
            count += 1
            if depth > MAX_XML_DEPTH:
                return f"XML nesting depth exceeds {MAX_XML_DEPTH} levels"
            if count > MAX_XML_ELEMENTS:
                return f"XML element count exceeds {MAX_XML_ELEMENTS:,}"
        else:
            depth -= 1
    return None


def validate(file_path):
    errors = []
    warnings = []

    # 1. Read file — resolve to canonical absolute path to prevent path
    # traversal (e.g., "../../etc/passwd.drawio") from hook input (CWE-22).
    # Uses os.path.realpath() as the semgrep-recognized taint sanitizer.
    path = Path(os.path.realpath(file_path))
    try:
        file_size = path.stat().st_size
    except OSError as e:
        errors.append(f"Cannot stat file: {e}")
        return errors, warnings

    if file_size > MAX_FILE_SIZE:
        errors.append(
            f"File too large ({file_size // 1024}KB > "
            f"{MAX_FILE_SIZE // 1024 // 1024}MB limit)"
        )
        return errors, warnings

    try:
        xml_text = path.read_text(encoding="utf-8")
    except Exception as e:
        errors.append(f"Cannot read file: {e}")
        return errors, warnings

    if not xml_text.strip():
        errors.append("File is empty")
        return errors, warnings

    # Pre-flight: check depth and element count before full parse
    limit_error = _check_xml_limits(xml_text)
    if limit_error:
        errors.append(limit_error)
        return errors, warnings

    # Parse XML
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as e:
        errors.append(f"XML parse error: {e}")
        return errors, warnings

    # 2. Validate structure - require <mxfile> wrapper per SKILL.md contract
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
        errors.append(
            "Missing <mxfile> wrapper. Output must use "
            "<mxfile><diagram><mxGraphModel> structure."
        )
        return errors, warnings
    else:
        errors.append(
            "Missing root element. draw.io files must start with <mxfile>."
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
                warnings.append(f'Vertex cell id="{_sanitize_attr(cell_id)}" is missing <mxGeometry>.')

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
                    f'Edge id="{_sanitize_attr(cell.get("id"))}" references '
                    f'non-existent source="{_sanitize_attr(source)}".'
                )
            if target and target not in cell_ids:
                errors.append(
                    f'Edge id="{_sanitize_attr(cell.get("id"))}" references '
                    f'non-existent target="{_sanitize_attr(target)}".'
                )

    # Report invalid AWS shapes
    if invalid_shapes:
        unique_invalid = list(dict.fromkeys(invalid_shapes))
        errors.append(
            f"Invalid AWS4 shape references: {', '.join(unique_invalid)}. "
            "Check the aws4-shapes.json registry for valid shape names."
        )

    # --- AWS Diagram Guideline Compliance Checks ---

    # 1. Background color check — no hardcoded background allowed (breaks dark mode)
    graph_models = [root] if tag == "mxGraphModel" else root.findall(".//mxGraphModel")
    for model in graph_models:
        bg = model.get("background")
        if bg is not None:
            errors.append(
                f'mxGraphModel has background="{_sanitize_attr(bg)}". '
                "Do not set a background attribute — it breaks dark mode adaptive contrast."
            )
            break

    # 2. Font size check — minimum 10px per style guide (service labels use 10px)
    has_small_font = False
    for cell in cells:
        style = cell.get("style", "")
        if cell.get("vertex") == "1":
            fs_match = re.search(r"fontSize=(\d+)", style)
            if fs_match and int(fs_match.group(1)) < 10:
                has_small_font = True
                break
    if has_small_font:
        warnings.append(
            "Some shapes use fontSize below 10px. "
            "Minimum per style guide: 10px for service labels."
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

    # Top-level try/except prevents unhandled exception tracebacks from
    # leaking file paths and source code lines into the hook systemMessage
    # (stderr is captured via 2>&1 in validate-drawio.sh).
    try:
        errors, warnings = validate(file_path)
    except Exception:
        print("VALIDATION FAILED: internal error during validation. Run manually for details.")
        sys.exit(1)

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
