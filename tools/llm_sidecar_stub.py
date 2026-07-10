#!/usr/bin/env python3
"""Network-free STUB sidecar for HexCombat LLM-policy tests.

Stands in for a real model so the deterministic gate (tools/validate_llm_policy.gd) can exercise
the calling code (scripts/LLMPolicy.gd) without contacting an LLM. Its stdin/stdout contract
mirrors the real sidecar (tools/llm_sidecar.py): read an observation JSON, print a JSON action
array to stdout, diagnostics to stderr. Standard library only.

Behavior is chosen by env var HEXCOMBAT_STUB_MODE (default "first_move"):
  first_move  one legal tactical move for the first eligible brigade of --perspective (else []).
  empty       [].
  malformed   one move with an illegal target_hex (parses, but the game rejects it).
  garbage     non-JSON text (exercises the caller's parse-failure fallback).
"""
import argparse
import json
import os
import sys


def _load_observation(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def _first_legal_move(observation, perspective):
    """First {type:move,...} for a perspective-owned brigade with a tactical hex != from_hex."""
    legal_moves = observation.get("legal_moves", {})
    for brigade_id, entry in legal_moves.items():
        if entry.get("team") != perspective:
            continue
        from_hex = entry.get("from_hex", "")
        for target in entry.get("tactical", []):
            if target != from_hex:
                return {
                    "type": "move",
                    "team": perspective,
                    "brigade_id": brigade_id,
                    "target_hex": target,
                    "mode": "tactical",
                }
    return None


def _build_actions(observation, perspective, mode):
    if mode == "empty":
        return []
    if mode == "malformed":
        return [{
            "type": "move",
            "team": perspective,
            "brigade_id": "STUB",
            "target_hex": "hex_does_not_exist",
            "mode": "tactical",
        }]
    move = _first_legal_move(observation, perspective)
    return [move] if move is not None else []


def _append_log(log_path, perspective, observation, actions):
    os.makedirs(os.path.dirname(os.path.abspath(log_path)), exist_ok=True)
    record = {"perspective": perspective, "turn": observation.get("turn"), "actions": actions,
              "observation": observation}
    with open(log_path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Network-free stub sidecar for HexCombat tests.")
    parser.add_argument("--obs", required=True, help="Path to the observation JSON file.")
    parser.add_argument("--perspective", required=True, choices=["Red", "Green"])
    parser.add_argument("--log", default="", help="Optional JSONL obs/action log to append to.")
    args = parser.parse_args()

    mode = os.environ.get("HEXCOMBAT_STUB_MODE", "first_move")
    observation = _load_observation(args.obs)

    if mode == "garbage":
        if args.log:
            _append_log(args.log, args.perspective, observation, None)
        sys.stdout.write("not json at all")
        return 0

    actions = _build_actions(observation, args.perspective, mode)
    if args.log:
        _append_log(args.log, args.perspective, observation, actions)
    sys.stdout.write(json.dumps(actions))
    return 0


if __name__ == "__main__":
    sys.exit(main())
