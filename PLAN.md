# PLAN.md — Active Work

The orchestrator works this file top-down each loop iteration. See `ROADMAP.md` for the long
view and `AGENTS.md` for the rules. Status: `[ ]` todo · `[~]` in progress · `[x]` done ·
`[!]` blocked (see Open Questions).

## M0 — Test & verification infrastructure  ✓ *(complete 2026-06-23)*

- [x] Install GdUnit4 into `addons/`; confirm headless CLI runs with exit codes.
- [x] Add a seedable RNG/dice abstraction; refactor `CombatCalculator` to accept it (remove
      global `randi()` from pure logic). Preserve all math.
- [x] Author `tools/run_all_tests.ps1` (import → smoke → `tools/` validation → GdUnit4; nonzero
      on any failure).
- [x] Add first golden combat test (fixed seed) matched to the source combat oracle
      (`TaiwanInvasionViewer` `boots_calculator.resolve_map_attack`).
- [x] Acceptance: `run_all_tests.ps1` green; combat reproducible under a fixed seed. **M0 DONE.**

## MA — Assets & data import  ✓ *(complete 2026-06-23)*

Scoped 2026-06-23 (sources located; see Decisions). Two independent sub-units; do the OOB first
(headless-testable), then symbols (needs pi's visual check).

**MA-1 — Green (ROC) OOB import** ✓ *(complete 2026-06-23)*
- [x] Normalize the **32 Green ROC brigades** from TIV `defaults/unit_hierarchy.json` into
      `data/roc_ground_forces.json` (same shape as `pla_ground_forces.json`). Includes the 3 Marine
      brigades BDE-66/77/99 (`nato_type:"amphibious"`) for M1's Green defender.
- [x] Extend `UnitStats.TYPE_DEFS` for the 3 missing green types (`Armor Battalion`, `Tank
      Battalion` = 2.0; `Infantry Battalion (Reserve)` = 0.5) — all 12 green types now resolve
      without fallback warnings.
- [x] Extend `GameData` to load BOTH OOBs (PLA + ROC) into typed `Brigade`s (143 total).
- [x] Validation script `tools/validate_oob_data.gd`: counts (111/32/143), teams, brigade
      contracts, all battalion types known. Gate green.

**MA-2 — Unit symbols import**
- [x] *(MA-2a)* Import the 185 NATO SVGs from TIV `symbols/` → `assets/symbols/` (+ `.import`).
- [x] *(MA-2a)* `data/nato_symbol_map.json` maps all 11 OOB nato_types to symbol files; adding a
      force type stays a data change. `tools/validate_symbol_map.gd` asserts each loads as Texture2D.
- [x] *(MA-2b)* `SymbolLibrary` loader (nato_type → `Texture2D`, fail loud on unknown) +
      `scenes/SymbolPreview.tscn`; pi rendered it and confirmed all 11 symbols display.
- [x] Acceptance: symbols render in a test scene (pi visual check). **MA COMPLETE 2026-06-23.**

## M1 — Unit placement + rendering  ✓ *(complete 2026-06-23)*

**M1a — Scenario authoring + loading** ✓ *(complete 2026-06-23)*
- [x] `data/scenario_default.json`: 4 PLA amphibious brigades on beach hexes 1-4 + 4 ROC brigades on
      the adjacent inland neighbors, each with an `offset_bearing`. Beach→hex by nearest center;
      inland = real HexMath neighbor matching the beach's advance bearing.
- [x] `Brigade.entry_bearing`; `GameData.load_scenario()` places the 8 brigades at startup (fail-loud).
- [x] `tools/validate_scenario_data.gd` (counts, brigade/team/hex integrity, beach adjacency) +
      `tests/scenario_loader_test.gd`. Gate green.

**M1b — Brigade marker rendering** ✓ *(complete 2026-06-23)*
- [x] `HexMap.render_brigade_markers()` draws the 8 placed brigades: team-colored backing + NATO
      symbol (by `nato_type`), nudged toward `entry_bearing`. Unplaced brigades don't render.
      Redraw-capable for M4. Headless guard "Rendered 8 brigade markers" added to the gate.
- [x] Acceptance: pi visually confirmed 8 markers on the correct hexes/sides, team-distinguishable.
      **M1 COMPLETE 2026-06-23.** (Known cosmetic: topmost markers clip at the viewport edge —
      camera fit deferred to Track C.)

## Upcoming (detail when reached — see ROADMAP for acceptance criteria)

- [ ] M1 — Unit placement + rendering (`data/scenario_default.json`, brigade markers)
- [x] M2 — Selection + event bus + info panel ✓ *(complete 2026-06-23)* — `EventBus` autoload
      (`hex_selected`/`brigade_selected`/`selection_cleared`); `GameController` emits on click;
      `HexMap` highlights via the bus; `InfoPanel` shows hex+brigade details; `selection_test.gd`
      covers select→signal. Gate: 5 validators + 8 GdUnit4 tests.
- [x] M3 — Turn/phase state machine (`GameState` autoload) ✓ *(complete 2026-06-23)* — WeGo action
      API: `Phase{PLANNING,RESOLUTION,END}`, per-team `MoveOrder` buffers, `add_move_order`
      (fail-loud), `resolve_turn` (move-then-fight; combat = M5 hook; detects `last_contested_hexes`),
      `begin_next_turn` (flag/buffer/turn resets). `EventBus.turn_resolved`/`phase_changed`. Gate:
      5 validators + 12 GdUnit4 tests.
- [x] M4 — Movement (reachable highlight, allowance) ✓ *(complete 2026-06-24)*
  - [x] **M4a**: `Movement.gd` (fast-mobility per TIV oracle; tactical 2/1, admin 20/10);
        `GameState.add_move_order` enforces mode + allowance (`find_reachable`) + blocks re-move;
        `_apply_move_orders` applies org costs (admin −100 / tactical −25) + admin flag.
  - [x] **M4b**: select brigade → mode (Tactical/Administrative) → `HexMap` highlights the reachable
        set → click reachable hex issues a `MoveOrder` → **End Turn** resolves + advances + re-renders
        markers. `movement_ui_test.gd`. Gate: 5 validators + 20 GdUnit4 tests. pi visually confirmed.
- [x] M5 — Combat wiring (apply casualties, FEBA, ownership) ✓ *(complete 2026-06-24)*
  - [x] **M5a** *(2026-06-24)*: continuous combat in `GameState.resolve_turn(dice)` — each contested
        hex runs the ported `resolve_map_attack` (Red attacker / Green defender; `CombatForces`
        maneuver/support split; admin-moved & destroyed excluded), applies casualties (battalion
        decrement → brigade destroy/remove), accumulates FEBA, sets `fought_this_turn`, then
        `recompute_hex_ownership` (occupancy). Seeded determinism. `combat_resolution_test.gd`
        (25 tests total). Gate green.
  - [x] **M5b** *(2026-06-24)*: post-combat retreat (`FEBA_RETREAT_THRESHOLD_KM`=10; FEBA-losing
        side retreats to a valid adjacent hex, feba resets; encircled holds; advance implicit),
        `HexOwner` constants, `combat_resolved` result summary, `HexMap.refresh_all_hex_colors` on
        `turn_advanced`. `combat_retreat_test.gd` (29 tests total). Gate green. **M5 acceptance met.**
  - [x] **M5c** *(2026-06-24)*: composition — `CommitOrder` + `GameState.add_commit_order` /
        `eligible_commit_brigades` / `_combat_contributors_for` (in-hex + committed adjacent, deduped;
        combat gated on presence-contested hexes); `CompositionPanel` UI + `commit_brigade`.
        `composition_test.gd` (33 tests total). Gate green.
- [x] M6 — Headless turn check (AI-readiness) ✓ *(complete 2026-06-24)* — `tools/validate_headless_turn.gd`
      drives a full WeGo turn (move → resolve → combat → reset) through the action layer with NO view,
      asserts the end state + two-run determinism (seed 20260624 → casualties=2, feba=0.76). In the gate.
- [x] M7 — Slice completion + Definition of done ✓ *(complete 2026-06-24)* — full
      `tools/run_all_tests.ps1` green (import + smoke + 6 validators + 33 GdUnit4 tests, incl. seeded
      golden combat + movement-reachability + headless full-turn). Interactive DoD loop proven via
      `scene_runner` tests driving the real `Main.tscn` controller; live windowed launch clean (8
      markers, no errors). Slice DONE.
      - *(2026-06-24 post-slice)* **Screenshot self-verification now works:** `tools/capture_screenshot.gd`
        renders `Main.tscn` to a PNG under a display/windowed session, so the agent can capture and
        inspect the live view directly (the old "screenshot API fails" caveat no longer holds).
      - *(2026-06-24 post-slice)* **Map rendering fix:** `MapProjection` now uses a uniform,
        `cos(mean_lat)`-corrected scale fit to the viewport with a centered margin (was independent
        per-axis scaling → ~2.75× horizontal stretch: flat/wide hexes, off-screen northern markers);
        brigade markers sized from the per-hex radius instead of hardcoded 82×58 px. Verified via a
        captured screenshot (Taiwan reads as a tall island; 8 hex-sized markers fully on-screen).

## Definition of done (vertical slice) — ✅ MET 2026-06-24

Windowed run: brigades visible; select one in Movement phase and move within range; switch to
Combat phase, attack an adjacent enemy hex, see casualties applied and the front/ownership shift;
ending the turn advances state. `tools/run_all_tests.ps1` green (smoke + validation + GdUnit4,
including seeded golden combat and movement-reachability tests).

**Status:** `tools/run_all_tests.ps1` GREEN (import + smoke + 6 `validate_*.gd` + 33 GdUnit4 tests).
The interactive loop (select → move → End Turn → combat → casualties → front/ownership shift → turn
advances) is verified by `scene_runner` tests that drive the real `Main.tscn` `GameController`
(`movement_ui_test`, `selection_test`, `composition_test`, `combat_*`), plus per-feature visual
confirmation in M1b (markers) and M5b (ownership colors). Live windowed launch is clean (8 markers,
no errors). Screenshot self-verification via `tools/capture_screenshot.gd` now works (display/windowed
session), so the agent can eyeball the live view directly; the earlier "can't screenshot in-harness"
caveat is resolved.

## Decisions log (append-only; record every autonomous choice here)

- **2026-06-26 — D4 pure-lib wave (D4-B/C/D/E) ported via pi, all gated + committed:** Dispatched the
  four dependency-independent IJFS pure libs as self-contained pi briefs, verified each with the full
  gate, committed individually (gate green throughout; ground-combat golden seed 20260624 → casualties=2
  feba=0.76 unchanged; GdUnit4 grew 81 → 210 cases). **Note for future agents:** the TIV source tree is
  nested one level deeper than AGENTS.md states — `C:\Users\mdogg\TaiwanInvasionViewer\TaiwanInvasionViewer\src\ijfs_standalone\`.
  Faithful-port divergences taken (all in-spirit of AGENTS.md, RNG order/formulas preserved):
  (1) **Tuple→Dictionary returns:** Python functions returning tuples (`select_munition*`,
  `_select_from_ordered_pairings`, detection passes) return `Dictionary` with stable source-parallel keys
  (`selected`/`reason`/`doctrine_name`/`selection`, `detected_ids`/`log`) so D4-G/H can build ledgers.
  (2) **`_wildcard` type-guard (IjfsStrike):** GDScript `bool == ""` raises (Python tolerates it), so
  wildcard checks short-circuit on type before string compare — required for bool match keys like
  `intel_locked`. (3) **Fail-loud firing-capacity keys:** `FiringCapacityBudget`/`OrganicStrikeBudget`
  push_error on a config entry missing `firing_units`/`sorties_per_unit_per_day` instead of the source's
  silent `.get(...,0)` default (per AGENTS.md fail-loud; shipped scenario data carries both keys).
  (4) **Shared `ScriptedDice`:** all IJFS GdUnit suites reuse `tests/helpers/ScriptedDice.gd` (global
  `class_name`; scripted `randf()` draws are its 3rd ctor arg) — never a local `class ScriptedDice`
  (class_name collision = parse error). RNG mapping: Python `rng.random()`→`dice.randf()`,
  `rng.sample(c,k)`→`dice.choose_indices(c.size(),k)`. Next: D4-F (SEAD/AD-health/warmup) → D4-G
  (daily orchestration) → D4-H (GameState wiring), which are sequential (each consumes the prior).

- **2026-06-25 — D4/D3 build kickoff + Wave 0 foundations complete:** Resolved the paused D3
  questions (see "D3 — Open Questions → Decision"): build **D4 (IJFS) first**, both **full faithful
  ports**, D3 inputs from **scenario/config defaults** (no UI), build **orchestrated/phased via pi**.
  Wave 0 (shared foundations, all committed, gate green) done: **D0-A** Dice/RNG extensions
  (`randf`/`weighted_choice`/`weighted_choices`/`shuffle_indices`/`derive` substreams on
  Dice/SeededDice/ScriptedDice; `validate_no_global_rng.gd` now skips `func ` definition lines so the
  abstraction can define its own `randf()`); **D0-B** Theater/TO model (`data/theaters.json` +
  `Theaters.gd` from TIV `contracts/theater.py`; validator cross-checks beach `to_number`); **D0-C**
  ship-type model (`data/ships.json` 27 entries, `ShipDef`/`ShipState`/`IndividualShip`; replaced the
  inert `ShipFleet` stub with a typed `GameState.fleet`; added the `pending_lost_at_sea` /
  `register_ship_losses` seam — **reporting only**, BN-removal deferred to D3-F so offload golden is
  byte-stable). Combat golden unchanged throughout (seed 20260624 → casualties=2, feba=0.76). Full
  sub-task breakdown in the approved plan file `~/.claude/plans/where-we-left-we-gentle-parnas.md`.

- **2026-06-24 — D2-C/D supply wiring decisions:** (1) **Unit selection:** supply consumption
  counts the FULL current composition of every Red brigade that is on-map (`hex_id` set) and not
  destroyed — the HexCombat analogue of TIV's `active_red_battalion_records` (Team=Red,
  Destroyed=0, Status=landed). The ship_reserve trickle is NOT separately excluded: a brigade
  consumes (and fights) at full composition the moment it is on-map (consistent with the D1-E
  decision); casualties already shrink composition, so destroyed BNs stop consuming. (2)
  **Deduction model:** deduct the FULL `red_dos_consumed_tons` from the single pool each turn,
  clamped at 0 — HexCombat does NOT model TIV's net-delta-vs-offload-baseline (no separate offload
  supply deduction in this slice). (3) **Ordering:** `resolve_supply_turn()` runs at the END of
  `resolve_turn` resolution (after combat/FEBA/ownership, before the flags reset in
  `begin_next_turn`) so `moved_this_turn`/`fought_this_turn` reflect the turn's activity. (4)
  **Effectiveness deferred:** supply exhaustion is tracked but does not yet modify combat (the
  `supply_effectiveness` combat input stays 1.0; wiring deferred to D4 IJFS).
- **2026-06-24 — D2 supply-turn tests live in a headless validator, not GdUnit:** a GdUnit
  `supply_turn_test` reliably triggered a Godot 4.7 **teardown heap-corruption** (process exit
  `-1073740940` / 0xC0000374) ONLY when run alongside the other GdUnit suites — it passed in
  isolation, and the identical code passes cleanly in `tools/validate_dos_consumption.gd` (its own
  SceneTree process). Bisected by removing the suite (full `tests/` reliably green 3×). Relocated
  the multi-turn-drain / clamp-at-zero / full-`resolve_turn`-hook assertions into the validator to
  keep full coverage with a reliably green gate. (If future GdUnit suites grow, watch for the same
  shutdown flake; the validator path is the safe home for turn-resolution integration checks.)

- **2026-06-24 — D2 scope = simplified single-pool supply (deliberate divergence from TIV):** TIV's
  supply system is elaborate (`services/supply/`: depots with real-valued `dos_amount`, per-brigade
  pools with organic basic loads `DOS_PER_REGULAR_BN=3` and caps, a ledger, out-of-supply
  effectiveness decay, JSON state IO). HexCombat's D2 ports ONLY the **activity-consumption calc**
  (`red_dos_consumption.py`) against a **single Red DOS pool** (`SupplyState.current_dos_tons`).
  Depots, per-brigade pools, organic loads, OOS surrender, and the ledger are out of scope for the
  slice. `red_dos_start` is given in DOS in the scenario (100) and stored as tons (×TONS_PER_DOS).
- **2026-06-24 — D2-B ports the implementation, not the test docstrings:** `_compute_unit_tons`
  uses **integer floor division** `base // 3` (300//3=100, 150//3=50). The pytest
  `TestNonDivisibleBaseRates` docstrings mention `round()` (half-up), but the actual TIV code uses
  `//`; the asserted values (151→101, 301→201) are identical under floor for these inputs, so the
  GDScript port uses `@warning_ignore("integer_division") base / 3` (floor) to match the real code.
  `activity_delta_rounded` uses `ceil` (positive up, negative toward zero) per the source.
  `by_brigade` `moved`/`in_combat` are per-brigade (all units of a brigade share the flag), so
  setting them at first-unit time equals the source's OR-accumulate.

- **2026-06-24 — D1-E partial-landing / map-token model:** a brigade's GameData map token appears
  on its `beach_hex` as soon as its FIRST BN lands (Day 1 = its 4 maneuver Amphibious Infantry
  BNs). `ship_reserve` tracks the per-BN trickle: each offload turn, landed BNs are removed from
  their entry's `bns`; the entry (brigade) leaves `ship_reserve` only when `bns` is empty (the 5
  support BNs land on Day 2+, throughput-gated by beach capacity). The brigade fights at its FULL
  OOB composition from the moment it is on-map — support-BN trickle is offload bookkeeping only;
  gating combat strength by landed-BN count is a deferred refinement (consistent with "brigade is
  the atomic unit; full supply assumed for the slice"). Not a blocking design question — the TIV
  oracle distributes BNs along a front line (no single brigade token), already a settled HexCombat
  divergence; "token appears when maneuver forces are ashore" is the in-spirit call.
- **2026-06-24 — D1-E offload hooked at start of RESOLUTION:** `resolve_turn` calls
  `resolve_offload_turn(dice)` before `_apply_move_orders`, so on Turn 1 Red lands during
  resolution and is first orderable on Turn 2 (no Red orders possible the turn it lands — Red is at
  sea during that turn's PLANNING). Turn 1 produces no combat (beach hexes are not co-located with
  the Green inland hexes). The headless-turn validator provisions Red with a real
  `resolve_offload_turn` call in setup (Red lands on hex_44_16) then runs the existing
  single-turn scripted move/combat; offload consumes no RNG so the golden values are unchanged.

- **2026-06-24 — D1-D ship-reserve rosters derived from OOB (single source of truth):** the
  scenario `red_ship_reserve` carries only `{brigade_id, locked_beach, beach_hex, offset_bearing}`;
  it does NOT duplicate battalion rosters (which live only in `pla_ground_forces.json`).
  `GameState._rebuild_ship_reserve()` expands each brigade's OOB `composition` into the
  `bns:[{id,type}]` list `OffloadCalculator.resolve_offload_day()` expects (bn id =
  `"<brigade_id>-<type_slug>-<n>"`, n 1-based across the brigade). `beach_hex`/`offset_bearing`
  preserve each brigade's former placement so D1-E knows the landing hex + seaward render offset.
  `ship_fleet` holds one forward-compat `ShipFleet` (amphibious_transport) sized to the reserve.
- **2026-06-24 — D1-D test fixtures self-provision Red:** since Red is no longer auto-placed by the
  scenario, tests/validators that drive a Red brigade place it themselves via
  `GameData.set_brigade_hex(RED_ID, START_HEX)` in setup (durable for movement/combat/selection
  unit tests; `validate_headless_turn.gd` + `validate_llm_api.gd` carry a note that D1-E replaces
  their manual placement with a real offload pass). Composition/combat tests were untouched — they
  build synthetic `TEST-RED-*` brigades and never depended on scenario Red placement. Headless
  full-turn golden values are unchanged (seed 20260624 → casualties=2, feba=0.76).

- **2026-06-24 — D1 scenario rework (user decision: full offload start):** Red starts at sea.
  All 4 PLA amphibious brigades move from beach hex placements to `GameState.ship_reserve` in
  `scenario_default.json`. Day 1 runs `resolve_offload_day(1, …)` → maneuver BNs land (4×4=16);
  support BNs wait. Calibrated for 4 beaches × 2 slots = 8 slots → all 4 brigades land Day 1.
  Smoke marker changes from 8 → 4 brigade markers at startup. Headless full-turn validator needs
  a turn-0 offload pass before the scripted move/fight sequence. Existing Red-on-beach test
  fixtures need updating after D1-D is committed.

- **2026-06-24 — D1-C OffloadCalculator Day 1 behavior (Day 1 redesign, deliberate scope):**
  Ported the "Day 1 redesign" behavior from `test_offload_day1_redesign.py` (not the
  older `test_offload_brigade_priority.py` behavior which tested pre-redesign support-BN
  blocking). On Day 1: ALL BNs count as "sent"; maneuver BNs bypass throughput and land
  (brigade-slot limited); support BNs wait. Ship state machine (ready/offloading/returning),
  civilian vs. military ship type restrictions, port/airbridge infrastructure, JLSF/DOS
  capacity — all deferred (no ship type model yet; those behaviors flow from anti-ship phase).
  Brigade slots = `floor(offload_rate / TONS_PER_BN)` per beach (matches TIV test math
  exactly with flat TONS_PER_BN, no amphib discount needed at this stage).

- **2026-06-24 — D1-A beaches.json normalization:** Rewrote the existing `data/beaches.json`
  (raw TIV PascalCase object dict format) into a clean snake_case array format matching our
  GDScript conventions. Stripped minefield data (deferred to anti-ship phase). Values (rates,
  coords, capacities) ported exactly from TIV `defaults/beaches.json`.

- **2026-06-24 — Movement mobility: nato_type only (deliberate divergence from the TIV oracle):**
  `Movement.is_fast_mobility` now classifies a brigade fast/slow from its **brigade `nato_type`
  only**, ignoring battalion composition. The TIV oracle
  (`boots_hex_service.infer_green_brigade_speed`) also promotes a brigade to fast if *any* battalion
  type string contains a `FAST_MOBILITY_HINTS` token ("mechanized"/"armor"/"tank"); that string
  matches "Mechanized **Artillery** Battalion" (77× across the OOBs), so leg/amphibious brigades were
  fast purely from a support battalion. **User chose to diverge** (2026-06-24) so support units don't
  change march speed. The amphibious scenario brigade is now slow (1-hex tactical / 10-hex admin).
  `movement_test.gd` updated (asserts nato_type-only + a leg-with-mech-artillery-stays-slow case);
  the headless full-turn validator is unaffected (its scripted move is to an adjacent hex, reachable
  for slow units). Surfaced via the click-through playtest.

- **2026-06-23 — M1 starter scenario placement (resolved a gap):** beaches 1-4 (TIV
  `defaults/beaches.json`, all TO 3 Northern) map by nearest hex center to hex_44_16/44_15/43_14/43_13;
  each Green inland hex = the real HexMath neighbor of the beach hex whose bearing best matches the
  beach's `Advance_Direction` → hex_43_17/43_15/42_15/42_14 (all unique, all adjacent). **Green
  defenders:** only **3 Marine brigades exist** (BDE-66/77/99, all southern), so beaches 1-3 get the
  marines and **beach 4 gets BDE-269 (269th Mechanized Infantry)** — the nearest northern green
  maneuver brigade. Scenario placement overrides each brigade's OOB garrison location (a contrived
  starter beachhead). **Red:** PLA-71-2 / 72-5 / 73-14 / 74-1 Amphibious (one per group army).
  `offset_bearing`: Red = seaward (advance+180), Green = bearing toward its beach hex. Not a blocking
  question — resolved in-spirit of the settled design.
