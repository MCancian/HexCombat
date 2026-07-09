#!/usr/bin/env python3
"""Reconcile taiwan_hex_grid.json against the real GSHHG coastline.

Keeps existing hexes with land_frac >= 0.05 (unchanged), drops existing hexes
below that threshold, and adds any missing lattice hexes that clear the same
threshold AND are odd-r-contiguous with the kept grid (flood-fill from the
kept hexes; rejects off-theater land such as the mainland/Matsu coast). Also
writes data/terrain/hex_land_frac.json (land fraction per hex in the
reconciled grid) and a plain-text report of drops/adds/rejections.

Usage:
  tools/terrain/.venv/bin/python3 tools/terrain/reconcile_grid.py [--dry-run]
"""

import argparse
import json
import sys
from pathlib import Path

import shapefile
from shapely.geometry import Polygon, shape
from shapely.ops import unary_union
from shapely.prepared import prep


# ---------------------------------------------------------------------------
# Lattice geometry (exact affine odd-r grid, verified zero residuals)
# ---------------------------------------------------------------------------

_COL_STEP = 0.098309708
_ROW_LAT_STEP = 0.078020306
_LON0 = 119.8093466

_VERTEX_OFFSETS = [
    (-0.026006769, 0.049154854),
    (0.026006769, 0.049154854),
    (0.052013538, 0.0),
    (0.026006769, -0.049154854),
    (-0.026006769, -0.049154854),
    (-0.052013538, 0.0),
]

_ROW_RANGE = range(60)
_COL_RANGE = range(30)

_LAND_FRAC_THRESHOLD = 0.05


def lattice_center(row: int, col: int, lat0: float) -> tuple[float, float]:
    lon = _LON0 + col * _COL_STEP + (row % 2) * _COL_STEP * 0.5
    lat = lat0 + row * _ROW_LAT_STEP
    return lat, lon


def lattice_vertices(center_lat: float, center_lon: float) -> list[dict]:
    ring = [
        {"lat": center_lat + dlat, "lon": center_lon + dlon}
        for dlat, dlon in _VERTEX_OFFSETS
    ]
    ring.append(dict(ring[0]))
    return ring


def build_hex_entry(row: int, col: int, lat0: float) -> dict:
    center_lat, center_lon = lattice_center(row, col, lat0)
    return {
        "id": f"hex_{row}_{col}",
        "center": {"lat": center_lat, "lon": center_lon},
        "vertices": lattice_vertices(center_lat, center_lon),
        "row": row,
        "col": col,
    }


def hex_to_polygon(h: dict) -> Polygon:
    return Polygon([(v["lon"], v["lat"]) for v in h["vertices"]])


# ---------------------------------------------------------------------------
# Land source
# ---------------------------------------------------------------------------

def load_land_union(shp_path: Path):
    sf = shapefile.Reader(str(shp_path))
    polys = []
    for sr in sf.iterShapeRecords():
        s = sr.shape
        bx_min, by_min, bx_max, by_max = s.bbox
        if bx_max < 119 or bx_min > 123 or by_max < 21 or by_min > 26:
            continue
        polys.append(shape(s.__geo_interface__))
    if not polys:
        raise RuntimeError(f"No land shapes found intersecting AOI in {shp_path}")
    return unary_union(polys)


def land_frac(poly: Polygon, land_union, land_prepared) -> float:
    if not land_prepared.intersects(poly):
        return 0.0
    inter = poly.intersection(land_union)
    area = poly.area
    if area == 0:
        return 0.0
    return inter.area / area


# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

def check_formula_matches_stored(hexes: list[dict], lat0: float) -> None:
    for h in hexes:
        exp_lat, exp_lon = lattice_center(h["row"], h["col"], lat0)
        got_lat = h["center"]["lat"]
        got_lon = h["center"]["lon"]
        if abs(exp_lat - got_lat) > 1e-6 or abs(exp_lon - got_lon) > 1e-6:
            raise AssertionError(
                f"Lattice formula mismatch for {h['id']}: "
                f"expected ({exp_lat}, {exp_lon}), stored ({got_lat}, {got_lon})"
            )


def check_magnitudes(dropped: list, added: list) -> None:
    if not (40 <= len(dropped) <= 60):
        raise AssertionError(
            f"Dropped count {len(dropped)} outside expected range [40, 60] "
            f"(prior analysis expected ~51)"
        )
    if not (55 <= len(added) <= 80):
        raise AssertionError(
            f"Added count {len(added)} outside expected range [55, 80] "
            f"(prior analysis expected ~62 after the contiguity filter)"
        )


