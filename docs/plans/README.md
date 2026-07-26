# HexCombat — plans index

Work orders for multi-session efforts. Each plan is a focused doc; **this index is the source
of truth** for status. Status vocabulary: `Sketch` → `Exploring` → `In progress` → `✅ Shipped`
→ `Superseded`.

**Plans are ephemeral by contract.** A plan holds the design, the checklist, and progress notes
*while the work is in flight*. It is not a reference: no durable fact may live only in a plan.

**Closeout rule** (enforced by `hexcombat-change-control` / `hexcombat-docs-and-writing`):
a plan is done only when its durable facts have landed in their canonical homes —
`docs/systems/<module>.md` updated, `docs/STATUS.md` bullet current, `hexcombat-failure-archaeology`
entry if there was an incident, a 3–5-line `docs/DECISIONS.md` entry — and the plan file gets a
3-line closeout header and moves to `docs/archive/`. If a future agent would need to read the
plan to act, the closeout wasn't done.

## Active

| # | Plan | Priority | Status |
|---|------|----------|--------|
| 0002 | [Per-hull escort magazines (D3-B3)](0002-per-hull-escort-magazines.md) | Low (needs ship-ammo subsystem) | Sketch |
| 0003 | [Combat-summary team attribution](0003-combat-summary-team-attribution.md) | Low (blocked on USER counterattack call) | Sketch |
| 0024 | [Order-entry facilitator flow (live play)](0024-order-entry-facilitator-flow.md) | Medium (live-facilitator UI) | Sketch |
| 0025 | [Front-line polyline-draw UI (D5-D)](0025-frontline-polyline-draw-ui.md) | Medium (live-facilitator UI; large feature) | Sketch |
| 0026 | [Live-play Godot map: camera, HUD, replay screenshotter](0026-liveplay-map-camera-hud.md) | Low (live-operator polish) | Sketch |
| 0027 | [Front-view per-beachhead pager (ocean-spanning fronts)](0027-front-view-beachhead-pager.md) | Low (build only when a talk needs it AND the sim produces an ocean-spanning front) | Sketch |
| 0028 | [Sustained follow-on interdiction](0028-sustained-followon-interdiction.md) | Medium (research; new mechanic — interdiction is a one-shot toll, follow-on crosses at 3% loss) | Sketch |
| 0029 | [Dynamic ROC defense](0029-dynamic-roc-defense.md) | Medium (research; Tier A policy cheap, Tier B counterattack deep — blocked on 0003 + USER call) | Tier A done (A1 repositioning + A2 mobilization phase-in shipped & measured: Red 100%→83.3%); Tier B still gated |
| 0030 | [JLSF first-class cohort (legibility)](0030-jlsf-first-class-cohort.md) | Low (refactor; byte-stable observability — enables 0031) | Sketch |
| 0031 | [Graduated port suppression](0031-graduated-port-suppression.md) | Medium (new mechanic; ROC-only, continuous port capacity, 0%-start default w/ deliberate golden re-baseline + deck refresh, JLSF repair vs off-island fires + IJFS-attritable HIMARS; DataOverrides wiring absorbed as step 0 — design calls settled) | Sketch |
| 0033 | [Brigade organization](0033-brigade-organization.md) | Medium (new mechanic; USER intends to build on it — currently a monotonic decay to zero that nothing reads and the observation misdescribes; design calls open) | Sketch |
| 0035 | [Scenario variant inheritance](0035-scenario-inheritance.md) | Medium (refactor; variants are full copies of the default, so "differs only in X" is unchecked — comparability is the research product) | Sketch |
| 0039 | [One truth about where a battalion is](0039-battalion-location-single-truth.md) | **High (risk buydown; the seam behind BOTH silent census bugs — location is derived by subtraction across 7 mutation paths, guarded only by after-the-fact tripwires). Large: data-model change with a serialization boundary. Step 1 is independently valuable** | Sketch |
| 0040 | [CombatRules — stop hand-threading 26 fields](0040-combatrules-threading.md) | Medium (risk buydown; a field added but not threaded is a silently-inert knob, no gate watches it. Recommended path is the completeness validator ALONE — ~1h — not the restructure) | Sketch |
| 0041 | [One pattern for reaching an autoload](0041-autoload-access-one-pattern.md) | Low (ergonomics; the failure is already CAUGHT by validate_tool_script_purity — this makes the correct pattern obvious rather than remembered) | Sketch |
| 0038 | [TurnConductor phase extraction](0038-turnconductor-phase-extraction.md) | Medium (refactor; ndeps 38 of 38 — the next phase resolver breaks the gate and the ceiling may not be raised. Pure restructuring, no design calls, no behaviour change; byte-stability is the whole acceptance test) | In progress (step 1 shipped: ndeps 38 → 28) |
| 0036 | [Airborne cost and sortie cadence](0036-airborne-cost-and-cadence.md) | Medium (balance; USER call 2026-07-25 answering the plan-0032 dial — double baseline attrition + 1 sortie per 2 days; `red_airborne` only, golden untouched, `validate_air_insertion` pin re-baselines) | Sketch |

