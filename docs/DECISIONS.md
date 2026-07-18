# Decisions changelog

Append-only, newest first. **An entry is a changelog, never a reference**: 3–5 lines — what was
decided, who decided (USER vs agent), and POINTERS to where the durable facts landed. If an agent
would need this entry to act, the fact is filed in the wrong place; put it in its canonical home:

| Fact type | Only home |
|---|---|
| Golden pins / exact validator output | `tools/validate_*.gd` (the PASS line is truth) |
| Module architecture, purity boundaries | code headers (`scripts/resolvers/*.gd`, `GameState.gd`) |
| Cross-module flow, data files, TIV divergence rationale | `docs/systems/<module>.md` |
| Procedures, gotchas | `.claude/skills/` |
| Incident history (root cause, rejected fixes) | `hexcombat-failure-archaeology` |
| What works now | `docs/STATUS.md` |
| Work in flight | `docs/plans/NNNN-*.md` (archived at closeout) |

History before 2026-07-10 lives verbatim in `docs/archive/PLAN.md` (→ "Decisions log" section);
code/doc references to "PLAN.md → Decisions <date>" resolve there.

---

- **2026-07-18 — Sweep review fixes: antiship harness was dead since plan 0004 (review of the
  agent implementation below).** The crossing sweep read 0.0 losses in every cell — including the
  mines-only floor — because since plan 0004 (`a2b60fc`) `resolve_antiship_turn` fires only on
  the sent sealift cohort, and the harness (old scripts and migration alike) never called
  `resolve_sealift_turn`. The 0≡0 "parity" that gated the legacy-script deletion was vacuous.
  Fixed: `run_sweep_cells.gd` now resolves sealift between IJFS and the crossing and measures the
  wave as `SealiftResolver.sent_cohort_bn_ids` (~81 BNs with follow-on echelons, vs the old 36-BN
  reserve) — so the plan-0001 ~25% dial reads differently now and awaits USER re-reading. Also
  fixed in the same pass: spec `scenario` is now actually applied (was silently ignored; the CRBM
  spec's `roc_full_defense` claim was wrong — pinned parity ran `scenario_default`, spec
  corrected); `ScenarioCatalog.resolve_path` round-trips the id `scenario_default` (previously
  resolved to a nonexistent `data/scenarios/` path and the run continued on a failed load);
  runner fail-louds on scenario mismatch/missing file and on `DataOverrides.unapplied()`;
  `make_sweep_report.py` matches cells by override content instead of hardcoded filename slugs
  (the spec pipeline's generated names never matched the old `ic_*` slugs — an antiship report
  would have rendered all-N/A); stale cell files are cleared before each run; the mines-only
  floor cell is declared in the spec (`extra_cells`) and rendered in the report; manifests store
  full seed lists; `--backend batch` with `--spec` errors until plan 0012.

- **2026-07-18 — Sweep orchestrator + cell backend (Plan 0011; agent implementation).** The Python `run_sweep.py` tool now orchestrates sweeps through `run_batch.py` or the new `run_sweep_cells.gd` backend. The legacy bespoke sweep scripts (`sweep_antiship_crossing.gd`, `sweep_crbm_maneuver.gd`, `ijfs_sweep_support.gd`) have been deleted. Replaced with generalized canned sweep specifications in `tools/sweeps/*.json`. Legacy powershell sweep tool `run_sweep.ps1` is deleted. Facts: `docs/STATUS.md` and `.claude/skills/hexcombat-research-runs`.

- **2026-07-17 — Removed the legacy mobile-target-destroy-cap Pk path (USER call, refactor idea #3).**
  `IjfsStrike._legacy_cap_probability`/`_resolve_cap`, the `mobile_target_destroy_caps` scenario
  block, and the always-null `mobile_cap_applied`/`legacy_cap_applied` strike-log fields are deleted.
  The path was inert in production: `destruction_probability` only reached it when
  `strike_probability_modifiers` was empty, and the shipped scenario always carries modifiers (it was
  already documented "dormant"). `strike_probability_modifiers` is now a required scenario block;
  `evaluate_strike_probability` is the sole Pk entry (empty list = base only). Golden-preserving (no
  strike outcome changed) — no re-baseline. Facts: `docs/systems/ijfs.md` §4 Strike. (Stale mention
  remains in `docs/systems/html/antiship_lethality_knobs.html`, a dated analysis snapshot.)

- **2026-07-17 — IJFS maneuver casualties now span all warmup days (Plan 0009 follow-up; USER call).**
  `compute_writeback` read maneuver kills from the final day's `ledgers` only, so multi-day warmup
  kills never decremented the OOB (anti-ship was already cumulative/state-based). Now
  `IjfsResolver.resolve` accumulates every day's strike log. Golden re-baselines (PASS lines are
  truth): `validate_golden_victory` 26/88 → 25/76, `validate_cleanup` casualties=8/feba=-0.23 →
  casualties=6/feba=0.34. Plan 0009's 0.15 dial predates this — its sweep should be re-run.

