# 0001 — Crossing-lethality calibration (D3-D)

**Status:** Shipped 2026-07-11 · **Dial:** `intel_locked_antiship_strike_bonus=0.20`,
`exquisite_intel.antiship.initial_count=36` in `data/ijfs/ijfs_scenario.json` (golden) · Facts:
`docs/systems/ijfs.md` → "Calibration knob", `hexcombat-config-and-knobs`; decision:
`docs/DECISIONS.md` 2026-07-11.

## Goal

Dial mean PLA crossing losses to the USER's ~25% target (baseline after the geometric mine model:
~32.4%), with the `intel_locked` strike bonus and exquisite-intel `initial_count` as the levers.

## What is already settled (do not re-litigate)

- Geometric danger model + decoy-sponge transit is IN (ported from TaiwanDefenseRefactor
  `mine_warfare.py`); the old geometry-free model is fenced off — see
  `hexcombat-failure-archaeology` → "Mine/crossing calibration".
- Exquisite intel decay (half-life 3d) kept; full TIV warmup wired 2026-06-28; selection is
  container-level (a lock reveals a whole battery).
- Detection alone can't reach 25% — coastal-launcher `p_destroy` (~0.045) doesn't key on
  `intel_locked`; a strike-side bonus is needed too.

Full analysis trail: `docs/archive/PLAN.md` → Open Questions → "D3-D crossing lethality
calibration"; missile-pipeline map: `docs/antiship_missile_pipeline_ref.md`.

## Approach

Empirical sweep, not derivation (warmup posture override × multi-day allocation × binary
container kills interact nonlinearly): sweep `initial_count` × strike-bonus on a common seed set
via `tools/run_sweep.ps1` / batch runner, report loss distributions, USER picks the dial.

## Checklist

- [x] Promote the `intel_locked` coastal-launcher strike bonus to a scenario-selectable knob —
      `intel_locked_antiship_strike_bonus` (float, default 0.0) in `data/ijfs/ijfs_scenario.json`,
      synthesized by `IjfsLoaders.apply_intel_locked_strike_bonus`; default preserves golden.
      Note: lives in the IJFS data file, not `data/scenario_default.json` — that file's path isn't
      yet `ScenarioCatalog`-selectable, so it's a knob, not (yet) a per-variant scenario key.
- [x] Sweep grid (N=30/condition, common seeds); report distributions — `tools/sweep_antiship_crossing.gd`,
      2026-07-11. `initial_count` swept by direct in-memory mutation (unchanged approach; not
      promoted to a knob this round).
- [x] USER dial-in; re-baseline goldens; record divergence in DECISIONS