| 0016 | [Separate State Data from Autoload](0016-separate-state-data.md) | Medium (hygiene/architecture) | Superseded by 0014 |
| 0022 | [Red reactive beach-opening (feasibility first)](0022-red-beach-switching.md) | Medium (research; new mechanic, gated on a feasibility spike) | Sketch |

## Execution order for the risk-buydown group (0038 → 0040 → 0039, with 0041 as filler)

Set 2026-07-25 after the session that shipped plans 0034/0037 and the gate hardening. These four are
sequenced, not independent — do them in this order unless the USER redirects.

1. **0038 — TurnConductor phase extraction.** FIRST, because it is a *prerequisite*, not a priority
   judgement: `TurnConductor` sits at its dependency ceiling (38 of 38), plan 0037 already had to
   reshape its design mid-implementation to avoid breaching it, and **0039 touches that file
   repeatedly**. Doing 0039 first means fighting the ceiling while also changing the data model.
   No design calls; byte-stability is the whole acceptance test.
2. **0040 — but only option (c), the completeness validator.** ~1 hour, no production code touched,
   removes a silent-failure class. Cheap enough to land between the two large items, and it does not
   touch `TurnConductor`, so it is not blocked by the ceiling. Defer option (a) indefinitely.
3. **0039 — one truth about battalion location.** The real prize and the real work. Needs 0038 done
   first for headroom. **Stop after its step 1 if that does not go green cheaply** — step 1 alone
   converts an undetectable desync into a loud one at every turn boundary, which is most of the risk
   for a fraction of the effort.
4. **0041 — autoload access.** Filler. Independent of the others; slot it in whenever. Ranked last
   deliberately: the failure it prevents is already caught by a gate that names the file and line, so
   this is legibility, not risk.

**Not in this group and not blocked by it:** 0036 (airborne balance dial — the USER's call is already
made, golden untouched, self-contained). If the USER wants a visible game change rather than
infrastructure, 0036 is the one to do first.

**Standing caveat, unrelated to sequencing:** every study measured before 2026-07-25 over-states Red
(census correction + landed-only combat). Re-running them is an open USER decision on compute.

## Archived

