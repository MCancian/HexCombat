# LLM API & self-play

## 1. Purpose

Structured JSON action API so LLM agents (and the self-play harness) can drive HexCombat headlessly — no UI, no mouse clicks. One autoload (`LLMGameAPI`) exposes observation + action routing; a companion harness (`SelfPlayRunner` + `SelfPlayPolicy`) enables deterministic AI-vs-AI play for regression gates.

**HexCombat-original** — TaiwanInvasionViewer has a Flask web UI, not a JSON agent API. No TIV oracle exists for this subsystem.

## 2. Files & responsibilities

| File | Role |
|---|---|
| `scripts/LLMGameAPI.gd` | Autoload `LLMGameAPI`. `observation(team)` builds a JSON observation; `apply_agent_response(dict)` routes `move`/`commit`/`end_turn` into `GameState`. `RefCounted`, all `static func`. |
| `scripts/SelfPlayPolicy.gd` | `RefCounted` with `build_actions(observation) -> Array`. Deterministic reference policy: each brigade tactical-moves to the first non-self hex in its `legal_moves`. Pluggable — any `Callable` matching the contract works. |
| `scripts/SelfPlayRunner.gd` | `RefCounted`. `play_game(policy, turns, base_seed)` — single-policy loop over the omniscient observation. `play_game_seats(red_policy, green_policy, turns, base_seed)` — TWO-SEAT loop: each seat decides from its own perspective observation, both buffers apply, one seeded `end_turn` resolves them simultaneously (WeGo). Both return `final_snapshot`, `turn_digests`, `all_resolved`, `final_turn`, `index_violations`. |
| `scripts/LLMPolicy.gd` | `RefCounted`, `build_actions(observation) -> Array` (id `llm_local` in `PolicyCatalog`). THIN marshaller: writes the observation to a temp file, shells out (`OS.execute`) to a Python sidecar, parses the returned JSON action array, strips `end_turn`, `[]` on any failure. No engine networking. Sidecar path defaults to `res://tools/llm_sidecar.py`, overridable via `HEXCOMBAT_LLM_SIDECAR`. |
| `scripts/PolicyCatalog.gd` | Policy registry (`selfplay_default`, `inland_clear`, `llm_local`); `create_for_seat` configures seat-aware policies and unknown ids fail loud. |
| `tools/llm_sidecar.py:1` | Out-of-process, stdlib-only local-LLM adapter. Reads `--obs`, builds a prompt (rules + legal sets), POSTs to an OpenAI-compatible endpoint (`HEXCOMBAT_LLM_BASE_URL`/`_MODEL`/`_API_KEY`), tolerantly extracts the first JSON array, validates against `legal_moves`/`legal_commits`, appends a JSONL obs/action line (`--log`), prints the validated actions. |
| `tools/llm_sidecar_stub.py:1` | Network-free test double with the same contract (`HEXCOMBAT_STUB_MODE`: `first_move`/`empty`/`malformed`/`garbage`). Used by the plumbing gate. |
| `tools/run_selfplay_game.gd` | Unified entrypoint: creates both seats via `PolicyCatalog` and plays via `play_game_seats`. `--policy` remains the common default; `--red-policy`/`--green-policy` select a matchup. LLM seats write replay logs and stamp provenance. |
| `tools/validate_llm_policy.gd` | Deterministic gate (no network): exercises `LLMPolicy` against the stub — marshalling, parse/strip helpers, malformed-output fallback, obs/action log. |
| `scripts/TurnEventLog.gd` | `build(state) -> Array[TurnEvent]`. Derives an ordered per-turn event log (ijfs, antiship, move, commit, combat, frontline, cleanup) from `GameState`. Called by `play_turn` and included in `turn_result`. |
| `tools/validate_llm_api.gd` | Headless gate: asserts observation keys, action application, missing-seed rejection, example/schema conformance. |
| `tools/validate_headless_selfplay.gd` | Runs 4-turn self-play twice with same seed; asserts identical snapshots + index health. |
| `tools/export_llm_observation.gd` | CLI: writes a fresh observation JSON to disk (`--team=Red --output=reports/obs.json`). |
| `tools/export_llm_result.gd` | CLI: writes a fresh action-result JSON to disk. |
| `tools/make_game_bundle.py` | Post-game bundler (stdlib-only): record + JSONL → `<name>.viewer.json` (+ optional per-side LLM SITREPs); `--html` bakes a single-file `game.html` report; `--from-bundle` re-bakes the HTML from an existing bundle without sitrep calls. Bundle schema lives in its module docstring. |
| `tools/viewer/game_viewer.html` | Self-contained briefing-mode report viewer (no libraries, works offline). Opens a dropped `.viewer.json` or runs baked inside `game.html`. See §7. |

