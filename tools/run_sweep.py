#!/usr/bin/env python3
"""Run a parameter sweep orchestrating batch jobs."""

import argparse
import itertools
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from datetime import datetime, timezone

REPO_ROOT = Path(__file__).resolve().parent.parent

def parse_args():
    parser = argparse.ArgumentParser(description="Run a sweep over parameter knobs.")
    parser.add_argument("--name")
    parser.add_argument("--spec")
    parser.add_argument("--backend", choices=["batch", "in-process"], default=None)
    parser.add_argument("--knob", action="append", help="<file:dot.path>", default=[])
    parser.add_argument("--values", action="append", help="comma-separated values", default=[])
    parser.add_argument("--scenario", default="scenario_default")
    parser.add_argument("--seeds", default="")
    parser.add_argument("--n", type=int, default=30)
    parser.add_argument("--base-seed", type=int, default=20260624)
    parser.add_argument("--turns", type=int, default=30)
    parser.add_argument("--parallel", type=int, default=4)
    parser.add_argument("--metrics", default="")
    parser.add_argument("--godot", default="")
    parser.add_argument("--run-past-game-over", action="store_true")
    return parser.parse_args()

def parse_value(v):
    v = v.strip()
    try:
        if '.' in v:
            return float(v)
        return int(v)
    except ValueError:
        if v.lower() == "true": return True
        if v.lower() == "false": return False
        return v

def git_output(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(REPO_ROOT), *args],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()

def make_cell_id(knobs, values):
    parts = []
    for k, v in zip(knobs, values):
        knob_name = k.split(":")[-1].split(".")[-1]
        val_str = f"{v:.2f}" if isinstance(v, float) else str(v)
        parts.append(f"{knob_name}_{val_str}")
    cell_id = "__".join(parts)
    return re.sub(r'[^A-Za-z0-9_.-]', '_', cell_id)

def clear_stale_cells(cells_dir: Path) -> None:
    """Cell files from a previous run (possibly a different grid or naming scheme) must not
    survive into this run's report — make_sweep_report globs the whole directory."""
    if not cells_dir.exists():
        return
    stale = list(cells_dir.glob("*.json"))
    for f in stale:
        f.unlink()
    if stale:
        print(f"Cleared {len(stale)} stale cell file(s) from {cells_dir}")

