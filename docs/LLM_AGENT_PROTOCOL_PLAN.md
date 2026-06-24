# LLM Agent Protocol Implementation Plan

Goal: make future development/playtesting LLMs understand HexCombat game state from structured JSON without needing to inspect Godot internals or infer rules from screenshots.

This is a development aid first, and a playtesting/tournament protocol later. The broader playtesting/tournament framing lives in `docs/LLM_PLAYTESTING.md`; this document is the implementation plan for the structured JSON protocol.

## Current status and known gaps

The protocol is intentionally evolving. Keep docs, examples, and code synchronized; the validator should catch drift.

Current implementation targets:

- `scripts/LLMGameAPI.gd` is the Godot-side public protocol surface.
- `tools/validate_llm_api.gd` already exists and should be expanded, not replaced.
- `tools/export_llm_observation.gd` is an on-demand fixture/export tool, distinct from the validator.

Important gap notes:

- `last_contested_hexes` is a bare list of hex IDs that were contested in the most recently resolved turn.
- `last_combat` is the richer combat-summary field. It is empty before any combat and must be documented as such.
- `objectives` is currently an empty/provisional field until scenario objective scoring is implemented.
- Movement-mode JSON keys must be the serialized strings `"tactical"` and `"administrative"`, not GDScript constant names.
- `end_turn.seed` is required for benchmark/playtest reproducibility.
- Action responses may include `perspective_team`; it controls the perspective of the returned observation.

## Design principle

Treat LLM-facing JSON as a documented public API:

- Stable field names.
- Versioned schema.
- Explicit enums and units.
- Legal actions included in observations where possible.
- Examples for every action type.
- Validation scripts that fail when docs/schema/examples drift from code.

LLMs should not need to know GDScript object layouts. They should reason from `docs/` plus JSON observations.

## Target protocol shape

Every observation should include:

```json
{
  "protocol_version": "0.1.0",
  "schema": "hexcombat.llm_observation",
  "scenario": "BOOTS Starter - Northern Beachhead",
  "turn": 1,
  "phase": "planning",
  "perspective_team": "Red",
  "rules_summary": {},
  "field_glossary": {},
  "map_summary": {},
  "brigades": [],
  "occupied_hexes": [],
  "legal_moves": {},
  "legal_commits": {},
  "pending_orders": {},
  "pending_commitments": {},
  "last_contested_hexes": [],
  "last_combat": [],
  "objectives": []
}
```

Notes:

- `last_combat` may be empty; do not infer that the field is missing.
- `objectives` is present but empty until Phase 6.
- The schema doc must describe live output, not wishful future fields. Planned-only fields belong in a “planned” section.

Every agent action response should include:

```json
{
  "protocol_version": "0.1.0",
  "schema": "hexcombat.llm_action_response",
  "perspective_team": "Red",
  "actions": [
    {"type": "move", "team": "Red", "brigade_id": "PLA-71-2-Amphibious", "target_hex": "hex_43_17", "mode": "tactical"},
    {"type": "end_turn", "seed": 20260624}
  ],
  "notes": "short rationale for logs"
}
```

## Implementation phases

### Phase 1 — Document and stabilize the current protocol

1. Add `protocol_version` and `schema` to `LLMGameAPI.observation()` and action results.
2. Require explicit `seed` in `end_turn` actions. Missing seed is an invalid action.
3. Add low-cost self-explanation fields now, not later:
   - `rules_summary`
   - `field_glossary`
   - `map_summary`
4. Create `docs/LLM_OBSERVATION_SCHEMA.md` documenting every current `LLMGameAPI.observation()` field:
   - type
   - meaning
   - example value
   - whether it is stable or provisional
5. Document every enum/string domain exactly as serialized:
   - teams: `Red`, `Green`
   - phases: `planning`, `resolution`, `end`
   - movement modes: `tactical`, `administrative`
   - owners: current `HexOwner` string values
6. Document action objects:
   - `move`
   - `commit`
   - `end_turn` with required `seed`
   - top-level `perspective_team`
