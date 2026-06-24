# LLM Playtesting Plan

Goal: let pi/Claude/other LLM agents play HexCombat from the same game-action layer as the UI, optionally with rendered screenshots, and record comparable benchmark runs.

For the implementation plan and schema discipline that make structured observations understandable to future development/playtesting LLMs, see `docs/LLM_AGENT_PROTOCOL_PLAN.md` and `docs/LLM_OBSERVATION_SCHEMA.md`.

## Recommended architecture

1. **Observation**: serialize game state to JSON (`turn`, `phase`, map cells, brigades, legal moves/commits, pending orders, last contested/combat summary fields).
2. **Action**: agents return a strict JSON command list, not mouse clicks:
   - `{"type":"move","team":"Red","brigade_id":"PLA-71-2-Amphibious","target_hex":"hex_43_17","mode":"tactical"}`
   - `{"type":"commit","team":"Green","brigade_id":"BDE-77","target_hex":"hex_43_17"}`
   - `{"type":"end_turn","seed":1234}`
3. **Resolver**: apply actions through `LLMGameAPI.gd`, which delegates to `GameState.add_move_order`, `GameState.add_commit_order`, and `GameState.resolve_turn`. The UI and all agents use the same game layer.
4. **Vision artifact**: render `scenes/Main.tscn` and save a PNG for multimodal LLMs or human review.
5. **Benchmark harness**: external Python/Node process loops observation → model call → action validation → resolver → screenshot/log. Score runs by objective metrics.

This avoids brittle mouse automation while still allowing screenshots when visual reasoning is desired.

## Existing game hooks that make this feasible

- `GameState` already has a headless action API (`add_move_order`, `add_commit_order`, `resolve_turn`, `begin_next_turn`).
- `GameData` holds all map/unit state and legal reachability helpers.
- `HexMap` renders from state and can be refreshed after turn resolution.
- Combat uses injectable seeded dice, so benchmark runs can be reproducible.

## Added LLM playtesting tools

- `scripts/LLMGameAPI.gd` — JSON-style observation builder and action applier for `move`, `commit`, and `end_turn` commands. It routes actions through `GameState` rather than mutating state directly. `end_turn.seed` is required for reproducibility.
- `tools/validate_llm_api.gd` — headless gate validation for the LLM API; confirms observations expose required keys/legal moves, examples parse/apply, movement-mode keys serialize as `tactical`/`administrative`, and missing seeds are rejected.
- `tools/export_llm_observation.gd` — on-demand fixture/export helper for generating observation JSON for docs, prompts, or harness input.
- `tools/capture_screenshot.gd` — windowed/display-backed screenshot capture for `scenes/Main.tscn`; saves PNG artifacts for human review or multimodal LLM prompts.

## Immediate command-line proof points

LLM API validation:

```bash
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/validate_llm_api.gd"
```

Export an observation fixture:

```bash
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/export_llm_observation.gd" -- --team=Red --output="reports/llm_observation_red.json"
```

Headless deterministic turn validation already works:

```bash
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/validate_headless_turn.gd"
```

Screenshot capture script for visual artifacts:

```bash
"C:\Godot_v4.7-stable_win64.exe" --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/capture_screenshot.gd" -- --output="reports/llm_screenshots/current.png"
```

For reliable rendered PNGs, run screenshot capture with a display driver/windowed session rather than `--headless`.

## Action schema summary

An agent response should be JSON only:

```json
{
  "protocol_version": "0.1.0",
  "schema": "hexcombat.llm_action_response",
  "perspective_team": "Red",
  "actions": [
    {"type":"move", "team":"Red", "brigade_id":"PLA-71-2-Amphibious", "target_hex":"hex_43_17", "mode":"tactical"},
    {"type":"end_turn", "seed":20260624}
  ],
  "notes": "optional short rationale for logs"
}
```

Validation rules:

- `team` must match the brigade's team.
- `mode` is the exact string `tactical` or `administrative`.
- Moves must be in `legal_moves`/`GameData.find_reachable(...)` for that brigade/mode.
- A brigade may have at most one pending move or commit per turn.
- `end_turn.seed` is required and resolves all buffered orders, then advances to the next planning turn.
- `perspective_team` controls the perspective of the returned observation.

See `docs/LLM_OBSERVATION_SCHEMA.md` for the canonical field-level schema.

## Observation fields to expose

Minimum useful fields:

- Protocol metadata: `protocol_version`, `schema`.
- Scenario, turn, phase, turn length, perspective team.
- `rules_summary`, `field_glossary`, `map_summary` for LLM self-explanation.
- For each placed brigade: id, name, team, type, hex, battalion count, organization, destroyed/moved/fought flags.
- For occupied/contested hexes: owner (`red`/`green`/`contested`/`none`), FEBA km, brigades in hex, neighbors.
- Legal moves per visible/friendly brigade for both movement modes.
- Legal commit options for target hexes.
- Pending orders and commitments.
- `last_contested_hexes` and `last_combat`.
- `objectives` currently exists as an empty/provisional array until scenario scoring is added.

Keep the canonical state machine in Godot. External harnesses should never mutate JSON directly.

## Benchmark harness outline

One turn loop:

1. Reset/load scenario with a known seed schedule.
2. Write observation JSON and optional screenshot PNG.
3. Send prompt + observation + optional screenshot to an LLM.
4. Parse JSON actions.
5. Apply actions through Godot; reject invalid actions loudly and log them.
6. Resolve turn with deterministic seed.
7. Save post-turn observation, screenshot, combat log, and score.

Possible scores:

- Red: captured hexes, Green battalion losses, Red losses avoided, FEBA progress, supply/logistics penalties later.
- Green: beach containment, Red losses, key hexes held, own losses avoided.
- General: invalid action count, turns survived, objective completion by turn N.

## Later improvements

- Add `tools/llm_step.gd` to read an action JSON file, call `LLMGameAPI.gd`, and write observation/result JSON after applying it.
- Add map overlays for hex IDs and selected legal moves to make screenshots more useful to vision models.
- Add scenario seeds/objectives and a scoreboard JSON file.
- Add a tournament runner that pits model adapters against the same scenario suite.
