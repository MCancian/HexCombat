#!/usr/bin/env python3
"""Run a scenario x matchup x common-seed research batch with process-level checkpoints."""

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SCENARIOS = ["default"]
DEFAULT_MATCHUPS = ["selfplay_default:selfplay_default"]
FILENAME_COMPONENT = re.compile(r"^[A-Za-z0-9_.-]+$")


@dataclass(frozen=True)
class Job:
    scenario: str
    red_policy: str
    green_policy: str
    seed: int
    record_path: Path
    command: list[str]

    @property
    def command_line(self) -> str:
        return shlex.join(self.command)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a checkpointable HexCombat scenario x matchup x seed batch."
    )
    parser.add_argument("--name", required=True, help="Output directory name under reports/batches.")
    parser.add_argument("--scenarios", default=",".join(DEFAULT_SCENARIOS))
    parser.add_argument("--matchups", default=",".join(DEFAULT_MATCHUPS))
    parser.add_argument("--seeds", default="")
    parser.add_argument("--n", type=int, default=30)
    parser.add_argument("--base-seed", type=int, default=20260624)
    parser.add_argument("--turns", type=int, default=30)
    parser.add_argument("--parallel", type=int, default=4)
    parser.add_argument("--godot", default="")
    parser.add_argument("--no-report", action="store_true")
    return parser.parse_args()


def split_csv(value: str) -> list[str]:
    values = [item.strip() for item in value.split(",") if item.strip()]
    if not values:
        raise ValueError("Expected at least one comma-separated value.")
    return values


def parse_matchup(value: str) -> tuple[str, str]:
    parts = value.split(":")
    if len(parts) == 1:
        policy = parts[0]
        return policy, policy
    if len(parts) == 2 and all(parts):
        return parts[0], parts[1]
    raise ValueError("Invalid matchup '%s'; use policy or red_policy:green_policy." % value)


def require_filename_component(value: str, label: str) -> str:
    if not FILENAME_COMPONENT.fullmatch(value):
        raise ValueError("%s '%s' cannot be used in a record filename." % (label, value))
    return value


def resolve_godot(value: str) -> str:
    candidate = value or os.environ.get("GODOT_BIN") or shutil.which("godot")
    if not candidate:
        raise ValueError("Godot was not found; pass --godot or set GODOT_BIN.")
    return candidate


def read_valid_record(record_path: Path) -> dict | None:
    if not record_path.is_file():
        return None
    try:
        with record_path.open(encoding="utf-8") as file:
            record = json.load(file)
    except (json.JSONDecodeError, OSError):
        return None
    if not isinstance(record, dict):
        return None
    if not record.get("all_resolved") or not isinstance(record.get("index_violations"), list):
        return None
    return record if not record["index_violations"] else None


def make_jobs(
    scenarios: list[str],
    matchups: list[tuple[str, str]],
    seeds: list[int],
    turns: int,
    godot: str,
    games_dir: Path,
) -> list[Job]:
    jobs: list[Job] = []
    for scenario in scenarios:
        scenario_id = require_filename_component(Path(scenario).stem, "Scenario id")
        for red_policy, green_policy in matchups:
            red_policy = require_filename_component(red_policy, "Red policy")
            green_policy = require_filename_component(green_policy, "Green policy")
            for seed in seeds:
                record_path = games_dir / (
                    "%s__%s-vs-%s__seed%d.json"
                    % (scenario_id, red_policy, green_policy, seed)
                )
                command = [
                    godot,
                    "--headless",
                    "--path",
                    str(REPO_ROOT),
                    "-s",
                    "res://tools/run_selfplay_game.gd",
                    "--",
                    "--scenario=%s" % scenario,
                    "--red-policy=%s" % red_policy,
                    "--green-policy=%s" % green_policy,
                    "--seed=%d" % seed,
                    "--turns=%d" % turns,
                    "--out=%s" % record_path,
                ]
                jobs.append(
                    Job(
                        scenario,
                        red_policy,
                        green_policy,
                        seed,
                        record_path,
                        command,
                    )
                )
    return jobs


def run_pending_jobs(pending: list[Job], parallel: int) -> None:
    queue = pending.copy()
    running: list[tuple[Job, subprocess.Popen[str], object, object]] = []
    while queue or running:
        while queue and len(running) < parallel:
            job = queue.pop(0)
            stdout = job.record_path.with_suffix(".log").open("w", encoding="utf-8")
            stderr = job.record_path.with_suffix(".err.log").open("w", encoding="utf-8")
            process = subprocess.Popen(
                job.command,
                cwd=REPO_ROOT,
                stdout=stdout,
                stderr=stderr,
                text=True,
            )
            running.append((job, process, stdout, stderr))
        time.sleep(0.1)
        still_running: list[tuple[Job, subprocess.Popen[str], object, object]] = []
        for job, process, stdout, stderr in running:
            if process.poll() is None:
                still_running.append((job, process, stdout, stderr))
                continue
            stdout.close()
            stderr.close()
            verdict = read_valid_record(job.record_path)
            if verdict is None:
                print("GAME FAILED: %s" % job.command_line)
            else:
                print("GAME OK: %s" % record_summary(verdict))
        running = still_running


