# AGENTS.md — HexCombat Agent Guide

Claude-specific orchestration material lives in `CLAUDE.md`.

**`docs/STATUS.md`** = what works today + how the docs are organized and the tracking rules; 
**`docs/plans/BACKLOG.md`** = the forward plan. Update STATUS.md (no dates) when you finish a feature.

## Project

Godot 4.7 / GDScript hex-grid wargame of a PLA invasion of Taiwan, ported from
**TaiwanInvasionViewer** (`C:\Users\mdogg\TaiwanInvasionViewer`), a Python/Flask simulation.

**Mission (user-ratified 2026-07-02; see PLAN.md → Decisions):**
1. **Primary — AI-vs-AI research instrument:** headless batch games → Monte Carlo outcome
   distributions, LLM players via the JSON API, human-readable narratives, parameter sweeps.
2. **Secondary — live-adjudication aid:** a facilitator enters both sides' orders in the UI and
   the sim resolves; projector-friendly display.
Scenario variants (same theater, different force mixes/timelines/postures) are first-class
content. The user is a non-coder; agents do all coding — legibility to future agents is a design
requirement, not a nicety.

**Design of record:** HexCombat itself. TIV was the port oracle — when adapting existing TIV
mechanics, read its source and `tests/python/` cases first and preserve ported math unless a
change is directed; but new design and rebalances are USER calls recorded in PLAN.md → Decisions,
not bound to TIV.

## Skills (read before acting)

`.claude/skills/` holds the procedure library — task→skill map in `.claude/skills/README.md`.
Minimum path for any change: `hexcombat-architecture-contract` (design rules) →
`hexcombat-change-control` (gating/commit) → the task-specific skill. Debugging starts at
`hexcombat-debugging-playbook`; settled battles live in `hexcombat-failure-archaeology`.

## Architecture (keep new code inside these layers)

- **Model — typed `Resource` classes** (`scripts/model/`): `Hex`, `Brigade`, `Battalion`,
  `CombatResult`. Plain typed data; no engine/scene/screen concerns. Prefer adding fields here
  over passing untyped `Dictionary` blobs.
- **Logic — pure libraries** (`scripts/`): `HexMath`, `CombatCalculator`, `UnitStats`,
  `MapProjection`. `RefCounted` / `static func`; no `Node` dependency; headless-testable.
- **Data service — one autoload** (`scripts/GameData.gd`, autoload `GameData`): loads JSON into
  typed objects once and holds lookups (hexes, neighbors, brigades, hex states). Autoloads init
  before the main scene.
- **Runtime state** (planned `GameState` autoload): turn / phase / active side. Game progression
  lives here, not in the view.
- **View / control**: `HexMap.gd` (Node2D renderer; owns projection, reads `GameData`),
  `GameController.gd` (scene root), `scenes/Main.tscn`.
- Compatibility wrappers `HexGrid.gd`, `UnitManager.gd`, `BOOTSCalculator.gd` forward to the new
  code — don't add logic to them.

Data: `data/*.json`. Custom validation scripts: `tools/`. GdUnit4 tests: `tests/`.

## Running & verifying

Godot binary: `C:\Godot_v4.7-stable_win64.exe`.

```bash
# build the class cache (after adding scripts / fresh checkout)
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" --import
# headless smoke test (expect 455 hexes / 143 brigades / 455 cells, zero errors)
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" --quit-after 30
# one validation/test script
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/<script>.gd"
# windowed (visual run)
"C:\Godot_v4.7-stable_win64.exe" --path "C:\Users\mdogg\Desktop\HexCombat"
```

**Canonical gate:** `tools/run_all_tests.ps1` runs import → smoke test → every `tools/`
validation script → the GdUnit4 suite, exiting nonzero on any failure. Run it before declaring
work done. The `.godot/` cache is git-ignored; `.gd.uid` files are committed with their scripts.

## Testing strategy (additive, two layers)

1. **Custom headless scripts** (`tools/validate_*.gd`): data-contract checks, startup smoke,
   Python-port equivalence. Dependency-light and agent-friendly. Keep these.
2. **GdUnit4** (`tests/`): structured unit tests, scene loading, input simulation, UI behavior,
   integration. The framework for the interactive-game side.

- **Seeded RNG.** Pure logic must not call global `randi()`/`randf()` directly — inject a
  seedable RNG/dice abstraction so combat and sim outcomes are reproducible. Required before
  writing golden tests.
- **Golden/regression tests:** with a fixed seed, ported math must match values from the source
  `tests/python/` cases.