- **2026-06-24 — M5 combat wiring sub-decisions (derived from settled design; not blocking):**
  (1) **Attacker/defender roles:** at a contested hex Red = attacker, Green = defender (the
  amphibious-grind framing; defender takes the terrain modifier, =1.0 for the slice). (2)
  **Maneuver vs support split:** a brigade's battalions tagged `artillery` or `rotary_wing` feed the
  **support dicts** (rocket→`rocket_artillery`, other artillery→`artillery`, rotary→`rotary_wing`;
  theater `cas`/`crbm`=0), and the **maneuver unit list** is the brigade's *non-support* battalions —
  so artillery isn't double-counted (it's support, never a maneuver casualty; consistent with
  `resolve_map_attack` never selecting artillery). (3) **Admin-moved brigades contribute nothing to
  combat** that turn (neither attack nor support — they road-marched) but still occupy the hex for
  ownership; combat at a hex only resolves if BOTH sides have ≥1 non-admin brigade. (4) **Casualty
  application:** each casualty unit decrements its battalion's qty by 1; a battalion at qty 0 is
  removed; a brigade at 0 battalions is marked destroyed and removed from the map. (5) **Ownership**
  recomputed by occupancy after all combats (both→contested, one→that side, empty→keep last owner).
  Retreat/advance + composition menu + colors/result = M5b.