def record_summary(record: dict) -> str:
    census = record.get("census", {})
    return (
        "scenario=%s red_policy=%s green_policy=%s seed=%s turns=%s/%s "
        "game_over=%s winner=%s census=%s:%s"
        % (
            record.get("scenario_id", "?"),
            record.get("red_policy_id", record.get("policy_id", "?")),
            record.get("green_policy_id", record.get("policy_id", "?")),
            record.get("base_seed", "?"),
            record.get("turns_played", "?"),
            record.get("turns_requested", "?"),
            record.get("game_over", "?"),
            record.get("winner", "?"),
            census.get("red", "?"),
            census.get("green", "?"),
        )
    )


def git_output(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(REPO_ROOT), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def write_manifest(
    batch_dir: Path,
    name: str,
    scenarios: list[str],
    matchups: list[tuple[str, str]],
    seeds: list[int],
    turns: int,
    jobs: list[Job],
    pending_count: int,
    failed: list[Job],
) -> None:
    manifest = {
        "batch_name": name,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "commit": git_output("rev-parse", "HEAD"),
        "dirty": bool(git_output("status", "--porcelain")),
        "scenarios": scenarios,
        "matchups": [
            {"red_policy_id": red_policy, "green_policy_id": green_policy}
            for red_policy, green_policy in matchups
        ],
        "seeds": seeds,
        "turns": turns,
        "games_total": len(jobs),
        "games_run": pending_count,
        "games_failed": len(failed),
        "results": [
            {
                "scenario": job.scenario,
                "red_policy_id": job.red_policy,
                "green_policy_id": job.green_policy,
                "seed": job.seed,
                "record": str(job.record_path),
                "ok": job not in failed,
                "command": job.command_line,
            }
            for job in jobs
        ],
    }
    with (batch_dir / "manifest.json").open("w", encoding="utf-8") as file:
        json.dump(manifest, file, indent=2)
        file.write("\n")


def make_report(godot: str, batch_dir: Path) -> bool:
    command = [
        godot,
        "--headless",
        "--path",
        str(REPO_ROOT),
        "-s",
        "res://tools/make_batch_report.gd",
        "--",
        "--batch=%s" % batch_dir,
    ]
    result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    return "REPORT OK:" in result.stdout and (batch_dir / "report.md").is_file()


def main() -> int:
    try:
        args = parse_args()
        if args.n <= 0 or args.parallel <= 0 or args.turns <= 0:
            raise ValueError("--n, --parallel, and --turns must be positive.")
        scenarios = split_csv(args.scenarios)
        matchups = [parse_matchup(value) for value in split_csv(args.matchups)]
        seeds = (
            [int(value) for value in split_csv(args.seeds)]
            if args.seeds
            else list(range(args.base_seed, args.base_seed + args.n))
        )
        godot = resolve_godot(args.godot)
    except ValueError as error:
        print("ERROR: %s" % error, file=sys.stderr)
        return 2

    batch_dir = REPO_ROOT / "reports" / "batches" / args.name
    games_dir = batch_dir / "games"
    games_dir.mkdir(parents=True, exist_ok=True)
    jobs = make_jobs(scenarios, matchups, seeds, args.turns, godot, games_dir)
    pending = [job for job in jobs if read_valid_record(job.record_path) is None]
    print(
        "Batch '%s': %d games (%d scenario(s) x %d matchup(s) x %d seed(s)); "
        "%d already recorded, %d to run."
        % (
            args.name,
            len(jobs),
            len(scenarios),
            len(matchups),
            len(seeds),
            len(jobs) - len(pending),
            len(pending),
        )
    )
    run_pending_jobs(pending, args.parallel)

    failed = [job for job in jobs if read_valid_record(job.record_path) is None]
    write_manifest(
        batch_dir,
        args.name,
        scenarios,
        matchups,
        seeds,
        args.turns,
        jobs,
        len(pending),
        failed,
    )
    print(
        "Batch '%s' complete: %d/%d games OK; records in %s"
        % (args.name, len(jobs) - len(failed), len(jobs), batch_dir)
    )
    if failed:
        print("FAILED GAMES:")
        for job in failed:
            print("  %s" % job.command_line)
        return 1
    if not args.no_report and not make_report(godot, batch_dir):
        print("REPORT FAILED: %s" % (batch_dir / "report.md"), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
