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

- **2026-07-22: Combat Constants Promoted to Scenario Knobs**
  - **Who**: USER (authorized) and Agent
  - **What**: Promoted all hardcoded combat parameters (support multipliers, loss rate parameters, FEBA shift, and default strength) from `CombatCalculator` and `UnitStats` into scenario configuration fields.
  - **Where**: `GameData.gd`, `CombatRules.gd`, `CombatCalculator.gd`, `UnitStats.gd`, and registered in `data/knobs/registry.json`.
  - **Why**: Allows research parameter sweeps over core combat mechanics (Track F, Item 2).

- **2026-07-22 — HexMap cosmetic literals hoisted to constants (USER authorized, agent implementation).**
  Track F backlog item completed. Grouped and hoisted 93 view-layer color and offset literals from `HexMap.gd` into named constants at the top of the file. Behavior preserving. Code headers in `scripts/HexMap.gd`.

- **2026-07-22 — Scenario files moved to one home (plan 0013; agent implementation).**
  Moved `data/scenario_default.json` and `data/scenario_golden.json` into `data/scenarios/` so all scenarios share a single location. `ScenarioCatalog` simplified to use a pure glob and no longer needs special-casing for the default scenario id. Fixed test paths and references across documentation. Golden byte-stable; Windows gate run pending but assumed green. Facts: `docs/STATUS.md`.
- **2026-07-21 — Garrison draw policy and sweep (plan 0021; agent implementation, USER design calls).**
  Added `garrison_draw` policy to simulate ROC commanders pulling non-landing theater garrisons toward
  the landing hexes while fighting locally at the landing. Introduced `garrison_draw_fraction` knob in
  `data/knobs/registry.json` and a new parameterized `data/policies/garrison_draw.json` policy. Added
  `garrison_draw` to `PolicyCatalog`. Golden byte-stable (tests run green). Verified behavior via
  GdUnit tests and a batch parameter sweep. Facts: `docs/STATUS.md` (AI-readiness).

- **2026-07-20 — Legibility refactor: the JSON path/array grammar has one home, `scripts/JsonPath.gd`
  (agent, USER-requested reflection).** The array-segment grammar had been reimplemented in two
  places (the read-side `KnobRegistry._extract` dump and the write-side `DataOverrides._set_override`)
  with byte-identical segment parsing — the very seam class plans 0019/0020 removed, re-introduced by
  the array-addressing follow-on. Extracted `JsonPath.parse_segment` / `select_indices` / `is_all_elements`
  as the canonical grammar; both callers use them (read stays lenient/null, write stays fail-loud —
  the asymmetry is why the traversals are NOT merged). Docs reconciled onto it: fixed the ghost method
  reference (`registry.json` said `GameData.dump_tunables()`, which never existed — it is
  `KnobRegistry.resolve_all`), removed stale "(dump-only)" array claims from the config skill +
  `KnobRegistry` header, pointed the four grammar re-specs at the JsonPath header, unified the
  `beach_capacities` path/label on `beaches[*]`, and dropped array-sweeping from the README follow-ups.
  Pure internal move under existing tests; golden byte-stable.

- **2026-07-20 — Plan 0018 follow-on: array knobs are now first-class sweepable (agent, USER-requested).**
  `DataOverrides` learned array-segment addressing once — `name[*]`/`name[]` (every element) and
  `name[N]` (one) — so any array knob is sweepable with no per-knob code; `KnobRegistry._extract`
  shares the same grammar for the record dump (single home for the syntax). Flipped `beach_capacities`
  to `sweepable: true` (the only change to the registry): `run_sweep.py --knob
  "data/beaches.json:beaches[*].capacity_battalions"` scales all nine beaches at once. Verified
  end-to-end (a real capacity sweep records the uniform vector; `capacity_battalions` is live via
  `OffloadCalculator.beach_capacity_bns`). Golden byte-stable (arrays only touched when an override
  targets them). Remaining 0018 follow-up: prompt-variant files.