- **2026-06-23 — MA-2 / symbols done:** copied all 185 NATO SVGs → `assets/symbols/`; mapped the 11
  OOB nato_types in `data/nato_symbol_map.json` (air-defense→air_defence, amphibious→amphibious_infantry,
  area-command→headquarters, armor→armour, artillery→artillery, aviation→helicopters, infantry→infantry,
  mech-infantry→mechanized_infantry_tracked, motorized-infantry→motorized_infantry, reserve→light_infantry,
  special-forces→sof). `SymbolLibrary` (RefCounted, cached, fail-loud) resolves nato_type→Texture2D;
  `validate_symbol_map.gd` + a GdUnit4 test gate load-correctness. pi visually confirmed all 11 render.
  **MA complete.** (MCP wasn't exposed to pi this run — it used a direct windowed run; headless
  texture-load checks corroborate.)
- **2026-06-23 — MA-1 done:** `data/roc_ground_forces.json` (32 Green brigades) generated by the
  orchestrator via a deterministic transform of `unit_hierarchy.json` (not LLM transcription); pi
  did the GDScript (UnitStats +3 types, GameData dual-OOB load, `validate_oob_data.gd`, 111→143
  smoke marker). Total on-map brigades now **143**. pi's "OOB contract JSON" machine-readability
  idea deferred (see `docs/REFACTOR_NOTES.md`). **Note:** background `pi` runs have twice exited
  silently (empty log, no edits) when launched right before the turn ended — run pi in the
  **foreground** (proven reliable) for orchestrated implementation steps.
