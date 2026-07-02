# HexCombat — Forward Backlog

The active forward plan, sequenced for the ratified mission (PLAN.md → Decisions 2026-07-02):
**primary** = AI-vs-AI research instrument (Monte Carlo, LLM players, narratives, sweeps);
**secondary** = live-adjudication aid (order entry + projector-friendly view). Pick the next
unstarted item in order; one coherent, verified unit at a time.

Completed tracks from the previous backlog (port audit, refactor audit items 1–9, victory
conditions, doc-restructure first pass) are recorded in `PLAN.md` → Decisions and
`docs/plans/refactor_audit.md` / `port_audit.md` — not repeated here.

---

## Track A — GameState decomposition *(the enabler)* — ✅ COMPLETE 2026-07-02

All four campaign phases done: 5 builders + 8 resolvers in `scripts/resolvers/`, thin delegating
wrappers, golden byte-stable at every step, isolation test suite added. Campaign skill marked
complete (kept as the record of method); `hexcombat-add-phase-resolver` activated. Record:
`docs/plans/refactor_audit.md` item 10 + PLAN.md → Decisions 2026-07-02.

## Track B — Research harness *(primary mission)*

Methodology contract: `.claude/skills/hexcombat-research-runs`. Build order:

- ✅ **B1 — Scenario selection** (2026-07-02). `ScenarioCatalog` (pure statics):
  `--scenario=<id-or-path>` user arg / `HEXCOMBAT_SCENARIO` env var per process, ids resolve to
  `data/scenarios/<id>.json`, default unchanged so all pins hold, selection survives
  `reset_to_scenario`; `validate_scenario_data.gd` now covers every scenario (generic checks) +
  default pins.
- ✅ **B2 — Batch runner** (2026-07-02). `tools/run_batch.ps1` (scenario × policy × common seed
  set, process-per-run, artifact-based verdicts, checkpoint/resume, manifest with commit +
  re-run command lines) + `tools/run_selfplay_game.gd` (byte-reproducible per-game JSON record)
  + `PolicyCatalog` (policy ids fail loud) + `SelfPlayRunner` optional stop_on_game_over.
- ✅ **B3 — Outcome reports** (2026-07-02). `BatchReport` (pure aggregation + Markdown render,
  GdUnit-tested) + `tools/make_batch_report.gd`: batch records → per-condition win rates,
  turn/census/margin distributions, loss means, methods line (commit/mixed-commit/dirty
  warnings), caveats.
- ✅ **B4 — Narrative renderer** (2026-07-02). `GameNarrative` (pure render of a game record's
  event log → turn-by-turn Markdown account, GdUnit-tested) + `tools/make_game_narrative.gd`
  (`--record=<path>` or `--batch=<name> --pick=median|longest|shortest`).
- ✅ **B5 — Sweep generalization** (2026-07-02). `tools/run_sweep.ps1 -Knob <dot.path>
  -Values a,b,c`: generates one-knob scenario variants (generated artifacts under the sweep's
  report dir, never `data/scenarios/`), runs the common-seed batch across them, and reports —
  condition rows ARE the sweep axis. Covers refactor_audit item 7's generalization for
  scenario-file knobs; phase-data-file knobs (e.g. minefield geometry) still need
  scenario-selectable data files (parameterization-gap rule).
- **B6 — LLM-player adapter.** A `SelfPlayPolicy`-contract policy that calls an LLM with the
  observation and parses the action response; full observation/action logging so games are
  replayable; policy-identity stamped into batch records.

**Done when:** one command produces a reproducible multi-condition study report from scenario
variants, with narratives, and an LLM policy can be swapped in for either side.

## Track C — Scenario variants *(with Track B)*

First real variant (user picks the research question; see
`.claude/skills/hexcombat-scenario-authoring`), proving the authoring recipe end-to-end:
variant file → validation → headless self-play → registered in the batch runner.

## Track D — Adjudication aid (graphics/UI) *(secondary — after A/B or on user request)*

Scope per user 2026-07-02: facilitator **order entry + turn resolution in the UI** and
**projector-friendly presentation**. (Umpire overrides and save/load were explicitly NOT
requested.) Sub-areas, priority to be set with the user when the track starts:

- Order-entry flow polish (select → move/commit → end turn) usable by a non-developer facilitator.
- Projector-readable map: markers, ownership colors, phase/turn/combat HUD, camera fit/zoom/pan.
- D5-D front-line polyline-draw UI (the one remaining D5 piece).
- Anti-ship/mine crossing visualization (makes D3 mechanics legible to a room).

All need visual verification (screenshot / Godot MCP / user) — headless gates don't cover pixels.

## Track E — Doc & code hygiene *(opportunistic)*

- ROADMAP.md refresh: milestone/phase sections are historical (all built) — archive or annotate.
- Remaining `refactor_audit.md` low-priority items (5–7) as needs arise.
- `docs/systems/html/` mirrors regenerated when their `.md` sources change materially.
