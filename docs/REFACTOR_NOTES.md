# Refactor Notes (append-only)

Per-iteration log of (a) what shipped and (b) machine-readability refactor suggestions —
from `pi` after it implements, or from the orchestrator on infra-only iterations. High-value,
in-scope suggestions are applied immediately; the rest are deferred with a one-line note.

---

## 2026-06-23 — M0 items 1 & 3: GdUnit4 install + canonical gate (orchestrator, infra-only)

**(a) What shipped**
- Installed GdUnit4 **v6.1.3** into `addons/gdUnit4/` (AssetLib layout; the framework's own
  `test/` self-tests stripped to keep the repo lean). Enabled via `project.godot`
  `[editor_plugins]`.
- Confirmed the headless CLI runner returns correct exit codes: `0` on pass, `100` on failure
  (invoked as `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode
  -a res://tests`). GdUnit4 refuses headless mode without `--ignoreHeadlessMode`.
- Added `tests/smoke_test.gd` (minimal `GdUnitTestSuite` sanity case).
- Authored `tools/run_all_tests.ps1` — the canonical gate: import → smoke (asserts the 455/111/455
  markers + no `SCRIPT ERROR`) → every `tools/validate_*.gd` → GdUnit4 suite; non-zero on any
  failure. Verified green end-to-end.
- Ignored the GdUnit4-generated `/reports/` directory.

**(b) Machine-readability suggestions** — _orchestrator note (no pi implementation this iteration)._
- The smoke phase asserts on **hard-coded human-readable log strings** ("Loaded 455 hexes"). That
  couples the gate to print wording. *Deferred:* when `GameState`/a status surface lands, expose a
  machine-readable startup summary (e.g. a JSON line or a queryable autoload field:
  `{hexes:455, brigades:111, cells:455}`) and assert on that instead of log scraping.
- pi's substantive machine-readability reports begin next iteration (M0 items 2 & 4: seedable RNG
  injection + golden combat test), which is the first pi-implemented logic work.

---

## 2026-06-23 — M0 items 2 & 4: seedable RNG injection + golden combat test (pi-implemented)

**(a) What pi did** (orchestrator-verified: full gate green, 3/3 tests pass)
- New `scripts/Dice.gd` (abstract injectable RNG: `roll_d100()`, `choose_indices(n,k)`),
  `scripts/SeededDice.gd` (production; Godot `RandomNumberGenerator` seeded; deterministic
  partial Fisher-Yates, not `Array.shuffle()`), `tests/helpers/ScriptedDice.gd` (test double).
- `CombatCalculator.resolve_map_attack` now takes a **required** `dice: Dice` first param (fail
  loud — no default); the three `randi()%100+1` rolls became `dice.roll_d100()` in the same order.
- `_select_casualties` rewritten to match the Python source exactly: **non-artillery only**,
  selected at random via `dice.choose_indices`, **artillery never a casualty**, `[]` when no
  eligible. (Corrected a real port divergence — the old code made artillery casualties in
  deterministic order.)
- Aligned `combat_detail.rolls` key `feba_roll` → `feba_movement_roll` to match the source shape.
- `BOOTSCalculator.gd` wrapper forwards the new `dice` param.
- `tests/combat_golden_test.gd`: Scenario A (golden formula, scripted rolls `[70,23,79]`) asserts
  the exact numbers extracted from the live Python `boots_calculator.resolve_map_attack`; Scenario
  B asserts artillery is never selected as a casualty.

**(b) pi's machine-readability suggestions**
1. `CombatFixtures.gd` test helper for building units consistently. — _Deferred (only 2 scenarios
   today; revisit when combat scenarios multiply at M5)._
2. JSON golden-fixture format (scenario + expected rolls/losses/FEBA/casualty IDs). — _Deferred
   (premature; revisit at M5/M6 when golden cases grow)._