- **2026-06-23 — MA green-OOB source (resolved a gap):** the Taiwan *OOB* file
  (`docs/reference/Taiwan_2028.oob.json`) holds only **aggregate battalion counts per theater** and
  has no discrete brigades/marines — so it is NOT the import source. The real structured green
  brigades live in TIV `defaults/unit_hierarchy.json`: **32 ROC brigades** (untagged team ⇒ Green per
  TIV's `defaults_builder._load_hierarchy_data`), same schema as `pla_ground_forces.json`, including
  3 Marine brigades (BDE-66/99/77, `nato_type:"amphibious"`) and full lat/lon. MA-1 normalizes those.
  No brigade synthesis and **no user pause needed**. (`config/taiwan_TOs.json` is just theater
  polygons — not used for the OOB.)
- **2026-06-23 — New green battalion types:** of the 12 distinct green battalion types, 9 already
  exist in `UnitStats.TYPE_DEFS`; MA-1 adds `Armor Battalion` and `Tank Battalion` (strength 2.0,
  `armor` tag — matching the existing `Armor`/`Tank` fallback scale and PLA heavy armor) and
  `Infantry Battalion (Reserve)` (reserve infantry, strength below light infantry; source
  `reserve_structure.combat_power` ≈ 0.5). Keeps `UnitStats` the single source of truth (no separate
  green strength table).
- **2026-06-23 — RNG abstraction (M0 item 2):** introduced `Dice` (abstract, `scripts/Dice.gd`)
  with `roll_d100()` + `choose_indices(n,k)`; `SeededDice` (production, seeded Godot RNG,
  deterministic Fisher-Yates — never `Array.shuffle()`); `ScriptedDice` (test double,
  `tests/helpers/`). `CombatCalculator.resolve_map_attack` and the `BOOTSCalculator` wrapper now
  take a **required** `dice: Dice` first arg (no default → fail loud). Combat consumes RNG in a
  fixed order: 3× `roll_d100()` (attacker/defender/feba), then attacker then defender casualty
  selection.
- **2026-06-23 — Casualty-selection port fix:** corrected a divergence from the source — casualties
  are now drawn **only from non-artillery** units, at random; **artillery is never a casualty**
  (zero casualties if no non-artillery eligible, even when a loss was computed). Old GDScript wrongly
  filled with artillery in deterministic order. Also aligned `combat_detail.rolls` key
  `feba_roll` → `feba_movement_roll` to match the source `combat_detail` shape.
- **2026-06-23 — Golden test (M0 item 4):** `tests/combat_golden_test.gd` cross-validates against
  the **live Python oracle** (`boots_calculator.resolve_map_attack`). Types that score identically
  in both strength tables (`Special Forces Battalion`=1.8, `Field Artillery Battalion`=0.8) let the
  GDScript port be asserted against numbers pulled from the Python source for the same scripted
  rolls. (numpy PCG64 isn't reproducible in Godot, so the test injects rolls and verifies the
  *formula*, per the M0 strategy decision.)
- **2026-06-23 — RNG guardrail enforced:** added `tools/validate_no_global_rng.gd` (in the gate) —
  fails if any `scripts/` file calls global `randi/randf/randi_range/randf_range/randomize`
  (instance calls like `_rng.randi_range` allowed). Negative-tested. From pi's machine-readability
  report; other suggestions (unit fixtures, JSON golden format, typed `combat_detail`) deferred in
  `docs/REFACTOR_NOTES.md`.
- **2026-06-23 — GdUnit4 version & layout:** pinned **v6.1.3** (latest; runs on Godot 4.7),
  installed at `addons/gdUnit4/` with the framework's own `test/` self-tests stripped (AssetLib
  package layout, keeps the repo lean). Plugin enabled in `project.godot` `[editor_plugins]`.
  Headless CLI requires `--ignoreHeadlessMode`; exit codes verified (0 pass / 100 fail). `/reports/`
  git-ignored.
- **2026-06-23 — Canonical gate:** `tools/run_all_tests.ps1` resolves the Godot binary from
  `-GodotBin` → `$env:GODOT_BIN` → `C:\Godot_v4.7-stable_win64.exe`. The smoke phase asserts on the
  startup log markers (455 hexes / 111 brigades / 455 cells) + absence of `SCRIPT ERROR`; tracked in
  `docs/REFACTOR_NOTES.md` to replace with a machine-readable startup summary later.
- **2026-06-23 — Golden-test strategy (settled, for M0 item 4):** numpy PCG64 cannot be reproduced
  bit-for-bit in Godot, so golden combat tests inject a **scripted roll sequence** through the new
  RNG abstraction and assert the *formulas* (loss-rate, FEBA, casualty selection) match the source
  `boots_calculator.resolve_map_attack` exactly — decoupled from the PRNG bitstream. Also noted:
  the current GDScript `_select_casualties` **diverges** from source (it makes artillery casualties
  in deterministic order; source selects only non-artillery, randomly, never artillery) — to be
  corrected under M0 item 2 to preserve ported math.
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
- **2026-06-23 — Unit model (B1):** the brigade is the atomic on-map unit. Battalions are tracked
  only as attributes of a brigade (composition, strength, casualties); never individually
  positioned. Manual mode follows approach A (select → move → declare attack) with one addition:
  declaring an attack opens a **combat-composition menu** where *both* sides may add eligible
  supporting forces and other available maneuver units before resolution.
