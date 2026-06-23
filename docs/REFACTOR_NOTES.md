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