7. Add a short “How an LLM should read this” section:
   - `legal_moves` is authoritative.
   - Prefer moves listed in `legal_moves`; do not invent hex IDs.
   - `pending_orders` means that unit already has an order this turn.
   - `end_turn` resolves all buffered orders and advances to next planning turn.

Acceptance:

- A future agent can read the schema doc and explain what every live field means.
- The schema doc does not promise fields that the live API lacks.

### Phase 2 — Add machine-readable schemas and fixtures

1. Add `schemas/llm_observation.schema.json`.
2. Add `schemas/llm_action_response.schema.json`.
3. Add checked-in examples:
   - `docs/examples/llm_observation_red_turn1.json`
   - `docs/examples/llm_action_response_move_end_turn.json`
   - `docs/examples/llm_result_after_turn.json`
4. Add `tools/export_llm_observation.gd` for on-demand fixture generation:
   - writes current observation JSON to a path
   - supports `--team=Red|Green`
   - supports `--output=...`
5. Expand existing `tools/validate_llm_api.gd` rather than creating a competing validator:
   - exports/builds an observation
   - verifies required top-level keys exist
   - verifies examples parse
   - verifies action examples apply cleanly through `LLMGameAPI`
   - verifies movement mode keys are `tactical` and `administrative`
   - verifies missing `end_turn.seed` is rejected

Acceptance:

- `tools/run_all_tests.ps1` includes protocol validation automatically because it runs all `tools/validate_*.gd` scripts.
- Examples stay synchronized with code.

### Phase 3 — Add a Godot step tool for external harnesses

Add `tools/llm_step.gd`:

Inputs:

```bash
--input=reports/llm_runs/run_001/red_actions_turn1.json
--output=reports/llm_runs/run_001/result_turn1.json
--team=Red
```

Behavior:

1. Load scenario or saved state.
2. Read action response JSON.
3. Call `LLMGameAPI.apply_agent_response(...)`.
4. Write result JSON containing:
   - `ok`
   - `errors`
   - `resolved`
   - `observation`
   - optional `score_delta`
5. Exit nonzero on malformed JSON or invalid actions, depending on harness mode.

Acceptance:

- A Python/Node harness can use Godot as a subprocess without custom Godot integration.

### Phase 4 — Add developer-facing prompts

Add prompt templates under `docs/prompts/`:

- `llm_player_system_prompt.md`
- `llm_red_player_prompt.md`
- `llm_green_player_prompt.md`
- `llm_developer_protocol_prompt.md`

These should instruct models to:

- read the schema first
- output JSON only for actions
- never invent brigade IDs or hex IDs
- use `legal_moves`/`legal_commits`
- include concise rationale in `notes`

Acceptance:

- Future coding agents and playtesting agents have reusable prompts instead of ad hoc instructions.

### Phase 5 — Benchmark/tournament readiness

Once gameplay is more complete:

1. Add scenario objective JSON.
2. Replace the currently empty/provisional `objectives` array with loaded scenario objectives.
3. Add score calculation to `LLMGameAPI` or a separate `ScoreCalculator.gd` pure library.
4. Add match logs:
   - observation before each side acts
   - action response
   - validation errors
   - combat summaries
   - screenshot path
   - score after turn
5. Add deterministic seed schedule per match.

Acceptance:

- Two LLMs can play a complete scenario with reproducible logs and comparable scores.

## Near-term task list

Recommended next concrete tasks:

1. Keep `LLMGameAPI.gd`, `docs/LLM_OBSERVATION_SCHEMA.md`, schemas, and examples in sync.
2. Use `tools/export_llm_observation.gd` to regenerate fixture examples when protocol fields change.
3. Expand `tools/validate_llm_api.gd` whenever a required protocol field is added.
4. Add `tools/llm_step.gd` once an external Python/Node harness is ready.

Do these before building a full tournament runner. They directly help development LLMs understand the game while the playable Godot UI is still evolving.
