"""Render a sweep's cell files into reports/sweeps/<name>/report.md.

Cells are matched to grid points by their recorded override maps (Python's ==
treats 0 and 0.0 as equal, absorbing the JSON int/float round-trip through
Godot), never by filename — cell ids are human-readable labels only.
"""

import argparse
import glob
import json
import os
import sys

from sweep_metrics import REGISTRY


def knob_leaf(knob):
    return knob.split(":")[-1].split(".")[-1]


def is_floor_cell(cell):
    """The mines-only floor cell: identified by its disable_antiship_systems override, so the
    report needs no runner-side marker (plan 0012)."""
    return any(key.endswith("disable_antiship_systems") and value
               for key, value in cell.get("overrides", {}).items())


def find_cell(cells, knobs, values):
    expected = dict(zip(knobs, values))
    for cell in cells:
        if not is_floor_cell(cell) and cell.get("overrides", {}) == expected:
            return cell
    return None


def fmt_value(v):
    return f"+{v:.2f}" if isinstance(v, float) and v >= 0 else str(v)


# Metric functions return raw numbers (plan 0012); the report owns ALL display formatting.
# A formatter maps the raw value to a display string, or to a {column: string} dict for
# multi-column metrics. Every REGISTRY metric must have one — missing is a wiring error.
FORMATTERS = {
    "crossing_loss_pct": lambda v: f"{v['mean']:.1f}±{v['sd']:.1f}",
    "maneuver_attrition_pct": lambda v: {
        "pool": f"{v['pool']:.0f}",
        "killed(mean+/-sd)": f"{v['killed_mean']:.1f}+/-{v['killed_sd']:.1f}",
        "%pool": f"{v['pct_pool']:.0f}%",
        "warmup_killed(mean)": f"{v['warmup_killed_mean']:.1f}",
        "taiwan_census(mean)": f"{v['taiwan_mean']:.1f}",
    },
    "red_win_rate": lambda v: f"{v:.1f}%",
}


def metric_fn_for(manifest):
    metrics = manifest.get("metrics", [])
    if not metrics:
        print("Manifest lists no metrics", file=sys.stderr)
        sys.exit(1)
    name = metrics[0]
    if name not in REGISTRY or name not in FORMATTERS:
        print(f"Metric {name} missing from REGISTRY/FORMATTERS", file=sys.stderr)
        sys.exit(1)

    def formatted(cell):
        return FORMATTERS[name](REGISTRY[name](cell))

    return name, formatted


def render_1d(lines, manifest, cells, metric_name, metric_fn):
    knobs = manifest["knobs"]
    axis = manifest["grid"][0]
    first = next((c for c in (find_cell(cells, knobs, (v,)) for v in axis) if c), None)
    if first is None:
        print("No cells match the manifest grid", file=sys.stderr)
        sys.exit(1)
    first_val = metric_fn(first)

    if isinstance(first_val, dict):
        header = [knob_leaf(knobs[0])] + list(first_val.keys())
    else:
        header = [knob_leaf(knobs[0]), metric_name]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "|".join(["---"] * len(header)) + "|")

    for v in axis:
        cell = find_cell(cells, knobs, (v,))
        if cell is None:
            lines.append("| " + " | ".join([fmt_value(v)] + ["N/A"] * (len(header) - 1)) + " |")
            continue
        val = metric_fn(cell)
        if isinstance(val, dict):
            row = [fmt_value(v)] + [str(val[k]) for k in first_val.keys()]
        else:
            row = [fmt_value(v), str(val)]
        lines.append("| " + " | ".join(row) + " |")


def render_2d(lines, manifest, cells, metric_fn):
    knobs = manifest["knobs"]
    y_vals, x_vals = manifest["grid"]

    header = [f"{knob_leaf(knobs[0])}\\{knob_leaf(knobs[1])}"] + [fmt_value(x) for x in x_vals]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "|".join(["---"] * len(header)) + "|")

    for y in y_vals:
        row = [str(y)]
        for x in x_vals:
            cell = find_cell(cells, knobs, (y, x))
            row.append(str(metric_fn(cell)) if cell else "N/A")
        lines.append("| " + " | ".join(row) + " |")


def render_markdown(manifest, cells, out_path):
    metric_name, metric_fn = metric_fn_for(manifest)
    grid = manifest.get("grid", [])

    lines = [
        f"# Sweep: {manifest.get('sweep_name', 'sweep')}",
        f"**Created:** {manifest.get('created_utc', '')}",
        f"**Commit:** `{manifest.get('commit', '')}`",
        f"**Scenario:** {manifest.get('base_scenario', '')}",
        f"**Command:** `{manifest.get('rerun_command', '')}`",
        "",
        f"## {metric_name}",
    ]

    if len(grid) == 1:
        render_1d(lines, manifest, cells, metric_name, metric_fn)
    elif len(grid) == 2:
        render_2d(lines, manifest, cells, metric_fn)
    else:
        print(f"Unsupported grid dimensionality: {len(grid)}", file=sys.stderr)
        sys.exit(1)

    floor_cell = next((c for c in cells if is_floor_cell(c)), None)
    if floor_cell:
        lines.append("")
        lines.append(f"**Mines-only floor** (all launchers destroyed): {metric_fn(floor_cell)}")

    lines.append("")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sweep", required=True, help="Sweep directory name or path")
    parser.add_argument("--out", help="Output markdown path")
    args = parser.parse_args()

    sweep_dir = args.sweep
    if not os.path.exists(sweep_dir):
        sweep_dir = os.path.join("reports", "sweeps", args.sweep)

    if not os.path.exists(sweep_dir):
        print(f"Sweep directory not found: {sweep_dir}", file=sys.stderr)
        sys.exit(1)

    manifest_path = os.path.join(sweep_dir, "sweep.json")
    if not os.path.exists(manifest_path):
        print(f"Manifest not found: {manifest_path}", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path, "r") as f:
        manifest = json.load(f)

    cells = []
    for cell_file in glob.glob(os.path.join(sweep_dir, "cells", "*.json")):
        with open(cell_file, "r") as f:
            cells.append(json.load(f))

    out_path = args.out or os.path.join(sweep_dir, "report.md")
    render_markdown(manifest, cells, out_path)
    print(f"REPORT OK: {len(cells)} cells -> {out_path}")


if __name__ == "__main__":
    main()
