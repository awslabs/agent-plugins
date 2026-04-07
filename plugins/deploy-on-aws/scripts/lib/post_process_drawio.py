#!/usr/bin/env python3
"""Unified post-processing pipeline for draw.io AWS architecture diagrams.

Chains all fixers in sequence:
1. fix_nesting — flatten Region container=1 to container=0 (fixes edge routing)
2. fix_step_badges — nudge overlapping step badges
3. fix_placement — move external actors below title block
4. fix_legend_size — resize legend panel to match diagram height

Reads JSON from stdin (PostToolUse hook format) or accepts file path as argument.
"""

import argparse
import importlib.util
import json
import os
import sys
import defusedxml.ElementTree as ET
from pathlib import Path

MAX_FILE_SIZE = 2 * 1024 * 1024  # 2 MB

# Import sibling modules by explicit file path (avoids sys.path manipulation
# that could allow module shadowing — see CWE-426)
SCRIPT_DIR = Path(__file__).parent


def _import_from(module_name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(module_name, SCRIPT_DIR / file_name)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_fix_icon_colors = _import_from("fix_icon_colors", "fix_icon_colors.py")
_fix_nesting = _import_from("fix_nesting", "fix_nesting.py")
_fix_step_badges = _import_from("fix_step_badges", "fix_step_badges.py")

fix_icon_colors = _fix_icon_colors.fix_icon_colors
fix_nesting = _fix_nesting.fix_nesting
fix_badges = _fix_step_badges.fix_badges


def get_style_dict(style_str: str) -> dict[str, str]:
    result: dict[str, str] = {}
    if not style_str:
        return result
    for part in style_str.split(";"):
        part = part.strip()
        if "=" in part:
            k, v = part.split("=", 1)
            result[k] = v
        elif part:
            result[part] = ""
    return result


def get_geometry(cell: ET.Element) -> dict[str, float] | None:
    for geom in cell:
        if geom.tag == "mxGeometry" and geom.get("as") == "geometry":
            if geom.get("relative") == "1":
                return None
            return {
                "x": float(geom.get("x", "0")),
                "y": float(geom.get("y", "0")),
                "w": float(geom.get("width", "0")),
                "h": float(geom.get("height", "0")),
            }
    return None


def set_geometry(cell: ET.Element, **kwargs: float) -> None:
    for geom in cell:
        if geom.tag == "mxGeometry" and geom.get("as") == "geometry":
            for k, v in kwargs.items():
                attr = {"x": "x", "y": "y", "w": "width", "h": "height"}[k]
                geom.set(attr, str(round(v, 1)))
            return


def fix_placement(tree: ET.ElementTree, verbose: bool = False) -> int:
    """Move external actors outside the AWS Cloud boundary.

    External actors must be:
    1. Below the title block (y >= 140)
    2. Horizontally outside the AWS Cloud group rectangle

    If an external actor is horizontally inside AWS Cloud, move it to
    x = aws_cloud_x - actor_width - 30 (30px gap left of cloud).

    Returns number of cells moved.
    """
    root_elem = tree.getroot()
    moved = 0
    title_bottom = 140

    # Find the AWS Cloud group geometry
    aws_cloud_geom = None
    for cell in root_elem.iter("mxCell"):
        style = cell.get("style", "")
        if "group_aws_cloud" in style:
            g = get_geometry(cell)
            if g:
                aws_cloud_geom = g
            break

    min_y = title_bottom
    if aws_cloud_geom is not None:
        min_y = max(title_bottom, aws_cloud_geom["y"])

    for cell in root_elem.iter("mxCell"):
        cid = cell.get("id", "")
        parent = cell.get("parent", "")
        style = cell.get("style", "")

        # Only check cells at root level (parent="1")
        if parent != "1":
            continue

        # Skip non-vertices
        if cell.get("vertex") != "1":
            continue

        # Skip AWS groups, title elements, legend, badges, text
        skip_patterns = [
            "mxgraph.aws4.group",
            "group;",
            "text;",
            "line;",
            "mxgraph.basic.rect",
            "edgeLabel",
        ]
        if any(p in style for p in skip_patterns):
            continue

        # Skip legend-related
        if "legend" in cid.lower():
            continue

        # Skip step badges
        if "step-" in cid.lower() and "fillColor=#007CBD" in style:
            continue

        # Skip service containers (svc-group-*) — these are AWS services, not external actors
        # After fix_nesting re-parents region children, services may end up at parent="1"
        if cid.lower().startswith("svc-"):
            continue

        # Skip cells with AWS service category stroke colors (service containers)
        svc_stroke_colors = ["#ED7100", "#C925D1", "#8C4FFF", "#3F8624", "#E7157B",
                             "#DD344C", "#01A88D", "#1A9C37", "#DE227B"]
        style_upper = style.upper()
        if any(f"STROKECOLOR={c.upper()}" in style_upper.replace(" ", "") for c in svc_stroke_colors):
            continue

        # Skip cells with resIcon for AWS services (not external actors)
        if "resIcon=mxgraph.aws4." in style:
            # Only external actor icons should be eligible
            external_icons = ["users", "mobile_client", "iot_sensor", "iot_thing",
                              "internet", "traditional_server", "generic_database", "client"]
            has_external_icon = any(f"resIcon=mxgraph.aws4.{icon}" in style for icon in external_icons)
            if not has_external_icon:
                continue

        # Check if this looks like an external actor container
        is_external = False
        value = (cell.get("value") or "").lower()
        if any(kw in value for kw in ["user", "client", "mobile", "on-prem", "sensor", "iot device"]):
            is_external = True
        if any(kw in cid.lower() for kw in ["user", "client", "mobile", "sensor", "external", "onprem"]):
            is_external = True
        if "resIcon=mxgraph.aws4.users" in style or "resIcon=mxgraph.aws4.mobile_client" in style:
            is_external = True
        if "resIcon=mxgraph.aws4.iot_sensor" in style or "resIcon=mxgraph.aws4.iot_thing" in style:
            is_external = True
        if "fillColor=#f5f5f5" in style.lower() or "fillColor=light-dark(#F5F5F5" in style:
            is_external = True

        if not is_external:
            continue

        g = get_geometry(cell)
        if g is None:
            continue

        changed = False

        # Fix 1: Move below title block
        if g["y"] < min_y:
            old_y = g["y"]
            set_geometry(cell, y=min_y)
            g["y"] = min_y
            changed = True
            if verbose:
                print(f"  Moved {cid} down: y={old_y:.0f} -> y={min_y:.0f}")

        # Fix 2: Move horizontally outside AWS Cloud if overlapping
        if aws_cloud_geom is not None:
            cloud_x = aws_cloud_geom["x"]
            cloud_x2 = cloud_x + aws_cloud_geom["w"]
            actor_x = g["x"]
            actor_x2 = actor_x + g["w"]

            # Check if actor overlaps AWS Cloud horizontally
            if actor_x >= cloud_x and actor_x < cloud_x2:
                # Actor starts inside cloud — move to left of cloud
                new_x = cloud_x - g["w"] - 30
                if new_x < 20:
                    new_x = 20  # minimum left margin
                set_geometry(cell, x=new_x)
                changed = True
                if verbose:
                    print(f"  Moved {cid} left: x={actor_x:.0f} -> x={new_x:.0f} (outside AWS Cloud)")

        if changed:
            moved += 1

    return moved


def fix_legend_size(tree: ET.ElementTree, verbose: bool = False) -> int:
    """Resize legend panel to match the diagram's main content height.

    Finds the legend-outer group and the AWS Cloud / Region group,
    then sets legend height to span from the legend's y to the diagram bottom.

    Returns 1 if resized, 0 if no change needed.
    """
    root_elem = tree.getroot()

    # Find legend-outer or legend-bg
    legend_outer = None
    legend_bg = None
    for cell in root_elem.iter("mxCell"):
        cid = cell.get("id", "")
        if cid == "legend-outer":
            legend_outer = cell
        elif cid == "legend-bg":
            legend_bg = cell

    if legend_outer is None:
        return 0

    legend_geom = get_geometry(legend_outer)
    if legend_geom is None:
        return 0

    # Find the diagram's main content bottom (AWS Cloud or Region group)
    diagram_bottom = 0
    for cell in root_elem.iter("mxCell"):
        parent = cell.get("parent", "")

        # Look at root-level elements (parent="1") that are large groups
        if parent == "1" and cell.get("vertex") == "1":
            g = get_geometry(cell)
            if g and g["h"] > 200:  # large elements only
                bottom = g["y"] + g["h"]
                if bottom > diagram_bottom:
                    diagram_bottom = bottom

    if diagram_bottom <= 0:
        return 0

    # Target: legend spans from its y to diagram_bottom + some padding
    target_height = diagram_bottom - legend_geom["y"] + 20  # 20px padding
    current_height = legend_geom["h"]

    # Only resize if significantly different (>50px)
    if abs(target_height - current_height) < 50:
        return 0

    if verbose:
        print(f"  Legend resize: {current_height:.0f} -> {target_height:.0f}")

    set_geometry(legend_outer, h=target_height)

    # Also resize legend-bg to match
    if legend_bg is not None:
        set_geometry(legend_bg, h=target_height)

    return 1


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Unified post-processing for draw.io diagrams"
    )
    parser.add_argument("file", nargs="?", help="Path to .drawio file (or reads JSON from stdin)")
    parser.add_argument("--verbose", "-v", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    # Determine file path: from argument or stdin JSON (PostToolUse hook)
    file_path = args.file
    if file_path is None:
        try:
            data = json.load(sys.stdin)
            file_path = data.get("tool_input", {}).get("file_path", "")
        except (json.JSONDecodeError, KeyError):
            pass  # Expected when not invoked as PostToolUse hook (CLI mode)

    if not file_path or not file_path.endswith((".drawio", ".drawio.xml")):
        # Not a drawio file, exit silently (hook compatibility)
        sys.exit(0)

    # Reject symlinks BEFORE realpath() — realpath follows symlinks, so
    # is_symlink() would always be False on the resolved path.
    if os.path.islink(file_path):
        print(f"Refusing to process symlink: {file_path}", file=sys.stderr)
        sys.exit(1)

    # Resolve path to canonical absolute form to prevent path traversal
    # (e.g., "../../etc/passwd.drawio") from hook input — see CWE-22.
    # All file operations below use only the resolved `path` object.
    # Uses os.path.realpath() as the semgrep-recognized taint sanitizer.
    path = Path(os.path.realpath(file_path))

    # Re-validate extension after resolution (traversal could change it)
    if not path.suffix == ".drawio" and not str(path).endswith(".drawio.xml"):
        sys.exit(0)

    # Reject files exceeding size limit before parsing
    try:
        file_size = path.stat().st_size
    except OSError as e:
        print(f"Cannot stat file: {e}", file=sys.stderr)
        sys.exit(1)
    if file_size > MAX_FILE_SIZE:
        print(
            f"Skipping: file too large ({file_size // 1024}KB > "
            f"{MAX_FILE_SIZE // 1024 // 1024}MB limit)",
            file=sys.stderr,
        )
        sys.exit(0)

    try:
        tree = ET.parse(path)
    except (ET.ParseError, FileNotFoundError) as e:
        print(f"Error parsing file: {e}", file=sys.stderr)
        sys.exit(1)

    # Top-level try/except prevents unhandled exception tracebacks from
    # leaking file paths and source code lines into the hook systemMessage
    # (stderr is captured via 2>&1 in validate-drawio.sh).
    try:
        changes = []

        # 0. Fix Region container nesting (MUST run first — changes coordinates)
        regions_fixed = fix_nesting(tree, verbose=args.verbose)
        if regions_fixed > 0:
            changes.append(f"nesting: {regions_fixed} regions flattened")

        # 1. Fix icon fill colors (before badge/layout fixes)
        icons_fixed = fix_icon_colors(tree, verbose=args.verbose)
        if icons_fixed > 0:
            changes.append(f"icons: {icons_fixed} colors corrected")

        # 2. Fix step badge overlaps (15px clearance for visual breathing room)
        badges_moved = fix_badges(tree, clearance=15.0, verbose=args.verbose)
        if badges_moved > 0:
            changes.append(f"badges: {badges_moved} moved")

        # 3. Fix external actor placement (below title + outside AWS Cloud)
        actors_moved = fix_placement(tree, verbose=args.verbose)
        if actors_moved > 0:
            changes.append(f"placement: {actors_moved} actors repositioned")

        # 4. Fix legend panel sizing (match diagram height)
        legend_resized = fix_legend_size(tree, verbose=args.verbose)
        if legend_resized > 0:
            changes.append("legend: resized to match diagram height")

        if changes:
            summary = "; ".join(changes)
            print(f"Post-processing: {summary}")
            if not args.dry_run:
                # Note: XML indentation skipped — defusedxml doesn't expose indent()
                # and importing stdlib xml.etree.ElementTree triggers security scanners.
                # Output is valid but not pretty-printed. If human-readable XML is needed,
                # add a custom indent helper that walks the element tree without stdlib import.
                tree.write(path, encoding="unicode", xml_declaration=False)
                print(f"Written: {path}")
            else:
                print("(dry run, no changes written)")
        else:
            print("Post-processing: no changes needed")
    except Exception:
        # Generic message only — do not include exception details or tracebacks,
        # as they would leak internal file paths and source lines into the agent
        # context via the hook's systemMessage.
        print("Post-processing: internal error during fixers. Run manually for details.")
        sys.exit(1)


if __name__ == "__main__":
    main()
