# LLM API & self-play

## 1. Purpose

Structured JSON action API so LLM agents (and the self-play harness) can drive HexCombat headlessly — no UI, no mouse clicks. One autoload (`LLMGameAPI`) exposes observation + action routing; a companion harness (`SelfPlayRunner` + `SelfPlayPolicy`) enables deterministic AI-vs-AI play for regression gates.

**HexCombat-original** — TaiwanInvasionViewer has a Flask web UI, not a JSON agent API. No TIV oracle exists for this subsystem.

## 2. Files & responsibilities

| File | Role |
|---|---|
| `scripts/LLMGameAPI.gd:1` | Autoload `LLMGameAPI`. `observation(team)` builds a JSON observation; `apply_agent_response(dict)` routes `move`/`commit`/`end_turn` into `GameState`. `RefCounted`, all `static func`. |
| `scripts/SelfPlayPolicy.gd:1` | `RefCounted` with `build_actions(observation) -> Array`. Deterministic reference policy: each brigade tactical-moves to the first non-self hex in its `legal_moves`. Pluggable — any `Callable` matching the contract works. |
| `scripts/SelfPlayRunner.gd:1` | `RefCounted` with `play_game(policy, turns, base_seed) -> Dictionary`. Runs a headless loop: `observation → policy.build_actions → append end_turn → apply_agent_response`. Returns `final_snapshot`, `turn_digests`, `all_resolved`, `final_turn`, `index_violations`. |
| `scripts/TurnEventLog.gd:1` | `build(state) -> Array[TurnEvent]`. Derives an ordered per-turn event log (ijfs, antiship, move, commit, combat, frontline, cleanup) from `GameState`. Called by `play_turn` and included in `turn_result`. |
| `tools/validate_llm_api.gd:1` | Headless gate: asserts observation keys, action application, missing-seed rejection, example/schema conformance. |
| `tools/validate_headless_selfplay.gd:1` | Runs 4-turn self-play twice with same seed; asserts identical snapshots + index health. |
| `tools/export_llm_observation.gd:1` | CLI: writes a fresh observation JSON to disk (`--team=Red --output=reports/obs.json`). |
| `tools/export_llm_result.gd:1` | CLI: writes a fresh action-result JSON to disk. |

## 3. Observation contract — `LLMGameAPI.observation(perspective_team: String = "")`

Returns a Dictionary. Verified keys (from `tools/validate_llm_api.gd:20-44`):

`protocol_version`, `schema`, `scenario`, `turn`, `phase`, `turn_length_days`, `perspective_team`, `rules_summary`, `field_glossary`, `map_summary`, `brigades`, `occupied_hexes`, `ship_reserve`, `supply_state`, `ijfs`, `antiship`, `legal_moves`, `legal_commits`, `pending_orders`, `pending_commitments`, `last_contested_hexes`, `last_combat`, `objectives`.

Additionally, the live `observation()` at `scripts/LLMGameAPI.gd:42-43` includes `game_over` and `winner`.

**Cross-link:** Full field-level schema, types, enums, and action examples → `docs/LLM_OBSERVATION_SCHEMA.md`.

### Per-observation sub-objects — where they're built

| Key | Builder method | File:line |
|---|---|---|
| `brigades` | `_brigade_observations()` | `LLMGameAPI.gd:176` |
| `occupied_hexes` | `_occupied_hex_observations()` | `LLMGameAPI.gd:198` |
| `legal_moves` | `_legal_move_observations(team)` | `LLMGameAPI.gd:275` |
| `legal_commits` | `_legal_commit_observations(team)` | `LLMGameAPI.gd:294` |
| `pending_orders` | `_pending_orders()` | `LLMGameAPI.gd:312` |
| `pending_commitments` | `_pending_commitments()` | `LLMGameAPI.gd:323` |
| `last_combat` | `_last_combat_summaries()` | `LLMGameAPI.gd:334` |
| `ship_reserve` | `_ship_reserve_observations()` | `LLMGameAPI.gd:216` |
| `supply_state` | `_supply_state_observation()` | `LLMGameAPI.gd:229` |
| `ijfs` | `_ijfs_observation()` | `LLMGameAPI.gd:240` (includes `maneuver_casualties` inside writeback) |
| `antiship` | `_antiship_observation()` | `LLMGameAPI.gd:259` |

