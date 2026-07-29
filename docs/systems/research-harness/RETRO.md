# Research Harness — Retrospectives

## 2026-07-18 — plan 0012: unified sweep extraction on the batch backend   (implementer: direct)

**What would you do differently (implementer):**
- The plan's premise ("the CRBM cell runner completely skips ground combat") was wrong — its
  empty-orders full turns still produced beach combat from offload landings. One 40-turn parity
  game caught it (43 vs 40 killed) before any spec shipped on `disable_phases`. Lesson: run the
  cheapest end-to-end parity probe BEFORE building on a plan's characterization of legacy
  behavior; the plan is a design, not evidence.
- Regenerating the LLM fixtures for `wave_bns` exposed that the gate's fixture-drift check had
  been vacuous since f37170f (missing `--` separator; exporters wrote to `reports/`). A guard
  that has never been seen failing should be distrusted — deliberately break a new guard once.

**Orchestrator triage:**
- Vacuous drift gate → **act now** (fixed both gate scripts, honest re-baseline, archaeology
  entry).
- Orphan fixture `docs/examples/llm_observation_after_turn.json` (nothing generates or checks
  it) → **act later** (flagged to USER in the session report).
- 14.8 MB per-cell aggregate JSONs (full records × 24 seeds) → **record only** (works; trim to
  digest-only samples if sweep disk use ever matters).