## 3. Observation contract — `LLMGameAPI.observation(perspective_team: String = "")`

Returns a Dictionary. Verified keys (from `tools/validate_llm_api.gd`):

`protocol_version`, `schema`, `scenario`, `turn`, `phase`, `turn_length_days`, `perspective_team`, `rules_summary`, `field_glossary`, `map_summary`, `brigades`, `occupied_hexes`, `ship_reserve`, `supply_state`, `ijfs`, `antiship`, `legal_moves`, `legal_commits`, `pending_orders`, `pending_commitments`, `last_contested_hexes`, `last_combat`, `objectives`.

Additionally, the live `observation()` at `scripts/LLMGameAPI.gd` includes `game_over` and `winner`.

**Cross-link:** Full field-level schema, types, enums, and action examples → `docs/LLM_OBSERVATION_SCHEMA.md`.

### Per-observation sub-objects — where they're built

| Key | Builder method | File:line |
|---|---|---|
| `brigades` | `_brigade_observations()` | `LLMGameAPI.gd` |
| `occupied_hexes` | `_occupied_hex_observations()` | `LLMGameAPI.gd` |
| `legal_moves` | `_legal_move_observations(team)` | `LLMGameAPI.gd` |
| `legal_commits` | `_legal_commit_observations(team)` | `LLMGameAPI.gd` |
| `pending_orders` | `_pending_orders()` | `LLMGameAPI.gd` |
| `pending_commitments` | `_pending_commitments()` | `LLMGameAPI.gd` |
| `last_combat` | `_last_combat_summaries()` | `LLMGameAPI.gd` |
| `ship_reserve` | `_ship_reserve_observations()` | `LLMGameAPI.gd` |
| `supply_state` | `_supply_state_observation()` | `LLMGameAPI.gd` |
| `ijfs` | `_ijfs_observation()` | `LLMGameAPI.gd` (includes `maneuver_casualties` inside writeback) |
| `antiship` | `_antiship_observation()` | `LLMGameAPI.gd` |

## 4. Action contract — `LLMGameAPI.apply_agent_response(response: Dictionary)`

Routes an action response object. Returns an action-result Dictionary (`ok`, `errors`, `resolved`, `seed`, `turn_result`, `observation`).

**Action types** (routed in `LLMGameAPI.gd`):

| `type` | Required fields | Routes to | Line |
|---|---|---|---|
| `move` | `team`, `brigade_id`, `target_hex`, `mode` | `GameState.add_move_order` | `LLMGameAPI.gd` |
| `commit` | `team`, `brigade_id`, `target_hex` | `GameState.add_commit_order` | `LLMGameAPI.gd` |
| `end_turn` | **`seed`** (required) | `GameState.play_turn([], [], SeededDice.new(seed))` then `begin_next_turn()` | `LLMGameAPI.gd` |

- Missing `end_turn.seed` is rejected at `LLMGameAPI.gd` — the gate (`validate_llm_api.gd`) asserts this.
- Protocol/schema version mismatch is checked at `LLMGameAPI.gd`.

**Validation gate:** `tools/validate_llm_api.gd` runs in order: observation shape → action application (move + end_turn, checks brigade advanced and turn incremented) → missing-seed rejection → example parse/apply → result-schema conformance.

## 5. Self-play — AI-vs-AI loop

`SelfPlayRunner.play_game(policy, turns, base_seed)` at `SelfPlayRunner.gd`:

1. `load_all()` / `reset_to_scenario()`
2. For each turn *t*:
   - `LLMGameAPI.observation("")` → pass to `policy.call(obs)`
   - Append `{"type": "end_turn", "seed": base_seed + t}`
   - Build and call `apply_agent_response(response)`
   - Collect `turn_result` digest
3. Return final snapshot + turn digests + index health

`SelfPlayPolicy.build_actions(obs)` at `SelfPlayPolicy.gd`: for each brigade in `legal_moves`, pick the first hex in its `tactical` array that is not its current hex. Zero randomness.

**Pluggable:** The policy argument is a `Callable(observation: Dictionary) -> Array`. Replace `SelfPlayPolicy.build_actions` with any function matching the contract (e.g., an LLM proxy).

### 5b. LLM players — two-seat LLM-vs-LLM (harness B6)

`play_game_seats(red_policy, green_policy, turns, base_seed)` at `SelfPlayRunner.gd` runs two INDEPENDENT deciders:

1. `observation("Red")` → `red_policy.build_actions` → buffer (move/commit only, no `end_turn`).
2. `observation("Green")` → `green_policy.build_actions` → buffer.
3. `apply_agent_response({actions:[{type:end_turn, seed: base_seed + t}]})` — one simultaneous WeGo resolve of both sides.

`LLMPolicy` is the decider for a seat: it marshals the perspective observation to `tools/llm_sidecar.py`, which calls a **local** OpenAI-compatible model (vLLM by default, `HEXCOMBAT_LLM_BASE_URL`/`_MODEL`/`_API_KEY`), validates the actions against the legal sets, and logs each observation/action pair. `tools/run_selfplay_game.gd --red-policy=llm_local --green-policy=llm_local` plays a full LLM-vs-LLM game; the same flags support mixed matches.

**Determinism caveat.** The RESOLVER stays deterministic (the `end_turn` seed), but the LLM DECIDER is not seed-reproducible — so LLM-game records are NOT byte-stable. The JSONL obs/action log is the replay artifact: re-feeding the logged actions through `apply_agent_response` with the recorded seeds reproduces the game (the resolver's determinism given a fixed action list + seed is what the self-play gate already proves). The plumbing (not the model) is gated deterministically by `validate_llm_policy.gd` via the network-free stub sidecar.

**Provider notes (from the 2026-07-08 vLLM `jarvis` bring-up).**
- Default endpoint is `http://127.0.0.1:8088/v1` — use **IPv4**, not `localhost`: a rootless-container `pasta` forward may serve only IPv4 and `localhost` can resolve to `::1` (connection reset).
- **Reasoning models** emit a chain-of-thought before the answer; the sidecar reads `message.content` and falls back to `message.reasoning`/`reasoning_content`. Give them room: `HEXCOMBAT_LLM_MAX_TOKENS` defaults to 8192 — too small a budget is spent entirely on reasoning (`finish_reason=length`, `content=null`, no actions). `HEXCOMBAT_LLM_TEMPERATURE` is also env-tunable.

## 6. Determinism & gates

- **Seed required.** `end_turn` must carry an explicit `seed` integer (`LLMGameAPI.gd`). The seed is passed to `SeededDice.new(seed)` inside `play_turn`.
- **Two-run determinism.** `validate_headless_selfplay.gd` runs `SelfPlayRunner.play_game` twice with the same policy and `BASE_SEED`, then asserts `final_snapshot` and `turn_digests` are identical. Also checks index consistency via `GameData.validate_runtime_indexes`.
- **API gate.** `validate_llm_api.gd` exits 0 on pass, 1 on fail. Auto-picked up by `run_all_tests.ps1`.
- **Self-play gate.** `validate_headless_selfplay.gd` same pass/fail pattern.

## 7. Post-game report: bundle & briefing viewer

`tools/make_game_bundle.py` merges a game record with its JSONL replay log into one
`.viewer.json` bundle — `{meta, turns[], sitreps, map_static}`; the authoritative shape is the
bundler's module docstring. SITREPs (3-line first-person commander summaries per side per turn)
are written at bundle time by a local LLM (same endpoint env vars as `tools/llm_sidecar.py`);
`--skip-summaries` or any model failure yields null sitreps, never a bundling failure.

`tools/viewer/game_viewer.html` renders the bundle as a **briefing**: it opens at turn 1 and
the reader advances one turn at a time (mouse wheel with a momentum guard, ◀ ▶ / ⏮ ⏭ buttons,
arrow keys / n / p, Home/End). Each advance re-renders the SVG hex map, extends the chart
reveal, and swaps the turn's narrative (SITREPs, collapsible transcripts, adjudication prose,
phase-detail tables) in place. The wheel scrolls the narrative instead of stepping when its
content overflows. If a turn lacks an observation (older logs), the map falls back to the
nearest earlier observed turn and flags it.

