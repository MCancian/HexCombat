---
status: ✅ Shipped
shipped: 2026-07-18
landed_in: 2537f5f (Phase A knobs), 9320c59 (wave_bns digest), + Phase B2/C/D commit (extractors, batch cutover, cell-runner deletion); gate repair e02abc7 surfaced en route
---
# 0012 — Unified Sweep Extraction & Batch Specs

**Closeout (2026-07-18):** All four phases shipped. Durable facts live in `docs/STATUS.md` (B5
bullet), `hexcombat-research-runs` (spec fields + backend), `hexcombat-config-and-knobs`
(`disable_phases`, `disable_antiship_systems`), `docs/DECISIONS.md` 2026-07-18, and
`hexcombat-failure-archaeology` (vacuous fixture-drift gate found en route). **One deliberate
divergence from Design §1:** the CRBM spec does NOT use `disable_phases` — the plan's premise
that the old cell runner "skipped ground combat" was wrong (its empty-orders full turns still
produced beach combat from offload landings, and the USER-dialed 0.15 reading includes those
dynamics). Parity demanded identical semantics, so the canned specs run a new `noop` matchup
instead; `disable_phases` shipped as designed and remains available for future fast what-ifs.
Proof: both 2026-07-18 reference tables reproduced **byte-identically** through the batch
backend (antiship golden-dial cell 32.9±9.4, mines-only floor 0.0±0.0, CRBM +0.15 = 46.0/124).

**Goal:** Decouple the parameter sweep engine (`run_sweep.py`) from bespoke GDScript extraction logic, allowing all canned sweeps to run natively via the fast, parallel `batch` backend while relying solely on standard game records for metric extraction.

## Phases

- [x] **Phase A — Formalize Bypass Knobs:** `disable_phases` (scenario, allowlist
  movement/ground_combat) + `disable_antiship_systems` (grouping spec). Gate green, golden
  byte-stable.
- [x] **Phase B — Python Extractors + raw-number metric contract:** `sweep_metrics.py` reads
  standard game records (turn digests + census; `wave_bns` added to the D3 digest); registry
  returns raw floats/dicts; `make_sweep_report.py` owns all formatting (`FORMATTERS`).
- [x] **Phase C — Cutover:** specs carry `matchup`/`turns`/`run_past_game_over`; `run_sweep.py`
  runs every cell through `run_batch.py`; parity verified byte-identical against the 2026-07-18
  reference tables (nonzero, per DECISIONS review-fixes entry).
- [x] **Phase D — Cleanup:** `run_sweep_cells.gd` deleted; its guards preserved (scenario
  existence check in `run_sweep.py`, `DataOverrides.unapplied()` in `run_selfplay_game.gd`).