3. Headless validation script that scans pure logic for forbidden global `randi(`/`randf(`. —
   **APPLIED:** added `tools/validate_no_global_rng.gd` (regex ignores `.`-prefixed instance calls
   like SeededDice's `_rng.randi_range`; ignores comments). Runs in the gate; negative-tested to
   exit 1 on a planted violation. Enforces the M0 invariant going forward.
4. Make `combat_detail` a typed Resource / centralize its string keys as constants to stop
   Python↔GDScript↔test key drift. — _Deferred (worthwhile; revisit when `combat_detail` is
   consumed by the view/action layer at M5)._

---

## 2026-06-23 — MA-1: Green ROC OOB import (pi-implemented; data file orchestrator-generated)

**(a) What shipped** (orchestrator-verified: full gate green, 143 brigades, 0 offending types)
- `data/roc_ground_forces.json` — 32 Green ROC brigades (incl. 3 Marine brigades BDE-66/77/99),
  generated deterministically by the orchestrator from TIV `defaults/unit_hierarchy.json` (more
  reliable than LLM transcription of 32 brigades).
- `UnitStats.TYPE_DEFS` += `Armor Battalion` (2.0), `Tank Battalion` (2.0), `Infantry Battalion
  (Reserve)` (0.5) — the 3 green battalion types not already present; all now resolve without
  fallback warnings.
- `GameData.load_brigades` refactored to load BOTH OOBs via `OOB_PATHS` + `_load_oob_file` helper
  (fail-loud `push_error` on malformed files); total count print (143).
- `tools/validate_oob_data.gd` — asserts counts (111/32/143), teams (Red/Green), brigade contracts
  (id + composition), and that every battalion type is a known `UnitStats.TYPE_DEFS` entry.
- Smoke marker 111→143 updated in `tools/run_all_tests.ps1` and `AGENTS.md`.

**(b) pi's machine-readability suggestion**
- Single machine-readable OOB contract file (`data/schema/oob_contract.json`) holding expected
  counts, allowed teams, required fields, and OOB paths, read by both `GameData` and
  `validate_oob_data.gd` instead of duplicating literals (111/32/143, "Red"/"Green", paths). —
  _Deferred: the pinned literals in the validator are intentional regression guards and the counts
  are stable through the slice; revisit if OOB content becomes dynamic/scenario-driven (Track C)._

---

## 2026-06-23 — MA-2b: SymbolLibrary + preview scene + render check (pi-implemented)

**(a) What shipped** (orchestrator-verified: full gate green, 5 GdUnit4 tests)
- `scripts/SymbolLibrary.gd` (RefCounted): loads `nato_symbol_map.json`, `texture_for_nato_type()`
  returns a cached `Texture2D`, fail-loud (`push_error`+null) on unmapped/unloadable type. This is
  the resolver M1 brigade rendering will use.
- `scenes/SymbolPreview.tscn` + `scripts/SymbolPreview.gd`: lays out every distinct OOB nato_type
  (symbol + "nato_type — N brigades", counted from both OOBs). Main scene unchanged.
- `tests/symbol_library_test.gd`: all 11 nato_types resolve to non-null Texture2D; unmapped type
  hits the fail-loud path (`assert_error`).
- **Visual check:** pi reported the MCP tools weren't exposed in its harness, so it ran the preview
  scene windowed directly and observed all 11 rows rendering with symbols (no blank boxes; the
  area-command/HQ glyph is visually minimal but present). The headless `validate_symbol_map.gd` +
  the GdUnit4 texture-load test independently corroborate every symbol loads as a Texture2D.

**(b) pi's machine-readability suggestion**
- `tools/dump_symbol_catalog.gd` emitting JSON per nato_type (filename, brigade_count,
  texture_load_ok, texture_size) so symbol coverage is inspectable without a screenshot. — _Deferred:
  nice agent-observability tool; `validate_symbol_map.gd` already gates load-correctness. Revisit if
  symbol coverage needs reporting (e.g. when more force types / phases are added)._

---

## 2026-06-23 — M1a: scenario authoring + loader + placement (data orchestrator-generated, code pi)

**(a) What shipped** (orchestrator-verified: full gate green, 5 validators + 6 GdUnit4 tests)
- `data/scenario_default.json` — authored by the orchestrator: 4 PLA amphibious brigades on beach
  hexes 1-4 (hex_44_16/44_15/43_14/43_13) + 4 ROC brigades on the adjacent inland neighbors
  (hex_43_16/43_15/42_15/42_14), with `offset_bearing` per brigade. Beach→hex by nearest center;
  inland neighbor = the real HexMath neighbor whose bearing best matches the beach's advance
  direction. (Caught + fixed an em-dash encoding corruption in the name.)
- `Brigade.entry_bearing: float` added (entry-side compass bearing for the render offset; data, not
  pixels — per the PLAN "Entry-side tracking" decision).
- `GameData.load_scenario()` (called from `load_all()`): places the 8 brigades on their hexes, sets
  `entry_bearing`, stores scenario meta (name, turn_length_days, stacking_soft_cap); fail-loud on
  malformed file / unknown brigade / team-vs-OOB mismatch.
- `tools/validate_scenario_data.gd` — counts, brigade existence + team match vs OOB, hex existence +
  uniqueness, 4 Red / 4 Green, and Green-inland-adjacent-to-Red-beach via `HexMath.neighbor_coords`.
- `tests/scenario_loader_test.gd` — 8 brigades placed, spot-checks (PLA-71-2→hex_44_16 bearing 315,
  BDE-66→hex_43_16), meta loaded.

**(b) pi's machine-readability suggestion**
- Typed `Scenario`/`ScenarioPlacement` Resources + a pure `ScenarioLoader`/`ScenarioValidator`, with
  GameData consuming a typed `Scenario` (not a raw Dictionary) and structured validation errors
  (`{code, brigade_id, path}`). — _Deferred: aligns with the typed-model architecture; revisit when
  scenarios multiply / become user-authored (Track C). The Dictionary path is fine for the single
  slice scenario and the validator already gates integrity._

---

## 2026-06-23 — M1b: brigade marker rendering (pi-implemented; M1 complete)

**(a) What shipped** (orchestrator-verified: full gate green incl. a new headless marker guard)
- `HexMap.render_brigade_markers()` (called from `_ready()`, redraw-capable for M4): for each placed
  brigade (hex_id != "") it projects the hex center, nudges by `0.4*radius` toward `entry_bearing`
  (north=-y, east=+x), and builds a marker = team-colored Polygon2D backing + Sprite2D NATO symbol
  (~48 px tall). Unplaced brigades don't render. Fail-loud on unknown hex / missing symbol / unknown
  team. `brigade_markers` dict keyed by brigade_id.
- Added smoke guard "Rendered 8 brigade markers" to `tools/run_all_tests.ps1` — headless regression
  evidence of the marker count (complements pi's visual check).
- **Visual check (pi):** 8 markers; 4 Red on the beach hexes nudged seaward, 4 Green on the inland
  hexes nudged toward the beach; correct NATO symbols; team obvious from the backing color.
- **Known cosmetic:** the northern beach markers sit near the top viewport edge and the topmost are
  slightly clipped — a camera-fit issue, deferred to **Track C** (Camera fit/zoom/pan). Does not
  affect the slice DoD (markers are on the correct hexes/sides).

**(b) pi's machine-readability suggestion**
- Extract a pure `BrigadeMarkerLayout.compute(brigade, hex, vertices, projection)` returning a
  record (brigade/hex id, screen center, radius, offset, final pos, team color, symbol) + a
  `HexMap.export_marker_snapshot()` for visual-regression tooling, and a test asserting the 8
  expected layout records. — _Deferred: good agent-observability; the new headless "Rendered 8
  brigade markers" guard + the scenario validators already cover placement/count. Revisit when
  marker layout gains complexity (stacking/counts at M5)._

---

## 2026-06-23 — M2: selection + event bus + info panel (pi-implemented; M2 complete)

**(a) What shipped** (orchestrator-verified: full gate green, 8 GdUnit4 tests)
- `scripts/EventBus.gd` (`class_name EventBusType`, autoload `EventBus` after GameData): signals
  `hex_selected`, `brigade_selected`, `selection_cleared`. No logic — pure bus.
- `GameController._on_hex_clicked`: emits `hex_selected(hex_id)` always, `brigade_selected(first)`
  only when the hex has a brigade; tracks `selected_hex`/`selected_brigade`.
- `HexMap` listens to `EventBus.hex_selected` and highlights the hex — no reach-through to UI/controller.
- `InfoPanel` (PanelContainer + RichTextLabel in Main.tscn UI) listens to the bus and shows hex
  (owner/FEBA/brigades present) + brigade (id/name/team/nato_type/battalions/composition); fail-loud
  on unknown brigade_id.
- `tests/selection_test.gd`: loads Main.tscn via `scene_runner`, drives the click handler, asserts
  `EventBus` emits the right signals/args + controller state (placed hex → both signals; empty hex →
  hex only). Headless input doesn't transport reliably, so the test exercises the handler path
  directly (still the full select→signal→state chain). pi confirmed the windowed map+markers render
  but could not do reliable manual GUI clicks in its harness.

**(b) pi's machine-readability suggestions**
- Typed `SelectionState` autoload (selected_hex_id / selected_brigade_id); typed `HexState` Resource
  replacing the `hex_states` Dictionary; a public `select_hex(hex_id)` command API instead of tests
  calling `_on_hex_clicked`; InfoPanel rendering from a typed view-model. — _Deferred: all sensible.
  The typed `HexState` Resource is worth doing when M5 combat wiring starts mutating hex_states
  (owner/FEBA); the `select_hex()` command + view-model are UI polish (Track C)._

---

## 2026-06-23 — M3: WeGo turn/phase state machine (GameState autoload; M3 complete)

**(a) What shipped** (orchestrator-verified: full gate green, 12 GdUnit4 tests)
- `scripts/model/MoveOrder.gd` (typed Resource: brigade_id, target_hex, mode).
- `scripts/GameState.gd` (autoload `GameState`, `class_name GameStateType`, after GameData/EventBus):
  the view-independent **action API** — `Phase {PLANNING,RESOLUTION,END}`, turn_number,
  turn_length_days (from scenario), per-team `orders` buffers, `last_contested_hexes`.
  `add_move_order` (fail-loud: wrong phase / unknown brigade / team mismatch / unknown hex),
  `resolve_turn` (MOVE-THEN-FIGHT: applies all moves from both buffers, then detects every hex with
  both teams — combat itself is the M5 hook), `begin_next_turn` (resets moved/fought flags on all
  brigades, clears buffers, turn++, back to PLANNING). Emits `EventBus.turn_resolved` /
  `phase_changed`.
- `EventBus`: added `turn_resolved(turn_number)` + `phase_changed(phase)`.
- `tests/game_state_test.gd`: reset defaults, order collection + 3 rejection cases, move-then-fight
  ordering (Red onto Green's hex → contested), flag/buffer/turn/phase resets. Isolated via
  before/after reload of GameData + GameState.

**(b) pi's machine-readability suggestions**
- `MoveOrder.mode` → typed enum once M4 validates movement modes (apply at M4); typed
  `TurnSnapshot`/`ContestedHex` models instead of raw `Array[String]`; a pure `TurnResolver`
  RefCounted so AI/headless sims run isolated from autoload state via the same typed order API. —
  _Deferred: the pure `TurnResolver` is directly relevant to M6 (headless AI-readiness) — revisit
  there; `mode` enum folds into M4; typed snapshot is polish._

---

## 2026-06-23 — M4a: movement logic + allowance/org wiring (pi-implemented)

**(a) What shipped** (orchestrator-verified: full gate green, 16 GdUnit4 tests)
- `scripts/Movement.gd` (pure RefCounted lib): `FAST_MOBILITY_HINTS = [mechanized, armor, tank]`
  (mirrors TIV `infer_green_brigade_speed` — fast if nato_type OR any battalion type matches);
  tactical speed 2/1, administrative 20/10; `move_allowance(brigade, mode)` (fail-loud on unknown mode).
- `Brigade.moved_admin_this_turn` flag (set on admin move; M5 will bar attacks — inert now).
- `GameState.add_move_order` now also: rejects unknown mode, blocks a 2nd order for the same brigade
  (re-move), and rejects targets beyond `find_reachable(start, allowance)`. `_apply_move_orders`
  applies the org cost (admin −100 / tactical −25 via `adjust_organization`) and sets the admin flag;
  `begin_next_turn` resets it.
- `tests/movement_test.gd`: fast/slow speeds + unknown-mode error, reachable/allowance enforcement
  vs the grid (distance-checked), re-move block, org-cost + admin-flag apply/reset.

**(b) pi's machine-readability suggestion**
- `MoveOrder.mode` as a typed enum (serialize to the strings at boundaries); a structured
  `MovementOrderValidationResult` ({valid, code, brigade_id, target_hex, allowance}) alongside the
  fail-loud push_errors for deterministic machine assertions / future UI diagnostics. — _Deferred:
  reasonable; the mode-enum folds in cleanly when M4b's UI offers the mode choice; structured
  validation results are worth it if a UI surfaces rejection reasons (Track C)._

---

## 2026-06-24 — M4b: interactive movement UI (pi-implemented; M4 complete)

**(a) What shipped** (orchestrator-verified: full gate green, 20 GdUnit4 tests)
- `EventBus`: `reachable_hexes_changed`, `move_mode_changed`, `move_order_issued`, `turn_advanced`.
- `GameController`: select a brigade → `_update_reachable()` emits the reachable set; clicking a
  reachable hex (≠ the brigade's hex) issues a `MoveOrder` (success detected via order-buffer growth)
  and clears the highlight; `set_move_mode()` (Tactical/Administrative) recomputes reachable;
  `end_turn()` = `resolve_turn()` + `begin_next_turn()` + re-render markers + advance counter.
- `HexMap`: reachable hexes highlighted light-blue, selected hex yellow (modulate over base colors),
  via `_refresh_highlights()`.
- `Main.tscn`: `MovementControls` (turn/mode status label, mode OptionButton, End Turn button).
- `tests/movement_ui_test.gd`: select→reachable, click→order, admin reachable > tactical, end_turn
  applies the move + advances the turn.
- **Visual (pi):** windowed launch renders scenario + 8 markers; the select→mode→highlight→order→
  end-turn loop verified via `scene_runner` (no manual desktop-click channel in pi's harness).

**(b) pi's machine-readability suggestions**
- Typed `SelectionState`/`PlanningUiState` resource instead of loose controller fields; move modes as
  a typed enum surfaced from one UI helper (so OptionButton indices don't encode meaning); a
  command/result wrapper around `add_move_order` so the UI inspects success/failure directly instead
  of checking buffer growth. — _Deferred: the command/result wrapper is the most valuable (cleaner
  than buffer-delta detection) and pairs with the M3/M4a "structured validation result" note —
  revisit when the UI needs to surface rejection reasons (Track C)._

---

## 2026-06-24 — M5a: headless continuous-combat resolution (pi-implemented)

**(a) What shipped** (orchestrator-verified: full gate green, 25 GdUnit4 tests)
- `scripts/CombatForces.gd` (pure lib): `is_support_type` (artillery|rotary_wing), `maneuver_units`
  (non-support battalions expanded per qty), `support_counts` (rocket→rocket_artillery, other
  artillery→artillery, rotary→rotary_wing; cas/crbm=0).
- `GameState.resolve_turn(dice = SeededDice(turn_number))`: after move-then-fight detection, calls
  `_resolve_combat_at(hex, dice)` for each contested hex, then `recompute_hex_ownership`.
  `_resolve_combat_at`: Red=attacker / Green=defender, excludes destroyed + admin-moved brigades
  (no combat unless both sides have ≥1 contributor), builds forces via CombatForces, runs the ported
  `resolve_map_attack` (terrain 1.0, feba_base 2.0), applies casualties, accumulates FEBA, sets
  `fought_this_turn`. `_apply_casualty` decrements the battalion (removes at qty 0; marks brigade
  destroyed + removes from map at 0 battalions).
- `GameData.recompute_hex_ownership` (occupancy: both→contested, one→that side, empty→keep) +
  `remove_brigade_from_map`.
- `tests/combat_resolution_test.gd`: forces split, single-hex casualties+FEBA+fought, occupancy
  ownership, admin-move exclusion, seeded determinism. (Math itself stays golden-tested in M0.)

**(b) pi's machine-readability suggestions**
- Typed combat force/result DTO resources instead of loose Dictionaries; a shared
  `tests/helpers/CombatFixture.gd`; `GameData.validate_runtime_indexes()` to assert
  `brigades_by_hex`/`hex_id` stay in sync after mutations; a `HexOwner` constants table to replace
  the "red"/"green"/"contested" string literals. — _Deferred: the `HexOwner` constants + a runtime-
  index invariant check are cheap hardening worth doing during M5b/M6; typed DTOs + CombatFixture are
  larger and fold in as combat grows. Logged for M5b._

---

## 2026-06-24 — M5b: post-combat retreat + ownership colors + result (pi-implemented)

**(a) What shipped** (orchestrator-verified: full gate green, 29 GdUnit4 tests)
- `scripts/HexOwner.gd` constants (RED/GREEN/CONTESTED/NONE); `GameData` + `HexMap` now use them
  instead of bare owner-string literals.
- `GameState`: `FEBA_RETREAT_THRESHOLD_KM = 10.0`; `_apply_feba_retreats()` (after combat, before the
  final ownership recompute) — when a contested hex's cumulative |feba| ≥ 10 km, the FEBA-losing side
  (Green if feba>0, Red if feba<0) retreats to the first adjacent hex with no enemy that it owns or is
  unowned; the hex's feba resets to 0; encircled units hold. Attacker advance is implicit (already
  co-located). Per-combat summaries collected → `EventBus.combat_resolved(summaries)`.
- `GameController` shows a one-line result on the DebugLabel; `HexMap.refresh_all_hex_colors()` runs
  on `EventBus.turn_advanced` so the front/ownership shift is visible.
- `tests/combat_retreat_test.gd`: retreat + ownership flip, encircled hold, combat_resolved signal,
  HexOwner constants. (Live interactive combat/retreat visual wasn't fully drivable in pi's harness;
  logic is headless-tested and color refresh is a re-apply of the spawn-proven `get_hex_color`.)

**(b) pi's machine-readability suggestions**
- Typed `CombatSummary` + `HexState` Resources (replace Dictionaries); a `GameData` test-fixture/reset
  API; a structured per-turn event log (movements/combats/casualties/FEBA/retreats/ownership). —
  _Deferred: the per-turn structured event log is high-value for M6 (headless AI-readiness) and
  save/replay — strongly consider at M6; typed HexState/CombatSummary fold in with that._

**M5 status:** acceptance criteria (seeded golden test, occupancy ownership, defeat/retreat,
headless-reproducible) are MET. **M5c** (the per-turn composition menu — commit adjacent maneuver/
artillery into a contested hex) remains to complete M5's full designed scope, then push.

---

## 2026-06-24 — M5c: combat composition (commit adjacent forces) (pi-implemented; M5 complete)

**(a) What shipped** (orchestrator-verified: full gate green, 33 GdUnit4 tests)
- `scripts/model/CommitOrder.gd` (typed). `GameState`: per-team `commitments` buffer;
  `add_commit_order` (fail-loud: phase / brigade+team / not destroyed / not admin / target exists /
  not-in-target / adjacent / one-order-per-brigade across move+commit); `eligible_commit_brigades`
  (UI helper); `_combat_contributors_for` = in-hex + committed-to-this-hex (deduped) feeding the
  existing CombatForces split; combat still gated on PRESENCE-contested hexes (commitments only add
  forces). Summaries enriched with combat_detail + brigade ids. `begin_next_turn` clears commitments.
- `EventBus`: `commit_options_changed`, `brigade_committed`. `GameController.commit_brigade` +
  emits options on selection. `CompositionPanel` (Main.tscn UI) lists eligible adjacent brigades as
  commit buttons (emits `commit_requested`, decoupled).
- `tests/composition_test.gd`: validation + one-order-per-brigade, eligibility filters, committed
  forces participate (fought + affect combat), commitments cleared next turn.
- Visual: windowed launch renders; commitment verified via deterministic tests (manual clicking not
  drivable in pi's harness).

**(b) pi's machine-readability suggestions**
- Typed `CommitOption`/`CombatSummary` DTOs; `add_move_order`/`add_commit_order` returning a typed
  result (enum/object) instead of buffer-growth detection; a headless command/test API for
  UI-equivalent order issuance (select hex / issue order) without scene introspection. — _Deferred:
  the headless command API + typed order-result are the highest value and align directly with M6
  (headless AI-readiness) — fold into M6; DTOs are incremental._

**M5 COMPLETE** (M5a resolution + M5b retreat/colors + M5c composition).

---

## 2026-06-24 — M6: headless WeGo turn check / AI-readiness (pi-implemented; M6 complete)

**(a) What shipped** (orchestrator-verified: direct run exit 0; full gate green)
- `tools/validate_headless_turn.gd` (SceneTree, auto-run by the gate): drives a full WeGo turn
  through the action layer with **no view nodes** — explicit `GameData.load_all()` +
  `GameState.reset_to_scenario()` (autoload `_ready` runs after a `-s` script's `_initialize`), a Red
  tactical move onto the adjacent Green hex via `add_move_order`, an optional Green commitment via
  `eligible_commit_brigades`/`add_commit_order`, `resolve_turn(SeededDice(20260624))`, then asserts
  movement-before-fight, contested detection, fought flags, a measurable combat effect (FEBA or
  battalion losses), valid ownership, `begin_next_turn` resets, and **two-run determinism** (identical
  positions/battalions/feba/owner/contested). Result: casualties=2, feba=0.76, deterministic.
  (The starter scenario has no Green brigade adjacent to that hex, so the commit path — already
  unit-tested in M5c — wasn't exercised here; the move+combat+determinism path is.)

**(b) pi's machine-readability suggestions**
- A `GameState.play_turn(red_orders, green_orders, dice) -> TurnResult` façade for AI/headless
  callers; typed `TurnResult`/`CombatSummary` Resources; `GameData.snapshot_state()` for exact
  golden/AI comparison; non-UI phase predicates (`is_planning_phase()`). — _Deferred to the post-slice
  AI track (Track E): the `play_turn` façade + `snapshot_state` are exactly what AI-vs-AI / B2 will
  want, but they're beyond the slice DoD; the action layer already supports full headless play._

---

## 2026-06-24 — M7: slice completion + Definition of Done

**Verification:** `tools/run_all_tests.ps1` GREEN — import + headless smoke (455 hexes / 143 brigades
/ 455 cells / 8 markers) + 6 `validate_*.gd` (combat_data, oob_data, scenario_data, symbol_map,
no_global_rng, headless_turn) + 33 GdUnit4 tests (incl. seeded golden combat, movement reachability,
selection, movement UI, combat resolution/retreat, composition, headless full turn).

**DoD interactive loop** is covered by `scene_runner` tests driving the real `Main.tscn`
`GameController` end-to-end, and per-feature visual confirmation landed in M1b (markers) / M5b
(colors). pi's final windowed launch was clean (8 markers, zero errors).

**Honest limitation (carried across the whole run):** the agent harness could neither capture a
screenshot nor perform manual mouse clicks in the live Godot window (`CopyFromScreen` fails), so a
human-eyes click-through of the running game was not performed by an agent. Recommend a final manual
eyeball. This is environmental, not an implementation gap — the same code paths are exercised
programmatically and pass.

**Process learnings logged for future tracks:** drive `pi` in the FOREGROUND (background runs
orphaned twice when launched at end-of-turn); the deferred machine-readability items most worth doing
next are the per-turn structured event log + a `GameState.play_turn(...) -> TurnResult` headless
façade + typed `HexState`/`CombatSummary` Resources (Track E / AI-readiness).

**SLICE COMPLETE.** Post-slice tracks (C/D/E) intentionally NOT started.
