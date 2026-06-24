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

All phases follow the per-phase template (see AGENTS.md): typed Resource model(s) in
`scripts/model/`, pure RefCounted logic lib, `GameData`/`GameState` wiring, `data/*.json`
content, `tools/validate_*.gd` headless check, and GdUnit4 tests mirroring the TIV pytests.

Before writing any logic, read the TIV source listed below **and** its `tests/python/unit/`
counterparts — those are the behavioral oracle. Preserve ported formulas, constants, and ordering
exactly unless a rebalance is explicitly requested.

---

#### D1 — Amphibious offload / beaches  *(in progress — D1-A/B/C done; D1-D/E blocked on design Q)*

**TIV oracle:**
- `src/services/offload_calculator.py`, `src/services/offload/beach_throughput.py`,
  `src/services/offload/_rates.py` (or `src/services/offload/offload_rates.py`)
- `src/contracts/units.py` (TONS_PER_BN = 2200)
- `defaults/offload_rates.json`, `defaults/beaches.json`
- Tests: `test_offload_day1_redesign.py`, `test_offload_brigade_priority.py`,
  `test_offload_brigade_spacing.py`, `test_offload_calculator_init.py`

**Key behavioral facts (already ported in D1-A/B/C):**
- Day 1 redesign: ALL BNs counted "sent"; maneuver BNs bypass throughput and land (brigade-slot
  limited); support BNs wait on ships. `bns_waiting = bns_sent - bns_landed - lost_at_sea`
- Beach slots = `floor(offload_rate / TONS_PER_BN)` per beach
- TONS_PER_BN = 2200. Maneuver BN types: Combined Arms, Amphibious Infantry, Mechanized Infantry,
  Air Assault Infantry, Special Forces
- `OffloadCalculator.gd` + `OffloadRates.gd` + `BeachDef.gd` + `data/beaches.json` + 
  `data/offload_rates.json` all green; 8 validators + 54 GdUnit4 tests passing

**Remaining (D1-D/E blocked — see PLAN.md Open Questions):**
- `scripts/model/ShipFleet.gd` — ship fleet Resource; `GameState.ship_reserve`
- `GameState.resolve_offload_turn(dice)` — runs OffloadCalculator → `GameData.set_brigade_hex()`
- `tools/validate_headless_offload.gd` — asserts ≥1 brigade lands in a headless offload turn
- **BLOCKER**: must decide whether Red starts at sea or initial brigades stay on beaches

**Acceptance:** headless offload turn drives ≥1 brigade to land on a beach hex; gate green.

---

#### D2 — Red DOS supply

**TIV oracle:**
- `src/services/red_dos_consumption.py` — `calculate_red_dos_consumption()`,
  `is_mechanized_red_unit()`, `_compute_unit_tons(mechanized, moved, in_combat)`
- `src/services/red_dos_extraction.py` — `active_red_battalion_records()` (DF → plain list)
- `src/services/supply/` or `src/services/supply_repo.py` — supply pool / DOS tracker
- Tests: `test_red_dos_consumption.py`, `test_dos_tracker.py`, `test_supply_state.py`,
  `test_supply_repo.py`, `test_supply_offload_day.py`

**Key behavioral facts:**
- BASE_MECHANIZED_TONS = 300, BASE_NON_MECHANIZED_TONS = 150, TONS_PER_DOS = 150
- Activity formula: `tons = base - (base//3 if not moved) - (base//3 if not in_combat)`
- Mechanized whitelist: Combined Arms, Mechanized Infantry, Mechanized Artillery, Tank,
  Amphibious Infantry battalions
- Net delta vs. offload baseline (1 DOS per BN/day at 150 tons)
- Supply pool: real number of DOS; game ends / degrades when DOS exhausted
- `moved_brigade_ids` and `engaged_brigade_ids` come from the turn resolution already tracked
  in `GameState` (`moved_this_turn`, `fought_this_turn`)

**What to build (per-phase template):**
- `scripts/model/SupplyState.gd` — typed Resource: current_dos_tons (float), history Array
- `scripts/DosConsumption.gd` — pure RefCounted lib: `is_mechanized_bn(type)`,
  `compute_unit_tons(mechanized, moved, in_combat)`, `calculate_consumption(units, moved_ids,
  engaged_ids, day)` → summary dict
