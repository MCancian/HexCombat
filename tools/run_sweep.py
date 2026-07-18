#!/usr/bin/env python3
"""Run a parameter sweep: generate override cells, execute them, render the report.

Two modes:
  --spec tools/sweeps/<name>.json   canned sweep, in-process backend (run_sweep_cells.gd)
  --name <study> --knob ... --values ...   ad-hoc one-off, batch backend (run_batch.py)
"""

import argparse
import itertools
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from sweep_metrics import REGISTRY

REPO_ROOT = Path(__file__).resolve().parent.parent
SWEEPS_ROOT = REPO_ROOT / "reports" / "sweeps"


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


def die(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


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


def validate_metrics(metrics):
    unknown = [m for m in metrics if m not in REGISTRY]
    if unknown:
        die(f"Unknown metric(s) {unknown}; registry has {sorted(REGISTRY)}")


def grid_cells(knobs, grid):
    if not (knobs and grid):
        return [{"id": "baseline", "overrides": {}}]
    return [
        {"id": make_cell_id(knobs, pt), "overrides": dict(zip(knobs, pt))}
        for pt in itertools.product(*grid)
    ]


def write_manifest(sweep_dir, name, scenario, knobs, grid, seeds, runtime_mode, metrics):
    manifest = {
        "sweep_name": name,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "commit": git_output("rev-parse", "HEAD"),
        "dirty": bool(git_output("status", "--porcelain")),
        "base_scenario": scenario,
        "knobs": knobs,
        "grid": grid,
        "seeds": seeds,
        "runtime_mode": runtime_mode,
        "rerun_command": " ".join(sys.argv),
        "metrics": metrics,
    }
    sweep_dir.mkdir(parents=True, exist_ok=True)
    with (sweep_dir / "sweep.json").open("w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)


def render_report(name):
    print("Delegating report generation to Python...")
    subprocess.run(
        [sys.executable, str(REPO_ROOT / "tools" / "make_sweep_report.py"), "--sweep", name],
        check=True,
    )


def run_spec_sweep(args):
    if args.backend == "batch":
        die("--spec sweeps run in-process only (custom metric extraction lives in "
            "run_sweep_cells.gd until plan 0012 moves it to Python).")

    with open(args.spec, "r") as f:
        spec = json.load(f)
    name = spec.get("sweep_name", Path(args.spec).stem)
    scenario = spec.get("scenario", "scenario_default")
    knobs = spec.get("knobs", [])
    grid = spec.get("grid", [])
    metrics = spec.get("metrics", [])
    validate_metrics(metrics)

    sweep_dir = SWEEPS_ROOT / name
    cells_dir = sweep_dir / "cells"
    write_manifest(sweep_dir, name, scenario, knobs, grid, spec.get("seeds", []),
                   "in_process", metrics)
    clear_stale_cells(cells_dir)

    spec["cells"] = spec.get("cells", grid_cells(knobs, grid)) + spec.get("extra_cells", [])
    spec["out_dir"] = str(cells_dir)
    run_spec_path = sweep_dir / "run_spec.json"
    with run_spec_path.open("w") as f:
        json.dump(spec, f)

    cmd = [
        args.godot or shutil.which("godot") or "godot",
        "--headless", "--path", str(REPO_ROOT),
        "-s", "res://tools/run_sweep_cells.gd",
        "--", f"--spec={run_spec_path}", f"--scenario={scenario}",
    ]
    print(f"Running in-process sweep: {name} (scenario={scenario})")
    subprocess.run(cmd, check=True)
    render_report(name)


def run_batch_cell(args, cell_id, overrides_path):
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


def collect_batch_samples(cell_dir):
    samples = []
    games_dir = cell_dir / "games"
    if games_dir.exists():
        for g in sorted(games_dir.glob("*.json")):
            with g.open("r", encoding="utf-8") as f:
                samples.append(json.load(f))
    return samples


def run_cli_sweep(args):
    if (args.backend or "batch") != "batch":
        die("in-process without --spec is not wired; write a spec in tools/sweeps/.")
    if args.knob and len(args.knob) != len(args.values):
        die("--knob and --values must be paired.")

    grid = [[parse_value(x) for x in v.split(",") if x.strip()] for v in args.values]
    metrics = [m.strip() for m in args.metrics.split(",") if m.strip()]
    validate_metrics(metrics)
    seeds = ([int(s) for s in args.seeds.split(",") if s.strip()] if args.seeds
             else [args.base_seed + i for i in range(args.n)])

    sweep_dir = SWEEPS_ROOT / args.name
    cells_dir = sweep_dir / "cells"
    clear_stale_cells(cells_dir)
    cells_dir.mkdir(parents=True, exist_ok=True)

    for cell in grid_cells(args.knob, grid):
        cell_dir = cells_dir / cell["id"]
        cell_dir.mkdir(parents=True, exist_ok=True)
        overrides_path = cell_dir / "overrides.json"
        with overrides_path.open("w") as f:
            json.dump(cell["overrides"], f)

        run_batch_cell(args, cell["id"], overrides_path)

        with (cells_dir / f"{cell['id']}.json").open("w", encoding="utf-8") as f:
            json.dump({"overrides": cell["overrides"],
                       "samples": collect_batch_samples(cell_dir)}, f)

    write_manifest(sweep_dir, args.name, args.scenario, args.knob, grid, seeds,
                   "full_game", metrics)
    render_report(args.name)


def main():
    args = parse_args()
    if args.spec:
        run_spec_sweep(args)
    elif args.name:
        run_cli_sweep(args)
    else:
        die("Must provide --name or --spec.")


if __name__ == "__main__":
    main()
