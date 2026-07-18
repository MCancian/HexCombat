---
status: Ready
shipped:
landed_in:
---
# 0012 — Unified Sweep Extraction & Batch Specs

**Goal:** Decouple the parameter sweep engine (`run_sweep.py`) from bespoke GDScript extraction logic, allowing all canned sweeps to run natively via the fast, parallel `batch` backend while relying solely on standard game records for metric extraction.

## Context & Motivation
In Plan 0011, we centralized sweep orchestration into `run_sweep.py`. However, the two critical calibration sweeps (`antiship_crossing` and `crbm_maneuver`) were ported into a specialized `run_sweep_cells.gd` single-process backend. This was done because:
1. `crbm_maneuver` needs to run very fast and thus completely skips the ground combat phase.
2. `antiship_crossing` requires a specialized "mines-only" floor baseline, which is currently achieved by manually erasing systems from the `GameState` in GDScript.
3. Both sweeps extract metrics directly from internal Godot structures during the run rather than standard JSON logs.

This hardcoding limits our ability to use the `--backend batch` parallel runner for these sweeps and requires new GDScript for every new metric. 

## Design

### 1. Data-Driven Fast-Forwarding
Introduce a new scenario knob (e.g., `disable_phases: ["ground_combat", "movement"]`) that allows the engine to skip heavy WeGo phases during a run. This allows the CRBM maneuver sweep to run as a standard `run_selfplay_game.gd` game but execute blisteringly fast, removing the need for a bespoke GDScript loop.

### 2. Formalize the "Mines-Only" Baseline
Promote the mines-only hack to a proper data feature. For instance, `disable_antiship_systems: true` in the scenario/override map. When set, `AntishipLoaders` yields no crossing interceptors, isolating the crossing loss to mines only. This avoids manual state mutation inside the sweep tool.

### 3. Metric Extraction in Python
Modify `sweep_metrics.py` to parse standard game records (`final_snapshot.json` / `turn_digests.json`) output by `run_selfplay_game.gd`.
- **`antiship_crossing`:** Parse the `bns_lost_at_sea` from the D3 antiship phase digest.
- **`crbm_maneuver`:** Parse the maneuver unit pool and attrition from the D4 IJFS phase digest.

### 4. Deprecate `run_sweep_cells.gd`
Once all specs can run through `run_batch.py` (via `--backend batch`) and their metrics can be extracted in Python, delete the `run_sweep_cells.gd` backend. All sweeps will be parallelizable and purely data-defined.

## Phases

- [ ] **Phase A — Formalize Bypass Knobs:** Add `disable_phases` and `disable_antiship_systems` to the scenario model. Implement them in `GameState.resolve_turn` and `AntishipLoaders`. Gate green.
- [ ] **Phase B — Python Extractors:** Update `sweep_metrics.py` to correctly extract `crossing_loss_pct` and `maneuver_attrition_pct` from standard Godot output records.
- [ ] **Phase C — Cutover:** Modify `tools/sweeps/*.json` to include the new bypass knobs. Update `run_sweep.py` to respect `--backend batch` for `--spec` and use the Python extractors. Verify parity with the 2026-07-18 post-review reference tables (the pre-review Phase E "pins" were vacuous all-zero antiship tables — see DECISIONS 2026-07-18 review fixes; parity references must be known-nonzero).
- [ ] **Phase D — Cleanup:** Delete `tools/run_sweep_cells.gd`. Update docs and closeout.