# ---------------------------------------------------------------------------
# Contiguity (odd-r pointy-top adjacency; matches HexMath.gd /
# tools/gen_main_island_hexes.py)
# ---------------------------------------------------------------------------

_NEIGHBOR_OFFSETS_EVEN = [(-1, -1), (-1, 0), (0, -1), (0, 1), (1, -1), (1, 0)]
_NEIGHBOR_OFFSETS_ODD = [(-1, 0), (-1, 1), (0, -1), (0, 1), (1, 0), (1, 1)]


def oddr_neighbors(row: int, col: int) -> list[tuple[int, int]]:
    offsets = _NEIGHBOR_OFFSETS_ODD if row % 2 else _NEIGHBOR_OFFSETS_EVEN
    return [(row + dr, col + dc) for dr, dc in offsets]


def filter_contiguous(kept: list, candidates: list) -> tuple[list, list]:
    """Flood-fill odd-r adjacency over (kept existing coords | candidate
    coords), seeded from the kept existing hexes; a candidate is accepted only
    if reachable. Keeps off-theater land (e.g. mainland/Matsu coast) out.
    Returns (accepted, rejected), preserving candidate order."""
    kept_coords = {(h["row"], h["col"]) for h, _ in kept}
    candidate_coords = {(h["row"], h["col"]) for h, _ in candidates}
    domain = kept_coords | candidate_coords

    reachable = set(kept_coords)
    frontier = list(kept_coords)
    while frontier:
        row, col = frontier.pop()
        for nb in oddr_neighbors(row, col):
            if nb in domain and nb not in reachable:
                reachable.add(nb)
                frontier.append(nb)

    accepted = [p for p in candidates if (p[0]["row"], p[0]["col"]) in reachable]
    rejected = [p for p in candidates if (p[0]["row"], p[0]["col"]) not in reachable]
    return accepted, rejected


# ---------------------------------------------------------------------------
# Reconciliation
# ---------------------------------------------------------------------------

def reconcile(grid: dict, land_union, land_prepared) -> tuple[list, list, list, list]:
    """Returns (kept, dropped, added, rejected); all are (hex_entry, frac)
    pair lists. rejected = threshold-passing candidates cut by the contiguity
    filter (off-theater)."""
    hexes = grid["hexes"]
    lat0 = hexes[0]["center"]["lat"] - hexes[0]["row"] * _ROW_LAT_STEP
    check_formula_matches_stored(hexes, lat0)

    existing_ids = {h["id"] for h in hexes}

    kept = []
    dropped = []
    for h in hexes:
        frac = land_frac(hex_to_polygon(h), land_union, land_prepared)
        if frac >= _LAND_FRAC_THRESHOLD:
            kept.append((h, frac))
        else:
            dropped.append((h, frac))

    candidates = []
    for row in _ROW_RANGE:
        for col in _COL_RANGE:
            hid = f"hex_{row}_{col}"
            if hid in existing_ids:
                continue
            candidate = build_hex_entry(row, col, lat0)
            frac = land_frac(hex_to_polygon(candidate), land_union, land_prepared)
            if frac >= _LAND_FRAC_THRESHOLD:
                candidates.append((candidate, frac))

    added, rejected = filter_contiguous(kept, candidates)
    added.sort(key=lambda pair: (pair[0]["row"], pair[0]["col"]))
    rejected.sort(key=lambda pair: (pair[0]["row"], pair[0]["col"]))

    check_magnitudes(dropped, added)

    return kept, dropped, added, rejected


# ---------------------------------------------------------------------------
# Output writers
# ---------------------------------------------------------------------------

def detect_json_style(text: str) -> tuple[int, tuple[str, str]]:
    """Infer indent width from the source file; separators stay json defaults
    with indent (', ' / ': ') which is what the existing file uses."""
    for line in text.splitlines():
        stripped = line.lstrip(" ")
        if stripped and stripped != line:
            return len(line) - len(stripped), (",", ": ")
    return 2, (",", ": ")


def write_grid(grid_path: Path, description: str, side_to_side_km, kept, added, indent: int) -> None:
    new_hexes = [h for h, _ in kept] + [h for h, _ in added]
    out = {
        "description": description,
        "side_to_side_km": side_to_side_km,
        "hexes": new_hexes,
    }
    grid_path.write_text(json.dumps(out, indent=indent))


