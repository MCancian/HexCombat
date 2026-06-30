# PLAN.md — Active Work

> **Orientation:** for *what works today* read **`docs/STATUS.md`** (the single current-state doc);
> for *forward work* read **`docs/plans/BACKLOG.md`**. This file is the **Decisions log** (append-only
> *why* record) + Open Questions; the milestone task lists below are largely historical.

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

- **2026-06-30 — Typed phase-summary Resources (refactor_audit item 9; done directly, frontier work — NOT
  a free-model task). 4 of 5 fields converted; the 5th left untyped by USER call.** Repeated the proven
  item-3 pattern (typed `Resource` + `to_dict()` at the JSON edge, `null` = unresolved sentinel), one
  field per commit, re-verifying the golden after each: **`last_frontline_summary`** → `FrontlineSummary`
  (`b3473bd`), **`last_cleanup_summary`** → `CleanupSummary` (`360ec26`), **`last_antiship_summary`** →
  `AntishipSummary` (`206bc5c`), **`last_ijfs_writeback`** → `IjfsWriteback` (`f0112b0`). EventBus signals,
  `TurnResult`, the event log, and `LLMGameAPI` all emit via `to_dict()`; in-process/cross-phase consumers
  read typed fields. **Judgment calls:** (1) **`null` not `{}`** as the "phase didn't resolve" sentinel
  (a `Resource` has no `is_empty()`; matches item-3's CombatSummary null-sentinel). (2) **Public
  `resolve_*` methods keep returning `Dictionary`** (via `to_dict()`) so the many validators/tools that
  read string keys + `JSON.stringify` the return are untouched — the Resource is in-process storage, the
  dict is the public/JSON contract. (3) **EventBus signals keep their `(summary: Dictionary)` signature and
  emit `to_dict()`** (per the handoff: signal payloads are a JSON-ish boundary), so zero listener churn —
  diverges slightly from item-3's combat_resolved (which carries Resources) but that signal is `Array`-typed
  and consumed only by a test. (4) **`last_antiship_summary` resolved case IS `summary.to_dict()`** — its
  keys/order already matched the LLM observation block exactly, so the observation became a
  single-source-of-truth `to_dict()` call + the explicit empty-case defaults (the `mine_status:{}`-vs-`Array`
  quirk preserved verbatim). (5) **`IjfsWriteback.from_dict()` factory added** (inverse of `to_dict()`) for
  the three sites that snapshot-mutate-reinject a writeback to probe the IJFS→antiship coupling
  (C2-suppression validator, mines-only sweep, maneuver-consume test); its internal reads
  (`_apply_ijfs_maneuver_casualties`, `resolve_antiship_turn`) are now typed-field accesses with an explicit
  null guard, so a key typo fails at parse time instead of silently breaking casualty/antiship coupling.
  **Byte-stability:** the `JSON.stringify(…, "\t")` exporter sorts keys, so only the key *set* + value types
  matter (both preserved); the item-8 `validate_fixtures` gate byte-compares both committed fixtures every
  gate run and all four conversions kept them identical; golden `validate_headless_turn`
  casualties=3/feba=-0.96 held throughout; full gate green (40 GdUnit + all validators). **`last_ijfs_summary`
  deliberately LEFT untyped (USER design call):** unlike the other four it is not an inline GameState dict
  but the ~21-key dynamic output of the faithful TIV-port `IjfsEngine.summarize_run` (conditional
  `firing_capacity_utilization` key + dynamic nested histograms/logs); only 3 keys are read (once each), the
  rest is JSON pass-through. A full-mirror Resource would be a fragile second source of truth for an engine
  port for read-safety on 3 fields — the same tradeoff the audit already declined for `combat_detail`. The
  `resolve_supply_turn`/`resolve_offload_turn` return dicts are out of scope for the same reason
  (engine-output dicts, not stored `last_*` summary fields). **Item 9 is DONE; the live refactor candidate
  is now item 10 (GameState decomposition).**

- **2026-06-30 — Larger structural-refactor backlog recorded + GameState-decomposition interface decided
  (USER design call; documentation only, NOT implemented).** After item 3, proposed four larger refactors
  for legibility/testability; had them **independently verified against the actual code by a read-only
  review**, then folded the corrected versions into `docs/plans/refactor_audit.md` → "Larger structural
  refactors (8–10)". Net corrections from the review: (a) RNG isolation is cleaner than first claimed —
  offload consumes **no** dice (deterministic), combat is the sole base-stream consumer, so there is no
  offload↔combat coupling to fear; (b) for item 9, `last_ijfs_writeback` is the riskiest summary (internal
  cross-phase `.get()` consumers) and must go last; (c) for item 10, the genuinely safe first extractions
  are the data-loading/rebuild helpers + `frontline`/`supply`, NOT cleanup (which is more coupled than it
  looks). **User design call:** for item 10 (decomposing the 1,414-line `GameState`), prefer the option
  that costs more up front but reads more clearly for future agents → **pure `RefCounted` resolver classes
  with explicit `resolve(game_data, dice) -> TypedSummary` signatures, NOT new autoloads** (autoloads are
  hidden globals; resolver signatures make dependencies visible and the unit headless-testable, matching
  AGENTS.md's logic-layer rule). Sequence is fixed: **8 (fixture-drift gate) → 9 (typed phase summaries)
  → 10 (GameState decomposition)**. Full coupling map + line refs live in `refactor_audit.md`.

- **2026-06-30 — Typed `HexState` + `CombatSummary` Resources (refactor_audit item 3; done directly,
  NOT via opencode — explicitly flagged "not a free-model task").** Replaced the two plain dicts
  threaded through the model/state/API/validators with typed Resources, one type at a time, re-running
  the golden invariant after each. **Type 1 `HexState`** (`{owner, feba_km}` → `scripts/model/HexState.gd`,
  ~30 sites): `snapshot_state()` and the LLM observation emit via `HexState.to_dict()`/typed reads, so
  serialized JSON is unchanged. **Type 2 `CombatSummary`** (the `_resolve_combat_at` dict →
  `scripts/model/CombatSummary.gd`): `last_combat_summaries` is now `Array[CombatSummary]`; in-process
  consumers (`GameController`, the post-recompute `owner_after` write, the `validate_cleanup` fingerprint)
  read typed fields, and every JSON boundary (`LLMGameAPI.last_combat`, `TurnEventLog` combat events,
  `TurnResult.to_dict`) emits via `CombatSummary.to_dict()` with the former dict's **exact key order +
  value types** preserved. **Judgment calls:** (1) did HexState first (bounded, internal, lower-risk) to
  establish the pattern and a green/committed baseline before the riskier CombatSummary, which crosses
  multiple JSON-serialization boundaries; (2) `to_dict()` is the single serialization seam — typed fields
  in-process, dict only at the JSON edge; (3) the empty-combat sentinel changed from `{}`/`is_empty()` to
  `null`/`!= null` (a Resource has no `is_empty()`); (4) `.duplicate(true)` → `.duplicate()` on the now-
  Resource arrays (deep-dict-copy semantics are moot for never-mutated Resources; `to_dict()` produces
  fresh dicts at the edge anyway). **Byte-stability proof (beyond the gate):** regenerated
  `docs/examples/llm_result_after_turn.json` with AND without the CombatSummary change → **identical
  hash**, so the Resource serializes bit-for-bit like the old dict. Golden `validate_headless_turn`
  casualties=3/feba=-0.96 byte-stable; full gate green (40 GdUnit suites + all validators); commits
  `388d4ae` (HexState) + `d911010` (CombatSummary). **Side finding (surfaced to user, NOT fixed here):**
  that fixture regeneration revealed the committed `llm_result_after_turn.json` is **stale** — its
  antiship section predates the 2026-06-29/30 mine/antiship balance work (a 318/247-line drift that
  reproduces on a clean tree, independent of this refactor). Left as a separate doc-hygiene regen so this
  refactor commit stays scoped; flag it for a follow-up.

- **2026-06-30 — Debug-only end-of-turn index assert (refactor_audit item 4, SCOPED; max-autonomy).**
  Wired `GameData.validate_runtime_indexes()` as an `OS.is_debug_build()`-gated assert at the END of
  `resolve_turn`. **Judgment call:** the audit flagged item 4 as "do with attention, not unattended"
  because a per-mutator HOT-PATH assert can trip on benign transient desync mid-resolution. I scoped it
  to the **settled end-of-turn boundary only** (after cleanup recomputes ownership) — which the passing
  self-play validator already proves is consistent — making it unattended-safe. Used `OS.is_debug_build()`
  (single validator call in debug, zero in release) rather than assert-only (which double-evaluates) or a
  bare hot-path assert. Held green across the golden turn, 4-turn self-play, 40-turn victory e2e, and all
  GdUnit suites; golden byte-stable. The hot-path variant stays intentionally un-done (attended work).

- **2026-06-30 — Per-hull mine neutralization likelihood override (refactor_audit item 2; max-autonomy).**
  Added optional `ShipDef.mine_neutralization_likelihood` (loaded from `ships.json` when present);
  `GameState._mine_ship_meta` precedence is now decoy-override > per-hull override > per-category table.
  **Judgment call:** chose the empty-default + category-fallback design and did NOT populate `ships.json`
  with any values — that keeps the change strictly byte-stable (every hull still resolves to its category
  label), making the field a tuning HOOK to populate when a concrete balance need arises ("tie to a need,
  not speculative"). Adding explicit per-hull values now would either change mine results (needs a
  re-baseline) or be no-op clutter. Test: `mine_neutralization_override_test`. Gate unchanged green.

- **2026-06-30 — Victory census counts PRESENT (landed) battalions (refactor_audit item 2b; max-autonomy).**
  `GameState._taiwan_battalion_census` now subtracts each brigade's still-at-sea battalions (the
  un-landed remainder in `ship_reserve`) from its composition count. Landing sets `hex_id` on the first
  BN, but support BNs waiting on ships stayed counted — a partially-landed brigade was credited at full
  OOB strength toward China. **Census shift:** golden terminal china **36→20** (4 amphibious brigades,
  9 BNs each, with 16 support BNs still at sea on turn 1); **winner unchanged** (red, 20 > 16 ROC), so
  the structural `validate_golden_victory` needed no edit. Golden combat invariant byte-stable (census
  consumes no dice). Test: `victory_present_census_test`. **Investigation note:** an initial full-gate
  run showed a non-deterministic census (20 vs 24); isolated re-runs + standalone validator + a clean
  full re-run all gave a stable 20 — it was a **stale class-cache flake** from running the gate
  mid-edit (the `--import` step hadn't consistently picked up the just-written files), NOT a
  `reset_to_scenario` state bleed. `reset_to_scenario` already restores compositions via `load_brigades`
  and rebuilds `ship_reserve` fresh. (Lesson: verify a determinism failure standalone before "fixing"
  reset — the implementer's retro proposed a phantom reset fix that the evidence ruled out.)

- **2026-06-30 — IJFS warmup_context fail-loud guard (refactor_audit item 1; max-autonomy).**
  `IjfsEngine.run_daily` reads every `warmup_context` entry via `wc.get(key, default)`, so a producer
  typo silently yields the default and the config goes dead — the bug class that left exquisite intel
  dormant for the whole project. Added `WARMUP_CONTEXT_KEYS` (the 9 keys the engine reads) +
  `unknown_warmup_keys()` and an `assert` in `run_daily`. **Judgment calls:** (1) allowlist/existence
  check, not a full typed `WarmupContext` — minimal, no behavior change, golden byte-stable (the real
  producer emits exactly the 9 keys so the assert never trips); (2) put the logic in a pure testable
  helper rather than a bare `assert`, and pin the *real* producer↔consumer contract in a unit test;
  (3) **deferred** opencode's key→type suggestion (scope-creep; the documented bug is a misspelled key,
  which existence-checking covers; producer is internal code). Test: `ijfs_warmup_context_guard_test`.

- **2026-06-30 — IJFS maneuver targets synced to live OOB each turn (2d follow-up; max-autonomy).**
  Resolves the 2d limitation. `GameState._sync_maneuver_targets_to_oob` (top of `resolve_ijfs_turn`)
  marks the excess of live "Maneuver Units" targets over current OOB qty `destroyed`, so IJFS stops
  firing at dead battalions. **Chose SYNC over the queue's literal "rebuild per turn":**
  `IjfsEngine.carry_to_next_day` persists `destroyed`/`known_to_red`/`last_detected_day`, so a full
  rebuild would wipe survivors' detection continuity; sync only ever sets `destroyed` (never resurrects),
  preserving continuity. Deterministic (sort by `target_id`). **Golden-safe:** turn-1 OOB is still full
  when IJFS runs (2d applies after) so the pass is a no-op. Test: `ijfs_maneuver_sync_test`.

- **2026-06-30 — IJFS posture-by-activity detectability bias (overnight 2c-ii; max-autonomy).** See the
  D4-H section below for the full design note; in short, `GameState._update_maneuver_posture` sets a
  maneuver target's `posture="active"` when its brigade moved/fought last turn (2a flags), feeding the
  existing detection seam (higher `detectability_active` + active multipliers) with no math edit.
  Golden-safe (turn-1 flags all false → all stay `"hiding"`). Test: `ijfs_maneuver_posture_test`.

- **2026-06-29 — IJFS→ground maneuver-casualty linkage CLOSED (overnight loop 2b–2d).** The open D4-H
  half is done: `IjfsLoaders.build_maneuver_targets` generates per-battalion-instance "Maneuver Units"
  IJFS targets from the ROC OOB (`{brigade_id}-MU-{n}` + `MANEUVER_TYPE_MAP` profile; port of TIV
  `default_targets.build_maneuver_targets`); `_rebuild_ijfs_state` adds them so they're struck;
  `_compute_ijfs_writeback` populates `maneuver_casualties`; `_apply_ijfs_maneuver_casualties` (after
  IJFS, before combat) decrements struck battalions' qty (capped at 0; brigade destroyed when depleted).
  Deterministic (no dice). **Golden unchanged** — the struck units (BDE-269) aren't the golden
  BDE-66/BDE-77 combatants. **Judgment calls (max-autonomy):** per-battalion-INSTANCE granularity (HexCombat
  settled design, finer than TIV's per-row); qty-decrement-by-(brigade,type) since the OOB stores
  `{type, qty}` not instance ids; consume right after IJFS. **Limitation:** `ijfs_state` is built once
  per scenario, so across many turns a removed battalion can re-appear as a target — the qty cap keeps
  it safe (never negative); rebuilding maneuver targets per turn is a future refinement. The 2c-ii
  detection/lethality bias (mobility/posture/hardness) is the remaining refinement.

- **2026-06-29 — Supply→combat effectiveness mapping (overnight loop item 1; max-autonomy call).** TIV
  stores per-brigade `effectiveness` (`_inject_supply_effectiveness` ← `SupplyRepo`); HexCombat has a
  single Red DOS **pool** (`supply_state.current_dos_tons`). Chosen mapping: inject at the combat call
  site (mirroring TIV) — Red maneuver units get `supply_effectiveness = 1.0` while the pool is positive,
  and `red_out_of_supply_effectiveness` (scenario knob, default **0.5**) once the pool is exhausted
  (≤0); Green unaffected (no DOS model). Binary-at-exhaustion is the v1; a graded ramp is a future
  refinement. Note: the golden 1-turn scenario never exhausts the pool, so the golden invariant is
  unchanged. Implemented under the overnight queue.

- **2026-06-29 — Port-audit Area 2 decisions actioned (user-ratified).** (1) **Unit strength table:**
  keep HexCombat's differentiated `UnitStats.TYPE_DEFS` (TIV's runtime flattens 12/17 maneuver types to
  1.0 via an incomplete type→key mapping; HexCombat reflects the *intended* table). Helicopters
  reconciled: `rotary_wing`/`artillery` battalions are combat **support**, not maneuver, in both repos —
  so the helicopter maneuver-strength (0.5 vs TIV 1.4) is never used; kept 0.5 + documented in
  `UnitStats.gd`. (2) **`feba_base_km`:** made scenario-configurable (`GameData.feba_base_km`, default
  **3.5** = TIV's value; was hardcoded 2.0). Golden re-baselined `feba=-0.55`→`feba=-0.96` (×1.75);
  `combat_resolution_test` FEBA-delta 1.0→1.75. Full gate green. See `/DECISIONS.md`.

- **2026-06-29 — Hex adjacency coordinate-system bug fixed + golden re-baseline (port audit, Area 1).**
  The TIV port audit found `HexMath` treated the grid's stored **offset (odd-r)** `row`/`col` as
  **axial** coordinates. Empirically, the prior axial neighbors matched true great-circle geometry on
  only **23/308** interior hexes vs **308/308** for odd-r (the TIV `get_hex_neighbors` scheme). Fixed
  `HexMath.neighbor_coords` to parity-aware odd-r offsets and `HexMath.distance` to offset→cube. **User
  call:** fix now (not defer) so the rest of the audit runs against correct adjacency, accepting the
  golden re-baseline. **Re-baseline:** the scripted golden turn now resolves to `casualties=3,
  feba=-0.55` (was `casualties=2, feba=0.76`) — the corrected adjacency aggregates the right adjacent
  supporting brigade (`BDE-77` now correctly commits to `hex_43_16`). Scenario beach-1 Green defender
  `BDE-66` moved `hex_43_17`→`hex_43_16` (a *real* odd-r neighbor of beach hex `hex_44_16`); the other
  three beach pairs were already valid odd-r neighbors. Updated the pinned fingerprint
  (`validate_cleanup.gd`), `STATUS.md`, all fixtures keyed to the old pair, and the LLM example docs.
  Full evidence + the original flag: `DECISIONS.md`; system doc: `docs/systems/hex-grid.md`.

- **2026-06-29 — Victory conditions implemented (Track 3a) + end-to-end golden test (Track 3b).** Built
  the end-of-cleanup win/loss census per the settled design (China loses if 0 PLA battalions on Taiwan
  when the loss check is armed; China wins if PLA battalions > ROC battalions). Pure checker
  `VictoryConditions.evaluate` (opencode) + integration in `GameState` (census, `game_over`/`winner`
  fields, `TurnResult` + LLM observation surfacing) + scenario `victory` config. **Key divergence
  forced by missing data:** "on Taiwan main-island land hexes" can't be computed — the hex grid has no
  land/island flag (terrain is a deferred ArcGIS phase) — so `taiwan_hexes: null` defaults to **all
  placed hexes** (exact for the main-island golden scenario; the array is the future land-data hook).
  Golden scenario armed `after_first_landing` (sea-start attacker) though the code default is
  `unconditional`. New gate `tools/validate_golden_victory.gd` (deterministic terminal + winner⇔census).
  Golden `casualties=2/feba=0.76` byte-stable; gate green. Census counts OOB `get_battalion_count`
  (over-counts sea losses) — logged as an offload-track follow-up (`refactor_audit.md`). Full detail:
  Open Questions → "Victory conditions" → IMPLEMENTED 2026-06-29; lessons: RETROSPECTIVES 2026-06-29
  victory-conditions.

- **2026-06-29 — Mine warfare: replace the geometry-free cap model with the GEOMETRIC danger model +
  decoy-sponge transit (USER design call).** After measuring that the planned `intel_locked` strike
  bonus could not reach the ~25% crossing-loss target (its whole band is ~54%→~41% mean; mines set a
  ~22% floor — see Open Question "D3-D crossing lethality calibration" UPDATE 2026-06-29), the user
  redirected calibration to the MINES and deferred the strike-coverage lever
  (memory `antiship-strike-coverage-lever`). Ported `TaiwanDefenseRefactor/mine_warfare.py`: mines are
  scattered uniformly in a `length×width` field, the fleet takes a *randomized* straight approach path
  (random incident angle ∈ [30,60]°, entry ∈ [0.3,0.7]), and only mines within `danger_radius` (50 m)
  of that path line are DANGEROUS (≈5–15, not all `num_mines`). Pre-landing sweepers clear the closest
  `assigned × prelanding_clear_per_sweeper` (default 1 → mainly LOCATES the field). The surviving
  crossing fleet then transits in order — **decoys first, then real ships by ascending value** — each
  detonating the next dangerous mine; a **decoy that survives a detonation CONTINUES and can trigger
  subsequent mines** (sponge). Neutralization-if-hit is by hardness (`high/medium/low → 0.9/0.5/0.25`,
  per-category table + decoy override). **Divergences from the source (documented):** (1) the source
  detonates exactly one mine per ship; the decoy-continue loop is a USER-specified refinement (decoys
  sponge ≥1); (2) non-decoys keep one-mine-each; (3) geometry RNG goes through the injected `Dice`
  (formula + draw order: angle, entry, (x,y)×num_mines, then one roll per detonation), not numpy; (4)
  positions are not retained after counting (all dangerous mines interchangeable for the count-based
  transit). Knobs live in `data/antiship/minefields.json` (`geometry` + `transit`). Files:
  `scripts/MineWarfareService.gd` (rewrite), `AntishipLoaders.load_mine_config`,
  `GameState._mine_ship_meta` + call-site rewire, `tests/mine_warfare_test.gd` (13 cases, geometry
  pinned via huge/zero `danger_radius`). **MEASURED (seed 20260624 golden + 24-seed means): mines-only
  floor ~22% → 0% (intact screen sponges all dangerous mines → 0 amphibs hit); baseline mean crossing
  loss 54% → 32.4% (golden 30.6%); the intel lever now bites again (32.4%→26.5% at ic=36/+0.2→18.4% at
  max) via emergent coupling (killing launchers preserves screen to sponge mines).** Golden
  `casualties=2/feba=0.76` byte-stable; full gate green (30 suites). Sweep harness:
  `tools/sweep_antiship_crossing.gd`. Final knob dial-in toward exactly ~25% left as a USER call (see
  RETROSPECTIVES.md 2026-06-29 mine-geometry).

- **2026-06-28 — D3-D crossing lethality: wire the prelanding WARMUP (activate exquisite intel) +
  planned strike bonus (USER calibration call).** Discovered the exquisite-intel mechanism
  (peacetime HUMINT/SIGINT that `intel_locked`s a decaying count of anti-ship *groups* → auto-detect,
  defeating the 0.01 mobile-coastal satellite floor) was **dead code** — `resolve_ijfs_turn` ran
  `run_daily` with no `warmup_context`, so the current ~67% golden crossing loss is measured with
  exquisite intel OFF. User chose: keep the exponential decay, **wire the full TIV warmup faithfully**
  (port of `ijfs_prewarmup._run_warmup_locked`: loop `prelanding.days`, build a per-`x_day`
  `warmup_context` with exquisite_intel + posture override + SEAD/AD rules + munition filter + release
  rules + profile-scaled firing capacity, `z_day = x_day − days − 1`), keep selection
  group/container-level (already so — TO3's 50-launcher threat = just 2 containers), then add an
  `intel_locked` strike bonus for coastal launchers and **empirically sweep `initial_count`** on the
  golden seed to hit ~25% crossing loss. Wiring delegated to opencode (`hexcombat-warmup-wiring`),
  orchestrator-verified. **RESULT: crossing loss ~67% → 50.0% (18/36), golden `casualties=2/feba=0.76`
  byte-stable, gate 204/204 green** — the golden did NOT move (crossing BN loss does not leak into the
  measured ground fight). Detection-only halves but doesn't reach 25%; strike bonus + `initial_count`
  sweep are the remaining levers. Full analysis: Open Questions → "D3-D crossing lethality calibration"
  → UPDATE 2026-06-28; knob map: `docs/antiship_lethality_knobs.html`; remaining steps:
  `docs/ORCHESTRATOR_HANDOFF.md`.

- **2026-06-28 — Victory conditions (USER design call; documentation only, not yet implemented).** Two
  conditions, both checked in **end-of-turn cleanup**, counting battalions **on Taiwan main-island land
  hexes**: **China loses** if zero Chinese battalions on Taiwan; **China wins** if Chinese battalions
  on Taiwan **strictly >** Taiwanese battalions. Loss check runs **unconditionally every cleanup by
  default**, but the arm is **configurable** (`unconditional` / `after_first_landing` / `after_turn:N`)
  for flexibility. Zero-sum `winner`/`game_over` field assumed (confirm at implementation). Full spec:
  Open Questions → "Victory conditions". Supersedes the 2026-06-23 "Victory deferred" decision.

- **2026-06-28 — IJFS → ground maneuver casualties = Option B + detectability extensions (USER design
  call; documentation only, not yet implemented).** Maneuver units become IJFS-targetable by porting
  TIV's `build_maneuver_targets` + `detection.py` model against the Green/ROC OOB: mint per-battalion
  IDs (`{brigade_id}-MU-{n}`), generate "Maneuver Units" targets with a ported `MANEUVER_TYPE_MAP`
  profile, and write destroyed/suppressed back by `battalion_id` into `maneuver_casualties`. Detection
  is biased per the user: **less-mobile** units (mobility tier → `mobility_multiplier`) and
  **recently-active** units (moved/fought last turn → `posture="active"` → higher detectability, a
  generalization of TIV's `antiship_exposure`) are more likely hit; **less-armored** units die more
  readily via `hardness` on the strike step. Requires **persistent prior-turn activity flags on
  `Brigade`** (`moved_last_turn`/`fought_last_turn`, latched in cleanup before the per-turn flags
  reset) — the "record historic actions per brigade" requirement. Must keep the golden invariant
  byte-stable (inject the IJFS substream). Sub-decisions RESOLVED same day: armor = **lethality only**
  (no detection divergence); Service/Support battalions **are** targetable (soft/high-detect); history
  depth **prior-turn only**; suppression **reporting-only** at first (destruction = `qty` loss). Design
  fully settled, ready to implement. Full spec: Open Questions → "D4-H writeback linkage" → "DECISION
  2026-06-28 — Option B".

- **2026-06-28 — Track E: reusable self-play runner + pluggable policy (via opencode).** Extracted the
  self-play loop into `scripts/SelfPlayRunner.gd` (`static play_game(policy: Callable, turns, base_seed) ->
  {final_snapshot, turn_digests, all_resolved, final_turn, index_violations}`) and `scripts/SelfPlayPolicy.gd`
  (RefCounted reference policy with the `build_actions(observation) -> Array` contract a real agent
  implements), and rewrote `tools/validate_headless_selfplay.gd` (133→75 lines) to delegate to them — all
  assertions + behavior preserved (identical PASS, combat in all 4 turns, cross-process deterministic).
  **DESIGN DECISION (diverged from the retrospective's "GameState.play_game" suggestion):** the runner lives
  at the **adapter layer**, NOT on GameState. A self-play game drives *through* the public agent API
  (`LLMGameAPI.observation` + `apply_agent_response`); since LLMGameAPI already depends on GameState
  (GameState ← LLMGameAPI ← SelfPlayRunner), putting the driver on GameState would **invert** that dependency.
  The policy plugs in via an instance-method `Callable(policy, "build_actions")` (instance-method Callables are
  robust in Godot 4; static-method Callables are not). No combat/RNG/GameState change; `validate_headless_turn`
  (golden validator) left untouched → golden 20260624 → casualties=2, feba=0.76 byte-stable; gate ALL PHASES
  GREEN. **Retrospective triage** (see `RETROSPECTIVES.md 2026-06-28 selfplay-runner`): all forward-looking
  (per-turn hooks / a mid-game `resolve_turn(policy, seed)` entrypoint, balance-sweep stats/parallelism/
  perturbation hooks, `export_turn_log`) recorded as **YAGNI until a consumer exists** — none acted on.
  **This is the last clearly-safe autonomous unit; the safe backlog is now exhausted** (remaining work is
  user design-calls, blocked, YAGNI-without-consumer, or risky typed-model migrations) → the orchestrator
  loop is stopping here with a clean handoff rather than manufacturing risky/speculative unattended work.

- **2026-06-28 — Track E capstone: headless AI-vs-AI self-play harness (via opencode).** Added
  `tools/validate_headless_selfplay.gd` (gated validator) — the Track-E goal ("agents drive the action API
  with no view; full games run headless"). It plays `TURNS=4` turns from a clean `reset_to_scenario()` through
  the existing `LLMGameAPI.observation("")` + `apply_agent_response(...)` layer with a trivial DETERMINISTIC
  policy (each placed brigade of either team issues a tactical move to the first legal target ≠ its own hex;
  `end_turn` seed = `BASE_SEED + turn`), then asserts: every turn resolved, **full-game determinism** (identical
  `snapshot_state()` + per-turn `turn_result` digests across two fresh games), runtime-index health after the
  game (cross-checks the M5a guard), and that the game advanced to `turn_number == TURNS+1`. Decisions:
  (1) **Drives both sides naturally from turn 1** (Red lands via the offload phase inside turn-1 resolve — no
  manual `resolve_offload_turn` provisioning), so it's a genuine end-to-end game, not a scripted fixture.
  (2) **Asserts loop + determinism + index health + turn advance ONLY — NOT that combat occurs** (kept
  design-free + gate-stable); in practice the trivial policy does drive contact (combat in all 4 turns).
  (3) **Verified cross-PROCESS determinism** (orchestrator ran the validator twice in separate Godot processes
  → byte-identical PASS) and **gate stability** (ran the full gate twice → ALL PHASES GREEN both times, golden
  20260624 → casualties=2, feba=0.76 byte-stable). No game-logic/combat/RNG touched. **This is the capstone of
  the Track-E AI-readiness arc** (play_turn façade → event log → LLM surfacing → result schema → index guard →
  **headless self-play regression test**). **Retrospective triage** (see `RETROSPECTIVES.md 2026-06-28
  selfplay-harness`): **promoted a `GameState.play_game(policy, turns, seed)` headless-driver entrypoint +
  a reusable `tools/policies/` helper** (DRYs the bootstrap across validators, makes real agent policies
  pluggable) as the next unit; recorded an `export_turn_log` JSON-per-turn helper for the save/replay track.

- **2026-06-28 — Data-layer hardening: `GameData.validate_runtime_indexes()` invariant guard (via opencode):**
  Added a read-only `validate_runtime_indexes() -> Array[String]` (REFACTOR_NOTES M5a) that bidirectionally
  checks the `brigades` ↔ `brigades_by_hex` indexes (every placed brigade listed in its bucket; every bucket
  entry references an existing brigade whose `hex_id` matches; no duplicates), returning human-readable
  violation strings (empty = healthy) + `tools/validate_runtime_indexes.gd` exercising 6 scenarios (load /
  offload / move+remove / full combat turn / **negative corruption test** injecting `__ghost__` and asserting
  the guard reports it / reload-restores). Decisions: (1) **Read-only, returns `Array[String]`** (not
  push_error) so callers can log/pattern-match — the negative test asserts a violation mentions `__ghost__`.
  (2) **Guard is invoked only from the dedicated validator for now, NOT wired into the hot path** — the
  retrospective's top idea (a debug-gated `assert(validate_runtime_indexes().is_empty())` in `set_brigade_hex`
  / end of `resolve_turn`) was **deliberately deferred**: a new hot-path assert could turn currently-green
  GdUnit/validator tests red on any benign transient desync, which is an unacceptable risk for an unattended
  overnight run — it's the right change to make with full attention, recorded as the top follow-up. No
  game-logic touched → golden 20260624 → casualties=2, feba=0.76 byte-stable; gate ALL PHASES GREEN.
  **Retrospective triage** (see `RETROSPECTIVES.md 2026-06-28 runtime-index-guard`): recorded the auto-run
  assert (top follow-up), a `validate_data_layer()` aggregation over the other indexes (`hex_states`/
  `hex_lookup` coverage, `fleet`/`ship_defs`, `ship_reserve` brigade refs — several low-drift today), and a
  reusable per-container `validate_invariants()` pattern (analogous to the existing `ShipState.validate()`).

- **2026-06-28 — Track E AI-readiness: `llm_action_result` JSON Schema + schema-driven key gate (via opencode):**
  Added `schemas/llm_action_result.schema.json` (the observation + action_response already had schema files;
  the action result did not — a contract-consistency gap). Mirrors the existing shallow draft-2020-12 style
  (`$id` "hexcombat.llm_action_result", top-level `required`+`properties`, `additionalProperties:true`); fully
  enumerates the 8 top-level result keys and documents the nested `turn_result`/`events` shape. Decisions:
  (1) **`turn_result` sub-keys are intentionally NOT `required`** so the `{}` (unresolved) form validates while
  the populated form is still documented; per-event `required:[seq,kind,hex_id,team,data]` + a `kind` enum ARE
  strict since every TurnEvent always carries all five. (2) **Schema is parse-checked + drives a key gate, not
  a real validator** — Godot has no JSON-Schema engine, so (consistent with `REQUIRED_OBSERVATION_KEYS`)
  `tools/validate_llm_api.gd` adds `REQUIRED_RESULT_KEYS` and `_validate_result_schema_conformance()`, which
  cross-checks the schema's `required` array against `REQUIRED_RESULT_KEYS` (sorted-set compare, so they can't
  drift) and asserts both a fresh resolved result and the committed fixture carry all 8 keys. No game-logic
  touched → golden 20260624 → casualties=2, feba=0.76 byte-stable; gate ALL PHASES GREEN. **Retrospective
  triage** (see `RETROSPECTIVES.md 2026-06-28 llm-result-schema`): all three lessons recorded (vendor a real
  JSON-Schema engine; the duplicated key-list is a deliberate cross-check guard, not pure smell;
  `additionalProperties:true` looseness is consistent with the existing schemas) — none acted on inline (no
  defect; each is a broader design call). **This completes the Track-E AI-readiness arc** (play_turn façade →
  event log → LLM surfacing → result schema); the autonomous Track-E backlog is now largely exhausted (next
  candidates: a `GameData.validate_runtime_indexes()` hardening guard from REFACTOR_NOTES M5a; a bulk
  `submit_and_resolve` wrapper; `game_over`/`winner` victory conditions = a USER design call).

- **2026-06-28 — Track E AI-readiness: surface event log + `TurnResult` through `LLMGameAPI` (via opencode):**
  `LLMGameAPI.apply_agent_response`'s `end_turn` action now routes through `GameState.play_turn([], [], dice)`
  (resolving the already-buffered orders) instead of bare `resolve_turn`, captures the returned `TurnResult`,
  and threads `turn_result.to_dict()` into the action result under a new top-level `"turn_result"` key (the
  structured record of the turn just resolved: turn_number, contested_hexes, combat_summaries, phase
  summaries, and the ordered `events` log). New `tools/export_llm_result.gd` (mirrors `export_llm_observation`)
  regenerates `docs/examples/llm_result_after_turn.json`. Decisions: (1) **`turn_result` lives in the action
  RESULT, not the observation** — the observation reflects *current/forward* state, while `turn_result` is the
  transient "what just happened" record; keeping them separate avoids bloating the always-serialized
  observation. (2) **Only populated when `resolved == true`** (`{}` otherwise) — the validator asserts both the
  populated shape (turn_number==1, contested includes the assaulted hex, events contain the move + combat) and
  the empty-on-reject case. (3) **`play_turn`'s own PLANNING guard replaces the old `phase_before == 0` check**
  (`turn_result != null` ⟺ was in planning) — semantically identical, cleaner. (4) **Fixture is tool-generated,
  never hand-edited** — orchestrator independently re-ran the export tool and confirmed the committed fixture
  is byte-identical. Verification: `tools/validate_llm_api.gd` PASS; gate ALL PHASES GREEN; golden 20260624 →
  casualties=2, feba=0.76 byte-stable; regenerated fixture's `turn_result.events` = `[ijfs, antiship, move,
  combat, cleanup]`. **Retrospective triage** (see `RETROSPECTIVES.md 2026-06-28 llm-event-surfacing`):
  **promoted a `hexcombat.llm_action_result` schema file** (the observation + action_response have schemas; the
  result doesn't — a contract-consistency gap) to the next unit; recorded the committed-fixture-vs-in-memory
  tradeoff; flagged that `game_over`/`winner` victory conditions are **new game-design (a design call, not a
  faithful port)** and must go to the user, while a bulk `submit_and_resolve` endpoint is a thin `play_turn`
  wrapper for later.

- **2026-06-28 — Track E AI-readiness: per-turn structured event log (`TurnEvent`) (via opencode):**
  Added `scripts/model/TurnEvent.gd` (typed Resource: `seq, kind, hex_id, team, data` + `to_dict()`) and
  `scripts/TurnEventLog.gd` (pure static `build(state) -> Array[TurnEvent]`), and populated `TurnResult.events`
  from it in `play_turn`. The log is an **ordered, turn-execution-order** trace: `ijfs` → `antiship` → `move`
  (Red then Green) → `commit` → `combat` (one per contested hex) → `frontline?` → `cleanup?`, each phase
  rollup emitted only when its `last_*` summary is non-empty. Decisions: (1) **Pure non-invasive derivation
  from already-stored state** — `TurnEventLog.build` reads only GameState `last_*` fields + the order buffers
  via `orders_for`/`commitments_for`; `resolve_turn`/combat math/RNG are untouched, so the golden invariant
  stays byte-stable (this was the explicit design constraint, not an accident). (2) **`combat` events copy the
  whole combat-summary dict verbatim** (deep-copied) rather than re-projecting fields — faithful and avoids
  type assumptions about the loss fields; `combat_detail` (full casualty/roll breakdown) rides along, so
  per-casualty granularity stays derivable without splitting events. (3) **`move`/`commit` events derive from
  the still-buffered orders**, which `begin_next_turn` clears — `play_turn` builds the log immediately after
  `resolve_turn` (before any advance), so the dependency is contained inside `play_turn`, not exposed to
  callers; documented in `TurnEventLog.build`'s docstring (orchestrator-added). (4) **`kind` is a String, not
  an enum** — it's a JSON serialization boundary for AI agents; revisit only when a second consumer appears.
  Verification: extended `tools/validate_play_turn.gd` asserts the golden turn's log is non-empty, contains a
  `move` for the Red mover → target hex and a `combat` at the target hex; the existing
  `result.to_dict() == result2.to_dict()` determinism assert now covers event-log determinism for free. Gate
  ALL PHASES GREEN; golden 20260624 → casualties=2, feba=0.76 byte-stable. **Retrospective triage** (see
  `RETROSPECTIVES.md 2026-06-28 turn-event-log`): acted now on the ordering-dependency docstring; **promoted
  surfacing the event log through `LLMGameAPI`** (action result / observation) to the next unit; recorded
  enum-`kind`, per-casualty sub-events, and `to_line`/`from_line` save-replay helpers (+ per-event
  `turn_number`) for the persistence track.

- **2026-06-28 — Track E AI-readiness: `play_turn` headless façade + `snapshot_state` (via opencode):**
  Added `scripts/model/TurnResult.gd` (typed Resource mirroring the `last_*` summary fields + `to_dict()`),
  `GameState.play_turn(red_orders, green_orders, dice) -> TurnResult`, and `GameData.snapshot_state()`
  (key-sorted deterministic brigade+hex snapshot for golden/AI byte-comparison). This is the deferred
  highest-value seam flagged in `REFACTOR_NOTES.md` (M3/M5c/M6) for Track E (headless AI-vs-AI / the
  autonomous orchestrator). Decisions: (1) **`play_turn` is pure orchestration over the existing
  `resolve_turn(dice)`** — it only buffers the bulk-order spec (`{kind:"move"|"commit", brigade_id,
  target_hex, mode?}` via `add_move_order`/`add_commit_order`, reusing their fail-loud validation) then
  delegates; it changes no combat math or RNG draw order, so the golden invariant stays byte-stable.
  (2) **Inspect-then-advance contract:** `play_turn` deliberately does NOT call `begin_next_turn()` — it
  leaves the caller in `Phase.END` so an AI/headless driver can read the `TurnResult` (contested hexes,
  losses) and snapshot before advancing. (3) **Fail-loud:** returns `null` (push_error) outside PLANNING
  and on unknown order `kind`. (4) **`snapshot_state` is GameData-only** (brigade positions/battalions/
  destroyed/team + hex owner/feba) — sufficient for the byte-comparison gate; a GameState-superset
  snapshot for save/replay is deferred. Verification: new `tools/validate_play_turn.gd` proves the façade
  is **byte-identical** to the hand-rolled `validate_headless_turn` sequence (snapshot equality) + two-run
  determinism + the fail-loud null path; gate ALL PHASES GREEN; golden 20260624 → casualties=2, feba=0.76
  byte-stable. **Retrospective triage** (see `RETROSPECTIVES.md 2026-06-28 play_turn-facade`): acted now on
  the error-path test (orchestrator added it inline); the typed per-turn **event log** is promoted to the
  next backlog unit; auto-advance convenience + GameState-superset snapshot recorded for the AI-driver/
  persistence track.

- **2026-06-27 — D5-C cleanup phase ported (end-of-turn system reset; via opencode):** Added
  `GameState.resolve_cleanup_phase()` + `EventBus.cleanup_resolved` + `tools/validate_cleanup.gd`,
  hooked into `resolve_turn` after `resolve_supply_turn` / before `phase = END`. **Scoping correction:**
  the ROADMAP described D5-C as "residual attrition + isolated-unit check", but reading the TIV oracle
  (`cleanup_calculator.py` `reset_systems`, `cleanup_hex_service.py`, `cleanup_application_service.py`)
  shows the real cleanup phase is a pure **end-of-turn system reset** (reset per-turn anti-ship/maneuver
  flags; restore moved/unavailable quantities) + ownership normalization — there is no attrition or
  isolation logic. Decisions: (1) **The only non-redundant work is resetting the anti-ship per-turn
  flags.** HexCombat already resets brigade flags in `begin_next_turn` and recomputes ownership after
  combat, and IJFS per-day flags clear in `carry_to_next_day` — but `AntishipSystem.fired / expended /
  destroyed_this_turn / suppressed / active` were reset NOWHERE and accumulate on the persistent
  `antiship_systems` array (latent bug, masked only because the crossing rarely runs past turn 1).
  Cleanup resets exactly those, leaving cumulative `destroyed`/`quantity`/`original_quantity` to
  resolve_antiship_turn's idempotent decrement. (2) **TIV `Quantity_Moved`/`Quantity_Unavailable`
  restore not ported** — no HexCombat equivalent (those are TIV DB columns; quantity is recomputed each
  turn); noted in-code. (3) **No RNG; runs after combat** → golden 20260624 → casualties=2, feba=0.76
  byte-stable. **Retrospective triage** (see `RETROSPECTIVES.md 2026-06-27 D5-C`): rejected/recorded —
  a `Phase.CLEANUP` enum state (positional hook works + commented; low value) and merging the brigade-
  flag reset into cleanup (tangles with `begin_next_turn`'s turn-advance/buffer-clear; risky, low
  value). No 2nd-subagent refactor warranted. Gate ALL PHASES GREEN.

- **2026-06-27 — D5-B front-line GameState wiring (via opencode):** Added
  `GameState.resolve_frontline_phase(polyline_coords) -> Dictionary` + the `_frontline_hex_centers()`
  adapter (flattens `GameData.hexes` → `[{id,lat,lon}]`, keeping `FrontLineService` pure) +
  `EventBus.frontline_resolved` + `tools/validate_frontline.gd`. Decisions: (1) **No RNG / not yet in
  `resolve_turn`.** The redistribution is deterministic (`floor(k*M/N)`), so the method takes no `dice`
  (ROADMAP's `(coords, dice)` stub dropped the unused param) and is a standalone, deterministically-
  callable method — turn integration + the polyline-draw UI are split into **D5-D** (a player-drawn
  polyline is a PLANNING-phase action, so it must be stored and executed at the right point in
  `resolve_turn`, like move orders — not auto-sequenced). Golden combat is byte-stable because nothing
  is wired into `resolve_turn` yet and no RNG is consumed. (2) **Affected = Red, non-destroyed brigades
  whose current hex is in the polyline's hex sequence** (snapshotted before moving, sorted for
  determinism), redistributed evenly across the sequence — faithful to TIV front_line_service ("only
  brigades in hexes the line passes through are affected; the front reshuffles along the drawn line").
  **Red-only is intentional** (TIV filters to one side; the amphibious attacker draws the front) and is
  commented in-code so it's not mistaken for a bug — a `team` parameter is the extension point if Green
  ever draws lines. **Retrospective triage** (see `RETROSPECTIVES.md 2026-06-27 D5-B`): acted now —
  the Red-only clarifying comment (too small for a 2nd subagent); rejected/deferred — pre-caching
  `_frontline_hex_centers()` (the phase runs once per turn, not per-frame; revisit only if D5-D adds a
  live drag-preview). No 2nd-subagent refactor warranted this iteration. Gate ALL PHASES GREEN.

- **2026-06-27 — D5-A FrontLineService ported (pure lib; via two opencode subagents):** Ported the
  polyline→hex-sequence core of TIV `services/front_line_service.py` + `core/hex_grid.point_to_hex`
  into `scripts/FrontLineService.gd` (pure RefCounted, static funcs). Faithful: `haversine_km`
  (radius 6371, `atan2(√a, √max(1e-12,1-a))`), `polyline_cumulative_lengths`, `interpolate_along_line`,
  `point_to_hex` (nearest hex CENTER by haversine — TIV's actual algorithm, not point-in-polygon),
  `find_hexes_for_polyline` (vertex + 2 km-interval midpoint sampling, dedupe first-seen). Decisions /
  divergences: (1) **Coords as `Vector2(lat,lon)`** (matches `Hex.center`) and **hex centers as a flat
  `Array[{id,lat,lon}]`** (not TIV's nested `{"hexes":[…]}`), so the lib stays pure — D5-B will add a
  thin GameData→flat adapter rather than passing `Hex` Resources into the lib. (2) **`distribute_units_
  along_hexes` replaces TIV `distribute_battalions_along_line`.** TIV repositions each maneuver
  battalion to an interpolated lat/lon within its hex; HexCombat tracks brigades as atomic hex-
  positioned units (battalions are attributes, never individually placed — settled B1 decision), so the
  slice distributes whole units EVENLY across the hex sequence (`floor(k*M/N)`) and returns
  `{unit_id: hex_id}`. The per-battalion lat/lon spacing + support-BN HQ offset are not ported (no
  per-battalion position state in HexCombat). (3) **`sample_polyline` extracted** (approved refactor,
  2nd subagent) so D5-B/C can reuse the raw sampled points; `find_hexes_for_polyline` consumes it with
  proven-identical output (regression test). **Retrospective triage** (see `RETROSPECTIVES.md 2026-06-27
  D5-A`): acted now — the `sample_polyline` extraction; rejected — a spatial-index micro-opt for
  `point_to_hex` (premature; O(N) is fine at game tick) and an arbitrary unit/hex-ratio warning in
  `distribute_units_along_hexes` (noisy). 23 GdUnit cases; gate ALL PHASES GREEN; golden byte-stable.
  Next: **D5-B** (`GameState.resolve_frontline_phase` + the GameData→flat-hex adapter), then **D5-C**
  (cleanup + polyline-draw UI — UI needs visual verification, less autonomous-friendly).

- **2026-06-27 — Gate now distinguishes the Godot 4.7 teardown flake from real failures:**
  `tools/run_all_tests.ps1` used to decide each phase purely on the process EXIT CODE, so the known
  Godot 4.7 *teardown* crash (the engine intermittently segfaults / corrupts the heap during
  SceneTree process SHUTDOWN when many headless scripts run back-to-back — exit `-1073741819`
  0xC0000005, `-1073740940` 0xC0000374, or a corrupted GdUnit `100`) flipped a fully-passing run to a
  red `FAILED`. This repeatedly wasted runs and even misled the opencode implementer into reporting a
  "pre-existing crash." **Fix:** the verdict is now taken from the OUTPUT, with crash exit codes
  downgraded to warnings when results are clean. Per phase: Import fails only on a SCRIPT/Parse/Compile
  error; Smoke on a missing marker / SCRIPT ERROR; each validator on a `^FAIL`/SCRIPT-ERROR marker or
  a non-crash nonzero exit (a real failure `quit(1)`s → exit 1, which is NOT a crash code, so it still
  fails); GdUnit on the summed `errors|failures` across its `Statistics:` lines (>0 = fail; no
  statistics = fail), never on the exit code. A known teardown-crash code with otherwise-clean output
  is logged as a `~ teardown-flake … ignored` warning and the gate still exits 0 (`ALL PHASES GREEN
  (with N teardown-flake warning(s) ignored)`). Verified: ran the gate 3×; one run hit the flake (2
  warnings) and still correctly reported GREEN / exit 0, the other two were clean. Real failures still
  fail (validator quit(1)=exit 1 and GdUnit failures>0 are not crash codes / are caught by statistics).
  Net: green output → green gate, and the flake is visible-but-not-fatal. This supersedes the manual
  "re-run in isolation to confirm the flake" dance noted in the 2026-06-24/06-27 decisions.

- **2026-06-27 — D3-D balance pass: multi-day pre-invasion IJFS + screen-preferential targeting
  (implemented via opencode, user-requested levers):** Two user-chosen levers to make the crossing
  survivable. **(1) Multi-day pre-invasion IJFS (`GameState`).** The first IJFS of the game now runs
  `PRE_INVASION_IJFS_DAYS = 4` daily cycles (the air campaign: several days attriting anti-ship
  platforms + a final suppression day) instead of one, carrying state forward between cycles; later
  turns run one cycle. The anti-ship writeback was changed to read the **cumulative** target state
  (`ijfs_state.targets`: `destroyed` persists across days, `suppressed` reflects the latest day)
  rather than a single day's `strike_log`, so multi-day attrition actually reaches the firing plan;
  the `resolve_antiship_turn` IJFS-kill decrement is now idempotent (`quantity = original_quantity -
  cumulative_killed`). Validator constraint preserved: `_ijfs_day == turn_number` after the campaign
  (validate_headless_ijfs). **(2) Screen-preferential targeting (`AntishipCrossing`).** Missiles that
  reach homing now weight escort warships (CG/DDG/FFG/FFL) and decoys by `screen_target_preference`
  (data key in `antiship_crossing_config.json`, **3.0**; code default 1.0 so existing synthetic-config
  tests are unchanged), modeling the screen surrounding the transports in the convoy centre — only
  capacity-bearing carrier losses cost landed BNs. A future version will model flotilla geometry +
  attack entry-angle; this is the simple stand-in. **Measured effect (avg 24 seeds, golden TO3
  crossing):** BNs lost at sea **33→~24 of 36**; of ~88 hulls destroyed the screen absorbs ~64 and
  carriers only ~24 (**carrier share 27%**). The crossing is now governed by two tunable knobs;
  screen preference caps protection at screen size (~73 hulls), so once the screen is exhausted
  overflow still hits carriers — driving lethality lower needs fewer missiles (more IJFS days /
  deeper suppression) or a lower leak rate (terminal defence). Verified: import clean; full gate ALL
  PHASES GREEN; golden 20260624 → casualties=2, feba=0.76 byte-stable; new coverage —
  `tests/antiship_crossing_test.gd` screen-preference case + `validate_headless_antiship.gd`
  cumulative-attrition reconciliation (writeback destroyed == cumulative target-state destroyed, > 0).
  **Retrospective triage** (see `RETROSPECTIVES.md 2026-06-27 D3-D balance`): acted now — added the
  cumulative-writeback test + "TOTAL not per-turn delta" invariant comments at both sites; the
  idempotent decrement already mitigates the in-place-mutation concern. Deferred — moving
  `PRE_INVASION_IJFS_DAYS` / `screen_target_preference` into scenario data (currently a const + a
  config key). See the updated Open Question "D3-D crossing lethality calibration".

- **2026-06-27 — D3-D anti-ship GameState wiring + BN↔ship mapping + C2 suppression (direct; D3
  milestone complete):** Wired `GameState.resolve_antiship_turn(dice)` to thread D3-B2 firing plan →
  D3-B3 crossing → D3-C mines, runs after `resolve_ijfs_turn` and before `resolve_offload_turn`
  (IJFS suppresses, then the crossing attrits the wave, then survivors land). Decisions / divergences:
  **(1) BN↔ship mapping (`scripts/ShipLoadingModel.gd`, new pure lib).** The user chose to derive
  the sent ships from BNs at sea (not a reporting-only stub). `build_sent_snapshots` does a **min-lift
  greedy** load — fill highest-capacity carriers first (capacity desc, ties by ship_type),
  `sent = mini(ready, ceil(remaining/cap))` — then appends the full escort+decoy screen (all ready
  sail). `resolve_bn_losses` converts destroyed hulls → `capacity_lost = Σ destroyed×capacity` →
  `bn_count_lost = floor(capacity_lost + accumulator)`, carrying the fractional + pool-exhaustion
  remainder across turns, and draws the specific lost BN ids via `dice.shuffle_indices(n)`.
  Simplifications: every BN is 1.0 BN-equiv; the amphibious-vs-cargo ship-eligibility split is dropped
  (any carrier lifts any BN). **(2) IJFS (TO,type) suppression join — decision 1-A.** Ported TIV's
  `build_antiship_targets`: `AntishipLoaders.load_containers` + `IjfsLoaders.build_antiship_targets`
  emit **one IJFS target per platform-group container** (an "operating bin", `systems_represented`
  carried in metadata), so strikes hit whole bins and the writeback keys by `encode_key(to,type)` —
  resolving the **D4-H Open Question** (TO linkage) as a pure data/loader change. Container granularity
  was essential: per-individual aircraft targets spread IJFS strikes too thin (41% suppressed); bins
  raised it to ~72%. **(3) C2 suppression (user decision).** A TO's mobile shoot-and-scoot coastal
  launchers (types 23/24) can't be IJFS-targeted directly; they depend on the TO's C2 node (type 99)
  for over-the-horizon targeting. So when the IJFS suppresses a TO's C2, every surviving anti-ship
  system in that TO fires at `C2_SUPPRESSED_FIRE_MULTIPLIER = 0.70` (stacking on direct per-system
  suppression). **No C2 destruction mechanic** — suppression already models the staff being knocked
  out. C2 itself never fires (excluded from the firing loop), so the suppressed-C2-TO set is computed
  up front from the writeback. **(4) Mine danger bound — decision 2-iii.** `MineWarfareService` caps
  dangerous mines per lane (`DEFAULT_MAX_DANGEROUS_PER_LANE = 10`) until the first successful transit
  clears+marks the lane. **(5) Phase order + offload seam.** Ship losses remove BNs from
  `ship_reserve` (D3-D now actually applies `lost_at_sea`, absorbing the formerly-deferred D3-F
  BN-removal) and feed `register_ship_losses`; `_apply_ship_losses_to_fleet` keeps `ShipState`
  invariants. **(6) Observation contract.** Added an `antiship` block to `LLMGameAPI.observation`
  (+ schema required-key + validator required-key + regenerated `red_turn1` fixture), mirroring the
  D4-H `ijfs` block. **(7) `validate_dos_consumption` relaxed:** the anti-ship phase can legitimately
  remove the entire landing wave at sea, so a turn may land zero forces and consume zero supply — the
  full-`resolve_turn` hook now asserts "pool did not increase" (exact consumption math stays covered
  by the isolated idle/activity cases). Verified: import clean; `tools/validate_headless_antiship.gd`
  (reconciliation: BNs removed == bns_lost_at_sea == pending_lost_at_sea; fleet `validate()`;
  determinism; **C2-suppressed TO fires strictly fewer systems**) + full gate ALL PHASES GREEN; golden
  20260624 → casualties=2, feba=0.76 byte-stable (anti-ship draws its own substream). **Open balance
  finding (see Open Questions):** for the golden scenario the wave crosses into **TO3**, but the IJFS
  suppressed **TO4/TO5** C2 (not TO3), so the 30% penalty never applies to the assaulted TO and 33/36
  BNs are still lost — non-aircraft fire-%/range calibration is the next lever. See
  `RETROSPECTIVES.md 2026-06-27 D3-D`. **D3 milestone complete — push.**

- **2026-06-27 — D3-B3 anti-ship crossing model ported (direct, count-based path):** Ported TIV
  `services/antiship_crossing.py` into `scripts/AntishipCrossing.gd` (pure RefCounted) — the
  6-stage missile-crossing pipeline (`resolve_crossing_damage` + `CrossingResult` ledgers +
  `validate_combat_catalog`/`validate_crossing_config`). **Implemented directly, not via opencode**
  (the largest, most RNG-draw-order-sensitive D3 sub-task; same rationale as D4-G/D3-B2). Key
  decision / documented divergence: **(1) Count-based path, not per-hull.** TIV's live
  `resolve_crossing_damage` dispatches stage 3 (escort interception) and stages 5/6 (terminal
  defense + damage) to **per-hull** variants (`_apply_interception_per_hull`,
  `_apply_terminal_defense_and_resolve_damage_per_hull`) that track each escort's `IndividualShip`
  magazines (hq10/hhq9 via `services.ship_ammo`) and apply damage-status combat multipliers
  (`services.ship_readiness_policy`), using **nested RNG substreams** seeded from the main rng.
  HexCombat models none of that ship-ammo/readiness subsystem. This port uses the **count-based
  stages also present in the TIV source** (`_apply_interception`, `_apply_terminal_defense`,
  `_resolve_damage`) — every assertion in `test_antiship_crossing.py` holds under them because the
  test escort `attempts`/`success_prob` are set so per-hull ammo never binds, and the damage math
  (fresh→damaged→sunk, re-hit fragility, overkill→wasted) is identical. Per-hull escort-magazine
  depletion across days is a real full-sim mechanic — **deferred (Open Question: per-hull ship
  magazines)** until HexCombat models ship ammo. (2) **RNG via injected `Dice`**, mirroring source
  **formulas + draw order**, not Python's PRNG bitstream (per AGENTS.md): `rng.random()`→`randf()`,
  `rng.shuffle`→`shuffle_indices`, `rng.choice`→`weighted_choice(ones)`, `rng.choices(pop,w,k)`→
  `weighted_choices(w,k)`, `rng.randrange(n)`→`weighted_choice(ones(n))`. Tests assert structural
  invariants + deterministic outcomes (not exact counts that would depend on the bitstream); two-run
  determinism holds via `SeededDice`. (3) **Tuple→String-key parity:** ledgers keyed by munition/
  ship-type strings (no tuple-key issue here). (4) **Theater range-tier data injected**
  (`active_tos`/`to_adjacency` params, default empty → own_to) to keep the lib pure (no `GameData`
  autoload dependency); the real-catalog test passes `theaters.json`'s TO graph. (5) **CrossingResult
  → Dictionary** of ledgers + computed `missile_stage_totals`/`casualty_totals` (the established
  dataclass→Dictionary divergence). (6) **`systems_fired` rows** read `location`/`to` +
  `type` + `systems_fired` (the D3-B2 `resolve_launch_attrition` output adapts to this in D3-D).
  Verified: import clean; `tests/antiship_crossing_test.gd` 15/15 (full `test_antiship_crossing.py`
  mirror incl. the real-shipped-config smoke test asserting reconciliation invariants + no warnings);
  full gate green (150→165 GdUnit cases); golden seed 20260624 → casualties=2, feba=0.76 byte-stable.
  **D3-B (magazine + firing plan + crossing) milestone-internal complete.** See
  `RETROSPECTIVES.md 2026-06-27 D3-B3`. Next: **D3-D** (GameState `resolve_antiship_turn`: thread
  D3-B2 firing → D3-B3 crossing → D3-C mines, propagate `lost_at_sea`, IJFS (TO,Type) join, tune mine
  lethality) — the final D3 sub-task before milestone push.

- **2026-06-27 — D3-C mine warfare ported (direct, deliberately simplified):** Ported the
  sweep/sink core of TIV `services/antiship/mine_warfare_service.py`
  (`MineWarfareService.resolve_ship_losses`) into `scripts/MineWarfareService.gd` (pure RefCounted).
  Per target beach, in **ascending beach_id order** (so the shared surviving-fleet pool depletes
  deterministically and a hull never sinks twice): minesweepers clear
  `min(remaining, assigned*mines_per_sweeper_per_day)`; each remaining unswept mine sinks one ship;
  the ship **type** is drawn from the surviving pool weighted by remaining count and removed.
  Deliberate divergences from the TIV oracle (all in-spirit of the settled simplified-slice
  philosophy — cf. D2 single-pool supply, D1 deferred ship geometry, D3-A geometry-free `Minefield`):
  (1) **Geometric danger model dropped.** TIV scatters mines via Python's **string-seeded Mersenne
  Twister** and filters "dangerous" mines by a ship-path danger-radius, plus builds beach/lane
  polygons. That RNG is **not reproducible in Godot**, the geometry fields are **absent from
  HexCombat's `Minefield`**, and the polygons are **UI-only** (D3 is headless, no new UI). So
  **dangerous mines == remaining unswept mines** — and in TIV's own test configs the danger radius
  already spans the whole beach (`|mine_x−500| ≤ 500` for all `mine_x∈[0,1000]`), so its dangerous
  count equals `num_mines` there too, making this behavior-preserving for the mirrored cases.
  *Balance note:* without the geometric filter every unswept mine is lethal, so the 100-mines/beach
  defaults (D3-A) are very lethal un-swept — flag for **D3-D** wiring / tuning. (2) **Same-day
  re-preview baseline dropped.** TIV recomputes from a saved day-start baseline when re-run on the
  same day (a web-UI idempotency concern); HexCombat resolves each turn exactly once through the
  action layer, so `last_resolved_day`/`*_day_start` are unnecessary — the one pytest exercising it
  (`test_same_day_rerun_…`) is the only one of seven not mirrored. (3) **Ship-type selection via
  injected `Dice.weighted_choice`** replaces Python's non-portable string-seeded `random.choices`,
  mirroring the **formula + one-draw-per-sinking order** per the AGENTS RNG strategy; determinism in
  tests comes from `SeededDice(seed)`. (4) **"Disabled beach" = no `Minefield` for that target
  beach** → skipped summary `{status:"disabled"}` (HexCombat's `Minefield` has no `enabled` flag;
  presence in the loaded set is enablement). (5) `int`/`String` assignment keys both accepted
  (faithful to TIV). Verified: import clean; `tests/mine_warfare_test.gd` 8/8; full gate green
  (142→150 GdUnit cases); golden seed 20260624 → casualties=2, feba=0.76 byte-stable (mine warfare
  uses its own injected stream, never combat RNG). See `RETROSPECTIVES.md 2026-06-27 D3-C`. Next:
  **D3-B3** (crossing model) then **D3-D** (GameState wiring: `resolve_antiship_turn`, `lost_at_sea`,
  IJFS (TO,Type) `to_number` join).

- **2026-06-27 — D3-B2 anti-ship firing plan ported (direct):** Ported `antiship_firing_plan.py`
  (`build_firing_plan`) + `antiship_allocation.py` (`allocate_firing_to_rows`) +
  `antiship_launch_attrition.py` (`resolve_launch_attrition`) into the new pure RefCounted
  `scripts/AntishipCalculator.gd`. **Implemented directly, not via opencode** — launch attrition is
  RNG-draw-order-sensitive and the firing plan has subtle largest-remainder + full-volley magazine
  gating; the handoff sanctions direct implementation for intricate RNG-sensitive sub-tasks
  (precedent: D3-A, D3-B1, D4-F/G/H). Decisions / faithful-port divergences:
  (1) **Tuple keys → `"<to>:<type>"` String keys.** TIV keys `firing_percentages` /
  `destroyed_fire_percentages` / `destroyed_firing_plan` on `(location, type_key)` tuples; GDScript
  Dictionaries can't key on value-arrays (Arrays compare by reference), so all four maps use
  `"<to>:<type>"` String keys via `AntishipCalculator.encode_key`. `type_key` is always int in
  HexCombat data, so TIV's `_normalize_type_key` str-fallback for non-numeric types is unexercised
  (a `_decode_key` helper still parses back to int when numeric for the summary ordering). (2)
  **Single-row allocation.** HexCombat's `AntishipSystem` rows are pre-aggregated one-per-(TO,type)
  by `AntishipLoaders`, so the per-container row split collapses to a single row; `allocate_firing_to_rows`
  is still ported faithfully (proportional largest-remainder, remainder ties to earlier rows) and
  unit-tested directly for the multi-row behavior even though `build_firing_plan` only calls it
  single-row. (3) **In-place row mutation replaces the pandas `systems_expended` copy.**
  `build_firing_plan` is pure (returns `{allocation_plan, destroyed_firing_plan}`, no mutation);
  `resolve_launch_attrition` mutates the `AntishipSystem` rows by `row_idx` (array index) — `active`,
  `quantity` (−attempted, clamp 0), `fired`/`expended` (+launched), `destroyed_this_turn` and
  `destroyed` (+pre+post). TIV's `Total_Destroyed_Cumulative` maps to `AntishipSystem.destroyed`;
  the `Final_Attrition_Pct` reporting-only derived column is not ported. (4) **RNG via injected
  `Dice`.** Per attempted shot: `dice.randf() < p_destroy` (=clamp(p_detect·p_destroy_if_detected));
  a second `dice.randf() < p_intercept_before_launch` ONLY when the first kills — exact source draw
  order. Launch-attrition config = the `launch_attrition` section of
  `data/antiship/antiship_crossing_config.json` (per-type with `_default` fallback; flat-config
  short-circuit preserved). (5) **C2 filter** on `type_id == 99` (`SYSTEM_TYPE_C2`), mirroring the
  source. Verified: import clean; `tests/antiship_firing_plan_test.gd` 9/9 (incl. the two
  `test_antiship_firing_plan.py` magazine-gating mirrors — shared-pool-once-across-locations and
  short-magazine-gates-before-row-split); full gate green (golden seed 20260624 → casualties=2,
  feba=0.76 byte-stable; 133→142 GdUnit cases). **Note (flake):** the gate's overall verdict is
  intermittently `FAILED` from a Godot 4.7 *teardown* segfault (exit `-1073741819` / 0xC0000005) in
  random SceneTree validators (`validate_no_global_rng`, `validate_symbol_map`, …) run back-to-back —
  all 142 cases PASS every run and the flagged validators pass deterministically (exit 0) in
  isolation; pre-existing, unrelated to this pure-lib change. See `RETROSPECTIVES.md 2026-06-27 D3-B2`.
  Next: **D3-B3** (crossing model) and **D3-C** (mine warfare) — dependency-independent.

- **2026-06-26 — D3-B split into B1/B2/B3; D3-B1 magazine service ported (direct):** The planned
  single `AntishipCalculator` (firing plan + crossing + magazine) is ~2,100 lines of TIV source with a
  tight dependency chain (firing plan needs the magazine reservation context — both firing-plan pytests
  exercise it), so D3-B is split **magazine (B1) → firing plan (B2) → crossing (B3)**, each a
  gated/committed unit. **D3-B1:** ported the *calculator-pure* parts of `antiship_magazine_service.py`
  into `scripts/AntishipMagazine.gd` — `MagazineReservation`-equivalent state seeded from
  `data/antiship/antiship_magazine_defaults.json` (single source of truth; the Python `_DEFAULTS`
  mirrors that JSON), `cap_launcher_count`, `reserve_full_volley` (additive / cross_draw / aircraft_pool
  modes, full-volley-or-nothing), `deduct_launcher_kills` (aircraft exempt). **Did NOT port the DB
  funcs** (`load_magazine_rows`/`seed_magazines_if_empty`/`persist_reservations`/`create_reservation_context`)
  — HexCombat has no DB; the pure reservation math is the slice. Faithful-port notes: integer floor
  division for the aircraft-pool `// mpl` cap (`@warning_ignore("integer_division")`); `_sorted_entries`
  reproduces Python's `-is_primary` ordering via a stable primary-then-secondary partition (GDScript
  `sort_custom` isn't guaranteed stable). 9 GdUnit cases mirror `test_antiship_magazine_service.py`
  (additive 19→block_i/surface, cross_draw fallback 20, aircraft_pool caps/primary-first 3, cap-exceeded
  block, ground deduction 5, aircraft exemption, full-volley exact+shortfall, cap_launcher_count). Gate
  green; golden 20260624 → casualties=2, feba=0.76 unchanged. Next: **D3-B2** (firing plan; IJFS
  coupling stays a plain input dict — the (TO,Type)/`to_number` join is deferred to D3-D wiring).

- **2026-06-26 — D3-A anti-ship data + models (direct):** Ported the D3 data layer. Decisions:
  (1) **TIV configs copied verbatim** into `data/antiship/` (systems_consolidated, grouping_spec,
  combat_catalog, crossing_config, magazine_defaults) — same precedent as D4-A; copying avoids
  transcription error on ~30KB of interdependent tuning data. The combat/crossing/magazine files are
  loaded as Dictionaries (the D3-B calculator consumes them); only systems + minefields expand into
  typed Resources. (2) **System rows aggregated by (TO, type_id).** The grouping spec stores platform
  groups as index-aligned `group_sizes[]` / `to_assignments[]`; the same (type, TO) recurs across
  entries (e.g. aircraft type 3, static sites type 5), so `AntishipLoaders.load_systems` sums quantity
  per (TO, type_id) into one `AntishipSystem` row — matching the firing plan's (TO, Type) keying
  (`FiringAllocationRow`) rather than TIV's per-container "Option B-lite" storage. Expansion yields
  **650 platforms** total (Keelung 4 / Cheng Kung 10 / Kang Ding 6 / Chi Yang 6 / Kwang Hua 30 / Tuo
  Chiang 12 / Anping 12 / aircraft 334 / coastal-HF 26 / coastal-Harpoon 100 / static-CDCM 104 /
  subs 2 / C2 4), all in TOs 2–5. (3) **Deprecated types dropped:** the grouping spec only references
  current type_ids (3, 5, 6, 16–24, 99); legacy platform groups 1/2/4 and 7–15 (in the catalog for
  backward compat) emit no rows. C2 (type 99) IS emitted from the grouping spec (carries
  `special:"C2"`); the D3-B firing plan will filter it (it is not a firing system). (4) **Minefields
  recovered:** D1-A stripped the `Minefield` blocks from `data/beaches.json`; recovered them into
  `data/antiship/minefields.json` (9 beaches × 100 mines, 1 mine/sweeper/day, `available_minesweepers`
  6 per `AntishipMinefieldSummary` default), carrying `to_number` for D3-C. `ships.json` + ShipDef/
  ShipState were already in place from D0-C — D3-A did not recreate them. Gate green; golden seed
  20260624 → casualties=2, feba=0.76 unchanged. See `RETROSPECTIVES.md 2026-06-26 D3-A`. Next: **D3-B**
  (`AntishipCalculator`: firing plan + crossing damage + magazine expenditure) — resolve the
  IJFS-target `to_number` stamping there (D4-H Open Question) so suppression joins per (TO,Type).

- **2026-06-26 — D4-H IJFS GameState wiring + writeback (direct); D4 milestone complete:** Wired
  `GameState.resolve_ijfs_turn(dice)` into `resolve_turn` (after `resolve_offload_turn`, before
  maneuver/combat — IJFS suppresses anti-ship systems for D3 and is conceptually Red's joint fires
  preceding the ground fight). `IjfsDailyState` is loaded once in `reset_to_scenario`
  (`_rebuild_ijfs_state`, incl. `enrich_sam_scores`) and advanced via `IjfsEngine.carry_to_next_day`
  at the start of each `resolve_ijfs_turn` after day 1. Decisions: (1) **RNG isolation is mandatory
  and dice-type-aware.** IJFS must never consume the combat dice. `SeededDice.derive()` returns a
  fresh independent stream (combat reproducible + isolated), but `ScriptedDice.derive()` returns
  `self` (shared queue) — so for scripted-combat unit tests we instead seed an independent
  `SeededDice.new(hash("ijfs:<turn>"))`. Verified: the golden seed 20260624 → casualties=2, feba=0.76
  is byte-stable with IJFS now running every `resolve_turn`, and all ScriptedDice combat suites stay
  green. (2) **Writeback keyed by Type, not (TO,Type).** The handoff/D3 want anti-ship destroyed/
  suppressed per **(TO,Type)**, but `data/ijfs/targets_master.json` carries **no `to_number`** (nor
  battalion/brigade IDs) on targets — so `last_ijfs_writeback` aggregates anti-ship by **subcategory
  (Type)** only, and the maneuver-casualty list (faithful port of
  `ijfs_maneuver_writeback_service.compute_maneuver_writeback`) stays **empty** because the target
  metadata lacks `battalion_id`. Both are structured so adding TO/IDs later is a pure data change.
  See **Open Question: D4-H writeback (TO + ground-casualty) linkage**. (3) **DB-backed TIV writeback
  not ported.** TIV's `ijfs_writeback_service`/`target_system_writeback_service` mutate SQL via repos;
  HexCombat has no DB — the in-memory ledger aggregation on `GameState` is the slice's equivalent and
  the forward-compat seam D3-B consumes. (4) **Theater CAS/CRBM into combat deferred** — IJFS does not
  produce a CAS/CRBM combat-support value in the oracle; combat support inputs stay as-is (revisit when
  D5/front-line or an explicit fires-support rebalance lands). (5) **Observation contract extended:**
  added an `ijfs` block to `LLMGameAPI.observation` (last summary + writeback aggregates), added `ijfs`
  to the schema (`schemas/llm_observation.schema.json`) + the validator's required-key list, and
  regenerated `docs/examples/llm_observation_red_turn1.json` (+11 lines, no reformat). Verified: import
  clean; full gate ALL PHASES GREEN; 124 GdUnit cases unchanged (D4-H is validator-tested, not GdUnit —
  integration assertions live in `tools/validate_headless_ijfs.gd` per the SceneTree/teardown-flake
  rule); golden byte-stable. **D4 (IJFS) milestone complete.** See `RETROSPECTIVES.md 2026-06-26 D4-H`.

- **2026-06-26 — D4-G IJFS daily orchestration ported (direct, not opencode):** Ported
  `run_daily_ijfs.py` (6-phase sequence) + `run_context.py` (day-semantics) + `logging_utils.summarize_run`
  into `scripts/ijfs/IjfsEngine.gd`, with `scripts/ijfs/IjfsDailyState.gd` as the in-memory state
  container (port of `state.py` `IJFSDailyState`). **Implemented directly, not via opencode** — D4-G is
  the central integration tying all six prior libs together with strict RNG-draw-order requirements
  across phases; the free model's risk of subtle, hard-to-catch fidelity bugs is highest exactly here,
  and the handoff sanctions direct implementation for intricate sub-tasks (precedent: D4-F). Decisions:
  (1) **No `write_outputs` file IO** (per handoff): `run_daily(state, dice, current_day, warmup_context=null)`
  returns the ledgers dict directly — `metadata`, `detection_log`, `strike_log`, `target_status_after`,
  `munition_inventory_after`, `engagement_log`, `contest_log`, `free_shot_log`, `air_oob_after`, `summary`.
  (2) **Single shared `Dice` replaces Python's `state.rng`**, threaded into every probabilistic phase in
  source order (exquisite-intel → satellite → pre-AD strike → SEAD → aircraft detect → post-AD strike →
  free shot), preserving draw order. (3) **In-memory continuity** via `carry_to_next_day(state)`, which
  reproduces `loaders.load_targets`'s runtime-reload reset (clear `suppressed`/`suppressed_this_turn`/
  `sead_result`; `destroyed`/`known_to_red`/`last_detected_day`/`detected_this_turn` + munition/squadron
  attrition persist) — the faithful equivalent of TIV's file-roundtrip continuity without file IO.
  (4) **`WarmupContext` → Dictionary** (established Python-dataclass→GDScript-Dictionary divergence);
  `IjfsRunContext` ported as a Dictionary from `make_run_context`. (5) **`IjfsTarget.to_dict()`** added,
  mapping GDScript sentinels back to the source's `None` (`last_detected_day`/`sam_score == -1` → null,
  `sead_result == "" ` → null) for faithful ledger/skip-log shapes. (6) **`air_oob_after`** built from the
  `Array[IjfsSquadron]` as `{model_version:3, squadrons:[…], provenance:{}}` mirroring
  `SquadronForce.to_dict`. Verified independently: import clean; full gate ALL PHASES GREEN; GdUnit
  119→124 cases (5 new engine tests mirroring `test_run_daily_outputs_and_continuity` + dedup +
  TestBudgetRouting); ground-combat golden seed 20260624 → casualties=2, feba=0.76 byte-stable
  (two-run deterministic). Note: the "238 cases" figure in earlier notes counted assertions, not
  GdUnit test methods — the real method count is 124. See `RETROSPECTIVES.md 2026-06-26 D4-G`.
  Next: **D4-H** (GameState wiring + writeback), then push the D4 milestone.

- **2026-06-26 — Implementer switched pi → opencode; retrospective loop added:** The `pi` CLI is
  unusable on this Windows box — it spawns its `opencode` provider backend via `spawn('opencode')`
  (no `shell:true`), which can't resolve the Windows `.cmd`/`.ps1` shim and dies `ENOENT`. Per user
  direction, the orchestrator now drives **`opencode` directly** (`opencode run -m
  opencode/deepseek-v4-flash-free`; `--agent explore` read-only, build agent auto-allows writes,
  `-s` for session continuity). Updated `CLAUDE.md`, `AGENTS.md`, `.claude/settings.json`
  (`Bash(opencode *)`), `docs/LLM_PLAYTESTING.md`; **left dated pi references in the logs intact**
  (append-only history). Caveat: the default model is a small free model (weaker than the prior
  GPT-5.5) → tighter briefs, higher orchestrator review bar. New **per-sub-task retrospective loop**
  (user-requested): after implementation + gating, ask the implementer "knowing what you know now,
  what would you do differently?", then the orchestrator reviews **both** the diff and the lessons.
  Design decisions → this log; implementer lessons + triage → new `docs/RETROSPECTIVES.md`. The
  active build plan/backlog for the next orchestrator is `docs/ORCHESTRATOR_HANDOFF.md`. Also: D4-F
  (SEAD + AD-health + warmup) was completed directly (pi quota exhausted) and committed (e20c582);
  gate green at 238 GdUnit4 cases, golden invariant unchanged. Next: **D4-G** (daily orchestration).

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
  question — resolved in-spirit of the settled design. _[corrected 2026-06-29: hex_43_17 was NOT
  actually a HexMath neighbor of beach hex hex_44_16 — that "adjacency" relied on the odd-r/axial
  coordinate bug since fixed; beach-1 Green is now hex_43_16. See the 2026-06-29 hex-adjacency entry
  above.]_
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
  Revisit with scenarios in Track C. **→ SUPERSEDED 2026-06-28:** user is now defining victory
  conditions — see Open Questions → "Victory conditions (design in progress)".
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

- [x] **D3-A** *(2026-06-26)* — Data + models. `data/ships.json` + `ShipDef`/`ShipState` already
      existed (D0-C). Added: `data/antiship/` (5 TIV configs copied verbatim — systems catalog,
      grouping spec, combat catalog, crossing config, magazine defaults — + `minefields.json`
      recovered from TIV `beaches.json`); `scripts/model/AntishipSystem.gd` (per-(TO,type) row,
      mirrors `AntishipSystemEntry`), `scripts/model/Minefield.gd` (per-beach, mirrors
      `AntishipMinefieldBeachSummary`); `scripts/AntishipLoaders.gd` (expands the grouping spec into
      650 systems aggregated by (TO,type_id); loads catalog/crossing/magazine/minefields, fail-loud);
      `tools/validate_antiship_data.gd` (per-type totals, aggregation uniqueness, catalog/crossing/
      magazine/minefield shapes). Gate green; golden invariant unchanged.

- **D3-B — split** (the original "firing plan + crossing + magazine in one lib" is ~2,100 lines of
  TIV source; dependency order is magazine → firing plan → crossing → calculator orchestration):
  - [x] **D3-B1** *(2026-06-26)* — Magazine service: `scripts/AntishipMagazine.gd` (calculator-pure
        port of `antiship_magazine_service.py` — `from_defaults`, `cap_launcher_count`,
        `reserve_full_volley` [additive / cross_draw / aircraft_pool], `deduct_launcher_kills`; DB
        seed/persist not ported — seeds from `antiship_magazine_defaults.json`).
        `tests/antiship_magazine_test.gd` (9 cases mirroring `test_antiship_magazine_service.py`).
        Gate green; golden unchanged.
  - [x] **D3-B2** *(2026-06-27)* — Firing plan: `scripts/AntishipCalculator.gd` —
        `build_firing_plan(systems, ijfs_destroyed, target_locations, firing_percentages,
        destroyed_fire_percentages, magazine)` over `AntishipSystem` rows (aggregated by (TO,type),
        so the per-container `allocate_firing_to_rows` is single-row); C2 (type 99) excluded;
        magazine `cap_launcher_count` + full-volley gate via D3-B1. Ports
        `antiship_allocation.allocate_firing_to_rows` (proportional largest-remainder) +
        `antiship_launch_attrition.resolve_launch_attrition` (per-shot RNG draw order, inventory
        mutation, systems-fired / launch-attrition summaries). `tests/antiship_firing_plan_test.gd`
        (9 cases: the 2 TIV magazine-gating mirrors + C2/no-magazine/destroyed-only + allocate +
        scripted launch-attrition). Gate green; golden 20260624 → casualties=2, feba=0.76 unchanged.
        IJFS coupling stays a plain `"<to>:<type>"`→count input dict (the (TO,Type) `to_number`
        join is wired in D3-D).
  - [x] **D3-B3** *(2026-06-27)* — Crossing model: `scripts/AntishipCrossing.gd` (pure RefCounted) —
        `resolve_crossing_damage(systems_fired, ship_snapshots, combat_catalog, crossing_config,
        target_tos, dice, active_tos, to_adjacency)`: the 6-stage count-based pipeline (launches +
        global munition/store-group pools + range-tier gating + partial-fire → in-flight failures →
        escort interception in groups → weighted homing + decoy discrimination → terminal defense →
        damage resolution with fresh/damaged/sunk hull states + re-hit fragility). Returns per-stage
        ledgers + `missile_stage_totals`/`casualty_totals`. `validate_combat_catalog` /
        `validate_crossing_config` ported (fail-loud). Count-based port (per-hull escort-magazine
        refinement deferred — see Decisions). `tests/antiship_crossing_test.gd` (15 cases — full
        `test_antiship_crossing.py` mirror incl. the real-catalog smoke test, no warnings). Gate
        green (150→165 GdUnit cases); golden 20260624 → casualties=2, feba=0.76 byte-stable.
        **D3-B (anti-ship calculator: magazine + firing plan + crossing) COMPLETE.**

- [x] **D3-C** *(2026-06-27)* — Mine warfare: `scripts/MineWarfareService.gd` (pure RefCounted) —
      `resolve_ship_losses(minefields, target_beaches, assignments, fleet_pool, dice)`: per beach
      (ascending beach_id), minesweepers clear `min(remaining, assigned*mines_per_sweeper)`, each
      remaining unswept mine sinks one ship (type drawn from the surviving fleet pool weighted by
      count via injected `Dice.weighted_choice`), pool depleted in place across beaches; mutates the
      matched `Minefield` rows + returns per-beach resolutions. `status_color` ported. Geometry-free
      simplified port (see Decisions). `tests/mine_warfare_test.gd` (8 cases mirroring 6 of the 7
      `test_antiship_mine_warfare_service.py` behaviors + lane/status). Gate green; golden 20260624 →
      casualties=2, feba=0.76 unchanged.

- [x] **D3-D** *(2026-06-27)* — GameState wiring: `GameState.resolve_antiship_turn(dice)` threads
      firing plan (D3-B2) → crossing (D3-B3) → mines (D3-C); the crossing wave = BNs at sea, mapped to
      a sent fleet via the new `ShipLoadingModel.gd` (min-lift greedy carrier fill + escort/decoy
      screen). Ship losses → BNs lost at sea, removed from `ship_reserve` and propagated via the D0-C
      `register_ship_losses` seam (fractional accumulator carried across turns). IJFS suppression joins
      per **(TO,type)** via container-level dynamic targets (decision 1-A, resolves the D4-H Open
      Question); **C2 suppression** (type 99) costs a TO 30% of its surviving anti-ship firing
      (`C2_SUPPRESSED_FIRE_MULTIPLIER`, no C2 destruction — user decision); bounded per-lane mine
      danger with first-transit lane clearing (decision 2-iii). LLM observation gains an `antiship`
      block (+schema/validator/fixture). `tools/validate_headless_antiship.gd` (reconciliation +
      determinism + C2-reduces-firing). Gate green; golden 20260624 → casualties=2, feba=0.76
      byte-stable. **D3 (anti-ship & mine warfare) milestone COMPLETE.** *Balance flag:* see Open
      Questions — for the golden scenario the wave crosses into TO3 whose C2 the IJFS did not suppress,
      so 33/36 BNs are still lost; non-aircraft fire-%/range calibration is the next tuning lever.

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
- [x] **D4-F** *(2026-06-26, committed e20c582)* — SEAD + AD health + warmup (`engagement.py`,
      `ad_health.py`, `warmup_profiles.py`) → `IjfsEngagement.gd` / `IjfsAdHealth.gd` / `IjfsWarmup.gd`.
- [x] **D4-G** *(2026-06-26)* — daily orchestration + continuity (`run_daily_ijfs.py` 6-phase sequence
      → `IjfsEngine.gd` + `IjfsDailyState.gd`). `run_daily(state, dice, current_day, warmup_context)`
      returns the ledgers dict directly (no `write_outputs` file IO); `summarize_run` ported;
      `carry_to_next_day` reproduces the loader reload reset for in-memory continuity. 5 GdUnit cases
      mirror the oracle full-run/continuity/dedup/budget-routing tests. Gate green (124 cases); golden
      invariant byte-stable.
- [x] **D4-H** *(2026-06-26)* — `GameState.resolve_ijfs_turn(dice)` wiring + writeback. Runs
      `IjfsEngine.run_daily` each turn on an **independent** IJFS substream (golden byte-stable),
      stores `last_ijfs_summary` + `last_ijfs_writeback` (anti-ship destroyed/suppressed **by Type**
      — TO unavailable in target data, see Open Question; SAM destroyed/suppressed; maneuver-casualty
      port). Hooked after offload, before maneuver/combat. `EventBus.ijfs_resolved`; `LLMGameAPI`
      `ijfs` observation block (schema + validator required-key + regenerated fixture);
      `tools/validate_headless_ijfs.gd` in the gate. **D4 (IJFS) milestone complete — pushed.**
      *Deferred:* theater CAS/CRBM into combat (combat `supply_effectiveness`/support inputs stay as-is);
      ground-casualty ID linkage (see Open Question).

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

- [x] **D5-A** *(2026-06-27)* — `scripts/FrontLineService.gd` (pure RefCounted, static funcs):
      `haversine_km` (exact port of TIV `_haversine_km`), `polyline_cumulative_lengths`,
      `interpolate_along_line`, `point_to_hex` (nearest hex CENTER by haversine — faithful to TIV
      `core/hex_grid.point_to_hex`), `sample_polyline` (vertices + 2 km-interval segment midpoints),
      `find_hexes_for_polyline` (= map `sample_polyline` points → `point_to_hex`, dedupe first-seen),
      and `distribute_units_along_hexes` (even `floor(k*M/N)` assignment — HexCombat-specific, replaces
      TIV's per-battalion lat/lon spacing since brigades are hex-positioned, not lat/lon-positioned).
      Coords are `Vector2(lat,lon)`; hex centers passed as `Array[{id,lat,lon}]` to keep the lib pure.
      `tests/frontline_service_test.gd` (23 cases). Ported + refactored via two opencode subagents;
      gate ALL PHASES GREEN; golden 20260624 → casualties=2, feba=0.76 byte-stable.

- [x] **D5-B** *(2026-06-27)* — GameState wiring (headless; UI split out to D5-D):
      `GameState.resolve_frontline_phase(polyline_coords) -> Dictionary` (no RNG — deterministic, not
      yet auto-called from resolve_turn): `_frontline_hex_centers()` adapter flattens GameData.hexes to
      `[{id,lat,lon}]`; `FrontLineService.find_hexes_for_polyline` → affected = Red non-destroyed
      brigades in the sequence (sorted, snapshotted) → `distribute_units_along_hexes` →
      `GameData.set_brigade_hex`; stores/emits `last_frontline_summary` (`EventBus.frontline_resolved`).
      `tools/validate_frontline.gd` (distribution + empty-polyline + no-brigades + determinism). Gate
      ALL PHASES GREEN; golden byte-stable. Red-only is intentional (TIV single-side filter; commented).

- [x] **D5-C** *(2026-06-27)* — Cleanup: `GameState.resolve_cleanup_phase()` — end-of-turn system
      reset (faithful to TIV `CleanupCalculator.reset_systems`, which is a per-turn flag reset, NOT the
      "residual attrition/isolation" the ROADMAP speculated). Resets the per-turn anti-ship flags
      (`fired`/`expended`/`destroyed_this_turn` → 0, `suppressed`/`active` → false) on the persistent
      `antiship_systems` array — fixing a latent cross-turn accumulation (reset nowhere before) — and
      runs `recompute_hex_ownership()` as the canonical end-of-turn ownership pass. Hooked into
      `resolve_turn` after `resolve_supply_turn`, before `phase = END` (no RNG → golden byte-stable).
      `EventBus.cleanup_resolved`; `tools/validate_cleanup.gd`. Gate ALL PHASES GREEN. (Brigade per-turn
      flags stay in `begin_next_turn`; TIV's Quantity_Moved/Unavailable restore has no HexCombat
      equivalent — both noted in-code.)

- [ ] **D5-D** — Front-line UI + turn integration: HexMap polyline-draw mode (player clicks vertices,
      Confirm commits → `resolve_frontline_phase`), store the drawn polyline as a PLANNING-phase action
      and execute it at the right point in `resolve_turn`, + an `frontline` LLM observation block
      (from `last_frontline_summary`). Needs visual verification. Gate green.

---

## Open questions (settle at the relevant milestone)

_None blocking the slice — the design is settled. Future-phase questions (supply/organization
interactions, fog of war, terrain via ArcGIS, theater fires) are tracked in `ROADMAP.md`._

### Victory conditions  *(DESIGN SETTLED 2026-06-28 — user-driven; supersedes the 2026-06-23 deferral; not yet implemented)*

Replaces the 2026-06-23 "Victory deferred" decision. **Two conditions, both evaluated in the
end-of-turn cleanup**, counting Chinese (PLA) and Taiwanese (ROC) battalions **on Taiwan**.
**Design is settled — this is documentation only; no code yet.**

- **China loses** if at the end of a turn there are **zero Chinese battalions on Taiwan**.
- **China wins** when the number of **Chinese battalions on Taiwan > Taiwanese battalions on Taiwan**
  at the end of a turn.
- (Implied) **neither fires when 1 ≤ Chinese ≤ Taiwanese** → game continues. Equal counts are *not* a
  Chinese win (strictly greater).

**Resolved sub-decisions (user, 2026-06-28):**
- **(a) Start-of-game guard → unconditional by default, but configurable.** The loss check runs
  **every cleanup unconditionally** (so an annihilated/failed crossing that leaves zero Chinese ashore
  ⇒ immediate Chinese loss). **But wire the arming as a config knob** so it can instead be set to fire
  **only after the first landing** (latch once China has ≥1 battalion ashore) or **only after N turns**.
  Implementation sketch: a scenario-level setting, e.g. `victory.loss_check_arm = "unconditional" |
  "after_first_landing" | "after_turn:<N>"` (default `"unconditional"`); the cleanup checker honors it.
- **(b) "On Taiwan" definition → main-island land hexes.** The census counts battalions on the
  **land hexes of the Taiwan main island only**. Offshore islands and sea hexes do **not** count toward
  either side's total. (Needs a way to identify main-island land hexes — terrain/land flag scoped to the
  main island; confirm the data source when implementing.)

**Still-open sub-decisions on Set 1:**
- **(c) Symmetry / winner field.** Assumed zero-sum (China loses ⇒ Taiwan wins; China wins ⇒ Taiwan
  loses), populating a single `winner` field (`"red"`/`"green"`/`null`) plus a `game_over` bool —
  confirm when implementing.
- **(d) Precedence.** The two clauses are mutually exclusive (can't have zero Chinese *and* Chinese >
  Taiwanese), so no conflict; check order is immaterial. Recorded for completeness.

**IMPLEMENTED 2026-06-29 (Track 3a + 3b).** `scripts/VictoryConditions.gd` (pure
`evaluate(china_bn, taiwan_bn, arm, turn_number, china_has_landed)`; opencode-implemented + 9-case
unit suite) is called at the end of `GameState.resolve_cleanup_phase` after `recompute_hex_ownership`
(pure board read — **no dice**, golden RNG untouched). `GameState._taiwan_battalion_census()` sums
`Brigade.get_battalion_count()` by team over placed hexes; new `game_over` / `winner` (`""`/`"red"`/
`"green"`) GameState fields, reset in `reset_to_scenario`, threaded into `TurnResult` + the LLM
observation (schema: optional props, `additionalProperties:true` so fixtures stay valid). Config:
scenario `victory` block (`loss_check_arm`, `taiwan_hexes`) on `GameData.victory_config`. **Resolved
(c):** single `winner` field + `game_over` bool, zero-sum. **Resolved (b) data source:** there is
**no land/island flag** in the hex grid (`taiwan_hex_grid.json` is geometry-only; terrain is a deferred
ArcGIS phase), so `taiwan_hexes: null` = **all placed hexes** count — correct for the main-island
golden scenario (no offshore islands); the `taiwan_hexes` array is the hook for when land data exists.
The **golden scenario uses `after_first_landing`** (PLA starts at sea; `unconditional` would declare a
turn-1 loss before it can land) while the **code default stays `unconditional`** per the design. E2e
gate `tools/validate_golden_victory.gd` plays the golden scenario to a deterministic, reproducible
terminal (turn 1, China win 36>17), asserting winner ⇔ census. Gate green (32 GdUnit suites).

**OPEN (census fidelity — promote to the offload track).** The census counts each landed brigade's
**OOB** `get_battalion_count()`, not its sea-loss-/combat-reduced *present* strength, so China can be
over-counted by battalions lost at sea before landing (the design's "battalions on Taiwan" implies
*present* battalions). For the golden scenario the outcome is robust either way (wave 36, minus ~sea
losses, still > 17 ROC), but the count should eventually reflect surviving battalions. See
`docs/plans/refactor_audit.md`.

### D3-D crossing lethality calibration  *(2026-06-28: exquisite-intel path chosen; warmup wiring IN PROGRESS — see UPDATE below)*

**Update (2026-06-27 balance pass):** two user-chosen levers landed — a **multi-day pre-invasion
IJFS** campaign (`PRE_INVASION_IJFS_DAYS = 4`, cumulative attrition into the firing plan) and
**screen-preferential targeting** (`screen_target_preference = 3.0`: escorts + decoys soak missiles
ahead of the transports). Together these cut golden-scenario BN loss from **33 → ~24 of 36** and hold
carriers to ~27% of destroyed hulls (the screen absorbs ~64 of ~88). Still open: ~24/36 is high, and
screen preference caps at screen size (~73 hulls) — once the screen is gone, overflow hits carriers.
Driving lethality lower needs **fewer missiles** (more IJFS days / deeper suppression) or a **lower
leak rate** (terminal defence / interception), or moving the two knobs into scenario data so designers
can tune per scenario. Remaining candidate levers (design calls for the user):

D3-D's anti-ship crossing is wired and reconciles correctly. Before the balance pass it was
**catastrophically lethal**: for the golden scenario (seed 20260624) the assault wave crosses into
**TO3** and lost **33 of 36 BNs** on turn 1. The two suppression levers in place did not bite here:
- **C2 suppression** (the user's 30% fire penalty) only applies to a TO whose C2 the IJFS suppressed.
  For this seed the IJFS suppresses **TO4 and TO5** C2 — *not* TO3 — so the assaulted TO fires at full
  surviving capacity (283 systems fire). The mechanic is correct and unit-tested (suppressing TO3's C2
  strictly reduces its firing); it simply doesn't trigger for the TO under assault here.
- **Aircraft suppression** works (container granularity → ~72% of air-launched platforms
  destroyed/suppressed), but the **mobile coastal launchers** (types 23/24, ~126 launchers) are
  shoot-and-scoot and get **zero direct IJFS suppression** — they only degrade via the C2 lever above.

**Candidate levers to settle with the user (design calls, not forced by the source):** (a) should the
IJFS prioritize the *assaulted* TO's C2 (targeting/value weighting) so C2 suppression actually lands
where the crossing happens; (b) tune `DEFAULT_ANTISHIP_FIRE_PCT` / per-type `range_tier` so a single
TO's arsenal isn't fully brought to bear on one wave; (c) magazine gating across turns (currently the
per-turn rebuild starts full and never binds — see the D3-D wiring note in `GameState`); (d) accept a
deadly unsupported crossing as intended and require the Red player to suppress the assault-TO C2 first.
All are additive on the existing seams. Until settled, the crossing is balance-flagged, not "done."

**UPDATE 2026-06-28 — exquisite-intel investigation + chosen path (user target: ~25% crossing loss,
not ~67%).** Deep-dived the suppression model with the user. Findings:

- **Suppression of anti-ship is two-gate + emergent, not a fixed %.** A system must first be DETECTED
  (`p_detect = satellite_floor + base(label)×mobility_mult×posture_mult×ISR`), then STRUCK
  (`destroyed` at the pairing `probability_destroyed`, else `suppressed` at
  `probability_suppressed_if_not_destroyed`). Net suppression ≈ `P(detect)×(1−p_destroy)×p_suppress`.
  The disparity is a **detection-gate** problem: satellite floor is **0.50–0.95 for moveable/air** vs
  **0.01–0.02 for mobile/hiding** (50× gap). Air-launched platforms (TO3: 149, High detect) get gutted;
  the **mobile coastal launchers** (TO3: types 23+24 = 50 systems, Medium detect, mobile/hiding) are
  near-invisible and fire near-full → ~2/3 loss. Full knob map: `docs/antiship_lethality_knobs.html`.
- **EXQUISITE INTEL IS DORMANT IN THE LIVE GAME.** `apply_exquisite_intel` (peacetime HUMINT/SIGINT that
  `intel_locked`s a decaying count of anti-ship groups → auto-detect, bypassing the satellite floor) is
  correct + unit-tested but **never runs**: `GameState.resolve_ijfs_turn` called `run_daily` with NO
  `warmup_context`, so the whole prelanding warmup branch (exquisite intel + posture override + SEAD
  rules + firing-capacity) was dead code. The current ~67% is measured with it **OFF**. (Third
  "looks-live-but-isn't" trap, after the dormant `mobile_target_destroy_caps` and firing-side magazine.)
- **Granularity is already by UNIT/GROUP (container).** Anti-ship IJFS targets are generated per
  *container* (73 total; 25 in TO3), each carrying `systems_represented`. TO3's entire 50-launcher
  mobile-coastal threat is **2 containers** (type 24 = 40, type 23 = 10). One exquisite-intel lock
  reveals a whole battery — so the "compromise count" needed is small, not hundreds. (The user's
  "exquisite intel by unit / a group of systems detected, not an individual" is already the model.)
- **Detection ≠ kill.** `intel_locked` opens the *detection* gate (auto-detect) but does NOT raise the
  *strike* `p_destroy` for coastal launchers (~0.045, a binary atomic container kill; the strike
  modifiers for that subcategory key on **posture**, not `intel_locked`). Two *other* subcategories
  (dispersed air platforms, C2) DO get an `intel_locked:false` penalty that exquisite intel removes. So
  detection-only likely won't reach 25% — a strike-side lever is probably needed too.

**User decisions (2026-06-28):** (1) **keep the exponential decay** (half-life 3d) — it models sources
fading over the campaign; (2) **wire the FULL TIV warmup** (faithful) into the pre-invasion days
(**DONE 2026-06-28**, opencode session `hexcombat-warmup-wiring`, committed); (3) selection stays
**group/container-level** (already so); (4) **then add an `intel_locked` strike bonus for coastal
launchers** and **empirically sweep `initial_count`** (+ the bonus) on the golden seed to find the value
that yields ~25% crossing loss — magnitude can't be derived (warmup posture override, multi-day
allocation, binary container kills interact nonlinearly), it must be MEASURED. See the handoff in
`docs/ORCHESTRATOR_HANDOFF.md` for the remaining steps.

**MEASURED RESULT (2026-06-28, golden seed 20260624):** wiring the warmup (activating exquisite intel)
cut crossing loss from **~24/36 (~67%) → 18/36 (50.0%)**, golden combat invariant **byte-stable**
(`casualties=2 feba=0.76`), full gate **204/204 green**. So detection-only (exquisite intel ON) gets
**halfway** there but **not to 25%** — confirming the analysis that the binding constraint for the
mobile coastal launchers is the **strike** `p_destroy` gate (~0.045 atomic kill), not just detection.
**Next levers** (step 4): the `intel_locked` coastal-launcher strike bonus, then sweep `initial_count`
(currently 8 groups) to dial in ~25%.

**UPDATE 2026-06-29 — step-4 premise MEASURED AND FALSIFIED; the strike bonus is a weak lever.**
Built a throwaway 2-D sweep harness (`tools/sweep_antiship_crossing.gd`, NOT committed/gated) that, on
the loaded scenario, varies `exquisite_intel.antiship.initial_count` × an injected `intel_locked:true`
strike-bonus (`match {category:"Anti-Ship Systems", intel_locked:true}`, additive on `p_destroy`) and
measures `bns_lost_at_sea / wave_bns` (denominator = BNs at sea = 36; the warmup note's "/36"). Findings
(24-seed means unless noted):
- **Baseline** (ic=8, no bonus): **54.1%** mean (single golden seed = exactly the 50.0% from the warmup note).
- **More intel** (ic=36, +0.20): **48.5%**. **Max intel** (ic=73 — *every* container locked — +0.80, near-certain
  kills): **41.0%** mean (44.4% on golden). So the entire reachable band of the intel/strike lever is **~54%→~41%**.
- **Mine-only floor** (force-kill *all* anti-ship systems via the writeback so the crossing fires nothing):
  **22.2%** (8/36) — **mines alone ≈ the ~25% target**, and are wholly independent of the IJFS lever.
- **Why the bonus barely moves it:** at max intel the crossing still loses **31 of 37** hull-kills vs baseline
  (only 6 removed). The binding constraint is **IJFS strike *coverage/throughput*** (how many launchers it can
  engage in the warmup window), **not** the per-strike `p_destroy` the bonus raises. Boosting `p_destroy` on
  targets IJFS never strikes does nothing. Biasing intel selection to the assaulted TO is also ruled out — ic=73
  already locks everything and still only reaches 41%.
**Conclusion:** the planned step-4 path (intel_locked strike bonus + `initial_count` sweep) **cannot reach ~25%**.
To hit ~25% the lever must be **crossing-model lethality** (`DEFAULT_ANTISHIP_FIRE_PCT` and/or per-ship-type
`p_destroy` in `antiship_crossing_config.json` — the direct knob on the 54%→target band) and/or **mine lethality**
(D3-C; mines are ~half the hull-kills and set the ~22% floor — the "every unswept mine is lethal" flag), possibly
plus **IJFS throughput** (firing capacity / warmup days / munition inventory) if "exquisite intel matters" is to
show. The intel_locked bonus is directionally correct and cheap but is a *flavor* mechanic, not the calibration
lever. **Surfaced to the user 2026-06-29 for the design call (which lever); not committed pending that decision.**

### D3-B3 per-hull escort magazines  *(open — settle if/when ship ammo is modeled)*

`AntishipCrossing.resolve_crossing_damage` ports TIV's **count-based** crossing stages; TIV's live
code instead runs **per-hull** escort interception + terminal defense that deplete each escort's
`hq10`/`hhq9` magazines (via `services.ship_ammo`) and scale interception/defense by damage status
(`services.ship_readiness_policy`), so escort defensive ammo runs out across multi-day crossings.
HexCombat has no ship-ammo/readiness subsystem (D0-C's `ShipState`/`IndividualShip` carry no
magazines). The count-based port matches all `test_antiship_crossing.py` behavior (escort ammo never
binds in those configs). **To revisit** if a later phase models ship magazines/readiness: add per-hull
escort ammo to the interception/terminal-defense stages (the count-based stage seams are isolated, so
this is an additive swap). Until then escort interception is bounded only by `attempts`/`success_prob`,
not magazine depletion.

### D4-H writeback (TO + ground-casualty) linkage  *(TO part RESOLVED 2026-06-27 in D3-D; ground-casualty DESIGN SETTLED 2026-06-28 = Option B + detectability; ready to implement — see below)*

**Update (D3-D, 2026-06-27):** the **(TO,Type)** half is resolved. D3-D's decision 1-A ports TIV's
`build_antiship_targets` so anti-ship IJFS targets are generated **per container** carrying
`to_number`/`type_id`, and `last_ijfs_writeback` now keys anti-ship destroyed/suppressed by
`encode_key(to,type)` — consumed by `resolve_antiship_turn` for the per-(TO,type) firing join and the
C2 lever. The **ground-casualty (`maneuver_casualties`) half remains open**: it is still empty because
the IJFS target set and the PLA/ROC OOB have no shared `battalion_id`/`brigade_id` key (see below).

`GameState.last_ijfs_writeback` aggregates IJFS anti-ship destroyed/suppressed by **Type
(subcategory) only**, and `maneuver_casualties` is **empty**, because `data/ijfs/targets_master.json`
carries neither a theater (`to_number`) field nor `battalion_id`/`brigade_id` on targets — the IJFS
target set and the ground-combat `Brigade`/`Battalion` OOB are currently disjoint datasets with no
shared keys. **To resolve when D3-B (anti-ship firing plan) is built:** decide how IJFS targets map
to theaters (add `to_number` to the target data, sourced from `data/theaters.json` polygons by
lat/lon) so anti-ship suppression can be consumed **per (TO,Type)**; and whether IJFS-destroyed
"Maneuver Units" should mark ground battalions (needs an ID bridge between the IJFS target set and the
PLA/ROC OOB, or a category→OOB mapping). Until then the writeback shape is forward-compatible (adding
the key is a data change). See `RETROSPECTIVES.md 2026-06-26 D4-H`.

**How TIV does it (sourced 2026-06-28, for the design call).** In TIV the bridge is *generated*, not
stored on the static target list: `src/ijfs_standalone/default_targets.py::build_maneuver_targets`
reads a **`maneuver_units` DB table** (`id, to_number, team, type, quantity, detectability,
brigade_id, battalion_id`) and emits one IJFS target **per battalion**, each stamped with
`brigade_id` + a stable `battalion_id` (resolved from a battalions table joined on
`(brigade_id, type, to_number)`, with fallback `f"{brigade_id}-MU-{row_id}"`). `"Maneuver Units"` is a
first-class IJFS category (`category_groups.py`) with **exquisite intel** (`run_daily_ijfs.py`:
`EXQUISITE_INTEL_CATEGORIES = {"maneuver": "Maneuver Units", "antiship": "Anti-Ship Systems"}`).
IJFS results then write casualties back to the `maneuver` table keyed by that `battalion_id`.
**Why HexCombat can't today:** (1) the ported `targets_master.json` is a curated *open-source
strategic-installation* list (54 fixed/mobile sites — airbases, SAMs, radars, HQ, anti-ship, naval
bases) that **deliberately excludes maneuver units** ("no tactical deployment locations for
mobile/moveable systems"); (2) the HexCombat ground OOB (`roc_/pla_ground_forces.json`) stores each
brigade as a **bag of battalion *types* + quantities** with **no per-battalion IDs** — so there is
nothing to key casualties on. The two datasets share only `lat/lon` and (derivable) `to_number`.

**Design options (user, 2026-06-28):**
- **(A) Leave empty / out-of-scope (faithful to the ported data).** Pre-invasion IJFS degrades only
  fixed/air/coastal targets; *all* ground attrition comes from ground combat. `maneuver_casualties`
  stays absent by design. Zero work; documents the gap as intentional.
- **(B) Port TIV's `build_maneuver_targets` (faithful to TIV).** Add a maneuver layer: **mint stable
  per-battalion IDs** from the OOB (`{brigade_id}-MU-{n}` over each composition row × qty), generate
  `"Maneuver Units"` IJFS targets from them per theater, and write IJFS casualties back to those
  battalions by ID (applied as OOB attrition). Reproduces TIV's mechanic and lets pre-invasion fires
  thin ground forces. Cost: ID-minting + maneuver target builder + writeback consumer + OOB-attrition
  application (medium; RNG-adjacent via IJFS draws — keep the golden invariant byte-stable).
- **(C) Theater-bucket (to_number) approximation.** No per-battalion IDs: allocate an IJFS maneuver
  pool per theater and distribute pro-rata (or by injected `Dice`) across that theater's brigades.
  Uses the existing shared key, no ID minting; diverges from TIV's per-battalion fidelity.
- **(D) Category→battalion-type mapping (partial).** Map the categories HexCombat *does* have (SAMs,
  Anti-Ship) onto matching battalion *types* in brigade compositions (Air Defense / coastal-anti-ship
  battalions) and attrit those. Connects existing targets to the OOB without inventing maneuver
  targets — but covers only air-defense/anti-ship battalions, not general maneuver infantry/armor.

**The core question for the user:** should pre-invasion IJFS inflict *ground maneuver* casualties at
all? If **no** → (A). If **yes, faithfully** → (B). If **yes, but cheaply** → (C)/(D).

---

#### DECISION 2026-06-28 — Option B + detectability extensions (user)

The user chose **B**: maneuver units are IJFS-targetable, with detection biased so that **less-armored,
less-mobile, and recently-active units are more likely to be hit**. This maps cleanly onto mechanics
TIV *already* implements (so it is a port, not new invention). **Direction:** IJFS is the PLA's
pre-invasion strike campaign, so maneuver targeting applies to the **defender's (Green/ROC) ground
OOB** (`data/roc_ground_forces.json`, which already carries `to_number`).

**B1 — Generate maneuver targets from the OOB** (port `build_maneuver_targets`). For each Green
brigade → each `composition` battalion row → each of `qty` instances, **mint a stable
`battalion_id`** (`{brigade_id}-MU-{n}` — TIV's own fallback scheme, since the HexCombat OOB stores
battalion *types*+quantities, not IDs). Emit one IJFS **"Maneuver Units"** target per instance,
stamped with `brigade_id`, `battalion_id`, `to_number` (from the brigade), and a profile from a ported
**`MANEUVER_TYPE_MAP`** keyed by battalion `type` → `(subcategory, mobility, hardness,
detectability_active, detectability_hiding)`. Add "Maneuver Units" to the IJFS category groups with
**exquisite intel** (mirrors anti-ship: `EXQUISITE_INTEL_CATEGORIES`).

**B2 — Detection = mobility × posture** (port TIV `detection.py`). Per-target detection probability is
`satellite_floor + base_probability(detectability_label) × mobility_multiplier(mobility) ×
posture_multiplier(mobility, posture) × weighted_isr`.
- **Less mobile ⇒ more likely hit** = the `mobility` tier (`mobile` / `moveable` / `static`) selects
  `mobility_multiplier` (lower mobility → higher multiplier). Static units default to **"active"**
  posture (always exposed).

**B3 — "Moved or fought ⇒ more detectable next turn" = posture flips to "active"** (generalizes TIV's
`antiship_exposure` "an active attempt raises next-day detectability" rule to maneuver units). The
target's `posture` is **"active"** if its brigade was active *last* turn, else **"hiding"** (default
for mobile units). Active posture selects the higher `detectability_active` label **and** the active
`posture_multiplier`. **This is the "record historic actions per brigade" requirement:** `Brigade`
already has `moved_this_turn` / `moved_admin_this_turn` / `fought_this_turn` (current-turn, reset each
turn) — add **persistent prior-turn flags** that survive `begin_next_turn` (e.g. `moved_last_turn`,
`fought_last_turn`, set from the current flags during cleanup before they reset) so the *next*
start-of-turn IJFS can read them. Keep them as separate booleans (not one combined flag) so move vs
combat can drive different exposure later.

**B4 — "Less armored ⇒ more likely hit" = `hardness`** (`hard` / `soft`), mapped from battalion type
(Tank/Armor/Mech-Inf/Amphibious = `hard`; artillery/light/reserve/support = `soft`). **Nuance to
confirm:** in TIV `hardness` feeds the **strike/damage** step (kill-probability *given* detected, in
`strike_probability.py`), **not** detection — so armor makes a unit *harder to kill once found*, and
the net effect ("less-armored units are removed more often") matches the user's intent. See open
sub-decision (1) below if the user instead wants armor to also lower *detection*.

**B5 — Writeback / OOB attrition.** IJFS destroyed/suppressed maneuver results write back keyed by
`battalion_id` → decrement that battalion's `qty` (or flag the instance destroyed) on the brigade, and
populate `last_ijfs_writeback.maneuver_casualties`. **RNG:** detection + strike use dice — inject the
existing **IJFS substream** and keep the golden ground-combat invariant (seed 20260624 → casualties=2,
feba=0.76) **byte-stable**.

**Sub-decisions — RESOLVED 2026-06-28 (user):**
1. **Armor → lethality only (TIV-faithful).** `hardness` affects kill-given-detected only; **no**
   armor term in `detection.py`. Less-armored units die more readily once found, but armor does not
   change findability. No divergence from TIV.
2. **Service Support / Support battalions ARE targetable**, modeled as **soft, high-detectability**
   (logistics tails are findable and fragile). So *all* battalion types are IJFS maneuver targets.

**Sub-decisions — DEFAULTED 2026-06-28 (recommended defaults; user may revisit):**
3. **History depth = prior-turn only.** A single prior-turn latch (`moved_last_turn`/`fought_last_turn`)
   drives "active" posture — matches TIV's "next-day exposure" model. (Not a multi-turn decay; can be
   extended later if a unit should stay "hot" for N turns after acting.)
4. **Suppression = reporting-only at first; destruction = `qty` loss.** Start with destroyed maneuver
   results decrementing battalion `qty`; treat *suppressed* as a reported status with no ground-combat
   penalty yet (an org/readiness penalty on suppressed battalions can be added later, mirroring the
   existing organization track).

**Still to assign at implementation (mechanical, not a design fork):** `(mobility, hardness,
detectability_active, detectability_hiding)` profiles for the HexCombat-only battalion types absent
from TIV's `MANEUVER_TYPE_MAP` — **Air Assault Infantry, Combined Arms, Reconnaissance, Service
Support, Support** — by analogy to the nearest TIV-mapped type (e.g. Air Assault ≈ Air Assault/Marine
profile; Combined Arms ≈ Mechanized Infantry; Reconnaissance ≈ mobile/soft/low-detect; Service
Support & Support ≈ soft/high-detect per (2)).

The design is now fully settled; the B port can proceed when scheduled (keep the golden invariant
byte-stable; inject the IJFS substream).

**IMPLEMENTED — full linkage closed (overnight loop, 2026-06-29 → 2026-06-30).** 2a (`Brigade.moved_last_turn`/
`fought_last_turn` latched in cleanup), 2b (`IjfsLoaders.build_maneuver_targets` + `MANEUVER_TYPE_MAP`
profiles realizing sub-decision 1's mobility/hardness lethality and sub-decision 2's all-types-targetable),
2c-i (wired into `_rebuild_ijfs_state`), 2c-ii (`GameState._update_maneuver_posture` realizes
sub-decision 3: recently-active brigades → `posture="active"` → higher `detectability_active` + active
posture/satellite multipliers in the unchanged `IjfsDetection` math), 2d (`_apply_ijfs_maneuver_casualties`
decrements struck battalions' `qty`, sub-decision 4). **Why 2c-ii is a pure data nudge:** the detection
port already keys detectability off `target.posture`; the only addition is *setting* posture from the 2a
activity flags at the top of `resolve_ijfs_turn` — no math edit, so the golden stays `casualties=3,
feba=-0.96` (turn-1 flags all false → all maneuver targets stay `"hiding"`). Tests:
`ijfs_maneuver_targets_test`, `ijfs_maneuver_consume_test`, `ijfs_maneuver_posture_test`.

**2d follow-up — per-turn OOB sync (orchestrator decision, 2026-06-30).** The 2d limitation was that
`ijfs_state` is built once per scenario, so maneuver targets for battalions killed (by IJFS or ground
combat) lingered and kept drawing fire. The queue framed the fix as "rebuild maneuver targets per turn,"
but `IjfsEngine.carry_to_next_day` persists `destroyed`/`known_to_red`/`last_detected_day` — a full
rebuild would WIPE detection continuity for surviving maneuver units. **Chose SYNC over rebuild:**
`GameState._sync_maneuver_targets_to_oob` (top of `resolve_ijfs_turn`) groups live "Maneuver Units"
targets by `(brigade_id, unit_type)` and marks the *excess* over current OOB qty as `destroyed` (highest
`target_id` first, deterministic). It only ever sets `destroyed` — never resurrects — so survivors keep
their continuity, and `carry_to_next_day` keeps the flag. Golden-safe: when IJFS runs on turn 1 the OOB
is still full (2d applies after), so live count == qty and nothing is touched. Test:
`ijfs_maneuver_sync_test`.

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
