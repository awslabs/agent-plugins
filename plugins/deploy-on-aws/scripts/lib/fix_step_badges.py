#!/usr/bin/env python3
"""Post-processing script to fix step badge overlap in draw.io XML files.

Improved algorithm (v2):
1. Parse .drawio XML
2. Identify on-diagram step badges and all obstacles (icons, containers,
   edge labels, text cells, other badges)
3. Resolve absolute coordinates by walking parent chains
4. Multi-pass iterative solver:
   a. For each badge with overlap, try a grid of candidate positions
      at multiple distances (30, 60, 90, 120, 150px) in 16 directions
   b. Score each candidate by minimum clearance to ALL obstacles
      (including already-placed badges)
   c. Pick the candidate with the best (highest) minimum clearance
   d. After moving all badges, re-check — repeat up to 3 passes
5. Update badge mxGeometry (convert back to parent-relative coords)

"""

import argparse
import math
import re
import defusedxml.ElementTree as ET
from dataclasses import dataclass


@dataclass
class Rect:
    x: float
    y: float
    w: float
    h: float

    @property
    def x2(self) -> float:
        return self.x + self.w

    @property
    def y2(self) -> float:
        return self.y + self.h

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2

    def overlaps(self, other: "Rect") -> bool:
        return (
            self.x < other.x2
            and self.x2 > other.x
            and self.y < other.y2
            and self.y2 > other.y
        )

    def min_clearance(self, other: "Rect") -> float:
        """Minimum distance between edges. Negative if overlapping."""
        dx = max(other.x - self.x2, self.x - other.x2, 0)
        dy = max(other.y - self.y2, self.y - other.y2, 0)
        if dx == 0 and dy == 0:
            ox = min(self.x2, other.x2) - max(self.x, other.x)
            oy = min(self.y2, other.y2) - max(self.y, other.y)
            return -min(ox, oy)
        return (dx**2 + dy**2) ** 0.5

    def expanded(self, margin: float) -> "Rect":
        return Rect(
            self.x - margin,
            self.y - margin,
            self.w + 2 * margin,
            self.h + 2 * margin,
        )


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


def get_geometry(cell: ET.Element) -> Rect | None:
    for geom in cell:
        if geom.tag == "mxGeometry" and geom.get("as") == "geometry":
            if geom.get("relative") == "1":
                return None
            x = float(geom.get("x", "0"))
            y = float(geom.get("y", "0"))
            w = float(geom.get("width", "0"))
            h = float(geom.get("height", "0"))
            return Rect(x, y, w, h)
    return None


def resolve_edge_label_position(
    cell: ET.Element,
    cells: dict[str, ET.Element],
    geom_cache: dict[str, Rect],
) -> Rect | None:
    """Resolve an edge label's absolute position by finding the midpoint
    of its parent edge's source and target, then applying offsets.

    Edge labels use relative geometry (position along the edge), which
    can't be resolved by the normal parent-chain walk. Instead we:
    1. Find the parent edge's source and target cells
    2. Resolve source and target center points
    3. Interpolate along the edge based on the label's relative x
    4. Apply the perpendicular y offset
    5. Estimate label text width (~7px per char) for the bounding box
    """
    parent_id = cell.get("parent", "1")
    parent_cell = cells.get(parent_id)
    if parent_cell is None or parent_cell.get("edge") != "1":
        return None

    source_id = parent_cell.get("source")
    target_id = parent_cell.get("target")
    if not source_id or not target_id:
        return None

    source_rect = resolve_absolute(source_id, cells, geom_cache)
    target_rect = resolve_absolute(target_id, cells, geom_cache)
    if source_rect is None or target_rect is None:
        return None

    # Get label's relative position along edge
    rel_x = 0.0  # default: midpoint
    offset_y = 0.0
    for geom in cell:
        if geom.tag == "mxGeometry":
            rel_x = float(geom.get("x", "0"))
            offset_y = float(geom.get("y", "0"))
            break

    # Interpolate: rel_x of 0 = midpoint, -1 = source, +1 = target
    t = 0.5 + rel_x * 0.5  # map [-1,1] -> [0,1]
    cx = source_rect.cx + t * (target_rect.cx - source_rect.cx)
    cy = source_rect.cy + t * (target_rect.cy - source_rect.cy) + offset_y

    # Estimate label dimensions from text content
    value = cell.get("value", "")
    text = re.sub(r"<[^>]+>", "", value).strip()
    est_w = max(len(text) * 7, 40)  # ~7px per char, min 40px
    est_h = 16  # single line height

    label_rect = Rect(cx - est_w / 2, cy - est_h / 2, est_w, est_h)
    return label_rect