| # | Plan | Status |
|---|------|--------|
| 0037 | [Only landed battalions fight, eat, and are reported](../archive/0037-landed-battalions-only.md) | ✅ Shipped 2026-07-25 — USER call: a brigade fights, eats and reports with only the battalions actually ashore. `Brigade.landed_qty` is the single home of the rule; `CombatForces`, `active_red_battalion_units`, `LLMGameAPI._brigade_observations` (+ new `battalions_not_ashore` and `mainland_pool`) and `GameData.snapshot_state` all delegate to it. A brigade with nothing ashore is no longer a combat contributor. Deliberate re-baseline of **two** pins (`validate_dos_consumption` 36→16 units, `validate_cleanup` casualties 5→3 / feba -0.72→-2.66); golden victory, headless turn and air insertion unmoved. |
| 0034 | [One home for pending-battalion pools](../archive/0034-pending-battalion-pools.md) | ✅ Shipped 2026-07-25 — `GameStateData.pending_battalion_pools()` is the sole enumeration of the three off-map pools; `CleanupResolver.census` takes the list; `PendingBattalions` owns the counting + shared manifest iteration. **Not a pure refactor after all:** `SealiftState.mainland_pool` was never subtracted and `_embark_followon` drains it partially, so Red's `scenario_default` census ran up to 8 BN high (turn 20: 57 → 49 corrected). Gate green with no pin moved — nothing was watching. Pre-2026-07-25 studies carry the inflated count. |
| 0032 | [Airborne / air-assault insertion](../archive/0032-airborne-insertion.md) | ✅ Shipped 2026-07-24 — the plan's premise was false (945 PLA BNs, zero airborne), so this ALSO built the PLAAF Airborne Corps: 6 brigades / 50 BNs in the OOB. Air insertion phase + `air_insert` order + AD-health-keyed attrition with permanent airframe loss + supply isolation until a corridor reaches the drop; `red_airborne` scenario, `air_assault` policy, 5 knobs. Golden byte-stable; `scenario_default` untouched. Measured: Red 83%→97% against the plan-0029 mobilizing defender, median decision 21→11 turns, but lift saturates at 3 BN/turn — balance call open, see `docs/reports/2026-07-24-airborne-insertion-sweep.md`. |
| 0023 | [Presentation visuals for headless LLM-vs-LLM games](../archive/0023-track-d-orchestration.md) | ✅ Shipped 2026-07-23 — P1 front-view largest-cluster framing (+ `test_clustering.mjs`), P2 canonical `ship_stats` bundle home (gate-guarded by `validate_make_game_bundle.py`) + map crossing annotation, P3 projector header + legend. Reframed presentation-first, swarm dropped; live-facilitator work split to 0024–0026, ocean-spanning pager to 0027. Visual log in `docs/reports/2026-07-23-plan-0023-visual-log.md`. |
| 0013 | [One home for scenario files](../archive/0013-scenario-files-one-home.md) | ✅ Shipped 2026-07-22 — `scenario_default.json` and `scenario_golden.json` moved to `data/scenarios/`. `ScenarioCatalog` updated. |
| 0021 | [Garrison draw policy + draw_fraction knob](../archive/0021-garrison-draw-policy.md) | ✅ Shipped 2026-07-21 — `garrison_draw` deterministic policy + `garrison_draw_fraction` knob added to registry. Evaluated via unit tests and batch sweep vs `inland_clear`. |
| 0018 | [Research Knob Tracking](../archive/0018-research-knob-tracking.md) | ✅ Shipped 2026-07-20 — curated knob registry `data/knobs/registry.json` + full resolved knob vector in every record (`KnobRegistry`), so all sweeps share one knob-space; `tools/research_knobs.py {ledger,sensitivity}`; LLM model/prompt-hash captured. USER calls: curated (not auto-dump), prompts capture-only, build all-at-once. Golden byte-stable. Array-knob sweeping shipped as a follow-on (`DataOverrides` array addressing via `JsonPath`); remaining follow-up: prompt-variant files |
| 0020 | [Lowercase "red"/"green" team-token seam](../archive/0020-lowercase-team-token-seam.md) | ✅ Shipped 2026-07-20 — Tier A: 3 resolver ownership reads onto `HexOwner.RED`. Tier B (USER Option 2): winner/census wire token gets its own home `Brigade.TEAM_KEY_RED`/`TEAM_KEY_GREEN` (const — used in `match` arms + dict keys), kept distinct from `HexOwner` ownership vocab; golden byte-stable |
| 0019 | [Consolidate Brigade.Team→string converters](../archive/0019-team-string-seam.md) | ✅ Shipped 2026-07-20 — `Brigade.team_name(team)` static now owns the capitalized `"Red"/"Green"` mapping; six byte-identical local copies deleted and repointed; lowercase record serialization untouched; pure dedup, golden byte-stable; entry in `docs/DECISIONS.md` |
| 0017 | [Move order validation off push_error](../archive/0017-validation-errors.md) | ✅ Shipped 2026-07-20 — `OrderValidator.add_move_order`/`add_commit_order` (+ `GameState` wrappers) return a typed `OrderResult` (`ok`/`code`/`message`, `scripts/model/OrderResult.gd`) instead of `push_error`; LLM API surfaces the rejection reason; 11 GdUnit assertions moved off `is_push_error` to `code`; golden byte-stable; facts in `docs/STATUS.md`, `docs/DECISIONS.md`, `docs/systems/turn-engine.md` + `llm-api-selfplay.md` |
| 0015 | [Fully Parallelize Tests](../archive/0015-parallel-tests.md) | ✅ Shipped 2026-07-19 — unified `run_all_tests.py` using `concurrent.futures`, isolated Godot caches, wrapped `.sh` and `.ps1` |
| 0014 | [GameState dependency ceiling](../archive/0014-gamestate-dependency-ceiling.md) | ✅ Shipped 2026-07-19 — `GameState` split into a `GameStateData` value object + `static` `TurnConductor`/`GameStateBuilder`/`OrderValidator` (take `GameStateData`, never the autoload); deps 48→24, ceiling gated in `gd_metrics.py --check-ceiling`; absorbed plan 0016; facts in `docs/STATUS.md`, `docs/DECISIONS.md` |
| 0012 | [Unified sweep extraction & batch specs](../archive/0012-unified-sweep-extraction.md) | ✅ Shipped 2026-07-18 — canned sweeps unified on the batch backend (`run_sweep_cells.gd` deleted); Python metric extractors over standard game records (raw numbers, report owns formatting); `noop` matchup preserves dialed measurement semantics (byte-identical parity tables); `disable_phases` + `disable_antiship_systems` knobs; facts in `docs/STATUS.md` B5, `hexcombat-research-runs`, `hexcombat-config-and-knobs`, `docs/DECISIONS.md` |
| 0011 | [Disciplined Sweep Ecosystem](../archive/0011-disciplined-sweep-ecosystem.md) | ✅ Shipped 2026-07-18 — unified `run_sweep.py` orchestrator + `run_sweep_cells.gd` in-process backend; canned specs under `tools/sweeps/*.json`; deleted legacy bespoke sweep scripts; facts in `docs/STATUS.md`, `docs/systems/ijfs.md`, `docs/DECISIONS.md` |
| 0009 | [CRBM Maneuver Attrition Calibration Knob](../archive/0009-crbm-maneuver-attrition-knob.md) | ✅ Shipped 2026-07-17 — 480-round CRBM volley (`crbm_maneuver_rounds_override`) + lethality bonus (`crbm_maneuver_strike_bonus`, USER-dialed 0.15) vs maneuver units; follow-ups: warmup-casualty writeback fix (26/88→25/76), legacy mobile-cap removal, sweep-plumbing dedup; facts in `docs/systems/ijfs.md` §4, `hexcombat-config-and-knobs`, `docs/DECISIONS.md` |
| 0010 | [Hierarchical Deterministic RNG (Sub-streams)](../archive/0010-hierarchical-rng-substreams.md) | ✅ Shipped 2026-07-17 — per-hex combat substream (`dice.derive("combat:<turn>:<hex>")`); ijfs/antiship already derived, offload dice-free; 2 SeededDice pins re-baselined; facts in `docs/STATUS.md`, `docs/DECISIONS.md` |
| 0008 | [Immortal Support Units in Ground Combat](../archive/0008-immortal-support-units-combat.md) | ✅ Shipped 2026-07-17 — quarter-weight support casualties, unscreened strength 0.5; facts in `docs/systems/ground-combat.md`, `docs/STATUS.md`, `docs/DECISIONS.md` |
| 0009 | [Code-quality baseline + remediation](../archive/0009-code-quality-baseline.md) | ✅ Shipped 2026-07-16 — audit + standards skill (`hexcombat-code-quality`) + full remediation (6 splits, 19 tests, const hoists), all golden byte-stable; report in `docs/reports/`, deferred debt in BACKLOG Track F |
| 0007 | [Offload weight rebalance investigation](../archive/0007-offload-weight-rebalance-investigation.md) | ✅ Shipped 2026-07-16 — reframed the plateau to a force-commitment question (matrix was inactive); `roc_full_defense` given `scenario_default`'s deep pool; facts in `docs/systems/amphibious-offload.md`, `docs/DECISIONS.md` |
| 0006 | [Offload capacity gate (beaches + ports)](../archive/0006-offload-capacity-gate.md) | ✅ Shipped 2026-07-15 — infrastructure nodes + JLSF repair + cost matrix + occupancy valve + day-N carry-over; facts in `docs/systems/amphibious-offload.md` §9, `docs/DECISIONS.md` |
| 0004 | [Port TIV ship-count & crossing model (sealift gap)](../archive/0004-port-ship-crossing-sealift-model.md) | ✅ Shipped 2026-07-12 — cross-turn ship lifecycle + follow-on echelons + escort SAM magazine; facts in `docs/systems/amphibious-offload.md` §8, `docs/DECISIONS.md` |
| 0001 | [Crossing-lethality calibration (D3-D)](../archive/0001-crossing-lethality-calibration.md) | ✅ Shipped 2026-07-11 — dial-in facts in `docs/systems/ijfs.md`, `hexcombat-config-and-knobs`, `docs/DECISIONS.md` |

## Tech Debt & Hygiene

See [BACKLOG.md](BACKLOG.md) for a running list of technical debt, hygiene issues, and refactor observations logged by agents.

## Parked refinements (no plan until a concrete need)

One-liners; detail in `docs/archive/port_audit.md`:
- Flotilla composition nuances (unit of allocation for the missile pipeline — only with 0001).
- Front-line distribution at battalion granularity (with the D5-D draw UI, Track D).
- ShipLoadingModel per-type transport weight + amphibious-vs-cargo eligibility (exact-manifest
  calibration only).
- Deliberately NOT ported (TIV-specific): SQL/DB writeback, mine same-day re-preview baseline,
  Streamlit dashboards — list in `docs/archive/port_audit.md` §Intentionally skipped.
