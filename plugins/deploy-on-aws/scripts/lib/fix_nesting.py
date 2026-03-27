#!/usr/bin/env python3
"""Fix container nesting issues in draw.io AWS architecture diagrams.

Region groups should use container=0 (decoration-only). If they use
container=1, services nested inside them cause edge routing failures
because draw.io's orthogonal auto-router can't resolve paths across
multiple container boundaries.

This script:
1. Finds Region cells with container=1 in their style
2. Changes them to container=0
3. Re-parents all children from the region to the region's parent
4. Converts children's relative coordinates to absolute by adding
   the region's offset

"""

import argparse
import defusedxml.ElementTree as ET


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


def set_style_value(style_str: str, key: str, value: str) -> str:
    parts = []
    found = False
    for part in style_str.split(";"):
        part = part.strip()
        if not part:
            continue
        if "=" in part:
            k, v = part.split("=", 1)
            if k == key:
                parts.append(f"{key}={value}")
                found = True
            else:
                parts.append(part)
        else:
            parts.append(part)
    if not found:
        parts.append(f"{key}={value}")
    return ";".join(parts) + ";"


def get_geometry(cell: ET.Element) -> tuple[float, float, float, float] | None:
    for geom in cell:
        if geom.tag == "mxGeometry" and geom.get("as") == "geometry":
            x = float(geom.get("x", "0"))
            y = float(geom.get("y", "0"))
            w = float(geom.get("width", "0"))
            h = float(geom.get("height", "0"))
            return (x, y, w, h)
    return None


def offset_geometry(cell: ET.Element, dx: float, dy: float) -> None:
    for geom in cell:
        if geom.tag == "mxGeometry" and geom.get("as") == "geometry":
            if geom.get("relative") == "1":
                return  # skip relative geometries (edge labels)
            old_x = float(geom.get("x", "0"))
            old_y = float(geom.get("y", "0"))
            geom.set("x", str(round(old_x + dx, 1)))
            geom.set("y", str(round(old_y + dy, 1)))
            return


def is_region_container(cell: ET.Element) -> bool:
    style = cell.get("style", "")
    style_dict = get_style_dict(style)
    return (
        "group_region" in style
        and style_dict.get("container") == "1"
    )


def fix_nesting(tree: ET.ElementTree, verbose: bool = False) -> int:
    root_elem = tree.getroot()

    cells: dict[str, ET.Element] = {}
    for cell in root_elem.iter("mxCell"):
        cid = cell.get("id")
        if cid:
            cells[cid] = cell

    fixed = 0

    for cid, cell in list(cells.items()):
        if not is_region_container(cell):
            continue

        region_parent = cell.get("parent", "1")
        region_geom = get_geometry(cell)
        if region_geom is None:
            continue

        rx, ry, rw, rh = region_geom

        if verbose:
            print(f"  Region {cid}: container=1 at ({rx},{ry}), parent={region_parent}")

        # Change region to container=0
        old_style = cell.get("style", "")
        new_style = set_style_value(old_style, "container", "0")
        cell.set("style", new_style)

        # Find all children of this region
        children_moved = 0
        for child_id, child_cell in cells.items():
            if child_cell.get("parent") != cid:
                continue

            # Re-parent to region's parent
            child_cell.set("parent", region_parent)

            # Convert relative coordinates to absolute
            if child_cell.get("edge") == "1":
                # Edges don't need coordinate conversion
                pass
            else:
                offset_geometry(child_cell, rx, ry)

            children_moved += 1

        if verbose:
            print(f"    Changed to container=0, re-parented {children_moved} children (offset +{rx},+{ry})")

        fixed += 1

    return fixed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fix Region container nesting in draw.io files"
    )
    parser.add_argument("file", help="Path to .drawio file")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    tree = ET.parse(args.file)
    fixed = fix_nesting(tree, args.verbose)

    if fixed > 0:
        print(f"Regions fixed: {fixed}")
        if not args.dry_run:
            ET.indent(tree, space="  ")
            tree.write(args.file, encoding="unicode", xml_declaration=False)
            print(f"Written: {args.file}")
        else:
            print("(dry run, no changes written)")
    else:
        print("No region nesting issues found")


if __name__ == "__main__":
    main()
