#!/usr/bin/env python3
"""Run a parameter sweep: generate override cells, execute them, render the report.

Two modes, one backend (plan 0012 — every cell is a set of standard run_batch.py games whose
records the Python metric extractors consume):
  --spec tools/sweeps/<name>.json   canned sweep (seeds/turns/knobs/metrics from the spec)
  --name <study> --knob ... --values ...   ad-hoc one-off
"""

import argparse
import itertools
import json
import re
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
    parser.add_argument("--knob", action="append", help="<file:dot.path>", default=[])
    parser.add_argument("--values", action="append", help="comma-separated values", default=[])
    parser.add_argument("--scenario", default="scenario_default")
    parser.add_argument("--matchup", default="selfplay_default",
                        help="policy or red:green matchup for every game")
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


def require_scenario_file(scenario):
    """Fail loud before burning a batch on a typo'd scenario id (the guard the retired
    run_sweep_cells.gd backend enforced in-process; mirrors ScenarioCatalog.resolve_path)."""
    if scenario in ("", "default", "scenario_default"):
        return
    candidates = [
        REPO_ROOT / scenario.replace("res://", ""),
        REPO_ROOT / "data" / f"{scenario}.json",
        REPO_ROOT / "data" / "scenarios" / f"{scenario}.json",
    ]
    if not any(c.is_file() for c in candidates):
        die(f"Scenario '{scenario}' does not resolve to a file (checked {[str(c) for c in candidates]})")


def run_batch_cell(cell_id, sweep_name, scenario, seeds, turns, matchup, run_past_game_over, args):
    cmd = [
        sys.executable,
        str(REPO_ROOT / "tools" / "run_batch.py"),
        "--name", cell_id,
        "--scenarios", scenario,
        "--matchups", matchup,
        "--parallel", str(args.parallel),
        "--turns", str(turns),
        "--seeds", ",".join(str(s) for s in seeds),
        "--out-root", f"reports/sweeps/{sweep_name}/cells",
        "--overrides", str(SWEEPS_ROOT / sweep_name / "cells" / cell_id / "overrides.json"),
        "--no-report",
    ]
    if args.godot:
        cmd.extend(["--godot", args.godot])
    if run_past_game_over:
        cmd.append("--run-past-game-over")

    print(f"Running cell {cell_id} via batch...")
    subprocess.run(cmd, check=True)


def collect_batch_samples(cell_dir):
    samples = []
    games_dir = cell_dir / "games"
    if games_dir.exists():
        for g in sorted(games_dir.glob("*.json")):
            with g.open("r", encoding="utf-8") as f:
                record = json.load(f)
                digests = record["turn_digests"]
                proj = {
                    "base_seed": record["base_seed"],
                    "census": record["census"],
                    "turn_digests": [digests[0], digests[-1]] if digests else []
                }
                if "winner" in record:
                    proj["winner"] = record["winner"]
                samples.append(proj)
    return samples


def run_cells(cells, sweep_name, scenario, seeds, turns, matchup, run_past_game_over, args):
    """Execute each cell as a run_batch job set and aggregate its game records into
    cells/<id>.json — the cell shape the metric registry consumes."""
    cells_dir = SWEEPS_ROOT / sweep_name / "cells"
    for cell in cells:
        cell_dir = cells_dir / cell["id"]
        cell_dir.mkdir(parents=True, exist_ok=True)
        with (cell_dir / "overrides.json").open("w", encoding="utf-8") as f:
            json.dump(cell["overrides"], f)

        run_batch_cell(cell["id"], sweep_name, scenario, seeds, turns, matchup, run_past_game_over, args)

        samples = collect_batch_samples(cell_dir)
        if len(samples) != len(seeds):
            die(f"Cell {cell['id']}: {len(samples)} valid records for {len(seeds)} seeds — "
                "a game failed; see its .err.log under the cell's games dir.")
        with (cells_dir / f"{cell['id']}.json").open("w", encoding="utf-8") as f:
            json.dump({"overrides": cell["overrides"], "samples": samples}, f)


def run_spec_sweep(args):
    with open(args.spec, "r") as f:
        spec = json.load(f)
    name = spec.get("sweep_name", Path(args.spec).stem)
    scenario = spec.get("scenario", "scenario_default")
    require_scenario_file(scenario)
    knobs = spec.get("knobs", [])
    grid = spec.get("grid", [])
    metrics = spec.get("metrics", [])
    validate_metrics(metrics)
    seeds = spec["seeds"]
    turns = int(spec["turns"])
    # Both canned calibration sweeps run noop-vs-noop: pure engine dynamics, the measurement
    # semantics their dialed reference tables were accepted under (the retired cell runner's
    # end_turn-only loop). A spec studying real play sets its own matchup.
    matchup = spec["matchup"]
    run_past_game_over = bool(spec.get("run_past_game_over", False)) or args.run_past_game_over

    cells = grid_cells(knobs, grid) + spec.get("extra_cells", [])
    for cell in cells:
        cell["overrides"] = cell.get("overrides", {})

    sweep_dir = SWEEPS_ROOT / name
    write_manifest(sweep_dir, name, scenario, knobs, grid, seeds, "batch", metrics)
    clear_stale_cells(sweep_dir / "cells")
    print(f"Running spec sweep: {name} (scenario={scenario}, {len(cells)} cells x {len(seeds)} seeds)")
    run_cells(cells, name, scenario, seeds, turns, matchup, run_past_game_over, args)
    render_report(name)


def run_cli_sweep(args):
    if args.knob and len(args.knob) != len(args.values):
        die("--knob and --values must be paired.")

    grid = [[parse_value(x) for x in v.split(",") if x.strip()] for v in args.values]
    metrics = [m.strip() for m in args.metrics.split(",") if m.strip()]
    validate_metrics(metrics)
    seeds = ([int(s) for s in args.seeds.split(",") if s.strip()] if args.seeds
             else [args.base_seed + i for i in range(args.n)])
    require_scenario_file(args.scenario)

    sweep_dir = SWEEPS_ROOT / args.name
    clear_stale_cells(sweep_dir / "cells")
    run_cells(grid_cells(args.knob, grid), args.name, args.scenario, seeds, args.turns,
              args.matchup, args.run_past_game_over, args)
    write_manifest(sweep_dir, args.name, args.scenario, args.knob, grid, seeds,
                   "batch", metrics)
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
