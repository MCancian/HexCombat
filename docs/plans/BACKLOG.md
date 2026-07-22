# HexCombat — Forward Backlog

Live tracks only, sequenced for the ratified mission (USER 2026-07-02): **primary** = AI-vs-AI
research instrument (Monte Carlo, LLM players, narratives, sweeps); **secondary** =
live-adjudication aid. Pick the next unstarted item in order; one coherent, verified unit at a
time. Focused multi-session efforts get a numbered plan — see [README.md](README.md).

Completed tracks (A decomposition, B1–B6 research harness, C first variant, F terrain) are
current behavior in `docs/STATUS.md`; their history is in `docs/archive/` (PLAN.md Decisions,
refactor_audit, port_audit).

## Track B — Research harness *(primary; complete)*

- [x] **B7 — Per-seat policies in the batch runner.** `tools/run_batch.py` runs explicit
  Red/Green matchups across common seeds and writes the multi-condition report automatically;
  LLM-vs-LLM and mixed games use the unified `run_selfplay_game.gd` entrypoint. Contract:
  `.claude/skills/hexcombat-research-runs`.

| ID | Plan Name | Priority | Status |
| :--- | :--- | :--- | :--- |
| 0002 | [Per-hull escort magazines (D3-B3)](0002-per-hull-escort-magazines.md) | Low (needs ship-ammo subsystem) | Sketch |
| 0003 | [Combat-summary team attribution](0003-combat-summary-team-attribution.md) | Low (blocked on USER counterattack call) | Sketch |

(Shipped plans move to `docs/archive/` and are indexed in [README.md](README.md) → Archived — not here.)

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

**Code-quality debt deferred from the 2026-07-16 baseline** (report:
`docs/reports/2026-07-16-code-quality-baseline.md`; actionable items worked under plan 0009):

- [x] **GameState dependency ceiling** — shipped as plan 0014 (2026-07-19): state → `GameStateData`
  value object, orchestration/construction/validation → `static` `TurnConductor`/`GameStateBuilder`/
  `OrderValidator` taking `GameStateData`; deps 48→24, ceiling enforced via
  `gd_metrics.py --check-ceiling`. See `docs/archive/0014-gamestate-dependency-ceiling.md`.
- [x] **HexMap cosmetic literals**: 93 view-layer color/offset literals — hoist opportunistically
  when Track D touches the view layer, not before.
- [ ] **Const→data knob promotion**: any const hoisted under 0009 the USER wants tunable moves to
  `data/*.json` per `hexcombat-config-and-knobs` — one USER call per knob (change-control #7).
