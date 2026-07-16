#!/usr/bin/env python3
"""Multi-game replay bundler for tools/viewer/game_viewer.html (STDLIB ONLY).

Combines several HexCombat AI-vs-AI game records into ONE self-contained replay HTML with a
game-selector tab bar, reusing tools/make_game_bundle.py's per-game bundle assembly untouched —
each record still gets its own {meta, turns, sitreps, map_static} bundle; this just wraps them as
{"games": [...]} and bakes that into the viewer instead of a single bundle.

Usage:
    python3 tools/make_multi_game_bundle.py \\
        --records reports/llm/overnight_s20260716.json reports/llm/overnight_s20260717.json \\
                  reports/llm/overnight_s20260718.json reports/llm/overnight_s20260719.json \\
        --out reports/llm/overnight_replay.game.html

--jsonl for each record defaults to its sibling <basename>.jsonl (same convention as
make_game_bundle.py). --skip-summaries skips the per-turn LLM SITREP calls for every game (fast,
no local model server required).
"""
import argparse
import sys
from pathlib import Path

import make_game_bundle as single


def build_game_bundle(record_path: Path, skip_summaries: bool) -> dict:
    stem = str(record_path.with_suffix(""))
    jsonl_path = Path(stem + ".jsonl")
    record = single.load_json(record_path)
    jsonl_entries = single.load_jsonl(jsonl_path)
    jsonl_by_turn = single.index_jsonl_by_turn(jsonl_entries)
    turns = single.build_turns(record, jsonl_by_turn)
    sitreps = single.generate_sitreps(turns, skip_summaries)
    return {
        "meta": single.build_meta(record),
        "turns": turns,
        "sitreps": sitreps,
        "map_static": single.load_map_static(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--records", nargs="+", required=True,
                         help="Game record JSON paths, in tab order.")
    parser.add_argument("--out", required=True, help="Output .game.html path.")
    parser.add_argument("--skip-summaries", action="store_true",
                         help="Skip the per-turn LLM SITREP calls (sitreps are all null).")
    args = parser.parse_args()

    games = [build_game_bundle(Path(p), args.skip_summaries) for p in args.records]
    out_path = Path(args.out)
    single.write_html_report({"games": games}, out_path)
    print("make_multi_game_bundle: wrote %s (%d bytes), %d games" % (
        out_path, out_path.stat().st_size, len(games)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
