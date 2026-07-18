import argparse
import json
import os
import glob
import sys
from sweep_metrics import REGISTRY

def render_markdown(manifest, cells, out_path):
    sweep_name = manifest.get("sweep_name", "sweep")
    created = manifest.get("created_utc", "")
    commit = manifest.get("commit", "")
    grid = manifest.get("grid", [])
    metrics = manifest.get("metrics", [])
    
    lines = []
    lines.append(f"# Sweep: {sweep_name}")
    lines.append(f"**Created:** {created}")
    lines.append(f"**Commit:** `{commit}`")
    lines.append(f"**Command:** `{manifest.get('rerun_command', '')}`")
    lines.append("")
    
    if len(grid) == 1:
        # 1D sweep
        knob = manifest["knobs"][0].split(":")[-1]
        lines.append(f"## {metrics[0]}")
        
        # Build header from the first cell's keys if it's a dict metric, or just 'value'
        metric_fn = REGISTRY.get(metrics[0])
        if not metric_fn:
            print(f"Unknown metric {metrics[0]}", file=sys.stderr)
            sys.exit(1)
            
        first_val = metric_fn(cells[0])
        
        if isinstance(first_val, dict):
            header = ["bonus"] + list(first_val.keys())
            lines.append("| " + " | ".join(header) + " |")
            lines.append("|" + "|".join(["---"] * len(header)) + "|")
            for bonus in grid[0]:
                slug = f"bonus_{bonus:.2f}"
                cell_data = next((c for c in cells if slug in c["_filename"]), None)
                if not cell_data:
                    continue
                val = metric_fn(cell_data)
                row = [f"+{bonus:.2f}" if bonus >= 0 else f"{bonus:.2f}"] + [str(val[k]) for k in first_val.keys()]
                lines.append("| " + " | ".join(row) + " |")
        else:
            lines.append(f"| {knob} | {metrics[0]} |")
            lines.append("|---|---|")
            for val in grid[0]:
                slug = f"{knob}_{val}" # Or matching how it was saved
                # TODO: refine matching
    
    elif len(grid) == 2:
        # 2D sweep (antiship_crossing)
        lines.append(f"## {metrics[0]}")
        
        metric_fn = REGISTRY.get(metrics[0])
        
        y_knob = manifest["knobs"][0].split(".")[-1]
        x_knob = manifest["knobs"][1].split(":")[-1]
        
        y_vals = grid[0]
        x_vals = grid[1]
        
        header = [f"{y_knob}\\{x_knob}"] + [f"+{x:.2f}" if isinstance(x, float) and x>=0 else str(x) for x in x_vals]
        lines.append("| " + " | ".join(header) + " |")
        lines.append("|" + "|".join(["---"] * len(header)) + "|")
        
        for y in y_vals:
            row = [str(y)]
            for x in x_vals:
                slug = f"ic_{y}__bonus_{x:.2f}"
                cell_data = next((c for c in cells if slug in c["_filename"]), None)
                if cell_data:
                    val = metric_fn(cell_data)
                    row.append(str(val))
                else:
                    row.append("N/A")
            lines.append("| " + " | ".join(row) + " |")
    
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
        
    cells_dir = os.path.join(sweep_dir, "cells")
    cells = []
    for cell_file in glob.glob(os.path.join(cells_dir, "*.json")):
        with open(cell_file, "r") as f:
            data = json.load(f)
            data["_filename"] = os.path.basename(cell_file)
            cells.append(data)
            
    out_path = args.out or os.path.join(sweep_dir, "report.md")
    render_markdown(manifest, cells, out_path)
    print(f"REPORT OK: {len(cells)} cells -> {out_path}")

if __name__ == "__main__":
    main()
