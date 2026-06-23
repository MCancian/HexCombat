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