- **2026-06-23 — Future modes (forward-compat now):** a "B2" intent/auto-resolve mode and a
  headless **AI-vs-AI** mode are first-class long-term targets. Therefore all gameplay must flow
  through a **view-independent action/resolution layer** — no game logic in the UI — so the human
  UI, AI agents, and auto-resolve all drive the same headless-testable logic.
- **2026-06-23 — Brigade in-hex rendering:** brigades render offset toward the hex side their
  force entered from (Red = entry/landing side, Green = opposite). Brigades on the same side
  cluster/stack without precise per-unit spacing; show a count if crowded.
- **2026-06-23 — Movement modes:** two modes. **Tactical** (short; may fight the same turn) —
  per-type per source `infer_green_brigade_speed`: mechanized/armor/tank 2 hexes, others 1.
  **Administrative** (long; may **not** attack at the end of the move): ~10 hexes leg infantry,
  ~20 mechanized.
- **2026-06-23 — Organization track (codified now, inert):** every brigade carries an
  `organization` value 0–100 (starts 100). Costs: **admin move −100**, **tactical move −25**,
  **−10 per turn in combat**. **Recovery: +10 per turn** on any turn the brigade neither moves nor
  fights. Does not affect anything yet; will feed combat later. Constants + `adjust_organization()`
  live on `Brigade`.
- **2026-06-23 — Victory:** deferred for the slice; end-turn advancing state is sufficient.
  Revisit with scenarios in Track C.
- **2026-06-23 — Turn model: WeGo.** Both sides plan a full turn of orders; orders resolve
  **simultaneously**. The action layer *collects* per-side orders (moves, attack declarations +
  composition) and a deterministic resolver applies them together. (Open: simultaneous-resolution
  ordering — see Open Questions.)
- **2026-06-23 — Turn length:** 1 turn = 1 day by default, **set per scenario** (future scenarios
  may vary it).
- **2026-06-23 — Information:** full information now; tag all state by owner and read through an
  indirection so per-side fog of war can be added later without reworking the action API.
- **2026-06-23 — Attacks:** both sides may attack; a unit may move *and* attack in the same turn
  (each once).
- **2026-06-23 — Stacking:** soft cap per side per hex, configurable in the scenario, and
  **advisory for the slice** — over-stacking is allowed (it only guides AI/UI); enforcement and any
  penalty are revisited when organization/supply start to bite.
- **2026-06-23 — Hex ownership = occupancy:** a hex is **contested** while both sides have units
  in it; with one side present it is that side's; when empty it keeps its **last** owner.
- **2026-06-23 — Post-combat movement:** engaged maneuver units advance **into** the target hex if
  not already there (brigades have no within-hex position). If a side is defeated and FEBA movement
  exceeds its share of the hex, that side's survivors **retreat** to an adjacent uncontested hex
  their side owns. Attackers do **not** advance beyond the one hex (no breakthrough).
- **2026-06-23 — Casualties:** remove battalions; brigade removed at last battalion. Future
  "reorganization" may merge weakened brigades' battalions into ad-hoc battlegroups; for now
  battalions stay with their parent brigade until destroyed.
- **2026-06-23 — Terrain deferred:** TIV has no terrain data. Drop terrain from the slice (combat
  terrain modifier stays 1.0); add it later as its own phase sourced from **ArcGIS**.
- **2026-06-23 — Supply / arrival deferred:** assume full supply; all scenario forces on-map at
  start (see Starter scenario).
- **2026-06-23 — Resolution order: move-then-fight (A).** Each WeGo turn, all movement resolves
  first; then every hex with both sides present resolves a combat round. Two forces moving into the
  same hex meet and fight. There is no targeted "attack that can fizzle" — combat happens wherever
  forces are co-located after movement.
- **2026-06-23 — Combat is continuous (amphibious grind).** A contested hex is an *ongoing*
  engagement: it resolves a round each turn (1 day), FEBA accumulates across turns, and units
  arriving on later turns join the unfolding battle. Player agency each turn = movement (reinforce
  or withdraw) + committing support/maneuver units; not one-shot battles.
- **2026-06-23 — FEBA retreat threshold:** cumulative FEBA reaching the full hex depth (~10 km,
  the grid side-to-side) pushes the defeated side's survivors out to an adjacent uncontested owned
  hex.
- **2026-06-23 — Starter scenario (M1):** 4 Red + 4 Green brigades around beaches 1–4 — one Red
  amphibious brigade on each beach hex (entry side seaward), one Green marine/amphibious brigade on
  an adjacent inland hex (entry side toward the coast). Red from the PLA OOB; **Green from the real
  Taiwan OOB** (imported in milestone MA). The loop maps each beach's lat/lon to its hex and picks
  an inland neighbor.