- New behavior ships with a test; when a source pytest exists for it, mirror that case.

## Conventions

- Typed GDScript throughout (`var x: Type`, typed params/returns, `class_name`).
- **Single source of truth** — no duplicated tables/constants (e.g. unit strengths live only in
  `UnitStats`).
- **Fail loud, not silent.** This is a **solo-developer tool**: a loud crash you fix at the root
  beats defensive error-handling that hides bugs. Don't wrap things in try/guards for hypothetical
  inputs — let it break visibly (`push_error`/assert) and fix the cause. Unknown/missing data →
  `push_warning`/`push_error`, never a silent default fallback.
- Pure logic = `static func` in `RefCounted` libs; runtime state = autoloads; visuals = view
  layer. Don't leak screen/pixel concerns into the model.

## Documentation map

- `AGENTS.md` (this file) — shared rules, canonical.
- `CLAUDE.md` — orchestrator role + how to use the opencode implementer (Claude-only).
- `ROADMAP.md` — long-term, sequenced milestones with acceptance criteria + forward-compat notes.
- `PLAN.md` — the active milestone in detail + an append-only **Decisions** log + open questions.
- `docs/ARCHITECTURE.md` — deeper design / rationale; per-phase notes under `docs/phases/`.
- `docs/systems/` — **per-system reference for agents** (one `.md` per system: data flow, key
  funcs, files, TIV-port fidelity notes). Start here to understand how a subsystem works.
  Human-readable HTML mirrors in `docs/systems/html/`. Index: `docs/systems/README.md`.
  Port-audit progress + open fidelity questions: `docs/plans/AUDIT_PROGRESS.md` / `DECISIONS.md`.
- `docs/LLM_PLAYTESTING.md` / `docs/LLM_AGENT_PROTOCOL_PLAN.md` — LLM playtesting API,
  structured observations/actions, screenshots, and benchmark harness planning.

## LLM playtesting / headless JSON API

HexCombat has a built-in JSON action API so LLM agents (including the orchestrator's headless
gates and future AI-vs-AI play) can drive the game without a UI:

**Core tools** (`scripts/LLMGameAPI.gd` autoload):

- `get_observation(team)` → JSON dict: `turn`, `phase`, `map_cells`, `brigades`, `legal_moves`,
  `pending_orders`, `last_combat_summary`
- `apply_action(action_json)` → routes to `GameState`:
  - `{"type":"move","team":"Red","brigade_id":"…","target_hex":"…","mode":"tactical"}`
  - `{"type":"commit","team":"Green","brigade_id":"…","target_hex":"…"}`
  - `{"type":"end_turn","seed":1234}` — seed required for reproducibility

**Validation gate** (`tools/validate_llm_api.gd`): auto-picked up by `run_all_tests.ps1`;
asserts observation keys, legal moves exposed, examples parse/apply, missing seeds rejected.

**One-shot tools:**

```powershell
# Run LLM API validation
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/validate_llm_api.gd"

# Export an observation fixture (Red turn 1)
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/export_llm_observation.gd" -- --team=Red --output="reports/llm_observation_red.json"

# Full headless turn validation (move → combat → reset, seeded)
"C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/validate_headless_turn.gd"

# Screenshot (windowed session only — not --headless)
"C:\Godot_v4.7-stable_win64.exe" --path "C:\Users\mdogg\Desktop\HexCombat" -s "res://tools/capture_screenshot.gd" -- --output="reports/current.png"
```

New phases must not break the JSON observation contract. When a phase adds new state (supply pool,
ship reserve, anti-ship systems), extend `get_observation()` with that state so LLM agents and
headless validation scripts can read it.

See `docs/LLM_PLAYTESTING.md`, `docs/LLM_OBSERVATION_SCHEMA.md`, and
`docs/LLM_AGENT_PROTOCOL_PLAN.md` for the full design.

## Guardrails

- Preserve ported combat math exactly (formulas, dice, clamps, FEBA, casualty ordering,
  `combat_detail` shape) unless a rebalance is explicitly requested by the user; record every
  deliberate divergence in PLAN.md → Decisions (HexCombat is the design of record).
- Adapting a TIV-lineage mechanic? Read the TIV source and its `tests/python/` cases first.
- Refactors keep the golden invariant **byte-stable**; re-baselines are user-aware change-control
  events (`.claude/skills/hexcombat-change-control`).
- **Git: only the primary (orchestrating) agent commits.** Subagents/auxiliary tools leave
  changes for it to verify and commit.
- `.mcp.json` is intentionally modified locally (machine-specific Godot path) — never commit it.