def main():
    args = parse_args()
    
    if not args.name and not args.spec:
        print("ERROR: Must provide --name or --spec.", file=sys.stderr)
        sys.exit(1)
        
    if args.spec:
        if args.backend == "batch":
            print(
                "ERROR: --spec sweeps run in-process only (custom metric extraction lives in "
                "run_sweep_cells.gd until plan 0012 moves it to Python).",
                file=sys.stderr,
            )
            sys.exit(1)
        with open(args.spec, "r") as f:
            spec = json.load(f)
        sweep_name = spec.get("sweep_name", Path(args.spec).stem)
        scenario = spec.get("scenario", "scenario_default")
        sweep_dir = REPO_ROOT / "reports" / "sweeps" / sweep_name
        cells_dir = sweep_dir / "cells"

        # Write sweep manifest
        sweep_manifest = {
            "sweep_name": sweep_name,
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "commit": git_output("rev-parse", "HEAD"),
            "dirty": bool(git_output("status", "--porcelain")),
            "base_scenario": scenario,
            "knobs": spec.get("knobs", []),
            "grid": spec.get("grid", []),
            "seeds": spec.get("seeds", []),
            "runtime_mode": "in_process",
            "rerun_command": " ".join(sys.argv),
            "metrics": spec.get("metrics", [])
        }
        sweep_dir.mkdir(parents=True, exist_ok=True)
        clear_stale_cells(cells_dir)
        with (sweep_dir / "sweep.json").open("w", encoding="utf-8") as f:
            json.dump(sweep_manifest, f, indent=2)

        cells = []
        if "cells" in spec:
            cells = spec["cells"]
        else:
            knobs = spec.get("knobs", [])
            grid = spec.get("grid", [])
            if knobs and grid:
                for pt in itertools.product(*grid):
                    overrides = {k: v for k, v in zip(knobs, pt)}
                    cells.append({"id": make_cell_id(knobs, pt), "overrides": overrides})
            else:
                cells.append({"id": "baseline", "overrides": {}})
        cells.extend(spec.get("extra_cells", []))

        spec["cells"] = cells
        spec["out_dir"] = str(cells_dir)
        temp_spec = sweep_dir / "run_spec.json"
        with temp_spec.open("w") as f:
            json.dump(spec, f)

        cmd = [
            args.godot or shutil.which("godot") or "godot",
            "--headless", "--path", str(REPO_ROOT),
            "-s", "res://tools/run_sweep_cells.gd",
            "--", f"--spec={temp_spec}", f"--scenario={scenario}"
        ]
        print(f"Running in-process sweep: {sweep_name} (scenario={scenario})")
        subprocess.run(cmd, check=True)
        
        print("Delegating report generation to Python...")
        subprocess.run([
            sys.executable,
            str(REPO_ROOT / "tools" / "make_sweep_report.py"),
            "--sweep", sweep_name
        ], check=True)
        return

    if args.knob and args.values:
        if len(args.knob) != len(args.values):
            print("ERROR: --knob and --values must be paired.", file=sys.stderr)
            sys.exit(1)
        axes = []
        for v in args.values:
            axes.append([parse_value(x) for x in v.split(",") if x.strip()])
    else:
        axes = [[]]
        
    backend = args.backend or "batch"
    grid_points = list(itertools.product(*axes)) if args.knob else [()]
    metrics = [m.strip() for m in args.metrics.split(",") if m.strip()]

    sweep_dir = REPO_ROOT / "reports" / "sweeps" / args.name
    cells_dir = sweep_dir / "cells"
    clear_stale_cells(cells_dir)
    cells_dir.mkdir(parents=True, exist_ok=True)

    grid_vals = []
    for axis in axes:
        grid_vals.append(axis)

    for pt in grid_points:
        cell_id = make_cell_id(args.knob, pt) if args.knob else "baseline"
            
        cell_dir = cells_dir / cell_id
        cell_dir.mkdir(parents=True, exist_ok=True)
        
        overrides = {}
        if args.knob:
            for k, v in zip(args.knob, pt):
                overrides[k] = v
                
        overrides_path = cell_dir / "overrides.json"
        with overrides_path.open("w") as f:
            json.dump(overrides, f)

        if backend == "batch":
            cmd = [
                sys.executable,
                str(REPO_ROOT / "tools" / "run_batch.py"),
                "--name", cell_id,
                "--scenarios", args.scenario,
                "--parallel", str(args.parallel),
                "--turns", str(args.turns),
                "--out-root", f"reports/sweeps/{args.name}/cells",
                "--overrides", str(overrides_path),
                "--no-report",
            ]
            if args.seeds:
                cmd.extend(["--seeds", args.seeds])
            else:
                cmd.extend(["--n", str(args.n), "--base-seed", str(args.base_seed)])
            if args.godot:
                cmd.extend(["--godot", args.godot])
            if args.run_past_game_over:
                cmd.append("--run-past-game-over")
                
            print(f"Running cell {cell_id} via batch...")
            subprocess.run(cmd, check=True)
            
            batch_games_dir = cell_dir / "games"
            samples = []
            if batch_games_dir.exists():
                for g in batch_games_dir.glob("*.json"):
                    with g.open("r", encoding="utf-8") as f:
                        samples.append(json.load(f))
            
            cell_file_path = cells_dir / f"{cell_id}.json"
            with cell_file_path.open("w", encoding="utf-8") as f:
                json.dump({
                    "overrides": overrides,
                    "samples": samples
                }, f)
        else:
            print("ERROR: in-process without --spec is not fully wired yet.", file=sys.stderr)
            sys.exit(1)
            
    sweep_manifest = {
        "sweep_name": args.name,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "commit": git_output("rev-parse", "HEAD"),
        "dirty": bool(git_output("status", "--porcelain")),
        "base_scenario": args.scenario,
        "knobs": args.knob,
        "grid": grid_vals,
        "seeds": ([int(s) for s in args.seeds.split(",") if s.strip()] if args.seeds
                  else [args.base_seed + i for i in range(args.n)]),
        "runtime_mode": "full_game",
        "rerun_command": " ".join(sys.argv),
        "metrics": metrics
    }
    
    sweep_json = sweep_dir / "sweep.json"
    with sweep_json.open("w", encoding="utf-8") as f:
        json.dump(sweep_manifest, f, indent=2)
        
    print("Delegating report generation to Python...")
    subprocess.run([
        sys.executable,
        str(REPO_ROOT / "tools" / "make_sweep_report.py"),
        "--sweep", args.name
    ], check=True)

if __name__ == "__main__":
    main()
