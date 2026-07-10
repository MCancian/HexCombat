# HexCombat — Forward Backlog

Live tracks only, sequenced for the ratified mission (USER 2026-07-02): **primary** = AI-vs-AI
research instrument (Monte Carlo, LLM players, narratives, sweeps); **secondary** =
live-adjudication aid. Pick the next unstarted item in order; one coherent, verified unit at a
time. Focused multi-session efforts get a numbered plan — see [README.md](README.md).

Completed tracks (A decomposition, B1–B6 research harness, C first variant, F terrain) are
current behavior in `docs/STATUS.md`; their history is in `docs/archive/` (PLAN.md Decisions,
refactor_audit, port_audit).

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

All need visual verification (screenshot / Godot MCP / USER) — headless gates don't cover pixels.

## Track E — Calibration & balance *(with Track B outputs)*

- Plan **0001 — Crossing-lethality calibration** (see README index) — the USER's ~25% target.
- MANPADS constants dial-in if future batches show the first-cut rates off
  (levers: `IjfsManpads.gd` consts; evidence pattern: 30-seed before/after batch, 2026-07-10).
