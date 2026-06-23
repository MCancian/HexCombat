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
  (hex_43_17/43_15/42_15/42_14), with `offset_bearing` per brigade. Beach→hex by nearest center;
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
  BDE-66→hex_43_17), meta loaded.

**(b) pi's machine-readability suggestion**
- Typed `Scenario`/`ScenarioPlacement` Resources + a pure `ScenarioLoader`/`ScenarioValidator`, with
  GameData consuming a typed `Scenario` (not a raw Dictionary) and structured validation errors
  (`{code, brigade_id, path}`). — _Deferred: aligns with the typed-model architecture; revisit when
  scenarios multiply / become user-authored (Track C). The Dictionary path is fine for the single
  slice scenario and the validator already gates integrity._