- **2026-07-20 — Plan 0018 shipped: research-knob tracking so all sweeps are comparable (agent
  implementation; USER design calls).** Curated knob registry `data/knobs/registry.json` (23 knobs);
  every game record now carries the full resolved knob vector `record["knobs"]` (via new pure
  `scripts/KnobRegistry.gd`, stamped by `run_selfplay_game.gd`), so records from any sweep share one
  knob-space. `tools/research_knobs.py {ledger,sensitivity}` renders the explored-space table and
  ranks which knobs move outcomes most. LLM `llm_model` + `llm_prompt_hash` captured (sidecar hashes
  its system prompt). USER calls: **curated** registry not auto-dump; prompts **capture-only** now
  (variant files deferred); build **all at once**. Golden byte-stable (knobs field additive to
  research records). Follow-ups: array-knob sweeping (beach capacity), prompt-variant files. Homes:
  `hexcombat-config-and-knobs` (registry), `hexcombat-research-runs` (ledger/sensitivity),
  `docs/STATUS.md`. Two gate validators added (`validate_knob_registry.gd`, `validate_research_knobs.py`).

- **2026-07-20 — Plan 0020 shipped: the lowercase `"red"/"green"` team-token seam consolidated,
  two homes kept distinct (Tier A agent; Tier B USER design call — Option 2).** Tier A: the three
  resolver hex-ownership *reads* that bypassed `HexOwner.RED` with a bare `"red"` (`OffloadResolver`,
  `InfrastructureResolver` ×2) now use the const — ownership vocabulary already lived on `HexOwner`.
  Tier B: the game-record `winner` field + team-keyed census/policy dicts got their own home —
  `Brigade.TEAM_KEY_RED`/`TEAM_KEY_GREEN` consts (const, not a func, because the token appears in
  `match` arms and dict keys where a call is illegal). USER chose Option 2: outcome/record token
  (`Brigade`) is deliberately SEPARATE from hex-ownership (`HexOwner`) despite the shared spelling.
  Producers + GDScript consumers repointed (VictoryConditions, CleanupResolver, GameNarrative,
  BatchReport, run_selfplay_game.gd, LLMGameAPI parse guard). Python report tools keep their own
  JSON-contract literals (language boundary). Golden byte-stable. `MineWarfareService.status_color`
  traffic-light `"red"/"amber"/"green"` is not a team token — untouched.

- **2026-07-20 — Plan 0019 shipped: the `Brigade.Team → "Red"/"Green"` display converter is now
  owned by the enum's owner (agent implementation).** Added `Brigade.team_name(team)` static; the
  six byte-identical local copies (`OrderValidator.team_to_string`, plus `_team_to_string`/`_team_str`
  in `GameData`, `GameController`, `InfoPanel`, `LLMGameAPI`, `TurnEventLog`) deleted and repointed
  to it. Lowercase `"red"/"green"` record serialization is a distinct mapping, untouched. Pure dedup;
  golden byte-stable; no STATUS change.

- **2026-07-20 — Plan 0019 follow-on: the inverse `string → Brigade.Team` parser folded onto
  `Brigade` too (agent implementation).** Added `Brigade.team_from_name(name)` (case-insensitive,
  silent RED default). `GameData._parse_team` deleted (both callers inlined); `LLMGameAPI._parse_team_string`
  reduced to a thin wrapper that appends the unknown-team parse error (the guard `_parse_action_team`
  relies on) then delegates. Input-side only; golden byte-stable.

- **2026-07-20 — Plan 0017 shipped: order validation returns a typed `OrderResult`, not
  `push_error` (agent implementation).** `OrderValidator.add_move_order` / `add_commit_order` (and
  their `GameState` wrappers) now return `OrderResult` (`ok` / `code`:enum / `message`; new
  `scripts/model/OrderResult.gd`, following the CombatResult/MineResult typed-Resource pattern)
  instead of `push_error(<string>)` + void. Callers branch on `result.ok`; the LLM API's old
  count-the-orders rejection hack is gone and now feeds `OrderResult.message` back to the agent in
  the result `errors` array. 11 GdUnit assertions moved off `assert_error().is_push_error(<string>)`
  to asserting `code` (`composition`/`movement`/`game_state` tests). `eligible_commit_brigades`'
  lone `push_error` stays (programmer-error guard, not order validation). Control-flow-only; golden
  byte-stable, 120 suites green. Behavior in `docs/systems/turn-engine.md` + `llm-api-selfplay.md`;
  contract in `OrderValidator.gd` header.