- **2026-06-23 — Unit symbols:** use the NATO-style SVGs in TIV `symbols/` (185 icons at
  `C:\TaiwanInvasionViewer\…\symbols\`) for brigade icons, mapped from `nato_type` / battalion
  types. Imported in milestone MA.
- **2026-06-23 — Green (Taiwan) OOB:** real green units exist in TIV
  (`docs/reference/Taiwan_2028.oob.json`, `config/taiwan_TOs.json`). Import/normalize the Taiwan
  ground/marine brigades into HexCombat's `Brigade` schema (milestone MA); `GameData` loads both
  OOBs.
- **2026-06-23 — Entry-side tracking:** the scenario sets each brigade's initial side; on a move the
  new side = the edge crossed into the destination hex. Used only for the rendering offset.
- **2026-06-23 — Combat support source (slice):** support comes only from **organic brigade
  artillery** (count artillery/rocket/rotary battalions in the committed brigades → support dicts).
  Theater CAS/CRBM stays 0 until the fires (IJFS) phase.

---

## Track D, Phase 1 — Amphibious Offload (D1)  *(scoped 2026-06-24)*

**Goal**: Port TIV's beach offload mechanism into HexCombat as a per-turn offload phase that
models Red reinforcement brigades arriving from sea to beach hexes via beach throughput limits,
brigade priority ordering, and the maneuver-first Day 1 landing rule.

**TIV source oracle**:
- Logic: `src/services/offload/beach_throughput.py`, `src/services/offload/_rates.py`,
  `src/services/offload_calculator.py`, `src/contracts/units.py`
- Tests: `tests/python/unit/test_offload_day1_redesign.py`,
  `tests/python/unit/test_offload_brigade_priority.py`,
  `tests/python/unit/test_offload_brigade_spacing.py`

**Architecture** (per-phase template):
- `scripts/model/BeachDef.gd` — typed Resource: id, name_en, offload_rate_tons, capacity_bns,
  to_number, floating_piers, jackup_barge, advance_direction_deg, lat, lng
- `scripts/OffloadRates.gd` — const class: all 9 rate keys (beach_base=4400,
  floating_pier=2200, jackup_barge=4400, operational_port=11000, etc.), TONS_PER_BN=2200
- `scripts/OffloadCalculator.gd` — pure RefCounted lib (no Node): beach throughput
  calculation (tons → BN slots), brigade-priority greedy admission, Day 1 maneuver-bypass rule,
  battalion manifest (sent/landed/waiting/lost formula), `bns_waiting = bns_sent - bns_landed - lost_at_sea`
- `data/beaches.json` — ported from TIV `defaults/beaches.json` (9 beaches, exact rates/TO/coords)
- `data/offload_rates.json` — ported from TIV `defaults/offload_rates.json` (9 rate keys)
- `GameData` extended: `load_beaches()` → `Dictionary` keyed by beach id (int)
- `GameState` extended: `ShipReserve` (Red brigades/BNs at sea, not yet on map),
  `resolve_offload_turn(dice)` → applies landing manifest → `GameData.set_brigade_hex()` for
  newly-fully-landed brigades

**Sub-tasks**:

- [x] **D1-A** *(2026-06-24)* — Beach data + model: `data/beaches.json` (9 beaches, exact TIV
      values, snake_case array format), `scripts/model/BeachDef.gd`, `GameData.load_beaches()`,
      `tools/validate_beaches_data.gd` (asserts 9 beaches, all TO/rate/coord fields present).
      Gate green (import + smoke + 7 validators + 33 GdUnit4 tests all pass).

- [x] **D1-B** *(2026-06-24)* — Offload rates: `data/offload_rates.json` (9 keys, exact TIV
      values), `scripts/OffloadRates.gd` (typed const class: TONS_PER_BN=2200, BEACH_BASE=4400,
      FLOATING_PIER=2200, JACKUP_BARGE=4400, PORT/AIRBRIDGE rates; REQUIRED_RATE_KEYS list).
      `tools/validate_offload_data.gd` asserts all 9 keys present in JSON and constants match
      JSON values. Gate green.

- [x] **D1-C** *(2026-06-24)* — `scripts/OffloadCalculator.gd` pure RefCounted lib — ports
      Day 1 redesign behavior from TIV: `beach_capacity_bns()` (rate/TONS_PER_BN per beach);
      `resolve_offload_day()` with Day 1 assault (maneuver bypass, brigade slots) and Day 2+
      (throughput-gated, greedy priority). `tests/offload_calculator_test.gd`: 21 tests all
      passing, mirroring TIV pytests: all 36 BNs sent; 16 maneuver land Day 1; 20 waiting;
      bypass holds at low throughput; locked-beach respected; brigades don't split beaches;
      Day 2 support lands up to throughput. Full gate green (8 validators + 54 GdUnit4 tests).

- [x] **D1-D** *(2026-06-24)* — Ship fleet model + scenario rework:
      - `scripts/model/ShipFleet.gd` typed Resource (ship_type, ready, offloading, returning,
        destroyed, carrying_capacity_bns).
      - `data/scenario_default.json`: removed the 4 Red placements; added `red_ship_reserve` array
        ({brigade_id, locked_beach, beach_hex, offset_bearing} — rosters stay in the OOB, not
        duplicated). Green defenders unchanged.
      - `GameData.red_ship_reserve` parsed fail-loud; Red no longer placed at startup.
        `GameState.ship_reserve` (OffloadCalculator-ready, bns expanded from OOB composition),
        `ship_fleet`, `ship_reserve_priority_order()`. Smoke marker 8→4;
        `validate_scenario_data` reworked (4 Green + reserve checks, beach_hex↔Green adjacency
        preserved). Tests/validators driving Red self-provision it via `set_brigade_hex`.
      - Gate green (import + smoke 4-markers + 8 validators + 54 GdUnit4). Orchestrator visual:
        captured `reports/d1d_startup.png` → 4 Green markers, 0 Red, no errors. (pi's Godot MCP
        not exposed this run; orchestrator used `capture_screenshot.gd` instead.)

- [x] **D1-E** *(2026-06-24)* — GameState offload wiring:
      - `GameState.resolve_offload_turn(dice)` runs `OffloadCalculator.resolve_offload_day(
        turn_number, beach_capacity, ship_reserve, priority_order)`; lands BNs per the manifest;
        places each brigade on its `beach_hex` the turn its first BN comes ashore. `ship_reserve`
        tracks the per-BN trickle (landed BNs removed from the entry; entry leaves the reserve only
        when fully ashore — support BNs land on later days, throughput-gated). Emits
        `EventBus.offload_resolved(manifest)`; `recompute_hex_ownership()` after landing.
      - Hooked at the start of RESOLUTION in `resolve_turn()` (before move-then-fight). Offload
        consumes no RNG → combat determinism unchanged (golden seed 20260624 → casualties=2,
        feba=0.76 preserved).
      - `tools/validate_headless_offload.gd` (in the gate): Turn 1 lands 16 maneuver BNs (4
        brigades on their exact beach hexes, appear in `GameData.brigades`), 20 waiting; Turn 2
        support BNs begin landing (throughput-limited).
      - `validate_headless_turn.gd` / `validate_llm_api.gd` now provision Red via a real
        `resolve_offload_turn` pass (replaced the D1-D `set_brigade_hex` stub).
      - `LLMGameAPI.observation` gains a `ship_reserve` block; schema + regenerated `red_turn1`
        example kept in sync (turn-1 example correctly lists the 4 reserve brigades, 9 BNs each).
      - Orchestrator visual: `reports/d1e_after_turn1.png` → after Turn 1, 4 Green + 4 Red markers
        on-map (Red on beach hexes), status "Turn 1 resolved: 0 combat(s)". Gate green (import +
        smoke + 9 validators + 54 GdUnit4).

- [x] **D1-F** *(2026-06-24)* — Full gate green: import + smoke (4-marker startup) + 9
      `validate_*.gd` + 54 GdUnit4 tests all pass. Post-Turn-1 8-marker outcome (4 Green + 4 Red on
      beaches) is covered by `validate_headless_offload.gd` (exact-beach-hex asserts) + the
      `movement_ui` scene_runner test (`Rendered 8 brigade markers`) + the captured screenshot.
      **D1 (Amphibious Offload) milestone complete — pushed.**

---

---

## Track D, Phase 2 — Red DOS Supply (D2)  *(COMPLETE 2026-06-24 — D2-A…D done)*

**Goal**: Port TIV's activity-aware Red supply consumption into HexCombat. Each turn, landed Red
battalions consume DOS (Days of Supply) based on mechanization, movement, and combat activity. The
supply pool decrements; exhaustion degrades combat effectiveness.

**TIV source oracle**:
- Logic: `src/services/red_dos_consumption.py` (`calculate_red_dos_consumption`,
  `is_mechanized_red_unit`, `_compute_unit_tons`), `src/services/red_dos_extraction.py`
- Supply pool/tracker: `src/services/supply_repo.py` (or `src/services/supply/`)
- Tests: `tests/python/unit/test_red_dos_consumption.py`, `test_dos_tracker.py`,
  `test_supply_state.py`, `test_supply_repo.py`, `test_supply_offload_day.py`

**Key constants** (from TIV):
- BASE_MECHANIZED_TONS = 300, BASE_NON_MECHANIZED_TONS = 150, TONS_PER_DOS = 150
- Consumption formula: `tons = base - (base//3 if not moved) - (base//3 if not in_combat)`
- Mechanized whitelist: Combined Arms, Mechanized Infantry, Mechanized Artillery, Tank,
  Amphibious Infantry battalions
- `moved_brigade_ids` and `engaged_brigade_ids` come from turn flags already on `GameState`

**Sub-tasks** (scope from TIV oracle before writing):

- [x] **D2-A** *(2026-06-24, with D2-B)* — Supply data + model: `scripts/model/SupplyState.gd`
      (typed Resource: `current_dos_tons: float`, `day_history: Array[Dictionary]`); added
      `red_dos_start: 100` to `data/scenario_default.json`; `GameData.red_dos_start` parsed
      (push_warning if ≤0); `GameState.supply_state` rebuilt in `reset_to_scenario` at
      `red_dos_start * TONS_PER_DOS` (15000 tons). Inert until D2-C deducts.

- [x] **D2-B** *(2026-06-24)* — `scripts/DosConsumption.gd` pure RefCounted lib: `is_mechanized_bn`
      (whitelist-first + substring/brigade-type fallbacks), `compute_unit_tons` (base − base//3 per
      inactive flag, integer floor division), `calculate_consumption` → summary dict mirroring
      TIV's `RedDosConsumptionSummary` (counts, tons, dos-equivalent, activity delta with `ceil`
      rounding + residual, `by_brigade`). `tests/dos_consumption_test.gd`: 15 cases mirroring
      `test_red_dos_consumption.py`. Gate green (69 GdUnit4 cases; golden combat unchanged).

- [x] **D2-C** *(2026-06-24, with D2-D)* — GameState wiring: `resolve_supply_turn()` runs
      `DosConsumption.calculate_consumption` on the full current composition of every on-map,
      non-destroyed Red brigade (activity from `moved_this_turn`/`fought_this_turn`), deducts the
      full `red_dos_consumed_tons` from `supply_state.current_dos_tons` (clamped at 0), appends a
      `day_history` entry, emits `EventBus.supply_updated`. `LLMGameAPI.observation` gains a
      `supply_state` block (schema + example synced). `tools/validate_dos_consumption.gd`: idle
      (36 BNs, 20 mech/16 non-mech, 2800 tons, 15000→12200), activity (all moved → 5600),
      multi-turn drain, clamp-at-zero, full-`resolve_turn` hook.

- [x] **D2-D** *(2026-06-24)* — Hooked `resolve_supply_turn()` into `resolve_turn` at
      end-of-resolution (after combat/FEBA/ownership, before END) so activity flags are accurate.
      Multi-turn drain verified in the validator. Combat-effectiveness modifier from supply
      exhaustion is TRACKED but deferred to D4 (combat `supply_effectiveness` stays 1.0). Gate
      green (3×): import + smoke + 10 validators + 69 GdUnit4; golden combat unchanged. **D2
      (Red DOS Supply) complete — pushed.**

---

## Track D, Phase 3 — Anti-ship & Mine Warfare (D3)  *(not yet started)*

**Goal**: Port TIV's anti-ship phase — Green missile/weapon systems fire at Red ships crossing
to beaches; minefields activate; ship losses propagate to BN `lost_at_sea` count in the offload
manifest.

**TIV source oracle**:
- `src/services/antiship_calculator.py` — top-level resolver (`AntishipResults`)
- `src/services/antiship_crossing.py` — `resolve_crossing_damage(crossing_result, rng)`
- `src/services/antiship_firing_plan.py` — `build_firing_plan(systems, ships, targets)`
- `src/services/antiship_launch_attrition.py`, `src/services/antiship_inventory_service.py`,
  `src/services/antiship_suppression_service.py`, `src/services/antiship_magazine_service.py`
- `src/services/antiship/mine_warfare_service.py`, `src/services/beach_minefield_support.py`
- `src/contracts/antiship.py` — shared dataclasses (`LaunchAttritionSummaryRow`, etc.)
- Tests: `test_antiship_calculator.py`, `test_antiship_crossing.py`,
  `test_antiship_firing_plan.py`, `test_antiship_mine_warfare_service.py`,
  `test_antiship_magazine_service.py`, `test_antiship_suppression.py`

**Sub-tasks** (scope from TIV oracle before writing):

- [ ] **D3-A** — Data + models: `data/ships.json` (Red ship types with capacity/count from TIV
      defaults), `data/antiship_systems.json` (Green weapon systems from TIV defaults);
      `scripts/model/ShipState.gd`, `scripts/model/AntishipSystem.gd`,
      `scripts/model/Minefield.gd`. `tools/validate_antiship_data.gd`. Gate green.

- [ ] **D3-B** — `scripts/AntishipCalculator.gd` — pure lib: `build_firing_plan()`,
      `resolve_crossing_damage()`, `apply_magazine_expenditure()`. Mirror TIV unit tests
      (`tests/antiship_calculator_test.gd`). Gate green.

- [ ] **D3-C** — Mine warfare: `scripts/MineWarfareService.gd` — `resolve_minefield()`,
      lay/sweep/activate logic. Mirror `test_antiship_mine_warfare_service.py`. Gate green.

- [ ] **D3-D** — GameState wiring: `GameState.resolve_antiship_turn(dice)` runs calculator,
      applies ship losses, propagates `lost_at_sea` back to the offload reserve (D1-E's
      manifest). Suppressed systems flag carried into next turn. `tools/validate_headless_antiship.gd`.
      Gate green.

### D3 — Open Questions  *(RESOLVED 2026-06-25 — see decision below)*

**Decision (2026-06-25, user):** (Q1 order) **D4 (IJFS) first, then D3** — so D3's firing plan
consumes real IJFS destroyed/suppressed anti-ship systems instead of a stub. (Q2 fidelity) **Full
faithful port of D3** — the 7-stage missile-crossing model + mine warfare + magazines + suppression
+ 28-ship roster + munition catalog. (Q3 ship depth) **Full 28-type ship roster** (implied by Q2;
replaces the inert `ShipFleet` stub and wires `lost_at_sea`). (D4 fidelity) **Full standalone-engine
port** of `ijfs_standalone` (all 6 phases). (D3 inputs) firing-% + minesweeper assignments come from
**scenario/config defaults** via the headless action layer — **no new UI** this phase (Track C).
**Build structure:** orchestrated, phased — each sub-task is a self-contained model+lib+tests unit
handed to a `pi` subagent, gated and committed independently; dependency-independent sub-tasks in a
wave run as concurrent `pi` sessions. Full sub-task breakdown (Wave 0 foundations D0-A/B/C; D4-A…H;
D3-A…F) lives in the approved plan file
`C:\Users\mdogg\.claude\plans\where-we-left-we-gentle-parnas.md`. The D3-A…D and D4-scope stubs above
are superseded by that breakdown.

<details><summary>Original scoping rationale (kept for the record)</summary>

Scoping read of the TIV anti-ship oracle (`antiship_calculator.py` 28KB, `antiship_crossing.py`
41KB, firing_plan/launch_attrition/magazine/suppression/mutation services, `mine_warfare_service.py`,
`contracts/antiship.py`, and the `defaults/` catalogs) shows D3 is **by far the largest, most
DB/pandas-centric, player-input-driven phase**, and it does not stand alone:

- **Full multi-stage missile model.** Crossing = launch attrition (per-system detect/destroy/
  intercept-before-launch) → missiles in groups of 4 → escort interception (CG/DDG/FFG/FFL,
  attempts × success_prob) → decoy discrimination → weighted homing by `target_value` → terminal
  defense (`base + susceptibility + capability`) → hit → neutralization (sink vs damage by ship
  `vulnerability` × munition `lethality`, damaged-hull multiplier). Plus a munition combat catalog,
  finite magazines, and suppression carry-over.
- **28-ship-type model + munition catalog** (`ship_types_definition.json`,
  `antiship_combat_catalog.json`, `antiship_crossing_config.json`) — HexCombat has **no ship-type
  model** (D1 deliberately deferred it; `ShipFleet` is an inert stub and `ship_reserve` carries BNs
  directly, no ships).
- **Coupled to D4 (IJFS).** `build_firing_plan(available_systems, ijfs_results, …)` consumes IJFS
  strike outputs (which anti-ship systems were destroyed) and suppression comes from IJFS hits.
  Building D3 before D4 means stubbing that coupling.
- **Player-input-driven.** Firing percentages per (location, system type) and minesweeper
  assignments are human inputs — no auto-policy exists; HexCombat would need new UI or an AI policy.
- **Only consumer in the current slice** is offload `lost_at_sea` (today hard-coded 0), which only
  reduces landed BNs — modest gameplay payoff for a very large build.

**Questions for the user (not answerable from the source — it has a full impl; the call is how much
of it fits HexCombat's simplified-slice philosophy, à la the D2 single-pool decision):**

1. **D3 vs D4 ordering.** The ROADMAP lists D3 before D4, but the source has D3 depend on D4's
   outputs (IJFS-destroyed/suppressed systems). Do D4 (IJFS) first, then D3? Or keep D3 first with a
   stubbed/zero IJFS-suppression input?
2. **D3 fidelity.** Full faithful port of the multi-stage pipeline + 28-ship model + munition
   catalog + magazines + suppression + mine warfare (multi-week, ≥6 sub-tasks)? A **simplified
   fleet-attrition slice** (abstract Green anti-ship strength vs Red crossing fleet → expected ship
   losses → `lost_at_sea`, single pure lib + minimal ship abstraction, mirroring the D2 approach)?
   Or **defer D3** until the ground slice needs it?
3. **Ship model depth.** Full 28-type ship roster with carrying-capacity-equiv and per-type
   profiles, or a minimal fleet abstraction (total carrying capacity → BN-equiv lost)?

**Recommendation:** simplified fleet-attrition slice (Q2) AND reorder so D4/IJFS precedes a fuller
D3 (Q1) — but this is the user's call; awaiting direction before any D3 coding.
*(User overrode the simplified recommendation: chose full faithful for both — see Decision above.)*

</details>

---

## Track D, Phase 4 — IJFS (D4)  *(in progress — pure-lib wave done; engine/wiring next)*

**Goal**: Port TIV's Joint/Air-Missile Fires phase. ISR → detection → targeting → fires
allocation → strike probability → hit/miss. Provides theater CAS/CRBM for combat (currently 0)
and suppresses anti-ship systems (feeding D3).

**Sub-task status** (full breakdown in the approved plan
`~/.claude/plans/where-we-left-we-gentle-parnas.md`; dep graph
D4-A → {B,C,D,E} → F → G → H):
- [x] **D4-A** *(committed prior session)* — data layer (8 ijfs_config JSONs → `data/ijfs/`),
      typed models (`scripts/model/ijfs/`), `IjfsLoaders.gd`, `validate_ijfs_data.gd`.
- [x] **D4-B** *(2026-06-26)* — `scripts/ijfs/IjfsDetection.gd`: 7 ISR degradation curves
      (`isr_sources.py`) + two-pass satellite/aircraft detection (`detection.py`) incl. inline
      antiship-exposure multiplier. Sorted-by-id iteration preserves `dice.randf()` order. Tests mirror
      the detection oracle cases.
- [x] **D4-C** *(2026-06-26)* — `scripts/ijfs/IjfsTargeting.gd`: `targets_to_attack`, pairing/doctrine
      match, `select_munition_with_doctrine` (priority/fallback + reason codes), phase filter,
      `target_release_eligible`, munition filter, posture override, `apply_exquisite_intel`
      (decay fraction via `IjfsDetection.evaluate_isr_source`; C2 exclusion; deterministic/random).
- [x] **D4-D** *(2026-06-26)* — `scripts/ijfs/IjfsStrike.gd`: add-then-multiply modifier formula
      (`strike_probability.py`) + legacy mobile cap + `resolve_strike` (organic/inorganic inventory,
      destroy-then-conditional-suppress RNG order) (`strike_resolution.py`).
- [x] **D4-E** *(2026-06-26)* — `scripts/ijfs/IjfsFiringCapacity.gd`: `FiringCapacityBudget` (inorganic
      floor budget) + `OrganicStrikeBudget` (aircraft-backed, scaled by surviving strike squadrons,
      platform-kind filter) (`firing_capacity.py`).
- [ ] **D4-F** — SEAD + AD health + warmup (`engagement.py`, `ad_health.py`, `warmup_profiles.py`).
- [ ] **D4-G** — daily orchestration + continuity (`run_daily_ijfs.py` 6-phase sequence → `IjfsEngine.gd`).
- [ ] **D4-H** — `GameState.resolve_ijfs_turn` wiring + writeback (anti-ship destroyed/suppressed per
      (TO,Type) for D3; maneuver casualties; theater CAS/CRBM; `EventBus.ijfs_resolved`; LLM block;
      `validate_headless_ijfs.gd`).

**TIV source oracle** — **read all of these before scoping sub-tasks**:
- `src/ijfs_standalone/` package (self-contained engine):
  - `detection.py`, `targeting.py`, `engagement.py`, `strike_probability.py`,
    `strike_resolution.py`, `firing_capacity.py`, `category_groups.py`, `ad_health.py`,
    `isr_sources.py`, `warmup_profiles.py`, `run_daily_ijfs.py`
- `src/services/ijfs_*.py` — wrappers / writeback services
- `src/services/ijfs_air_oob.py` — air OOB (platforms, daily capacity)
- Tests: `test_ijfs_standalone.py`, `test_ijfs_targets.py`, `test_ijfs_funnel_by_category.py`,
  `test_ijfs_default_targets.py`, `test_ijfs_grouped_targets.py`,
  `test_ijfs_timeline_and_profiles.py`, `test_ijfs_payload_summary_totals.py`,
  `test_ijfs_buried_integration.py`, `test_ijfs_prewarmup_fingerprint.py`

**Pre-scoping note**: Read `src/ijfs_standalone/run_daily_ijfs.py` top-to-bottom first; that is
the authoritative sequencing of ISR → targeting → allocation → strike. Then scope sub-tasks
into the PLAN.md pattern. Expect ≥3 sub-tasks (models, strike engine, GameState wiring).

- [ ] **D4-scope** — Read TIV IJFS oracle; write detailed D4 sub-tasks into this section before
      any coding. Record in Decisions log.

---

## Track D, Phase 5 — Front-line / Cleanup (D5)  *(not yet started)*

**Goal**: Port TIV's front-line distribution and cleanup hex ownership. Player draws a polyline;
Red maneuver BNs redistribute along it. Cleanup phase normalizes ownership after casualties.

**TIV source oracle**:
- `src/services/front_line_service.py` — `find_hexes_for_polyline()`,
  `distribute_battalions_along_line()`, `_interpolate_along_line()`,
  `_polyline_cumulative_lengths()`. Uses `sample_interval_km = 2.0`
- `src/services/cleanup_hex_service.py` — `CleanupHexService.update_hex_ownership()`;
  owner normalization (red/green/contested/none)
- `src/services/cleanup_application_service.py` — orchestrates Cleanup phase
- `src/services/cleanup_calculator.py` — residual attrition / isolation check
- Tests: `test_front_line_service.py`, `test_cleanup_hex_service.py`,
  `test_cleanup_casualty_lifecycle.py`, `test_cleanup_map_manipulation.py`

**Sub-tasks** (scope from TIV oracle before writing):

- [ ] **D5-A** — `scripts/FrontLineService.gd` — pure lib: `polyline_to_hex_sequence(coords,
      hex_lookup)` samples at 2 km intervals; `distribute_bns(bns, hex_sequence)` assigns BNs
      evenly. `tests/frontline_service_test.gd` mirroring `test_front_line_service.py`. Gate green.

- [ ] **D5-B** — UI: HexMap polyline-draw mode — player clicks to add polyline vertices on the
      map; Confirm button commits → `GameState.resolve_frontline_phase(coords, dice)` applies
      `FrontLineService` and calls `GameData.set_brigade_hex()` for moved brigades.
      `tools/validate_frontline.gd` headless scripted polyline test. Gate green.

- [ ] **D5-C** — Cleanup: `GameState.resolve_cleanup_phase()` runs residual attrition + isolated
      unit check + final `recompute_hex_ownership()`. Hook into end-of-turn after combat.
      Gate green.

---

## Open questions (settle at the relevant milestone)

_None blocking the slice — the design is settled. Future-phase questions (supply/organization
interactions, fog of war, terrain via ArcGIS, theater fires) are tracked in `ROADMAP.md`._

### D1 — Amphibious Offload design decision  *(RESOLVED 2026-06-24)*

**Decision: Option 2 — Full offload start.**

Red starts with all 4 PLA amphibious brigades at sea (in `GameState.ship_reserve`); no Red units
are pre-placed on beach hexes in the scenario. Turn 1 runs the offload phase: the Day 1 redesign
behavior (already in `OffloadCalculator`) lands all maneuver BNs (4 brigades × 4 maneuver BNs =
16 BNs) on Turn 1. Support BNs wait and offload on subsequent turns. The scenario is calibrated
so all 4 brigades get beach slots on Day 1 (4 beaches × `floor(4400/2200)` = 2 slots each = 8
total slots; 4 brigades fit easily).

**Implications for D1-D/E**:
- `data/scenario_default.json`: remove Red brigades from their current beach hex placements;
  replace with a `red_ship_reserve` block listing the 4 PLA brigades and their battalion rosters
  at sea. Green defenders remain on their inland hexes unchanged.
- `scripts/model/ShipFleet.gd`: ship_type, ready_count, offloading_count, returning_count,
  destroyed_count, carrying_capacity_bns (enough capacity for the 4 brigades)
- `GameState.ship_reserve`: Array of brigade dicts (brigade_id, locked_beach, bns) — the same
  shape `OffloadCalculator.resolve_offload_day()` already expects
- `GameState.resolve_offload_turn(dice)`: on Turn 1 runs `resolve_offload_day(1, …)`; landed
  brigades get `GameData.set_brigade_hex()` on the beach hex; subsequent turns run day 2+
- Smoke test marker will need updating from "Rendered 8 brigade markers" → "Rendered 4 brigade
  markers" (Red starts at sea; only Green 4 are on map at startup)
- `validate_headless_turn.gd` scripted move may need adjustment (Red has no unit on-map at
  start; validate offload lands ≥1 brigade first, then the existing movement/combat scripted
  sequence)
- Existing tests that expect Red on beach hexes (scenario_loader_test, movement tests) will need
  fixture updates — pi should catch these when running the gate after D1-D
