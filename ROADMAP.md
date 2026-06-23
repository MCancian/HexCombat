# HexCombat Roadmap

Long-term, sequenced view so the orchestrator designs each step forward-compatibly. `PLAN.md`
holds the active milestone in detail. Read both each loop iteration.

## Vision

A playable Godot wargame that reproduces TaiwanInvasionViewer's phases as interconnected,
data-driven, independently testable modules. BOOTS (ground combat) is the proving ground for the
**per-phase template**: typed model + pure logic lib + `GameData`/`GameState` wiring + view +
validation/golden tests. Every later phase copies that template.

## Forward-compatibility principles (apply to every milestone)

- **Phases are modules.** Each phase = its own pure logic lib + typed model + tests, sharing
  `GameData`/`HexMath`. Keep them decoupled so they build and test independently.
- **Extensible enums/state.** The turn/phase state machine must accept new phases later (Fires,
  Naval, Offload, Logistics) without rework.
- **Data-driven content.** Forces, scenarios, terrain, OOBs come from `data/*.json` + typed
  Resources — adding content is a data change, not a code change.
- **Deterministic core.** All randomness flows through an injectable seeded RNG so any phase is
  reproducible and golden-testable.
- **Event bus, not reach-through.** Cross-module communication via signals.

---

## Milestone 0 — Test & verification infrastructure  *(prerequisite for everything)*

- Install GdUnit4 into `addons/`; confirm headless CLI runs and returns exit codes.
- Add a seedable RNG/dice abstraction; refactor `CombatCalculator` to take it (global `randi()`
  removed from pure logic). **Preserve the math** — same formulas, just an injectable source.
- Author `tools/run_all_tests.ps1` (import → smoke → `tools/` validation → GdUnit4; nonzero on
  any failure).
- Add the first **golden combat test** with a fixed seed, matched against
  `tests/python/unit/test_hex_combat_phase4.py`.
- **Acceptance:** `run_all_tests.ps1` is green; combat is reproducible under a fixed seed.

## Vertical slice — BOOTS playable (Milestones 1–7)

### M1 — Unit placement + rendering
- Define `data/scenario_default.json` (a small starting layout — a few Red brigades on/near beach
  hexes from `beaches.json`, some Green defenders inland; **not** all 111). Render brigades as
  markers on their hexes with team/type styling.
- *Forward-compat:* scenario format should generalize to other forces and future phases.
- **Acceptance:** windowed run shows the scenario's brigades on the correct hexes; a validation
  script asserts scenario load + placement integrity.

### M2 — Selection + event bus
- Minimal signal bus; clicking selects a hex/brigade and emits signals; an info panel shows hex +
  brigade details. Decouple controller / UI / view.
- **Acceptance:** selecting updates the panel; GdUnit4 input-sim test covers select → signal.

### M3 — Turn/phase state machine (`GameState` autoload)
- Turn number, active side, phase enum (Movement → Combat → End), end-turn resets per-turn flags.
  UI shows turn/phase.
- *Forward-compat:* phase enum + transitions must be extensible for later phases.
- **Acceptance:** end-turn advances state correctly; unit test covers transitions + flag resets.

### M4 — Movement
- Movement phase: select brigade → highlight reachable hexes (`HexMath.find_reachable`, with a
  movement allowance) → click destination → move via `GameData.set_brigade_hex`, mark
  `moved_this_turn`, re-render.
- **Acceptance:** reachable-set test vs. known grid; move respects allowance and blocks re-move.

### M5 — Combat wiring
- Combat phase: attacker hex + adjacent enemy hex → `Brigade.to_combat_units()` →
  `CombatCalculator.resolve_map_attack` → apply casualties (mark destroyed), shift FEBA / update
  hex ownership + colors, show result in UI, mark `fought_this_turn`.
- **Acceptance:** golden combat test (seeded) for the applied outcome; ownership/FEBA update
  validated.

### M6 — Terrain modifier
- Port terrain classification so `defender_terrain_modifier` is real, not always 1.0.
- **Acceptance:** terrain lookup test; combat uses the correct modifier.

### M7 — Slice completion
- Full `run_all_tests.ps1` green; **Definition of done** (see `PLAN.md`) met; slice summarized
  for the user.

---

## Post-slice (future tracks — do NOT start until the slice is done)

### Track C — Engine & architecture hardening
- Save/load via Godot resource serialization.
- Scenario loading + victory conditions (generalize `scenario_default.json`).
- Camera fit/zoom/pan; selection/hover/info-panel polish.

### Track D — Other phases (each: model + pure logic + validation + GdUnit4 + UI, mirroring source pytest)
- **Amphibious offload / beaches** — `beaches.json`, `offload/`, `setup_prelanding_service`.
  Natural next phase (lands ground forces). Mirrors offload tests.
- **Red DOS supply** — `red_dos_consumption`/`extraction`; feeds `supply_effectiveness`.
- **Anti-ship & mine warfare** — `antiship_*`, `mine_warfare_service`.
- **Joint/air-missile fires (IJFS)** — largest: targeting, detection, ISR, strike
  probability/resolution, air OOB.
- **Front-line / cleanup** — `front_line_service`, `cleanup_hex_service`.