## 4. Action contract — `LLMGameAPI.apply_agent_response(response: Dictionary)`

Routes an action response object. Returns an action-result Dictionary (`ok`, `errors`, `resolved`, `seed`, `turn_result`, `observation`).

**Action types** (routed in `LLMGameAPI.gd:68-86`):

| `type` | Required fields | Routes to | Line |
|---|---|---|---|
| `move` | `team`, `brigade_id`, `target_hex`, `mode` | `GameState.add_move_order` | `LLMGameAPI.gd:130` |
| `commit` | `team`, `brigade_id`, `target_hex` | `GameState.add_commit_order` | `LLMGameAPI.gd:144` |
| `end_turn` | **`seed`** (required) | `GameState.play_turn([], [], SeededDice.new(seed))` then `begin_next_turn()` | `LLMGameAPI.gd:78` |

- Missing `end_turn.seed` is rejected at `LLMGameAPI.gd:74` — the gate (`validate_llm_api.gd:133`) asserts this.
- Protocol/schema version mismatch is checked at `LLMGameAPI.gd:53-56`.

**Validation gate:** `tools/validate_llm_api.gd:70-75` runs in order: observation shape → action application (move + end_turn, checks brigade advanced and turn incremented) → missing-seed rejection → example parse/apply → result-schema conformance.

## 5. Self-play — AI-vs-AI loop

`SelfPlayRunner.play_game(policy, turns, base_seed)` at `SelfPlayRunner.gd:22`:

1. `load_all()` / `reset_to_scenario()`
2. For each turn *t*:
   - `LLMGameAPI.observation("")` → pass to `policy.call(obs)`
   - Append `{"type": "end_turn", "seed": base_seed + t}`
   - Build and call `apply_agent_response(response)`
   - Collect `turn_result` digest
3. Return final snapshot + turn digests + index health

`SelfPlayPolicy.build_actions(obs)` at `SelfPlayPolicy.gd:11`: for each brigade in `legal_moves`, pick the first hex in its `tactical` array that is not its current hex. Zero randomness.

**Pluggable:** The policy argument is a `Callable(observation: Dictionary) -> Array`. Replace `SelfPlayPolicy.build_actions` with any function matching the contract (e.g., an LLM proxy).

## 6. Determinism & gates

- **Seed required.** `end_turn` must carry an explicit `seed` integer (`LLMGameAPI.gd:74-76`). The seed is passed to `SeededDice.new(seed)` inside `play_turn`.
- **Two-run determinism.** `validate_headless_selfplay.gd:19-34` runs `SelfPlayRunner.play_game` twice with the same policy and `BASE_SEED`, then asserts `final_snapshot` and `turn_digests` are identical. Also checks index consistency via `GameData.validate_runtime_indexes`.
- **API gate.** `validate_llm_api.gd:286-295` exits 0 on pass, 1 on fail. Auto-picked up by `run_all_tests.ps1`.
- **Self-play gate.** `validate_headless_selfplay.gd:66-75` same pass/fail pattern.

## 7. Relationship to existing docs

| Doc | What it covers | Relationship |
|---|---|---|
| `docs/LLM_PLAYTESTING.md` | Broader playtesting plan, screenshot capture, benchmark harness outline, CLI commands | Design context; this doc is the system map |
| `docs/LLM_OBSERVATION_SCHEMA.md` | Canonical field-level schema with types, enums, table per object, action examples, result shape | Schema reference; this doc cross-links and points to builder methods |
| `docs/LLM_AGENT_PROTOCOL_PLAN.md` | Implementation phases, near-term tasks, known gaps, protocol evolution | Forward plan; this doc captures the current implementation |
| `docs/systems/README.md` | Index of all system docs | Entry point for agents; this doc fills the `_pending_` row |

## 8. Note: HexCombat-original

TaiwanInvasionViewer has no LLM agent API — it is a Python/Flask web app with a browser-based UI, not a headless JSON protocol. This subsystem was designed from scratch for HexCombat's Godot engine.

## CLI commands

```powershell
# Validate the LLM API (observation keys, action apply, missing seed, examples)
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/validate_llm_api.gd"

# Validate deterministic self-play (4 turns, two runs, identical snapshots)
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/validate_headless_selfplay.gd"

# Export an observation fixture
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/export_llm_observation.gd" -- --team=Red --output="reports/llm_observation_red.json"
```