_LAND_FRAC_DESCRIPTION = (
    "Fraction of each hex's area over GSHHG land (generated by "
    "tools/terrain/reconcile_grid.py; inclusion rule: keep/add hexes with "
    "land_frac >= 0.05 - user decision 2026-07-09)"
)


def write_land_frac(out_path: Path, kept, added) -> None:
    ordered = {}
    for h, frac in kept:
        ordered[h["id"]] = round(frac, 4)
    for h, frac in added:
        ordered[h["id"]] = round(frac, 4)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(
            {"description": _LAND_FRAC_DESCRIPTION, "land_frac": ordered},
            indent=2,
        )
        + "\n"
    )


def write_report(out_path: Path, kept, dropped, added, rejected) -> None:
    lines = []
    lines.append("Dropped hexes (land_frac < 0.05):")
    for h, frac in sorted(dropped, key=lambda p: (p[0]["row"], p[0]["col"])):
        lines.append(f"  {h['id']}: land_frac={frac:.4f}")
    lines.append("")
    lines.append("Added hexes (land_frac >= 0.05):")
    for h, frac in added:
        lines.append(f"  {h['id']}: land_frac={frac:.4f}")
    lines.append("")
    lines.append("Rejected non-contiguous candidates (off-theater):")
    for h, frac in rejected:
        lines.append(f"  {h['id']}: land_frac={frac:.4f}")
    lines.append("")
    lines.append("Summary:")
    lines.append(f"  kept:   {len(kept)}")
    lines.append(f"  dropped: {len(dropped)}")
    lines.append(f"  added:   {len(added)}")
    lines.append(f"  rejected_noncontiguous: {len(rejected)}")
    lines.append(f"  total_new: {len(kept) + len(added)}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    script_dir = Path(__file__).resolve().parent
    default_repo = str(script_dir.parent.parent)

    parser = argparse.ArgumentParser(
        description="Reconcile taiwan_hex_grid.json against the real coastline"
    )
    parser.add_argument(
        "--cache-dir",
        default=str(Path.home() / "geodata" / "hexcombat"),
        help="Geodata cache directory (default: ~/geodata/hexcombat)",
    )
    parser.add_argument(
        "--repo-root",
        default=default_repo,
        help="Repository root (default: two dirs up from script)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute and report only; write no grid/land_frac files",
    )
    args = parser.parse_args()

    cache_dir = Path(args.cache_dir)
    repo_root = Path(args.repo_root)
    grid_path = repo_root / "data" / "taiwan_hex_grid.json"
    land_frac_path = repo_root / "data" / "terrain" / "hex_land_frac.json"
    report_path = script_dir / "out" / "reconcile_report.txt"
    shp_path = cache_dir / "coastline" / "GSHHS_shp" / "f" / "GSHHS_f_L1.shp"

    if not grid_path.is_file():
        print(f"ERROR: Hex grid not found: {grid_path}", file=sys.stderr)
        sys.exit(1)
    if not shp_path.is_file():
        print(f"ERROR: Coastline shapefile not found: {shp_path}", file=sys.stderr)
        sys.exit(1)

    raw_text = grid_path.read_text()
    indent, _ = detect_json_style(raw_text)
    grid = json.loads(raw_text)
    print(f"Loaded {len(grid['hexes'])} hexes from {grid_path}")

    print(f"Loading land polygons from {shp_path} ...")
    land_union = load_land_union(shp_path)
    land_prepared = prep(land_union)

    kept, dropped, added, rejected = reconcile(grid, land_union, land_prepared)

    if not args.dry_run:
        write_grid(
            grid_path,
            grid["description"],
            grid["side_to_side_km"],
            kept,
            added,
            indent,
        )
        write_land_frac(land_frac_path, kept, added)
        print(f"Wrote {grid_path}")
        print(f"Wrote {land_frac_path}")
    else:
        print("(dry run: no grid/land_frac files written)")

    write_report(report_path, kept, dropped, added, rejected)
    print(f"Wrote {report_path}")

    print("Summary:")
    print(f"  kept:      {len(kept)}")
    print(f"  dropped:   {len(dropped)}")
    print(f"  added:     {len(added)}")
    print(f"  rejected_noncontiguous: {len(rejected)}")
    print(f"  total_new: {len(kept) + len(added)}")


if __name__ == "__main__":
    main()
