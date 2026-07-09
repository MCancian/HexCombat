#!/usr/bin/env python3
"""Plot terrain-classified hex grid with coastline overlay."""

import json
import os
import sys
from pathlib import Path

import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
import shapefile

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
OUT_DIR = SCRIPT_DIR / "out"
OUT_DIR.mkdir(parents=True, exist_ok=True)

CACHE = Path.home() / "geodata" / "hexcombat"

COAST_SHP = CACHE / "coastline" / "GSHHS_shp" / "f" / "GSHHS_f_L1.shp"

TERRAIN_COLORS = {
    "mountain": "#8B7355",
    "hills": "#C4A96A",
    "urban": "#9E9E9E",
    "plains": "#DCE8C0",
}

EXTGE = (119.5, 122.5, 21.5, 25.5)

with open(REPO_ROOT / "data" / "taiwan_hex_grid.json") as f:
    grid = json.load(f)

with open(REPO_ROOT / "data" / "terrain" / "hex_terrain.json") as f:
    terrain = json.load(f)

classes = terrain["classes"]
hexes_by_id = {h["id"]: h for h in grid["hexes"]}

fig, ax = plt.subplots(figsize=(12, 14))

for hex_id, h in hexes_by_id.items():
    tc = classes.get(hex_id, "plains")
    color = TERRAIN_COLORS.get(tc, "#DCE8C0")
    verts = [(v["lon"], v["lat"]) for v in h["vertices"]]
    ax.add_patch(mpatches.Polygon(verts, closed=True, facecolor=color,
                                  edgecolor="gray", linewidth=0.3))

# Coastline
if COAST_SHP.exists():
    sf = shapefile.Reader(str(COAST_SHP))
    for sr in sf.shapeRecords():
        sh = sr.shape
        if sh.bbox:
            xmin, ymin, xmax, ymax = sh.bbox
            if not (xmax < EXTGE[0] or xmin > EXTGE[1]
                    or ymax < EXTGE[2] or ymin > EXTGE[3]):
                pts = list(sh.points)
                parts = list(sh.parts)
                for i, start in enumerate(parts):
                    end = parts[i + 1] if i + 1 < len(parts) else len(pts)
                    seg = pts[start:end]
                    xs, ys = zip(*seg)
                    ax.plot(xs, ys, color="blue", linewidth=0.7)
    sf.close()
else:
    print(f"Warning: coastline shapefile not found at {COAST_SHP}", file=sys.stderr)

ax.set_xlim(EXTGE[0], EXTGE[1])
ax.set_ylim(EXTGE[2], EXTGE[3])
ax.set_aspect("equal")

legend_handles = [
    mpatches.Patch(color=c, label=k.capitalize())
    for k, c in TERRAIN_COLORS.items()
]
ax.legend(handles=legend_handles, loc="lower right")
ax.set_title("HexCombat terrain classification")
ax.set_xlabel("Longitude")
ax.set_ylabel("Latitude")

plt.tight_layout()
plt.savefig(OUT_DIR / "terrain_preview.png", dpi=200)
print(f"Saved {OUT_DIR / 'terrain_preview.png'}")