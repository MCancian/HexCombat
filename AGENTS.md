# AGENTS.md — HexCombat Agent Guide

Canonical rules for **every** agent working in this repo (Claude, pi/GPT-5.5, and any other).
Read this first. Claude-specific orchestration material lives in `CLAUDE.md`.

## Project

Godot 4.7 / GDScript hex-grid wargame, ported from the **BOOTS** (Boots On The Ground)
ground-combat phase of **TaiwanInvasionViewer** (`C:\Users\mdogg\TaiwanInvasionViewer`), a
Python/Flask simulation. Long-term goal: bring the other phases of that sim — joint/air-missile
fires ("IJFS"), anti-ship & mine warfare, amphibious offload/logistics, supply consumption,
front-line tracking — into the same Godot game.

The source logic is ~1:1 portable to GDScript. **Before writing new game logic, check
TaiwanInvasionViewer for an existing implementation and its `tests/python/` cases** — those
tests are the behavioral oracle for the port.

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
# headless smoke test (expect 455 hexes / 111 brigades / 455 cells, zero errors)
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
- **Fail loud, not silent** — unknown/missing data → `push_warning`/`push_error`, never a silent
  default fallback.
- Pure logic = `static func` in `RefCounted` libs; runtime state = autoloads; visuals = view
  layer. Don't leak screen/pixel concerns into the model.

## Documentation map

- `AGENTS.md` (this file) — shared rules, canonical.
- `CLAUDE.md` — orchestrator role + how to use pi (Claude-only).
- `ROADMAP.md` — long-term, sequenced milestones with acceptance criteria + forward-compat notes.
- `PLAN.md` — the active milestone in detail + an append-only **Decisions** log + open questions.
- `docs/ARCHITECTURE.md` — deeper design / rationale; per-phase notes under `docs/phases/`.

## Guardrails

- Preserve ported combat math exactly (formulas, dice, clamps, FEBA, casualty ordering,
  `combat_detail` shape) unless a rebalance is explicitly requested.
- Check TaiwanInvasionViewer before writing new logic.
- **Git: only the orchestrator commits** (see `CLAUDE.md`). Other agents leave changes for the
  orchestrator to verify and commit.
- `.mcp.json` is intentionally modified locally (machine-specific Godot path) — never commit it.