- **2026-07-19 — Plan 0014 shipped: GameState genuinely decoupled + dependency ceiling gated
  (agent implementation, USER-directed re-scope).** `GameState` (autoload) was split three ways:
  runtime state moved to a plain `GameStateData` value object (`scripts/model/`, absorbing plan
  0016), and orchestration/construction/order-validation moved to `static` services
  `TurnConductor` / `GameStateBuilder` / `OrderValidator` (`scripts/resolvers/`) that take a
  `GameStateData` and never the autoload — genuine decoupling, not the reference-laundering of the
  reverted first attempt. `GameState` is now a thin state-holder with typed forwarding properties;
  deps 48→24. Ceiling enforced in the gate via `gd_metrics.py --check-ceiling` (GameState 27,
  TurnConductor 36). Byte-stable golden throughout. Purity contract in the class headers; behavior
  in `docs/STATUS.md` (Engine). Superseded plan 0016.

- **2026-07-19 — Plan 0015 shipped: parallelized verification gate (agent implementation).**
  The gate's per-validator and per-GdUnit-suite phases now fan out across `os.cpu_count()` workers
  via a single unified `tools/run_all_tests.py` (Python `concurrent.futures`), each Godot process
  handed an isolated `--user-data-dir` to avoid class-cache contention; `run_all_tests.sh`/`.ps1`
  are thin wrappers over it, so both boxes run identical gate logic. Teardown-flake tolerance and
  phase semantics preserved. Verified ALL PHASES GREEN on Linux; Windows `.ps1` wrapper unrun
  (same pending-Windows-gate caveat as plan 0013).

- **2026-07-18 — Plan 0012 shipped: unified sweep extraction on the batch backend (agent
  implementation).** `run_sweep_cells.gd` deleted; every sweep cell is now a parallel
  `run_batch.py` set of standard `run_selfplay_game.gd` games, with `sweep_metrics.py` extracting
  raw numbers from game records (`wave_bns` added to `AntishipSummary` for the denominator) and
  `make_sweep_report.py` owning all formatting. Canned specs run `matchup: noop` (new
  `NoopPolicy`) — NOT the plan's `disable_phases` route — because the dialed reference tables
  include beach-combat dynamics from offload landings; `disable_phases` shipped anyway as a
  scenario knob, and the mines-only floor became the `disable_antiship_systems` override. Proof:
  both reference tables reproduced byte-identically (antiship golden-dial cell 32.9%, CRBM +0.15
  = 46.0/124). Facts: `docs/STATUS.md` B5, `hexcombat-research-runs`, `hexcombat-config-and-knobs`.

- **2026-07-18 — Fixture drift gate was vacuous; fixed + honest re-baseline (agent, e02abc7).**
  Both gate scripts called `export_llm_*.gd` without the `--` separator, so the drift check
  compared an untouched `docs/examples/` with itself since f37170f; the committed result fixture
  had rotted through the plan-0004..0011 sea-phase evolution. Separator fixed on both boxes,
  fixture regenerated and committed. Incident: `hexcombat-failure-archaeology` → "Fixture drift
  gate was vacuous".

- **2026-07-18 — Sweep tooling refactor pass (review follow-up ideas 2/3/4/7; agent
  implementation, USER-approved).** `run_sweep.py` restructured into `run_spec_sweep` /
  `run_cli_sweep` + shared helpers, with metrics validated against the `sweep_metrics.REGISTRY`
  at launch; `mines_only` moved from a fake override key to a cell-level runner directive (the
  overrides namespace now holds only `file:dot.path` keys); `run_sweep_cells.gd` drops the
  redundant eager `_rebuild_ijfs_state` (reset lazy-nulls it; the CRBM path keeps one eager
  build for its pre-resolve pool census); `run_batch.py`'s manifest override embed fails loud
  instead of silently recording a path. Proof: both canned sweeps byte-identical before/after;
  gate green. Plans: 0013 authored (scenario files one-home — idea 5); 0012 updated (raw-number
  metric contract folded into Phase B — idea 6).

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
  full seed lists; `--backend batch` with `--spec` errors until plan 0012. **USER call 2026-07-18: the golden dial stays at ic=36/bonus=0.20 — the 32.9% reading on the new 81-BN sent-cohort wave is accepted as the standing calibration** (supersedes plan 0001's ~25%-of-36-BN target; no re-dial).

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