- `GameState.supply_state` + `resolve_supply_turn()` — calls DosConsumption on all landed Red
  BNs using moved/fought flags from the just-resolved turn; deducts from supply pool
- `data/scenario_default.json` — add `red_dos_start` (initial DOS pool, e.g. 100)
- `tools/validate_dos_consumption.gd` — headless: load scenario + land 4 brigades + resolve
  supply → assert pool decremented correctly (mech vs. non-mech consumed)
- `tests/dos_consumption_test.gd` — mirror `test_red_dos_consumption.py` cases (whitelist
  classify, formula, activity delta, empty-unit edge case)

**Acceptance:** supply pool decremented each turn by activity-aware consumption; `supply_effectiveness` modifier wired to combat (or zeroed pending D4); gate green.

---

#### D3 — Anti-ship & mine warfare

**TIV oracle:**
- `src/services/antiship_calculator.py` — top-level resolver; `AntishipResults` dataclass
- `src/services/antiship_crossing.py` — `resolve_crossing_damage(crossing_result, rng)` —
  damage % → ship losses per type
- `src/services/antiship_firing_plan.py` — `build_firing_plan(systems, ships, targets)` —
  assigns weapon systems to targets
- `src/services/antiship_launch_attrition.py` — launcher attrition/dud rate
- `src/services/antiship_inventory_service.py` — magazine/ammo tracking
- `src/services/antiship_suppression_service.py` — suppression of anti-ship systems
- `src/services/antiship/mine_warfare_service.py` — minefield lay/sweep/activation
- `src/services/beach_minefield_support.py` — minefield integration with beach state
- `defaults/` — ship types, weapon systems, mine densities
- Tests: `test_antiship_calculator.py`, `test_antiship_crossing.py`,
  `test_antiship_firing_plan.py`, `test_antiship_mine_warfare_service.py`,
  `test_antiship_magazine_service.py`, `test_antiship_suppression.py`,
  `test_antiship_inventory_service.py`

**Key behavioral facts:**
- Anti-ship systems fire at crossing ships; hit probability × ship type → damage
- Launch attrition: some % of missiles fail at launch
- Magazine: each anti-ship system has finite ammo; track expended count
- Suppression: systems hit by IJFS are suppressed (reduced effectiveness) for N turns
- Minefields: lay by day, sweep by Green navy, activate against ship crossings
- Ship loss → BN casualty: ships carry BNs; sunk ship → BN `lost_at_sea` (ties into D1)
- This is the most DB-state-heavy TIV phase; for HexCombat, encode state in `GameState`
  resources (no SQLite); use `data/ships.json` + `data/antiship_systems.json`

**What to build (per-phase template):**
- `scripts/model/ShipState.gd`, `scripts/model/AntishipSystem.gd`,
  `scripts/model/Minefield.gd` — typed Resources
- `scripts/AntishipCalculator.gd` — pure lib: `build_firing_plan()`, `resolve_crossing()`,
  `apply_magazine_expenditure()`, `resolve_minefields()`
- `GameState.resolve_antiship_turn(dice)` — runs calculator, applies ship losses,
  propagates BN `lost_at_sea` back to offload manifest
- `tools/validate_antiship_data.gd` — asserts ship/weapon JSON keys present
- `tests/antiship_calculator_test.gd` — mirror key TIV unit tests

**Acceptance:** anti-ship turn resolves; ship losses propagate to BN count; mine state
persists across turns; gate green.

---

#### D4 — Joint/air-missile fires (IJFS)  *(largest phase — scope carefully before coding)*

**TIV oracle:**
- `src/ijfs_standalone/` package — self-contained IJFS engine:
  - `detection.py` — ISR source → detection probabilities per target category
  - `targeting.py` — target priority / assignment
  - `engagement.py` — fires allocation
  - `strike_probability.py` — Pk per weapon/target pair
  - `strike_resolution.py` — hit/miss per strike
  - `firing_capacity.py` — daily fires budget per platform
  - `category_groups.py` — target category taxonomy
  - `ad_health.py` — air-defense health / suppression
  - `isr_sources.py` — ISR platform registry
  - `warmup_profiles.py` — multi-day capability ramp
