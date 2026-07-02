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

- **B1 — Scenario selection.** `GameData` loads a scenario by path/id (default unchanged so all
  pins hold); `data/scenarios/` directory; `validate_scenario_data.gd` covers every scenario.
- **B2 — Batch runner.** N seeded headless games (process-per-run) over a scenario × policy
  matrix; per-game JSON records (seed, commit, terminal state, per-turn digests) checkpointed to
  `reports/`; deterministic re-run of any single game.
- **B3 — Outcome reports.** Aggregate batch records → win rates, casualty/duration
  distributions, census margins; Markdown report per the skill's report shape.
- **B4 — Narrative renderer.** `TurnResult.to_dict().events` → readable turn-by-turn account of
  a selected game (median/extreme picks).
- **B5 — Sweep generalization.** The `sweep_antiship_crossing` pattern generalized to any
  scenario knob (refactor_audit item 7), reporting per-knob outcome deltas.
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
