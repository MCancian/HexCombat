---
status: Sketch
shipped:
landed_in:
---
# 0011 — Disciplined Sweep Ecosystem

## Goal
One disciplined way to run any parameter sweep: vary knob(s) → measure → report, reaching **any**
data-file knob, at the right runtime granularity, with batch-grade provenance, on both platforms.
Retire the bespoke, stdout-only GDScript sweeps and the Windows-only `run_sweep.ps1`.

## Context & Settled Facts
- **USER calls (2026-07-17):** target **Tier 2** (full unification) but land it in stop-anywhere
  increments; the knob-injection primitive is a **runtime override map** (not variant-file
  generation, not in-process privates).
- **What's already disciplined:** `tools/run_batch.py` (B7) + `tools/run_sweep.ps1` (B5) — one-knob
  *scenario-file* variants → common-seed batch → reproducible per-game records + `manifest.json`
  (commit/seeds/re-run cmd) + auto-report. This is the contract to generalize.
- **What's undisciplined:** `tools/sweep_antiship_crossing.gd`, `tools/sweep_crbm_maneuver.gd` —
  in-process, reach `GameState` privates (`_rebuild_ijfs_state`), hand-roll injection/metric/stats,
  print an ephemeral stdout table with **no provenance and no re-run path**. They exist because
  their knobs live in `data/ijfs/ijfs_scenario.json` (a phase data file `run_sweep` can't reach)
  and/or they need single-phase speed. `tools/ijfs_sweep_support.gd` already shares their kernel.
- **Three drivers of the fragmentation:** (1) knob reachability — scenario-file keys vs
  phase-data-file keys; (2) runtime granularity — full-game process-per-run vs single-phase
  in-process (a crossing-loss dial doesn't need a 40-turn game); (3) platform + artifacts —
  `run_sweep.ps1` is Windows-only (this Linux box can't run it) and the GDScript sweeps persist
  nothing.
- **Architecture dependency:** the override map adds a cross-cutting load-time seam — read
  `hexcombat-architecture-contract` before Phase A. Non-negotiable invariant: **no override present
  ⇒ byte-identical to today** (golden-preserving; the seam is a no-op on the empty map).

## Approach — stop-anywhere increments
Each phase ships value and can be the stopping point.

### Phase A — Runtime override map + public loader seam *(keystone)*
A process-level override map `"<data-file>:<dot.path>" → value`, sourced from a `--overrides` user
arg / env var (parallel to `HEXCOMBAT_SCENARIO`), applied at load time inside the data loaders
(`GameData`, `IjfsLoaders`, antiship/minefield loaders) right after each JSON read. Public,
unit-tested, deterministic. Precedence vs `HEXCOMBAT_SCENARIO` defined explicitly. Replaces both the
GDScript in-process scenario-dict mutation and (eventually) variant-file generation.
- Validator: overrides apply to the named path; empty map = byte-identical load (golden guard).

### Phase B — Sweep record + provenance contract
Define the sweep-record schema (knob axis, value grid, per-cell per-seed samples, chosen metrics,
provenance: commit, base scenario, seed set, runtime mode, re-run command). Emit under
`reports/sweeps/<name>/`. Retrofit the two existing sweeps to drive via the Phase-A override map and
**emit records** (they keep their in-process runtime for now). Auto-report table generator (mirrors
`make_batch_report`).

### Phase C — Metric registry
Named, reusable extractors computed in python over the emitted records: `crossing_loss_pct`,
`maneuver_attrition_pct`, `terminal_census`, `red_win_rate`, … A sweep declares metrics by name; the
report computes them. Makes a new sweep a *spec*, not a script.

### Phase D — Python sweep orchestrator over `run_batch`
`tools/run_sweep.py` (cross-platform): knob(s) + value grid + metrics + runtime-mode → drives
`run_batch.py` (full-game, process-per-run, parallel) via the override map, writes records + report.
Retires `run_sweep.ps1`.

### Phase E — Single-phase fast-path + retire bespoke scripts
Fold `sweep_antiship_crossing` / `sweep_crbm_maneuver` into the orchestrator as specs with an
in-process single-phase backend (for calibrations that don't need a full game), selected by the
sweep spec. Delete the bespoke scripts. Update `hexcombat-research-runs` and
`hexcombat-config-and-knobs`.

### Phase F — (optional) machine-readable knob registry
Promote `hexcombat-config-and-knobs` prose to a knob manifest (address, default, type, range, data
file, doc link) so sweeps reference knobs by name and validation is centralized. Deferred until a
concrete need.

## Risks & Validation
- **Loader seam is cross-cutting** — must be zero-cost and a strict no-op on the empty map; guard
  with a golden byte-identical validator (Phase A). Any golden drift = a bug, not a re-baseline.
- **In-process vs process-per-run determinism** — assert the two backends agree on a shared metric
  for one cell (cross-checks the override map applies identically both ways).
- **Provenance completeness** — a sweep record must re-run byte-identically for deterministic seats
  (same bar as `run_batch`).
- Sweeps stay **out of the gate** (on-demand research tools); verification is artifact-based +
  re-run, per `hexcombat-research-runs`.

## Checklist
- [ ] Phase A — override map + public loader seam + golden-guard validator.
- [ ] Phase B — sweep-record schema + provenance + retrofit both sweeps to emit records + auto-report.
- [ ] Phase C — metric registry over records.
- [ ] Phase D — `run_sweep.py` orchestrator over `run_batch`; retire `run_sweep.ps1`.
- [ ] Phase E — single-phase backend + fold in & delete the bespoke sweeps; update skills.
- [ ] Phase F — (optional) knob manifest.
- [ ] Closeout: facts to `hexcombat-research-runs` / `hexcombat-config-and-knobs` / STATUS / DECISIONS;
  archive this plan.
