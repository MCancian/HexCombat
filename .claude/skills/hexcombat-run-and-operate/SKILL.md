---
name: hexcombat-run-and-operate
description: How to run HexCombat in every mode — headless smoke, windowed, screenshot capture, single validators, the LLM JSON API tools, self-play, exporters — and where output artifacts land. Use when you need to launch the game, drive a turn headlessly, capture the view, or produce an observation/result fixture.
---

# Running & operating HexCombat

Godot binary: `C:\Godot_v4.7-stable_win64.exe` (below: `$G`). Project: this repo root (`$P`).

## Run modes

```powershell
# Headless smoke (boots Main.tscn, quits): expect "Loaded 466 hexes", "Loaded 143 brigades",
# "Spawned 466 hex cells", "Rendered 32 brigade markers", zero SCRIPT ERRORs
& $G --headless --path $P --quit-after 30

# Windowed (visual run — the adjudication-aid view)
& $G --path $P

# One headless tool/validator script
& $G --headless --path $P -s "res://tools/<script>.gd"

# Screenshot of the live scene (WINDOWED session only — not --headless)
& $G --path $P -s "res://tools/capture_screenshot.gd" -- --output="reports/current.png"
```

Artifacts land in `reports/` (git-ignored working output) and `docs/examples/` (committed,
gate-byte-compared fixtures — regenerate only via the exporters below).

## Driving turns headlessly (the research path)

The whole game is drivable with no UI through `LLMGameAPI` (autoload) — observation in, action in,
resolved turn out:

- `get_observation(team)` → turn, phase, map_cells, brigades, legal_moves, pending_orders,
  last_combat_summary, phase summaries, `game_over`/`winner`.
- `apply_action(json)` → `move` / `commit` / `end_turn` (seed **required** on end_turn).
- `GameState.play_turn(red_orders, green_orders, dice) -> TurnResult` — bulk façade; leaves phase
  at END so you can inspect before `begin_next_turn()`.
- `SelfPlayRunner.play_game(policy, turns, base_seed)` with a `SelfPlayPolicy`-style
  `build_actions(observation) -> Array` — full deterministic games headless.

Schemas: `schemas/*.schema.json`. Contract docs: `docs/LLM_OBSERVATION_SCHEMA.md`,
`docs/systems/llm-api-selfplay.md`.

```powershell
# Ready-made drivers
& $G --headless --path $P -s "res://tools/validate_headless_turn.gd"      # golden scripted turn
& $G --headless --path $P -s "res://tools/validate_headless_selfplay.gd"  # 4-turn self-play
& $G --headless --path $P -s "res://tools/export_llm_observation.gd" -- --team=Red --output="reports/obs.json"
& $G --headless --path $P -s "res://tools/export_llm_result.gd"           # regenerates the result fixture
python3 tools/run_sweep.py --spec tools/sweeps/antiship_crossing.json     # parameter sweep harness example
```

## Reading results

- Turn events: `TurnResult.to_dict().events` — ordered `ijfs → antiship → move → commit → combat →
  frontline → cleanup` rollups (the seed for narrative reporting).
- Deterministic state snapshot for comparisons: `GameData.snapshot_state()` (key-sorted).
- Victory: `game_over` / `winner` on GameState, TurnResult, and the observation.

## Rules of operation

- **Seeds:** every resolving action takes/needs a seed. Reproducibility = same seed, same build,
  fresh process. Cross-process determinism is expected and asserted by the self-play validator.
- Don't hand-edit anything in `docs/examples/` — regenerate via the export tools (the gate
  byte-compares them).
- The windowed view and the headless path share the same action layer; if something only works
  windowed, that's a bug (see `hexcombat-architecture-contract`).