Charts draw ghost-future — the full game's shape in faint gray, turns up to the current one in
color: battalion census, cumulative PLA ship losses, and per-turn battalion losses per side.
The casualty series is derived client-side from the digests, nothing extra in the bundle:
Taiwan = `combat_summaries` losses attributed via a brigade→team index built from the
observations, plus one battalion per `ijfs_writeback.maneuver_casualties` entry (fires kills);
China = `combat_summaries` losses plus `antiship_summary.bns_lost_at_sea` (battalions drowned
crossing, rendered as a stacked at-sea segment). `crossing_casualties` counts SHIPS and stays
in the ship chart only.

```bash
# Full bundle from a game record (sitreps need the local model up; --skip-summaries to skip)
python3 tools/make_game_bundle.py --record reports/llm/game_20260711.json --html

# Re-bake only the game.html after a viewer change (no sitrep calls)
python3 tools/make_game_bundle.py --from-bundle reports/llm/game_20260711.viewer.json
```

Viewer and bundler are tooling, not gated engine code: no headless validator covers them.
Verify viewer changes with a headless-Chromium (Playwright) pass over a rebuilt `game.html` —
assert turn stepping, narrative swap, chart reveal — plus light/dark screenshots.

## 8. Relationship to existing docs

| Doc | What it covers | Relationship |
|---|---|---|
| `docs/LLM_PLAYTESTING.md` | Broader playtesting plan, screenshot capture, benchmark harness outline, CLI commands | Design context; this doc is the system map |
| `docs/LLM_OBSERVATION_SCHEMA.md` | Canonical field-level schema with types, enums, table per object, action examples, result shape | Schema reference; this doc cross-links and points to builder methods |
| `docs/LLM_AGENT_PROTOCOL_PLAN.md` | Implementation phases, near-term tasks, known gaps, protocol evolution | Forward plan; this doc captures the current implementation |
| `docs/systems/README.md` | Index of all system docs | Entry point for agents; this doc fills the `_pending_` row |

## 9. Note: HexCombat-original

TaiwanInvasionViewer has no LLM agent API — it is a Python/Flask web app with a browser-based UI, not a headless JSON protocol. This subsystem was designed from scratch for HexCombat's Godot engine.

## CLI commands

```powershell
# Validate the LLM API (observation keys, action apply, missing seed, examples)
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/validate_llm_api.gd"

# Validate deterministic self-play (4 turns, two runs, identical snapshots)
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/validate_headless_selfplay.gd"

# Export an observation fixture
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/export_llm_observation.gd" -- --team=Red --output="reports/llm_observation_red.json"

# Gate the LLM-policy plumbing (no network — uses the stub sidecar)
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/validate_llm_policy.gd"

# Play one full LLM-vs-LLM game against a local model (vLLM). Requires the server reachable and
# HEXCOMBAT_LLM_MODEL set (env or --model). Best on the full-defense scenario.
#   $env:HEXCOMBAT_LLM_BASE_URL="http://localhost:8088/v1"; $env:HEXCOMBAT_LLM_MODEL="<served-id>"
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/run_selfplay_game.gd" -- --seed=20260624 --scenario=roc_full_defense --red-policy=llm_local --green-policy=llm_local --turns=30 --out="reports/llm/game.json"
```