- `src/services/ijfs_*.py` — wrappers/writeback services
- `src/services/ijfs_air_oob.py` — air OOB (platforms, capacity)
- `defaults/` — weapon systems, target types, detection tables, firing capacity tables
- Tests: `test_ijfs_standalone.py`, `test_ijfs_targets.py`, `test_ijfs_funnel_by_category.py`,
  `test_ijfs_default_targets.py`, `test_ijfs_grouped_targets.py`,
  `test_ijfs_timeline_and_profiles.py`, `test_ijfs_payload_summary_totals.py`

**Key behavioral facts:**
- ISR → detection → targeting → fires allocation → strike Pk → hit/miss resolution
- Multi-day warmup: platform effectiveness ramps over days since deployment
- Air-defense suppression degrades AD health; suppressed systems excluded from D3 firing
- Fires budget is per-platform per-day; greedy allocation across target priority list
- Theater CAS/CRBM (currently 0 in the BOOTS slice) feeds combat support pool

**Scope first, then implement.** Read `ijfs_standalone/run_daily_ijfs.py` top-to-bottom before
writing any GDScript. This phase has the most moving parts; expect to split into ≥3 sub-tasks.

---

#### D5 — Front-line / cleanup

**TIV oracle:**
- `src/services/front_line_service.py` — distribute Red maneuver BNs along a drawn polyline;
  `find_hexes_for_polyline()`, `distribute_battalions_along_line()`,
  `_interpolate_along_line()`, `_polyline_cumulative_lengths()`
- `src/services/cleanup_hex_service.py` — `CleanupHexService.update_hex_ownership()`;
  Owner normalization (red/green/contested/none ↔ DB values)
- `src/services/cleanup_application_service.py` — orchestrates the Cleanup phase
- `src/services/cleanup_calculator.py` — cleanup combat resolution (if any)
- Tests: `test_front_line_service.py`, `test_cleanup_hex_service.py`,
  `test_cleanup_casualty_lifecycle.py`, `test_cleanup_map_manipulation.py`

**Key behavioral facts:**
- Front-line phase: player draws a polyline on the map; the service distributes Red maneuver
  BNs evenly along it (spacing = polyline_length / bn_count km); brigades move to assigned hexes
- Polyline → hex: sample at `sample_interval_km = 2.0`; each sample point → `point_to_hex()`
- In Godot: the polyline input replaces Flask's `POST /frontline`; player clicks to add points
  on the HexMap then confirms; GameState distributes the BNs
- Cleanup hex ownership: same `red/green/contested/last_owner` logic already in M5 (`HexOwner`
  constants, `recompute_hex_ownership()`); `cleanup_hex_service` adds explicit player override
- Cleanup calculator: apply residual combat/attrition; check for isolated units (no supply)

**What to build (per-phase template):**
- `scripts/FrontLineService.gd` — pure lib: `polyline_to_hex_sequence()`, `distribute_bns()`;
  no scene deps; testable with scripted hex grids
- `GameState.resolve_frontline_phase(polyline_coords, dice)` — calls FrontLineService, applies
  BN moves via `GameData.set_brigade_hex()`
- UI: `HexMap` polyline-draw mode (player clicks to add vertices; confirm button commits)
- `tools/validate_frontline.gd` — headless: scripted polyline → assert correct hex sequence
- `tests/frontline_service_test.gd` — mirror `test_front_line_service.py` cases

**Acceptance:** player can draw a polyline, brigades redistribute; ownership updates; gate green.

---

- **Terrain (ArcGIS)** — per-hex terrain classification sourced via ArcGIS, feeding the combat
  terrain modifier (TIV has no terrain data of its own). Deferred; currently terrain modifier = 1.0.

### Track E — Modes & AI
- **B2 intent/auto-resolve mode:** high-level orders; the engine auto-deploys and resolves fronts
  (the source's automated behavior) atop the same action layer, with optional player intervention.
- **Headless AI-vs-AI:** agents drive the action API with no view; full games run headless for
  testing, balancing, and the autonomous orchestrator.