def resolve_absolute(
    cell_id: str,
    cells: dict[str, ET.Element],
    geom_cache: dict[str, Rect],
) -> Rect | None:
    if cell_id in geom_cache:
        return geom_cache[cell_id]

    cell = cells.get(cell_id)
    if cell is None:
        return None

    local = get_geometry(cell)
    if local is None:
        # Check if this is an edge label with relative geometry
        style = cell.get("style", "")
        if "edgeLabel" in style:
            label_rect = resolve_edge_label_position(cell, cells, geom_cache)
            if label_rect:
                geom_cache[cell_id] = label_rect
                return label_rect
        return None

    parent_id = cell.get("parent", "1")
    if parent_id in ("0", "1"):
        geom_cache[cell_id] = local
        return local

    parent_abs = resolve_absolute(parent_id, cells, geom_cache)
    if parent_abs is None:
        geom_cache[cell_id] = local
        return local

    abs_rect = Rect(
        parent_abs.x + local.x,
        parent_abs.y + local.y,
        local.w,
        local.h,
    )
    geom_cache[cell_id] = abs_rect
    return abs_rect


def is_on_diagram_badge(cell: ET.Element) -> bool:
    """On-diagram step badge: fillColor=#007CBD, numeric value, not in legend."""
    style = get_style_dict(cell.get("style", ""))
    fill = style.get("fillColor", "").upper()
    value = (cell.get("value") or "").strip()
    cell_id = (cell.get("id") or "").lower()
    parent_id = (cell.get("parent") or "").lower()

    if "legend" in cell_id or "legend" in parent_id:
        return False

    if fill != "#007CBD":
        return False
    # Value may be plain "1" or HTML-wrapped like '<font style="...">1</font>'
    if re.match(r"^\d{1,2}$", value):
        return True
    stripped = re.sub(r"<[^>]+>", "", value).strip()
    return bool(re.match(r"^\d{1,2}$", stripped))


def classify_cell(cell: ET.Element) -> str:
    """Classify a cell as 'badge', 'obstacle', or 'skip'."""
    cell_id = cell.get("id", "")
    if cell_id in ("0", "1"):
        return "skip"

    if is_on_diagram_badge(cell):
        return "badge"

    style_str = cell.get("style", "")
    style = get_style_dict(style_str)

    # Edges (not labels) — skip
    if cell.get("edge") == "1":
        return "skip"

    # Edge labels — skip (handled by model placement, not script).
    # Badges and edge labels both annotate the same arrow, so they're
    # inherently near each other. The model places them on opposite sides
    # of the arrow. Script focuses on preventing badge-icon overlaps.
    if "edgeLabel" in style_str:
        return "skip"

    # Must be a vertex
    if cell.get("vertex") != "1":
        return "skip"

    geom = get_geometry(cell)
    if geom is None or (geom.w == 0 and geom.h == 0):
        return "skip"

    # Large architectural groups — skip (badges sit on these)
    if "mxgraph.aws4.group" in style_str:
        return "skip"

    # Legend panel backgrounds — skip
    if "mxgraph.basic.rect" in style_str:
        return "skip"
    if "legend" in cell_id.lower():
        return "skip"

    # Invisible groups — skip
    if style_str.startswith("group") or style.get("group") == "":
        return "skip"

    # Line elements (title separator) — skip
    if "line" in style_str.split(";") or style.get("line") == "":
        return "skip"

    # Text cells — obstacle (badges shouldn't cover text)
    if style_str.startswith("text;") or style.get("text") == "":
        return "obstacle"

    # Everything else with geometry (icons, containers, etc.) — obstacle
    return "obstacle"


def generate_candidates(
    origin: Rect,
    distances: list[float],
    n_angles: int = 16,
) -> list[tuple[float, float]]:
    """Generate candidate (dx, dy) offsets in a radial grid."""
    candidates: list[tuple[float, float]] = []
    for dist in distances:
        for i in range(n_angles):
            angle = 2 * math.pi * i / n_angles
            dx = round(dist * math.cos(angle) / 10) * 10  # snap to 10px grid
            dy = round(dist * math.sin(angle) / 10) * 10
            if (dx, dy) not in candidates:
                candidates.append((dx, dy))
    return candidates


def compute_min_clearance(
    badge_rect: Rect,
    clearance: float,
    obstacle_rects: list[Rect],
) -> float:
    """Compute the minimum clearance between an expanded badge and all obstacles."""
    expanded = badge_rect.expanded(clearance)
    min_c = float("inf")
    for obs in obstacle_rects:
        c = expanded.min_clearance(obs)
        if c < min_c:
            min_c = c
    return min_c