- **2026-07-17 — CRBM heavy-volley maneuver-attrition knob (Plan 0009; USER design call).** Red now
  fires massive CRBM volleys at ROC maneuver battalions to convert its idle missile inventory into
  real attrition despite the one-attack-per-target-per-day rule. Two coupled scenario knobs in
  `data/ijfs/ijfs_scenario.json`: `crbm_maneuver_rounds_override` (480 — depletion only) and
  `crbm_maneuver_strike_bonus` (0.15 — the lethality lever; STARTING value, awaits USER batch re-dial
  like plan 0001's crossing dial). Mechanism/rationale: `docs/systems/ijfs.md` §4 Strike. Golden pin
  `validate_golden_victory.gd` re-baselined 25/92 → 26/88 (PASS line is truth). Current behavior:
  `docs/STATUS.md`.

- **2026-07-17 — Hierarchical RNG substreams (Plan 0010; agent implementation).** Each contested
  hex's ground fight now draws from its own dice stream, `dice.derive("combat:<turn>:<hex_id>")`,
  instead of a single linear root stream shared across hexes — so a design tweak that changes the
  roll count in one hex no longer scrambles every other hex's dice. IJFS and anti-ship already
  derived their own substreams (`IjfsResolver._derive_day_dice`, `resolve_antiship_turn`); offload
  is dice-free. `SeededDice.derive`/`ScriptedDice.derive` (returns self) pre-existed. Two SeededDice
  golden pins re-baselined (re-derived, not behaviour): `validate_cleanup.gd` and
  `validate_golden_victory.gd` (PASS lines are truth). Current behavior: `docs/STATUS.md`.

- **2026-07-17 — Support unit casualties in ground combat (Plan 0008; USER decision, agent implementation).**
  Support units (artillery, rotary wing) are no longer immortal. They are pooled with maneuver units during casualty selection, weighted 1:4. If a side has only support units, they are considered "unscreened", contributing 0.5 strength each and taking the minimum-blood losses. `ScriptedDice` now uses `weighted_choices` for casualty selection. The golden scenario is re-baselined to reflect these changes. Facts: `docs/systems/ground-combat.md`; current behavior: `docs/STATUS.md`.

- **2026-07-17 — B7 replay and artifact hardening (USER-directed follow-up).** Mixed LLM/heuristic
  matches now log both seats, malformed policy identity records assert instead of grouping under a
  placeholder, and live-model parallelism warns. `validate_batch_runner.py` is part of both
  canonical gates and covers these seams. Facts: `docs/systems/llm-api-selfplay.md`; operation:
  `hexcombat-research-runs`; current behavior: `docs/STATUS.md`.

- **2026-07-17 — Per-seat research matchups (B7; approved plan, agent implementation).**
  `run_selfplay_game.gd` now unconditionally uses the two-seat path; v2 records stamp
  `red_policy_id`/`green_policy_id`, while reports retain legacy-record fallback. The stdlib-only
  `tools/run_batch.py` replaces the PowerShell-only runner with explicit matchup conditions and
  automatic reports. Facts: `docs/systems/llm-api-selfplay.md`; operation:
  `hexcombat-research-runs`; current behavior: `docs/STATUS.md`. Evidence: full gate green and
  90-game common-seed stub-sidecar demonstration (`reports/batches/b7_demo/`, ignored).

- **2026-07-16 — Code-quality baseline + full remediation (plan 0009; USER call on scope).**
  Audit measured (report: `docs/reports/2026-07-16-code-quality-baseline.md`, tool:
  `tools/gd_metrics.py`); standards enshrined as `hexcombat-code-quality` skill + AGENTS.md
  pointer; 6 oversized resolve-path functions split behavior-preserving (golden byte-stable
  throughout), 19 new builder/resolver tests, formula constants named. Deferred debt →
  BACKLOG Track F. Evidence: full gate green per commit.

- **2026-07-16 — `roc_full_defense` given the deep mainland pool (plan 0007; USER decision).**
  Investigation of 4 overnight LLM-vs-LLM games (offload_weights.json re-dial question, plan 0006's
  open item) found the cost matrix was never active in `roc_full_defense` (`use_offload_weight_matrix`
  unset) — the actual cause of the observed landed-force plateau was the scenario's fixed 14-brigade/
  126-BN invasion force exhausting itself by turn ~15-30 with no reinforcement. USER chose to give
  the scenario a deep pool rather than keep it a fixed grind: `auto_seed_followon_pool: true` +
  emptied `red_followon_reserve` (was a curated 10-brigade echelon), same shape as `scenario_default`.
  Verified: `validate_scenario_data.gd` PASS, deterministic self-play (byte-identical repeat), landed
  force now climbs continuously instead of plateauing (44→81 BNs over 12 turns in one seed check),
  full gate green. Facts: `docs/systems/amphibious-offload.md` → "Sealift lifecycle"; investigation +
  options: `docs/archive/0007-offload-weight-rebalance-investigation.md`.

- **2026-07-15 — Post-0006 refactor batch (agent judgment).** Behavior-preserving cleanups from the
  C8 session's findings: deferred-reason constants + day-N decomposition on `OffloadCalculator`;
  `GameData.ship_defs_by_name` index (fail-loud duplicate-name check); JLSF queueing policy
  extracted to `JlsfCargo.queue_deployments`; research policy `inland_clear` registered in
  `PolicyCatalog` (C8-style studies now run via `run_selfplay_game.gd --policy=inland_clear`, no
  scratch drivers). Trap recorded in code: `PolicyCatalog.create` runs in `SceneTree._initialize`,
  before autoload `_ready` — policies must resolve GameData lazily. Golden byte-stable throughout.

- **2026-07-15 — Offload capacity gate shipped (plan 0006; USER design calls + agent implementation).**
  USER calls (AskUserQuestion): data-driven cost matrix (`data/offload_weights.json`, per-type
  weight × bn_class/ship_category multiplier, TIV defaults); JLSF-faithful port repair (seized = 0
  throughput until an abstract, attritable `jlsf_lift_bn_equiv` deployment lands; explicit
  `deploy_jlsf` order + `auto_jlsf` policy knob); per-beach occupancy valve (`BeachDef.depth`,
  default 2); 5 TIV ports + 8 airfields seeded. All knobs default-off ⇒ golden byte-stable, no
  re-baseline. C8 research verification found + fixed a sealift livelock (heavy BNs unlandable in
  one day → carry-over; see `hexcombat-failure-archaeology`). Facts:
  `docs/systems/amphibious-offload.md` §9; knobs: `hexcombat-config-and-knobs`.
  Follow-on to plan 0004. (1) `scenario_default` opts into a **deep mainland pool** auto-seeded from the
  OOB (`auto_seed_followon_pool`) so sustained sealift is gated by amphibious lift capacity, not pool
  size. (2) Fixed two silent lift bugs (see `hexcombat-failure-archaeology`): the amphibious-lift
  filter matched `"Amphibious"` as a **substring** (admitted `Civilian_Non_Amphibious`) — now
  `ShipDef.is_amphibious_lift()` exact membership; and `pack_bns_into_hulls` floored capacity **per
  hull** (sub-1.0 hulls carried 0) — now aggregates `floor(N·C)`. (3) **Golden/research split (USER
  option B):** `scenario_default` = realistic deep-pool default; the gate runs a frozen
  `scenario_golden.json` (one-shot assault) via `HEXCOMBAT_SCENARIO`, so golden pins stay byte-stable
  with **no re-baseline** while the default evolves; deep-pool coverage via
  `tools/validate_deep_pool_smoke.gd`. Shore offload capacity (the second gate) deferred to plan 0006.
  Facts: `docs/systems/amphibious-offload.md` §8; `docs/STATUS.md`.

- **2026-07-12 — Sustained sealift: cross-turn ship lifecycle + capacity-gated echelons + escort
  SAM ammo (USER: scope "Both"; plan 0004).** Replaced the one-shot `ship_reserve` + same-turn
  ship round-trip with a real lifecycle: `SealiftState` (mainland follow-on pool, hull↔BN cohorts,
  return/reload pipeline, escort SAM magazine) advanced by `SealiftResolver` before the crossing;
  follow-on echelons embark onto ready amphibious lift (departed-brigades-first). **Semantic change
  (USER-accepted re-baseline):** a BN now crosses **once** (attrited on its crossing turn, then safe
  in an offloading cohort) instead of the old phantom re-attrition every turn — `scenario_default`
  crossing numbers shifted (fixture regenerated). Escort SAM magazine + reload cycle is off by
  default (seeded only when a scenario sets `escort_reload_time_turns > 0`), so the default pin stays
  byte-stable. Facts: `docs/systems/amphibious-offload.md` → "Sealift lifecycle"; knobs in
  `hexcombat-config-and-knobs`; code headers in `scripts/resolvers/SealiftResolver.gd` +
  `scripts/model/SealiftState.gd`. Evidence: roc_full_defense self-play (seed 20260624) — crossing
  resumes at turn 6 (was 0 for turns 4–30), red reaches china_majority by turn 9.

- **2026-07-11 — Viewer map box split into theater + front viewports (USER request).** The map
  pane now shows the whole island (theater) beside a zoom (front) cropped to contested/Red hexes +
  their neighbors. Implemented as two `<svg>` `<use>`-ing one shared `<defs>` render, differing
  only in `viewBox` (chosen over parameterizing every render fn — single source of truth, SVG-
  native crop). Change made in the `tools/viewer/game_viewer.html` template so it carries to all
  future baked reports. Details in `docs/STATUS.md`; non-contiguous-front corner case → BACKLOG.

- **2026-07-11 — Crossing-lethality calibration: dial picked, golden re-baselined (USER, per plan
  0001).** `intel_locked_antiship_strike_bonus` promoted from an ad-hoc sweep-script modifier to a
  named scenario knob; ran an N=30/seed sweep grid across it and
  `exquisite_intel.antiship.initial_count`, USER picked bonus=0.20 / initial_count=36
  (~27.3% mean crossing loss) over a marginally-closer-to-target alternative. Golden scenario
  re-baselined to these values; `validate_cleanup.gd`, `validate_golden_victory.gd`, and the
  `llm_result_after_turn.json` fixture pins moved accordingly (their comments carry the new
  numbers — never repeated here). Facts: `docs/systems/ijfs.md` → "Strike"; knob details in
  `hexcombat-config-and-knobs`; plan (now closed):
  `docs/archive/0001-crossing-lethality-calibration.md`.

- **2026-07-10 — Viewer briefing mode + casualty charts (USER).** Game-report viewer rebuilt
  from scrollytelling to turn-at-a-time briefing (wheel/buttons/keys, in-place narrative swap,
  ghost-future chart reveal) with a new per-side battalion-loss bar chart; bundler gained
  `--from-bundle` re-bake. USER picked the interaction model (wheel+buttons+keys, ghost reveal,
  turn-1 start, paired bars). Facts: `docs/systems/llm-api-selfplay.md` → §7. Verified by
  headless-Chromium (Playwright) pass — new precedent for browser-tool verification.

- **2026-07-10 — Doc-rot guard: dead anchors fail the gate (USER asked for a guard; agent
  design).** `tools/validate_doc_anchors.gd` (auto-globbed into the gate) rejects dead
  paths/scripts/members and `file.gd:123` citations in `docs/systems/*.md`; `(historical)` marks
  intentional dead names. Checkable diff→owning-doc procedure + ownership table:
  `hexcombat-docs-and-writing` step 2. First run caught 89 line-citations + 1 real rename.

- **2026-07-10 — Docs architecture B: one home per fact (USER).** PLAN.md (2,525 lines, ~84%
  historical by its own admission) and six dead docs archived to `docs/archive/`; lore-style
  `docs/plans/` index + numbered ephemeral plans with a closeout rule; this changelog replaces
  PLAN.md's Decisions log. Rules enforced in `hexcombat-docs-and-writing` +
  `hexcombat-change-control`; audit evidence in the two 2026-07-10 survey reports (session
  history). Systems-doc rot repaired same day (resolver decomposition, terrain, MANPADS).

- **2026-07-10 — MANPADS layer (USER; TIV divergence).** Spec: `docs/systems/ijfs.md` →
  "MANPADS layer". Incident that triggered it: `hexcombat-failure-archaeology` → "2,500 Mobile
  SAMs". Calibration evidence: 30-seed batch (session 2026-07-10); USER accepted first-cut
  constants. Full original entry: `docs/archive/PLAN.md` Decisions 2026-07-10.
