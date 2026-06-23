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
- **Headless-drivable actions.** Gameplay flows through a view-independent command/resolution
  layer (e.g. `MoveBrigade`, `ResolveCombat`). The human UI, AI agents, and the future B2
  auto-resolve mode all emit the *same* actions; rendering/input never own game state. This is
  what makes AI-vs-AI play and deterministic headless tests possible.
- **Brigade is the atomic unit.** Battalions are brigade attributes, never separately positioned.
- **Scenario-parameterized.** Turn length, stacking caps, and similar tunables come from the
  scenario, not hard-coded.
- **Organization tracked early.** Brigades carry an organization value adjusted by movement
  (admin/tactical) and combat from the start; inert until a later milestone wires it into combat.

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

## Vertical slice — BOOTS playable (Milestones MA, 1–7)

### MA — Assets & data import
- Import the NATO unit symbols from TIV `symbols/` (185 SVGs) into the project (e.g.
  `assets/symbols/`); establish a `nato_type` / battalion-type → symbol mapping.
- Import/normalize the **Taiwan (green) OOB** — real ROC ground/marine brigades from
  `docs/reference/Taiwan_2028.oob.json` (and/or `config/taiwan_TOs.json`) into HexCombat's
  `Brigade` schema (e.g. `data/roc_ground_forces.json`); extend `GameData` to load both OOBs.
- **Acceptance:** symbols import and render in a test scene; green brigades load (count > 0); a
  validation script asserts both OOBs parse into typed `Brigade`s with resolvable types.

### M1 — Unit placement + rendering
- Define `data/scenario_default.json`: 4 Red + 4 Green brigades around beaches 1–4 (one Red
  amphibious brigade on each beach hex, one Green marine/amphibious brigade on an adjacent inland
  hex). Red from the PLA OOB, Green from the imported Taiwan OOB (MA). Render brigades as markers
  using the imported **unit symbols**, colored by team — **not** all 111.
- *Rendering:* offset each brigade toward the hex side its force entered from (Red = entry/landing
  side, Green = opposite), clustered per side without precise per-unit spacing.
- *Forward-compat:* scenario format should generalize to other forces and future phases.
- **Acceptance:** windowed run shows the scenario's brigades on the correct hexes/sides; a
  validation script asserts scenario load + placement integrity.

### M2 — Selection + event bus
- Minimal signal bus; clicking selects a hex/brigade and emits signals; an info panel shows hex +
  brigade details. Decouple controller / UI / view.
- **Acceptance:** selecting updates the panel; GdUnit4 input-sim test covers select → signal.

### M3 — Turn model & state (`GameState` autoload) — **WeGo**
- Both sides plan a turn of orders; orders resolve **simultaneously**. `GameState` tracks turn
  number, per-side order buffers, and phase (Planning → Resolution → End). Turn length is a
  scenario parameter (default 1 day). Resolution is **move-then-fight**: all movement applies
  first, then every hex with both sides present fights.
- *Forward-compat:* the resolver is the single place simultaneous orders are applied — reused by
  AI and B2 auto-resolve; turn structure stays extensible for later phases.
- **Acceptance:** a planned turn resolves deterministically (seeded); unit tests cover order
  collection, resolution ordering, and per-turn flag resets.

### M4 — Movement
- Two modes: **tactical** (mech/armor/tank 2 hexes, else 1; may fight the same turn) and
  **administrative** (~10 hexes leg infantry, ~20 mechanized; may **not** attack after). Select
  brigade → choose mode → highlight reachable hexes (`HexMath.find_reachable`) → move via
  `GameData.set_brigade_hex`, mark `moved_this_turn`, re-render.
- Apply **organization** costs via `Brigade.adjust_organization` (admin −100, tactical −25) —
  tracked, inert for now.
- **Acceptance:** reachable-set test vs. known grid; move respects allowance and blocks re-move.

### M5 — Combat wiring
- Combat is **continuous**: every hex with both sides present resolves a round each turn (1 day),
  FEBA accumulating across turns, so reinforcements arriving later join the unfolding battle. Each
  turn a side commits supporting forces and maneuver units to its ongoing/assaulted hexes via a
  **composition menu** (target hex contributes all units; adjacent hexes contribute committed
  maneuver/artillery; support assets feed the support dicts).
- Resolution: `Brigade.to_combat_units()` + support counts → `CombatCalculator.resolve_map_attack`
  → apply casualties (mark destroyed), shift FEBA / update hex ownership + colors, show result,
  mark `fought_this_turn`. Perform it **through the action layer** so AI / auto-resolve can run
  the same attack headlessly.
- Post-combat: engaged maneuver units advance **into** the target hex; ownership is by
  **occupancy** (both sides → contested; one side → that side; empty → last owner); on defeat with
  FEBA exceeding the loser's hex share, survivors **retreat** to an adjacent uncontested owned hex;
  attackers do not break through beyond the hex.
- **Acceptance:** golden combat test (seeded); occupancy-ownership and defeat/retreat validated;
  the same attack reproducible via a headless action call (no UI).

### M6 — Headless turn check (AI-readiness)
- Verify a full WeGo turn (orders → resolution) runs through the action layer with **no UI** — a
  headless script plans moves/attacks for both sides and resolves deterministically. Foundation
  for AI-vs-AI and B2.
- **Acceptance:** headless script plays a scripted turn end-to-end, asserted against expected
  state; included in `run_all_tests.ps1`.
- *(Terrain is deferred — TIV has no terrain data; it becomes a later ArcGIS-sourced phase.)*

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
- **Terrain (ArcGIS)** — per-hex terrain classification sourced via ArcGIS, feeding the combat
  terrain modifier (TIV has no terrain data of its own).

### Track E — Modes & AI
- **B2 intent/auto-resolve mode:** high-level orders; the engine auto-deploys and resolves fronts
  (the source's automated behavior) atop the same action layer, with optional player intervention.
- **Headless AI-vs-AI:** agents drive the action API with no view; full games run headless for
  testing, balancing, and the autonomous orchestrator.