def fix_badges(
    tree: ET.ElementTree,
    clearance: float = 10.0,
    verbose: bool = False,
) -> int:
    """Fix badge overlaps in-place. Returns number of badges moved."""
    root_elem = tree.getroot()

    cells: dict[str, ET.Element] = {}
    for cell in root_elem.iter("mxCell"):
        cid = cell.get("id")
        if cid:
            cells[cid] = cell

    # Classify all cells
    badge_ids: list[str] = []
    obstacle_ids: list[str] = []

    for cid, cell in cells.items():
        cls = classify_cell(cell)
        if cls == "badge":
            badge_ids.append(cid)
        elif cls == "obstacle":
            obstacle_ids.append(cid)

    if verbose:
        print(f"Found {len(badge_ids)} badges, {len(obstacle_ids)} obstacles")

    # Semantic-aware placement: tight local search only.
    # A badge at the right location with slight overlap is better than
    # a badge at the wrong location with no overlap.
    # Max 50px displacement keeps badges in their semantic zone (near their arrow).
    distances = [10, 20, 30, 40, 50]
    drift_penalty = 0.3  # penalize distance from original position

    total_moved = 0
    max_passes = 2

    for pass_num in range(max_passes):
        # Rebuild absolute positions from scratch each pass
        geom_cache: dict[str, Rect] = {}

        # Resolve obstacle positions
        obstacle_rects: list[Rect] = []
        for oid in obstacle_ids:
            rect = resolve_absolute(oid, cells, geom_cache)
            if rect:
                obstacle_rects.append(rect)

        pass_moved = 0

        for bid in badge_ids:
            badge_abs = resolve_absolute(bid, cells, geom_cache)
            if badge_abs is None:
                continue

            # Build obstacle list = static obstacles + other badges (not self)
            all_obstacles = list(obstacle_rects)
            for other_bid in badge_ids:
                if other_bid == bid:
                    continue
                other_abs = resolve_absolute(other_bid, cells, geom_cache)
                if other_abs:
                    all_obstacles.append(other_abs)

            # Check current clearance (with the tight clearance threshold)
            current_clearance = compute_min_clearance(
                badge_abs, clearance, all_obstacles
            )

            # Only move if actually overlapping (clearance < 0)
            if current_clearance >= 0:
                if verbose and pass_num == 0:
                    print(
                        f"  Badge {bid} (value={cells[bid].get('value')}): "
                        f"OK (clearance={current_clearance:.0f})"
                    )
                continue

            # Generate local candidates (tight radius, stays near original)
            candidates = generate_candidates(badge_abs, distances)

            best_dx, best_dy = 0.0, 0.0
            # Score = clearance - penalty * distance_from_origin
            # This prefers closer positions even if clearance is slightly worse
            current_score = current_clearance  # distance=0 so no penalty
            best_score = current_score

            for dx, dy in candidates:
                candidate = Rect(
                    badge_abs.x + dx,
                    badge_abs.y + dy,
                    badge_abs.w,
                    badge_abs.h,
                )
                c = compute_min_clearance(candidate, clearance, all_obstacles)
                dist = (dx**2 + dy**2) ** 0.5
                score = c - drift_penalty * dist

                if score > best_score:
                    best_score = score
                    best_dx, best_dy = dx, dy

            if best_dx == 0 and best_dy == 0:
                if verbose:
                    print(
                        f"  Badge {bid} (value={cells[bid].get('value')}): "
                        f"no better position within 50px "
                        f"(clearance={current_clearance:.0f})"
                    )
                continue

            # Apply the move
            cell = cells[bid]
            for geom in cell:
                if geom.tag == "mxGeometry" and geom.get("as") == "geometry":
                    old_x = float(geom.get("x", "0"))
                    old_y = float(geom.get("y", "0"))
                    geom.set("x", str(round(old_x + best_dx, 1)))
                    geom.set("y", str(round(old_y + best_dy, 1)))
                    break

            # Invalidate cache
            if bid in geom_cache:
                del geom_cache[bid]

            disp = (best_dx**2 + best_dy**2) ** 0.5
            new_clearance = best_score + drift_penalty * disp
            pass_moved += 1
            if verbose:
                print(
                    f"  Badge {bid} (value={cells[bid].get('value')}): "
                    f"nudged ({best_dx:+.0f}, {best_dy:+.0f}), "
                    f"clearance {current_clearance:.0f} -> {new_clearance:.0f}, "
                    f"displacement {disp:.0f}px"
                )

        total_moved += pass_moved
        if verbose and max_passes > 1:
            print(f"  Pass {pass_num + 1}: nudged {pass_moved} badges")
        if pass_moved == 0:
            break

    return total_moved


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fix step badge overlap in draw.io XML files"
    )
    parser.add_argument("file", help="Path to .drawio file")
    parser.add_argument(
        "--clearance",
        type=float,
        default=10.0,
        help="Minimum clearance in px around badges (default: 10)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Analyze but don't write changes",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print detailed analysis",
    )
    args = parser.parse_args()

    tree = ET.parse(args.file)
    moved = fix_badges(tree, args.clearance, args.verbose)

    print(f"Badges moved: {moved}")

    if not args.dry_run and moved > 0:
        ET.indent(tree, space="  ")
        tree.write(args.file, encoding="unicode", xml_declaration=False)
        print(f"Written: {args.file}")
    elif args.dry_run and moved > 0:
        print("(dry run, no changes written)")


if __name__ == "__main__":
    main()
