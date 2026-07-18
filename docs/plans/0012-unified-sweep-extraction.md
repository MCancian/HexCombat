---
status: Ready
shipped:
landed_in:
---
# 0012 — Unified Sweep Extraction & Batch Specs

**Goal:** Decouple the parameter sweep engine (`run_sweep.py`) from bespoke GDScript extraction logic, allowing all canned sweeps to run natively via the fast, parallel `batch` backend while relying solely on standard game records for metric extraction.

## Context & Motivation
In Plan 0011, we centralized sweep orchestration into `run_sweep.py`. However, the two critical calibration sweeps (`antiship_crossing` and `crbm_maneuver`) were ported into a specialized `run_sweep_cells.gd` single-process backend. This was done because:
1. `crbm_maneuver` needs to run very fast and thus completely skips the ground combat phase (empty-orders self-play, no per-game process boot).
2. `antiship_crossing` requires a "mines-only" floor baseline, achieved by overwriting the IJFS writeback's destroyed-launcher counts in GDScript (a cell-level `mines_only` runner directive since the 2026-07-18 refactor — no longer a fake override key, but still an imperative hack).
3. Both sweeps extract metrics directly from internal Godot structures during the run rather than standard JSON logs.

This hardcoding limits our ability to use the `--backend batch` parallel runner for these sweeps and requires new GDScript for every new metric.

**State as of 2026-07-18 (post-review + refactor pass):** `run_sweep.py` is modular
(`run_spec_sweep` / `run_cli_sweep` / shared `write_manifest`/`grid_cells`/`render_report`);
the batch cutover point is the guard at the top of `run_spec_sweep`. The antiship measurement
sequence is IJFS → **sealift** → antiship (mandatory post-plan-0004; wave = sent cohort) — any
batch-backend replacement must reproduce that full-turn context, which `run_selfplay_game.gd`
gets for free by running real turns.

## Design

### 1. Data-Driven Fast-Forwarding
Introduce a new scenario knob (e.g., `disable_phases: ["ground_combat", "movement"]`) that allows the engine to skip heavy WeGo phases during a run. This allows the CRBM maneuver sweep to run as a standard `run_selfplay_game.gd` game but execute blisteringly fast, removing the need for a bespoke GDScript loop.

### 2. Formalize the "Mines-Only" Baseline
Promote the mines-only directive to a proper data feature: `disable_antiship_systems: true` in the scenario/override map. When set, `AntishipLoaders` yields no crossing interceptors, isolating the crossing loss to mines only. This deletes the cell-level `mines_only` directive and its writeback surgery in the runner. (Note the expected reading: the mines-only floor is legitimately **0.0% BN loss** under the current decoy-sponge model — mines kill sponge ships, lanes clear. Keep it in the report as the standing floor check.)

### 3. Metric Extraction in Python — and split stats from formatting (refactor item 6)
Modify `sweep_metrics.py` to parse standard game records output by `run_selfplay_game.gd`:
- **`antiship_crossing`:** `bns_lost_at_sea` and the sent-cohort wave size from the D3 antiship phase digest.
- **`crbm_maneuver`:** maneuver pool / attrition from the D4 IJFS phase digest (pool census currently needs `ijfs_state` built pre-resolve — the digest must carry the pool so Python doesn't need engine internals).

While in there, restructure the metric contract: registry functions return **raw numbers**
(floats / dicts of floats), and `make_sweep_report.py` owns all formatting (`±`, `%`, decimals).
Today they return preformatted strings, which blocks sorting/thresholding and would force every
new extractor to duplicate format code. Do this WITH the extractor rewrite — one contract change,
one churn.

### 4. Deprecate `run_sweep_cells.gd`
Once all specs can run through `run_batch.py` (via `--backend batch`) and their metrics can be extracted in Python, delete the `run_sweep_cells.gd` backend. All sweeps will be parallelizable and purely data-defined. Its fail-loud guards must survive the move: spec-scenario enforcement (id match + file exists) and `DataOverrides.unapplied()` belong in `run_selfplay_game.gd` / `run_batch.py` (the selfplay entrypoint already checks `unapplied()`).

## Phases

- [ ] **Phase A — Formalize Bypass Knobs:** Add `disable_phases` and `disable_antiship_systems` to the scenario model. Implement them in `GameState.resolve_turn` and `AntishipLoaders`. Gate green.
- [ ] **Phase B — Python Extractors + raw-number metric contract:** Update `sweep_metrics.py` to extract `crossing_loss_pct` and `maneuver_attrition_pct` from standard game records, returning raw numbers; move all formatting into `make_sweep_report.py`.
- [ ] **Phase C — Cutover:** Modify `tools/sweeps/*.json` to include the new bypass knobs. Update `run_sweep.py` to respect `--backend batch` for `--spec` and use the Python extractors. Verify parity with the 2026-07-18 post-review reference tables (the pre-review Phase E "pins" were vacuous all-zero antiship tables — see DECISIONS 2026-07-18 review fixes; parity references must be known-nonzero: antiship golden dial reads 32.9%, CRBM +0.15 reads 46.0/124 killed).
- [ ] **Phase D — Cleanup:** Delete `tools/run_sweep_cells.gd` (guards preserved per Design §4). Update docs and closeout.
