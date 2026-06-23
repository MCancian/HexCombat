# PLAN.md — Active Work

The orchestrator works this file top-down each loop iteration. See `ROADMAP.md` for the long
view and `AGENTS.md` for the rules. Status: `[ ]` todo · `[~]` in progress · `[x]` done ·
`[!]` blocked (see Open Questions).

## Current milestone: M0 — Test & verification infrastructure

- [ ] Install GdUnit4 into `addons/`; confirm headless CLI runs with exit codes.
- [ ] Add a seedable RNG/dice abstraction; refactor `CombatCalculator` to accept it (remove
      global `randi()` from pure logic). Preserve all math.
- [ ] Author `tools/run_all_tests.ps1` (import → smoke → `tools/` validation → GdUnit4; nonzero
      on any failure).
- [ ] Add first golden combat test (fixed seed) matched to
      `TaiwanInvasionViewer/tests/python/unit/test_hex_combat_phase4.py`.
- [ ] Acceptance: `run_all_tests.ps1` green; combat reproducible under a fixed seed.

## Upcoming (detail when reached — see ROADMAP for acceptance criteria)

- [ ] M1 — Unit placement + rendering (`data/scenario_default.json`, brigade markers)
- [ ] M2 — Selection + event bus + info panel
- [ ] M3 — Turn/phase state machine (`GameState` autoload)
- [ ] M4 — Movement (reachable highlight, allowance)
- [ ] M5 — Combat wiring (apply casualties, FEBA, ownership)
- [ ] M6 — Terrain modifier port
- [ ] M7 — Slice completion + Definition of done

## Definition of done (vertical slice)

Windowed run: brigades visible; select one in Movement phase and move within range; switch to
Combat phase, attack an adjacent enemy hex, see casualties applied and the front/ownership shift;
ending the turn advances state. `tools/run_all_tests.ps1` green (smoke + validation + GdUnit4,
including seeded golden combat and movement-reachability tests).

## Decisions log (append-only; record every autonomous choice here)

- **2026-06-23 — Testing:** GdUnit4 adopted *additively* alongside the existing `tools/`
  validation scripts (not a replacement). GdUnit4 for unit/scene/input/UI/integration; custom
  scripts for data-contract/smoke/port-equivalence. Seed/inject RNG before golden tests.
  Canonical gate: `tools/run_all_tests.ps1`.
- **2026-06-23 — Visual verification:** delegated to **pi** via the Godot MCP (richer runtime
  context); the orchestrator relies on headless logs + validation scripts. No golden-image
  diffing for now.
- **2026-06-23 — Docs:** lightweight. `AGENTS.md` canonical + thin `CLAUDE.md`; decisions logged
  here in PLAN.md; single `docs/ARCHITECTURE.md`; no separate ADR folder.
- **2026-06-23 — Git autonomy:** orchestrator auto-commits work that passes its gates; pushes at
  milestones; never commits `.mcp.json`.
- **2026-06-23 — First objective:** vertical slice making BOOTS playable, after M0 test infra.

## Open questions for the user (resolve before/at the relevant milestone)

- [ ] **M1 unit placement:** the OOB has no `hex_id` and null lat/lon. Default to a small
      hand-placed scenario (a few Red brigades near beach hexes, some Green inland)? How many
      units in the starter scenario?
- [ ] **M4 movement allowance:** hexes per brigade per turn — fixed value, or per unit type?
      (Source repo may define this — check `boots_hex_service` first.)
- [ ] **Victory / end condition:** needed for a "playable" loop, or is end-turn enough for the
      slice?
