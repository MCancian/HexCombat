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
- [ ] M3 — Turn/phase state machine (`GameState` autoload)
- [ ] M4 — Movement (reachable highlight, allowance)
- [ ] M5 — Combat wiring (apply casualties, FEBA, ownership)
- [ ] M6 — Headless turn check (AI-readiness)
- [ ] M7 — Slice completion + Definition of done

## Definition of done (vertical slice)

Windowed run: brigades visible; select one in Movement phase and move within range; switch to
Combat phase, attack an adjacent enemy hex, see casualties applied and the front/ownership shift;
ending the turn advances state. `tools/run_all_tests.ps1` green (smoke + validation + GdUnit4,
including seeded golden combat and movement-reachability tests).

## Decisions log (append-only; record every autonomous choice here)

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

## Open questions (settle at the relevant milestone)

_None blocking the slice — the design is settled. Future-phase questions (supply/organization
interactions, fog of war, terrain via ArcGIS, theater fires) are tracked in `ROADMAP.md`._
