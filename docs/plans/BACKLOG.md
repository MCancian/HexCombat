# HexCombat — Forward Backlog

Live tracks only, sequenced for the ratified mission (USER 2026-07-02): **primary** = AI-vs-AI
research instrument (Monte Carlo, LLM players, narratives, sweeps); **secondary** =
live-adjudication aid. Pick the next unstarted item in order; one coherent, verified unit at a
time. Focused multi-session efforts get a numbered plan — see [README.md](README.md).

Completed tracks (A decomposition, B1–B6 research harness, C first variant, F terrain) are
current behavior in `docs/STATUS.md`; their history is in `docs/archive/` (PLAN.md Decisions,
refactor_audit, port_audit).

## Numbered plans queued (see [README.md](README.md))

- **0004 — Port TIV ship-count & crossing model** *(High)*. Sealift is a one-shot fixed reserve
  that drains by ~turn 3; no follow-on echelon exists, so 27/30 turns run with no crossing. Port
  the stateful ship / reinforcement model from TaiwanInvasionViewer. `0004-*.md`.
- **0005 — Game-record inconsistency audit** *(Medium)*. Dispatch brief for an agent to audit
  `reports/llm/*.viewer.json` for other engine/model inconsistencies (excludes 0004/0003).
  `0005-*.md`.

---

## Track B — Research harness *(primary; one item left)*

- **B7 — Per-seat policies in the batch runner.** `run_batch.ps1`/`run_selfplay_game.gd` are
  single-policy; LLM seats currently run only via `tools/run_llm_game.gd`. Wire per-seat policy
  ids through the batch layer so LLM-vs-LLM (and mixed) games flow into multi-condition studies.
  Done when: one command produces a reproducible multi-condition study report with an LLM policy
  on either side. Contract: `.claude/skills/hexcombat-research-runs`.

## Track D — Adjudication aid (graphics/UI) *(secondary — on USER request)*

Scope per USER 2026-07-02: facilitator order entry + turn resolution in the UI, and
projector-friendly presentation. (Umpire overrides and save/load explicitly NOT requested.)
Priorities to be set with the USER when the track starts:

- Order-entry flow polish (select → move/commit → end turn) usable by a non-developer facilitator.
- Projector-readable map: markers, ownership colors, phase/turn/combat HUD, camera fit/zoom/pan.
- D5-D front-line polyline-draw UI (the one remaining D5 piece; battalion-granularity
  distribution refine rides with it).
- Anti-ship/mine crossing visualization (makes D3 mechanics legible to a room).
- Viewer front-zoom: non-contiguous fronts. The briefing viewer's "front" viewport (theater +
  front split, 2026-07-11) crops to one bbox over ALL contested/Red hexes; two separate
  beachheads yield a single frame spanning both (and the empty ocean between). Follow-up: cluster
  the focus set and frame the active/largest cluster (or offer per-cluster paging). USER-flagged
  as a future plan. Lives in `tools/viewer/game_viewer.html` (`updateZoomViewport`).

All need visual verification (screenshot / Godot MCP / USER) — headless gates don't cover pixels.

## Track E — Calibration & balance *(with Track B outputs)*

- Plan **0001 — Crossing-lethality calibration** (see README index) — the USER's ~25% target.
- MANPADS constants dial-in if future batches show the first-cut rates off
  (levers: `IjfsManpads.gd` consts; evidence pattern: 30-seed before/after batch, 2026-07-10).

## Track F — Tech Debt & Hygiene

- **carry_to_next_day parity gap**: Add a continuity test that roundtrips through `IjfsLoaders` and asserts field-by-field parity with `carry_to_next_day`.
- **Shared test-fixture constant for beach-1 pair**: Refactor duplicated literals (like `"hex_44_16"`) into a shared test-fixture constant in `movement_test.gd` and `composition_test.gd`.
- **Rebuild maneuver targets per turn**: Update to rebuild maneuver targets per turn from the live OOB.
- **Isolation tests for Phase C/D resolvers**: Add isolation tests for Phase C and D resolvers.
- **Offload telemetry gap** (found by plan 0007, 2026-07-16): `TurnResult`/turn digests have no
  `offload_summary` — `OffloadResolver`'s manifest (bns_sent/landed/waiting/lost_at_sea + deferral
  reasons) only reaches `EventBus.offload_resolved`, never a game record. Add an `offload_summary`
  field (mirroring `antiship_summary`'s shape) so research runs can read offload activity directly
  instead of reconstructing it from census deltas + combat summaries (measurably unreliable — see
  `docs/archive/0007-offload-weight-rebalance-investigation.md` → Findings → Method).
