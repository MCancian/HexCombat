#!/usr/bin/env python3
"""Aggregate a HexCombat batch (run_batch.py output) into a Monte Carlo summary JSON.

Reads every valid v2 game record under <batch>/games/, classifies each game by its
victory outcome (winner + present-battalion census), and emits a compact, committable
summary: outcome counts, the census-margin / battalions-ashore / turns-to-decision
distributions (with histogram bins ready for a chart), and the reproduction metadata
(commit, scenario, matchup, seed list) pulled from the batch manifest.

Deliberately stdlib-only and timestamp-free so the summary is byte-reproducible from a
byte-reproducible batch. Usage:

    python3 tools/mc_summarize.py --batch reports/batches/<name> \
        --out reports/mc/<name>.summary.json
"""

import argparse
import json
import statistics
import sys
from pathlib import Path


def read_valid_record(path: Path) -> dict | None:
    """A record counts only if it fully resolved with no index violations (batch verdict rule)."""
    try:
        with path.open(encoding="utf-8") as file:
            record = json.load(file)
    except (json.JSONDecodeError, OSError):
        return None
    if not isinstance(record, dict):
        return None
    if not record.get("all_resolved") or record.get("index_violations"):
        return None
    return record


def classify(record: dict) -> str:
    """Outcome axis: the record's own winner is truth; empty winner = no decisive result."""
    winner = (record.get("winner") or "").strip().lower()
    if winner in ("red", "green"):
        return winner
    return "none"


def histogram(values: list[int], lo: int, hi: int, width: int) -> list[dict]:
    """Fixed-width integer bins over [lo, hi]; each bin is [start, end) except the last (inclusive)."""
    bins: list[dict] = []
    start = lo
    while start <= hi:
        end = start + width
        is_last = end > hi
        count = sum(1 for value in values if start <= value < end or (is_last and value == hi))
        bins.append({"start": start, "end": min(end, hi + 1), "count": count})
        start = end
    return bins


def distribution(values: list[int]) -> dict:
    if not values:
        return {"n": 0}
    return {
        "n": len(values),
        "min": min(values),
        "max": max(values),
        "mean": round(statistics.fmean(values), 2),
        "median": statistics.median(values),
        "stdev": round(statistics.pstdev(values), 2) if len(values) > 1 else 0.0,
    }


def summarize(batch_dir: Path) -> dict:
    manifest_path = batch_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else {}

    records = [
        record
        for record in (read_valid_record(path) for path in sorted((batch_dir / "games").glob("*.json")))
        if record is not None
    ]
    if not records:
        raise SystemExit("ERROR: no valid records under %s" % (batch_dir / "games"))

    per_game = []
    for record in records:
        census = record.get("census", {})
        red = int(census.get("red", 0))
        green = int(census.get("green", 0))
        per_game.append(
            {
                "seed": record.get("base_seed"),
                "winner": classify(record),
                "red_ashore": red,
                "green": green,
                "margin": red - green,
                "turns": record.get("turns_played"),
                "game_over": bool(record.get("game_over")),
            }
        )
    per_game.sort(key=lambda row: (row["seed"] is None, row["seed"]))

    outcomes = {"red": 0, "green": 0, "none": 0}
    for row in per_game:
        outcomes[row["winner"]] += 1

    margins = [row["margin"] for row in per_game]
    red_ashore = [row["red_ashore"] for row in per_game]
    turns = [row["turns"] for row in per_game if isinstance(row["turns"], int)]

    # Symmetric, human-legible margin bins centred on the win threshold (margin 0).
    margin_lo = min(-25, (min(margins) // 5) * 5)
    margin_hi = max(25, -(-max(margins) // 5) * 5)

    return {
        "batch_name": manifest.get("batch_name", batch_dir.name),
        "commit": manifest.get("commit"),
        "dirty": manifest.get("dirty"),
        "scenarios": manifest.get("scenarios"),
        "matchups": manifest.get("matchups"),
        "turns_requested": manifest.get("turns"),
        "seeds": manifest.get("seeds"),
        "n_games": len(per_game),
        "outcomes": outcomes,
        "win_rates": {
            side: round(count / len(per_game), 4) for side, count in outcomes.items()
        },
        "margin": {
            **distribution(margins),
            "bins": histogram(margins, margin_lo, margin_hi, 5),
        },
        "red_ashore": distribution(red_ashore),
        "green": distribution([row["green"] for row in per_game]),
        "turns_to_decision": distribution(turns),
        "per_game": per_game,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", required=True, help="Batch directory (contains games/ + manifest.json).")
    parser.add_argument("--out", required=True, help="Summary JSON output path.")
    args = parser.parse_args()

    summary = summarize(Path(args.batch))
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as file:
        json.dump(summary, file, indent=2)
        file.write("\n")

    print(
        "MC SUMMARY OK: %d games | Red %d / Green %d / none %d | margin mean %s (%s..%s)"
        % (
            summary["n_games"],
            summary["outcomes"]["red"],
            summary["outcomes"]["green"],
            summary["outcomes"]["none"],
            summary["margin"]["mean"],
            summary["margin"]["min"],
            summary["margin"]["max"],
        )
    )
    print("  wrote %s" % out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
