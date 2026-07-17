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
| 0008 | [Immortal Support Units in Ground Combat](0008-immortal-support-units-combat.md) | High | Sketch |
| 0009 | [CRBM Maneuver Attrition Calibration Knob](0009-crbm-maneuver-attrition-knob.md) | High | Sketch |
| 0005 | [Game-record inconsistency audit (agent brief)](0005-game-record-inconsistency-audit.md) | Medium | Sketch |
| 0002 | [Per-hull escort magazines (D3-B3)](0002-per-hull-escort-magazines.md) | Low (needs ship-ammo subsystem) | Sketch |
| 0003 | [Combat-summary team attribution](0003-combat-summary-team-attribution.md) | Low (blocked on USER counterattack call) | Sketch |

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

- **GameState dependency ceiling**: 47 class references (next-worst: GameData 18). Turn-conductor
  role justifies breadth, but growth is unbounded — future campaign: push reference ownership
  into builders/resolvers, then enforce a ceiling via `tools/gd_metrics.py`.
- **HexMap cosmetic literals**: 93 view-layer color/offset literals — hoist opportunistically
  when Track D touches the view layer, not before.
- **Const→data knob promotion**: any const hoisted under 0009 the USER wants tunable moves to
  `data/*.json` per `hexcombat-config-and-knobs` — one USER call per knob (change-control #7).
- **IjfsDetection satellite/aircraft near-clone**: 37 duplicated lines; merge behind one
  parameterized helper next time detection logic changes.
- **Order-dependent `combat_resolution_test`** (found 2026-07-16): fails standalone on a fresh
  autoload state, passes inside the full gate — it depends on state earlier suites leave in
  GameData/GameState. Make its `before()` self-sufficient so standalone runs are trustworthy
  during refactors.

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
