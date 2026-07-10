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
- ✅ **B6 — LLM-player adapter** (2026-07-08). `LLMPolicy` (SelfPlayPolicy-contract, id
  `llm_local`) marshals the perspective observation to an out-of-process Python sidecar
  (`tools/llm_sidecar.py`, OpenAI-compatible local model via `HEXCOMBAT_LLM_*`), validates the
  returned actions against the legal sets, and logs every observation/action pair as JSONL for
  replay. `SelfPlayRunner.play_game_seats` drives two independent seats (Red vs Green) to a
  simultaneous WeGo resolve; `tools/run_llm_game.gd` plays one full LLM-vs-LLM game.
  Deterministically gated with no network by `tools/validate_llm_policy.gd` (stub sidecar
  `tools/llm_sidecar_stub.py`); `HEXCOMBAT_LLM_SIDECAR` swaps the sidecar. **Live-verified**
  2026-07-08 against local vLLM (model `jarvis`): full two-seat game to a decision, record +
  JSONL replay log. **Remaining:** per-seat policies in the B2 batch runner
  (`run_batch.ps1`/`run_selfplay_game.gd` are still single-policy) so LLM seats flow into
  multi-condition *studies*.

**Done when:** one command produces a reproducible multi-condition study report from scenario
variants, with narratives, and an LLM policy can be swapped in for either side. *(Single
LLM-vs-LLM games ship via `run_llm_game.gd`; the batch-runner per-seat wiring is the last step for
LLM policies inside multi-condition studies.)*

## Track C — Scenario variants *(with Track B)*

First real variant (user picks the research question; see
`.claude/skills/hexcombat-scenario-authoring`), proving the authoring recipe end-to-end:
variant file → validation → headless self-play → registered in the batch runner.

- ✅ **First variant — `roc_full_defense`** (2026-07-08, USER-requested). All 32 ROC brigades
  (124 battalions) from `data/roc_ground_forces.json` placed at their nearest-unoccupied hex by
  real lat/lon, vs the same 4 PLA amphibious brigades as the default. Proves the recipe end-to-end
  (validated + deterministic 8-turn self-play, census r:g 36:112, no early finish) and gives
  LLM-vs-LLM games a meaningful multi-turn fight instead of the default's turn-1 census decision.
  Select with `--scenario=roc_full_defense`.

## Track D — Adjudication aid (graphics/UI) *(secondary — after A/B or on user request)*

Scope per user 2026-07-02: facilitator **order entry + turn resolution in the UI** and
**projector-friendly presentation**. (Umpire overrides and save/load were explicitly NOT
requested.) Sub-areas, priority to be set with the user when the track starts:

- Order-entry flow polish (select → move/commit → end turn) usable by a non-developer facilitator.
- Projector-readable map: markers, ownership colors, phase/turn/combat HUD, camera fit/zoom/pan.
- D5-D front-line polyline-draw UI (the one remaining D5 piece).
- Anti-ship/mine crossing visualization (makes D3 mechanics legible to a room).

All need visual verification (screenshot / Godot MCP / user) — headless gates don't cover pixels.

## Track F — Map & terrain model *(bigger effort; design + data sourcing with the user)* — ✅ COMPLETE 2026-07-09

From the 2026-07-08 external map review (items 1 and 4; items 2/3/5 fixed same day):

- ✅ **Terrain/sea model, including map rendering** (2026-07-09). Hexes carry a terrain class
  (`data/terrain/hex_terrain.json` + `data/terrain/terrain_types.json`, USER design calls on
  classes + modifiers), movement consumes `move_cost`/`impassable` (`GameData._terrain_entry_cost`,
  `_with_impassable`), and ground combat consumes `defender_modifier`
  (`CombatResolver.resolve_at` → `GameState._defender_combat_modifier`; golden re-baselined —
  current pins live in `tools/validate_headless_turn.gd`; see PLAN.md → Decisions 2026-07-09).
  `terrain` is also surfaced per-hex in the LLM `occupied_hexes` observation. Map rendering
  landed stage 6 and iterated same-day to its final form: pure terrain fills + red/contested
  region borders (`HexMap._build_ownership_borders`), numbered beach glyphs. Full detail:
  `docs/systems/terrain.md`.
- ✅ **East-coast hex fidelity** (2026-07-09, bundled with the terrain-data sourcing above per
  plan). `data/taiwan_hex_grid.json` regenerated against the real GSHHG coastline
  (`tools/terrain/reconcile_grid.py`): ≥5% land-fraction inclusion rule + odd-r contiguity filter,
  404 hexes kept byte-identical, 51 dropped, 62 added (Hualien–Taitung shore concavity fixed by
  the added east-coast hexes) — net 466 hexes. See PLAN.md → Decisions 2026-07-09.

**Deferred out of this track:**

- **Beach first-landing ×2 defender penalty** — deferred design call (2026-07-09): should a
  defender get a temporary combat bonus on the turn an amphibious brigade first lands on their
  hex, modeling the chaos/vulnerability of an unopposed or lightly-opposed landing? Needs a USER
  decision on trigger condition (first landing only? every landing turn?) and whether it stacks
  with terrain. Implementation seam is already in place and unused: the composite-modifier
  structure of `GameState._defender_combat_modifier` (`scripts/GameState.gd:561-568`) multiplies
  the terrain modifier by a literal `* 1.0` situational-modifier slot specifically reserved for
  this — a beach-first-landing multiplier plugs in there without touching `CombatResolver` or
  `GameData`.

## Track E — Doc & code hygiene *(opportunistic)*

- ROADMAP.md refresh: milestone/phase sections are historical (all built) — archive or annotate.
- Remaining `refactor_audit.md` low-priority items (5–7) as needs arise.
- `docs/systems/html/` mirrors regenerated when their `.md` sources change materially.
