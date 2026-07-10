#!/usr/bin/env python3
"""Post-game bundler for tools/viewer/game_viewer.html (STDLIB ONLY, no pip dependencies).

Merges one HexCombat AI-vs-AI game record (reports/llm/<name>.json, written by
tools/run_llm_game.gd) with its JSONL replay log (<name>.jsonl, one line per side per turn,
appended by tools/llm_sidecar.py) into a single self-contained bundle file that the viewer
opens directly — no live game data, no cross-referencing two files at view time.

Usage:
    python3 tools/make_game_bundle.py --record reports/llm/game_20260710.json
    python3 tools/make_game_bundle.py --record reports/llm/game_20260710.json \\
        --jsonl reports/llm/game_20260710.jsonl --out reports/llm/game_20260710.viewer.json
    python3 tools/make_game_bundle.py --record reports/llm/game_20260710.json --skip-summaries

--jsonl defaults to the record's sibling <basename>.jsonl; --out defaults to
<basename>.viewer.json. --skip-summaries omits the per-turn-per-side LLM SITREP call (fast,
useful for CI / offline bundling — the viewer falls back to a raw_reply excerpt when a sitrep
is null).

Bundle shape (see tools/viewer/game_viewer.html for the consumer):
  meta        — scenario_id/name, model, base_seed, turns_played, winner/game_over/victory_reason,
                census, commit (copied verbatim from the record).
  turns[]     — one entry per turn_digests[n]: {turn_number, digest, sides: {Red, Green}}, where
                each side is {model, raw_reply, actions, warnings, observation} joined from the
                JSONL (warnings/observation are null/absent on older logs — tolerated throughout).
  sitreps     — {"<turn_number>": {"Red": str|null, "Green": str|null}}, a 3-line first-person
                commander SITREP per side per turn, written by a local LLM at bundle time.
                Null on --skip-summaries or on any model failure — bundling never fails because
                the model is down.
  map_static  — hex grid (data/taiwan_hex_grid.json), terrain classes+colors
                (data/terrain/terrain_types.json, data/terrain/hex_terrain.json), and beaches
                (data/beaches.json), embedded so the viewer is a single data-complete file.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "data"

# SITREP model call config. Mirrors tools/llm_sidecar.py's call_model: same env vars, same
# urllib POST to an OpenAI-compatible /chat/completions endpoint, same finish_reason=length
# caveat. Budget/temperature differ on purpose — a 3-line SITREP needs far less headroom than a
# policy decision and should read terse and consistent, not creative.
DEFAULT_BASE_URL = "http://127.0.0.1:8088/v1"
# 6144, not 2048: DeepSeek-V4-Flash burned 2048 entirely on chain-of-thought for 3/60 sitreps in
# the first bundling run (game 20260711) — the budget must cover reasoning + the 3 lines.
SITREP_MAX_TOKENS = 6144
SITREP_TEMPERATURE = 0.3
HTTP_TIMEOUT_SECONDS = 120

META_KEYS = [
    "scenario_id", "scenario_name", "model", "base_seed", "turns_played",
    "winner", "game_over", "victory_reason", "census", "commit",
]

RAW_REPLY_EXCERPT_LIMIT = 1200


def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def load_jsonl(path: Path) -> list:
    entries = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            entries.append(json.loads(line))
    return entries


def index_jsonl_by_turn(entries: list) -> dict:
    """turn_number -> {"Red": entry, "Green": entry}. Last entry wins on a duplicate
    (turn, perspective) pair — shouldn't happen in a well-formed log, but bundling must not
    crash on one."""
    by_turn: dict = {}
    for entry in entries:
        turn = entry.get("turn")
        perspective = entry.get("perspective")
        if turn is None or perspective not in ("Red", "Green"):
            print("make_game_bundle: skipping malformed JSONL entry: %r" % (entry,),
                  file=sys.stderr)
            continue
        by_turn.setdefault(turn, {})[perspective] = entry
    return by_turn


def build_side_entry(entry) -> dict:
    if entry is None:
        return None
    return {
        "model": entry.get("model"),
        "raw_reply": entry.get("raw_reply"),
        "actions": entry.get("actions", []),
        # Older logs (pre-observation format) lack these keys entirely; the viewer degrades to
        # text-only for those turns rather than treating their absence as an error.
        "warnings": entry.get("warnings", []),
        "observation": entry.get("observation"),
    }


def build_meta(record: dict) -> dict:
    return {key: record.get(key) for key in META_KEYS}


def build_turns(record: dict, jsonl_by_turn: dict) -> list:
    turns = []
    for digest in record.get("turn_digests", []):
        turn_number = digest.get("turn_number")
        sides = jsonl_by_turn.get(turn_number, {})
        turns.append({
            "turn_number": turn_number,
            "digest": digest,
            "sides": {
                "Red": build_side_entry(sides.get("Red")),
                "Green": build_side_entry(sides.get("Green")),
            },
        })
    return turns


def load_map_static() -> dict:
    hex_grid = load_json(DATA_DIR / "taiwan_hex_grid.json")
    terrain_types = load_json(DATA_DIR / "terrain" / "terrain_types.json")
    hex_terrain = load_json(DATA_DIR / "terrain" / "hex_terrain.json")
    beaches = load_json(DATA_DIR / "beaches.json")
    return {
        "hexes": hex_grid.get("hexes", []),
        "side_to_side_km": hex_grid.get("side_to_side_km"),
        "terrain_types": terrain_types.get("types", {}),
        "hex_terrain": hex_terrain.get("classes", {}),
        "beaches": beaches.get("beaches", []),
    }


def call_sitrep_model(messages: list) -> str:
    """POST to the chat-completions endpoint; returns the assistant's `content`. Raises on hard
    failure (unreachable / HTTP error / malformed envelope / no usable content) — the caller
    turns any exception into a null sitrep, never a bundling failure.

    Deliberately does NOT fall back to `reasoning`/`reasoning_content` the way
    tools/llm_sidecar.py's call_model does. That fallback is fine there because the caller
    regexes a JSON array out of whatever text comes back; here the whole point is a clean
    3-line first-person SITREP, and a reasoning model's raw chain-of-thought is a wall of
    think-aloud prose, not that — observed in practice (game_20260711 excerpt, DeepSeek-V4-Flash
    reasoning model): `content` came back null with finish_reason=length and `reasoning` held
    several paragraphs of "wait, let me reconsider..." deliberation. Treating that as the sitrep
    would be worse than no sitrep, so an empty `content` is always a failure -> null."""
    base_url = os.environ.get("HEXCOMBAT_LLM_BASE_URL", DEFAULT_BASE_URL).rstrip("/")
    model = os.environ.get("HEXCOMBAT_LLM_MODEL", "")
    api_key = os.environ.get("HEXCOMBAT_LLM_API_KEY", "EMPTY")
    if not model:
        raise RuntimeError("HEXCOMBAT_LLM_MODEL is not set")

    body = json.dumps({
        "model": model,
        "messages": messages,
        "temperature": SITREP_TEMPERATURE,
        "max_tokens": SITREP_MAX_TOKENS,
    }).encode("utf-8")
    request = urllib.request.Request(
        base_url + "/chat/completions",
        data=body,
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + api_key},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
        payload = json.load(response)
    choice = payload["choices"][0]
    text = (choice.get("message") or {}).get("content") or ""
    if not text:
        reason = choice.get("finish_reason")
        raise RuntimeError(
            "sitrep model returned no `content` (finish_reason=%s) — likely a reasoning model "
            "that burned SITREP_MAX_TOKENS=%d on chain-of-thought; raising the budget would "
            "reduce this, at the cost of slower bundling" % (reason, SITREP_MAX_TOKENS))
    return text


def _trim(text, limit=RAW_REPLY_EXCERPT_LIMIT) -> str:
    if not text:
        return ""
    text = text.strip()
    return text if len(text) <= limit else text[:limit] + "…[truncated]"


def _digest_highlights(side: str, digest: dict) -> dict:
    """Compact, side-relevant slice of the turn digest for the SITREP prompt — the full digest
    is large (firing-capacity tables, per-round rolls, etc.) and most of it isn't commander-voice
    material. Red = PLA/China (attacker: IJFS strikes, amphibious losses); Green = ROC/Taiwan
    (defender: anti-ship kills, ground defense)."""
    cleanup = digest.get("cleanup_summary") or {}
    highlights = {
        "contested_hexes": digest.get("contested_hexes", []),
        "china_battalions_on_taiwan": cleanup.get("china_battalions_on_taiwan"),
        "taiwan_battalions_on_taiwan": cleanup.get("taiwan_battalions_on_taiwan"),
    }

    combats = []
    for combat in digest.get("combat_summaries") or []:
        is_mine = (
            (side == "Red" and combat.get("attacker_brigade_ids"))
            or (side == "Green" and combat.get("defender_brigade_ids"))
        )
        if not is_mine:
            continue
        combats.append({
            "hex_id": combat.get("hex_id"),
            "result": (combat.get("combat_detail") or {}).get("result"),
            "attacker_losses": combat.get("attacker_losses"),
            "defender_losses": combat.get("defender_losses"),
            "owner_after": combat.get("owner_after"),
        })
    highlights["combats"] = combats

    antiship = digest.get("antiship_summary") or {}
    if side == "Red":
        ijfs = digest.get("ijfs_summary") or {}
        highlights["ijfs_attacks_executed"] = (ijfs.get("attacks") or {}).get("executed")
        highlights["destroyed_targets_by_category"] = ijfs.get("destroyed_targets_by_category")
        highlights["own_ship_losses"] = (antiship.get("crossing_casualties") or {}).get("destroyed")
    else:
        highlights["ships_destroyed"] = (antiship.get("crossing_casualties") or {}).get("destroyed")
        highlights["destroyed_by_ship_type"] = antiship.get("destroyed_by_ship_type")

    return highlights


def build_sitrep_prompt(turn_number, side: str, digest: dict, side_entry: dict) -> list:
    side_name = "PLA / China (Red)" if side == "Red" else "ROC / Taiwan (Green)"
    highlights = _digest_highlights(side, digest)
    system = (
        "You write terse first-person commander SITREPs for a wargame post-game viewer. "
        "Output EXACTLY 3 short lines, first-person commander voice, no preamble, no markdown, "
        "no numbering, no quotation marks. Example line: 'Pushed 3 brigades toward Taoyuan; "
        "holding hex_43_14 despite losses.'"
    )
    user = (
        "You are the %s commander reporting after turn %s.\n"
        "This side's orders this turn: %s\n"
        "Digest highlights: %s\n"
        "Your own reasoning/orders reply this turn (may be cut short):\n%s\n\n"
        "Write the 3-line SITREP now."
    ) % (
        side_name, turn_number,
        json.dumps(side_entry.get("actions", [])),
        json.dumps(highlights),
        _trim(side_entry.get("raw_reply")),
    )
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def generate_sitreps(turns: list, skip: bool) -> dict:
    sitreps: dict = {}
    for turn in turns:
        turn_key = str(turn["turn_number"])
        sitreps[turn_key] = {}
        for side in ("Red", "Green"):
            side_entry = turn["sides"].get(side)
            if skip or side_entry is None:
                sitreps[turn_key][side] = None
                continue
            try:
                messages = build_sitrep_prompt(turn["turn_number"], side, turn["digest"], side_entry)
                text = call_sitrep_model(messages)
                sitreps[turn_key][side] = text.strip()
            except (urllib.error.URLError, OSError, RuntimeError, KeyError, ValueError, IndexError) as error:
                print("make_game_bundle: sitrep failed (turn %s, %s): %s" % (turn_key, side, error),
                      file=sys.stderr)
                sitreps[turn_key][side] = None
    return sitreps


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--record", required=True, help="Path to the game record JSON.")
    parser.add_argument("--jsonl", default=None,
                         help="Path to the JSONL replay log (default: record's sibling .jsonl).")
    parser.add_argument("--out", default=None,
                         help="Output bundle path (default: <record-basename>.viewer.json).")
    parser.add_argument("--skip-summaries", action="store_true",
                         help="Skip the per-turn LLM SITREP calls (sitreps are all null).")
    parser.add_argument("--html", action="store_true",
                         help="Also write <record-basename>.game.html: the viewer with the bundle "
                              "baked in — a single shareable report file, no drag-drop needed.")
    args = parser.parse_args()

    record_path = Path(args.record)
    stem = str(record_path.with_suffix(""))
    jsonl_path = Path(args.jsonl) if args.jsonl else Path(stem + ".jsonl")
    out_path = Path(args.out) if args.out else Path(stem + ".viewer.json")

    record = load_json(record_path)
    jsonl_entries = load_jsonl(jsonl_path)
    jsonl_by_turn = index_jsonl_by_turn(jsonl_entries)

    turns = build_turns(record, jsonl_by_turn)
    sitreps = generate_sitreps(turns, args.skip_summaries)

    bundle = {
        "meta": build_meta(record),
        "turns": turns,
        "sitreps": sitreps,
        "map_static": load_map_static(),
    }

    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(bundle, handle, separators=(",", ":"))

    print("make_game_bundle: wrote %s (%d bytes), %d turns, sitreps %s" % (
        out_path, out_path.stat().st_size, len(turns),
        "skipped" if args.skip_summaries else "generated",
    ), file=sys.stderr)

    if args.html:
        html_path = Path(stem + ".game.html")
        write_html_report(bundle, html_path)
        print("make_game_bundle: wrote %s (%d bytes)" % (html_path, html_path.stat().st_size),
              file=sys.stderr)
    return 0


def write_html_report(bundle: dict, html_path: Path) -> None:
    """Bake the bundle into the viewer as a <script type=application/json> tag (data, not code —
    the viewer JSON.parses it; it is never executed). `</` must be escaped so model text
    containing `</script>` cannot close the tag early — `<\\/` is a valid JSON string escape."""
    viewer_path = REPO_ROOT / "tools" / "viewer" / "game_viewer.html"
    viewer = viewer_path.read_text(encoding="utf-8")
    payload = json.dumps(bundle, separators=(",", ":")).replace("</", "<\\/")
    tag = '<script type="application/json" id="embedded-bundle">%s</script>\n' % payload
    marker = "<script>"
    if marker not in viewer:
        raise RuntimeError("viewer HTML has no <script> tag to inject before: %s" % viewer_path)
    with open(html_path, "w", encoding="utf-8") as handle:
        handle.write(viewer.replace(marker, tag + marker, 1))


if __name__ == "__main__":
    sys.exit(main())
