# HexCombat — plans index

Work orders for multi-session efforts. Each plan is a focused doc; **this index is the source
of truth** for status. Status vocabulary: `Sketch` → `Exploring` → `In progress` → `✅ Shipped`
→ `Superseded`.

**Plans are ephemeral by contract.** A plan holds the design, the checklist, and progress notes
*while the work is in flight*. It is not a reference: no durable fact may live only in a plan.

**Closeout rule** (enforced by `hexcombat-change-control` / `hexcombat-docs-and-writing`):
a plan is done only when its durable facts have landed in their canonical homes —
`docs/systems/<module>/<module>.md` updated, `docs/systems/<module>/STATUS.md` bullet current,
`hexcombat-failure-archaeology` entry if there was an incident, a 3–5-line `docs/DECISIONS.md`
entry — and the plan file gets a 3-line closeout header and moves to `docs/archive/`. If a future
agent would need to read the plan to act, the closeout wasn't done.

## Active

| #    | Plan                                                                                      | Priority                                                                                                                                                                                                                                               | Status                                                                                                                                                                                                                                      |
| ---- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0002 | [Per-hull escort magazines (D3-B3)](0002-per-hull-escort-magazines.md)                       | Low (needs ship-ammo subsystem)                                                                                                                                                                                                                        | Sketch                                                                                                                                                                                                                                      |
| 0003 | [Combat-summary team attribution](0003-combat-summary-team-attribution.md)                   | Low (blocked on USER counterattack call)                                                                                                                                                                                                               | Sketch                                                                                                                                                                                                                                      |
| 0024 | [Order-entry facilitator flow (live play)](0024-order-entry-facilitator-flow.md)             | Medium (live-facilitator UI)                                                                                                                                                                                                                           | Sketch                                                                                                                                                                                                                                      |
| 0025 | [Front-line polyline-draw UI (D5-D)](0025-frontline-polyline-draw-ui.md)                     | Medium (live-facilitator UI; large feature)                                                                                                                                                                                                            | Sketch                                                                                                                                                                                                                                      |
| 0026 | [Live-play Godot map: camera, HUD, replay screenshotter](0026-liveplay-map-camera-hud.md)    | Low (live-operator polish)                                                                                                                                                                                                                             | Sketch                                                                                                                                                                                                                                      |
| 0027 | [Front-view per-beachhead pager (ocean-spanning fronts)](0027-front-view-beachhead-pager.md) | Low (build only when a talk needs it AND the sim produces an ocean-spanning front)                                                                                                                                                                     | Sketch                                                                                                                                                                                                                                      |
| 0028 | [Sustained follow-on interdiction](0028-sustained-followon-interdiction.md)                  | Medium (research; new mechanic — interdiction is a one-shot toll, follow-on crosses at 3% loss)                                                                                                                                                       | Sketch                                                                                                                                                                                                                                      |
| 0029 | [Dynamic ROC defense](0029-dynamic-roc-defense.md)                                           | Medium (research; Tier A policy cheap, Tier B counterattack deep — blocked on 0003 + USER call)                                                                                                                                                       | Tier A done (A1 repositioning + A2 mobilization phase-in shipped & measured: Red 100%→83.3%); Tier B still gated                                                                                                                           |
| 0030 | [JLSF first-class cohort (legibility)](0030-jlsf-first-class-cohort.md)                      | Low (refactor; byte-stable observability — enables 0031)                                                                                                                                                                                              | Sketch                                                                                                                                                                                                                                      |
| 0031 | [Graduated port suppression](0031-graduated-port-suppression.md)                             | Medium (new mechanic; ROC-only, continuous port capacity, 0%-start default w/ deliberate golden re-baseline + deck refresh, JLSF repair vs off-island fires + IJFS-attritable HIMARS; DataOverrides wiring absorbed as step 0 — design calls settled) | Sketch                                                                                                                                                                                                                                      |
| 0033 | [Brigade organization](0033-brigade-organization.md)                                         | Medium (new mechanic; USER intends to build on it — currently a monotonic decay to zero that nothing reads and the observation misdescribes; design calls open)                                                                                       | Sketch                                                                                                                                                                                                                                      |
| 0035 | [Scenario variant inheritance](0035-scenario-inheritance.md)                                 | Medium (refactor; variants are full copies of the default, so "differs only in X" is unchecked — comparability is the research product)                                                                                                               | Sketch                                                                                                                                                                                                                                      |
| 0039 | [One truth about where a battalion is](0039-battalion-location-single-truth.md)              | Superseded — a derived ledger cannot catch the historical one-sided transition bug                                                                                                                                                                    | **Superseded by 0044**                                                                                                                                                                                                                |
| 0040 | [CombatRules — stop hand-threading 26 fields](../archive/0040-combatrules-threading.md)     | Medium (risk buydown; a field added but not threaded is a silently-inert knob, no gate watches it. Recommended path was the completeness validator ALONE — not the restructure)                                                                       | **Complete 2026-07-26** — option (c) shipped as `tools/validate_combat_rules_threading.gd`, no production code touched; (a) deferred indefinitely, (b) blocked by tool purity                                                      |
| 0041 | [One pattern for reaching an autoload](0041-autoload-access-one-pattern.md)                  | Low (ergonomics; the failure is already CAUGHT by validate_tool_script_purity — this makes the correct pattern obvious rather than remembered)                                                                                                        | Sketch                                                                                                                                                                                                                                      |
| 0043 | [Anti-ship mutation authority + permanent launch destruction](../archive/0043-antiship-mutation-authority.md) | **High — first vertical slice + USER-ruled permanent launch destruction** | **Complete 2026-07-27** — the first ENFORCED aggregate: `scripts/transitions/AntishipTransitions.gd` is the anti-ship establishment's only writer; all five legacy-writer exceptions removed, each re-tested with a deliberate direct write. USER call shipped: launchers destroyed during launch attrition stay destroyed — two source-specific cumulative totals, `destroyed`/`quantity` are clamped projections of them, and attempting to fire consumes nothing. Measured over 12 common seeds (scenario_default, selfplay_default): Green shots −5.4/campaign and never up, Red losses unmoved, **no pin moved, no rebalance** (`docs/reports/2026-07-27-antiship-permanent-launch-destruction.md`). `expended` deleted, `suppressed`→`suppressed_now` (a count, because firing falls in proportion to it). `Theaters` deleted to PAY for the FiresPhases dependency instead of raising its ceiling. Both 0042-deferred validator cleanups landed (typed `Finding`; `Verdict` split out of `Ownership`). Role directories `scripts/{phases,builders,calc}/`; `AntishipResolver` deliberately left behind as mixed. Optional validator split skipped (1054→1094 lines, all per-function budgets met). |
| 0042 | [Mutation-authority foundation](../archive/0042-mutation-authority-foundation.md)            | **High — establishes the controller/API rule and staged enforcement gate**                                                                                                                                                                      | **Complete 2026-07-26** — `tools/validate_mutation_authority.gd` + `tools/mutation_authority_manifest.json` + self-proving fixtures; anti-ship registered in migration mode (5 named legacy writers); no production script moved |
| 0044 | [Force mutation authority](../archive/0044-force-mutation-authority.md)                                 | **High — brigades, battalions, manifests, placement; replaces 0039**                                                                                                                                                                            | **✅ Shipped 2026-07-29** — `ForceTransitions` is the sole writer for the `force` aggregate. All legacy writers eliminated.                                                                                   |
| 0045 | [Sealift/fleet mutation authority](../archive/0045-sealift-fleet-mutation-authority.md)       | High — hull/cohort/pipeline conservation and one writer                                                                                                                                                                                               | **✅ Shipped 2026-07-29** — `SealiftTransitions` is the sole writer of the `ShipState` fleet projection, cohort hulls/legs, the return-reload pipeline and escort magazines; hull losses and the reprojection that keeps the conservation equation true are one checked call. A cohort became a typed `SealiftCohort` split by field between `force` (`bn_ids`) and `sealift_fleet` (`hulls_by_type`, `cohort_state`) — as a dictionary neither half was gate-enforceable. `sent_original` deleted (vacuous invariant, no consumer); `ship_category` now planned as a map and applied by the force authority instead of stamped into force-owned rows by the planner. Zero legacy writers, no behavior/RNG/golden change. Review round also moved the `ship_category` stamp out of the planner (it was writing force-owned reserve rows) and relocated the now write-free `SealiftResolver` to `scripts/calc/`. |
| 0046 | [IJFS mutation authority](0046-ijfs-mutation-authority.md)                                   | High — targets, munitions, squadrons, typed stocks and writeback                                                                                                                                                                                      | Sketch                                                                                                                                                                                                                                      |
| 0047 | [Map/infrastructure mutation authority](0047-map-infrastructure-mutation-authority.md)       | High — ownership, FEBA, seizure, repair and JLSF lifecycle                                                                                                                                                                                            | Sketch                                                                                                                                                                                                                                      |
| 0048 | [Reinforcement-state mutation authority](0048-reinforcement-state-mutation-authority.md)     | High — mobilization and air-insertion capacity/history                                                                                                                                                                                                | Sketch                                                                                                                                                                                                                                      |
| 0049 | [Accounting/turn mutation authority](0049-accounting-turn-mutation-authority.md)             | High — supply, orders, latches, phase and result application                                                                                                                                                                                          | Sketch                                                                                                                                                                                                                                      |
| 0050 | [Mutation-authority campaign closeout](0050-mutation-authority-enforcement-closeout.md)      | High — independent audit, hard enforcement, deterministic closeout                                                                                                                                                                                    | Sketch                                                                                                                                                                                                                                      |
| 0051 | [Destroyed coastal launchers get a last salvo away](0051-destroyed-systems-still-fire.md) | Medium (balance; a ported TIV mechanic that has never once fired — needs a USER dial + a crossing-calibration re-run) | Sketch |
| 0052 | [Legibility sweep: unenforced budget, dead seams, half-finished role layout](../archive/0052-legibility-and-dead-seams.md) | Medium (hygiene; documented parameter budget now enforced; dead seams removed; role directories completed) | **Complete 2026-07-27** — `gd_metrics.py --check-ceiling` counts wrapped signatures and enforces per-function parameter ceilings; `HexGrid` and test-only GameState/FiresPhases façades deleted; `launch_attrition` dead return dropped; calculators/loaders moved into role directories; `AntishipResolver.resolve` now takes a typed context. |
| 0036 | [Airborne cost and sortie cadence](0036-airborne-cost-and-cadence.md)                        | Medium (balance; USER call 2026-07-25 answering the plan-0032 dial — double baseline attrition + 1 sortie per 2 days;`red_airborne` only, golden untouched, `validate_air_insertion` pin re-baselines)                                            | Sketch                                                                                                                                                                                                                                      |
| 0053 | [Documentation hierarchy refactor (hub-and-spoke)](../archive/0053-doc-hierarchy-refactor.md) | Medium (developer experience; ~85% orientation token reduction) | **✅ Shipped 2026-07-29** — Monolithic STATUS.md and RETROSPECTIVES.md fragmented into per-module STATUS.md and RETRO.md files in `docs/systems/<module>/`. Global STATUS.md trimmed to cross-cutting hub. Research harness silo created. |

| 0016 | [Separate State Data from Autoload](0016-separate-state-data.md) | Medium (hygiene/architecture) | Superseded by 0014 |
| 0022 | [Red reactive beach-opening (feasibility first)](0022-red-beach-switching.md) | Medium (research; new mechanic, gated on a feasibility spike) | Sketch |

## Mutation-authority campaign — required sequence

**Implementation readiness:** the architecture and sequencing review is complete and USER-ratified.
**0042 shipped 2026-07-26** — the enforceability question is answered (receiver-TYPE resolution, not
field names; see the validator header) and the manifest format is fixed. The next implementation work
starts at plan 0043. Later plans must not start early.

**USER direction:** every gameplay-relevant mutable aggregate gets one controller/API; calculators
return outcomes, only the authority applies them, and cross-aggregate transitions prove exact deltas.
This is a uniform mutation discipline, **not** one universal state representation or God controller.
No new autoloads; `GameStateData` stays data-only; `TurnConductor` keeps phase order.

The campaign is intentionally serial. Each plan establishes APIs the next plan consumes, and every
step touches deterministic turn-path state. Only one migration family lands per commit, with the full
gate green before the next begins.

1. **0042 — foundation and enforceability gate; no production moves.** Inventory write forms across
   all script trees, prove the source gate can detect direct, nested, alias, setter/model-mutator, and
   container mutations, establish `tools/mutation_authority_manifest.json`, and register anti-ship in
   migration mode. Authority permission is exact-file, never directory-wide. **Stop the campaign** if
   enforcement would be a regex that misses aliases while claiming completeness; choose a proven
   narrower mechanism first. Keep suffix/exact-manifest orientation in the current layout through this
   plan.
2. **0043 — anti-ship pilot, permanent destruction, then role-layout checkpoint.** First complete
   vertical slice. Separate launch calculation from state application; keep IJFS and launch
   destruction permanently, keep suppression transient, remove contradictory writers, then measure
   the deliberate outcome change. Review the shipped API/manifest/snapshot/receipt pattern before
   copying it. Only after that review, make separate byte-stable mechanical commits for clear phase,
   builder, and proven-pure anti-ship calculator moves; mixed files stay put until their owning plan.
3. **0044 — force authority.** Brigades, battalion roster counts, manifests, map placement and exact
   casualty/transfer deltas. This supersedes 0039: a ledger derived from already-drifted inputs cannot
   detect the ghost-landing bug. Keep counts and serialized BN ids; instances remain deferred.
4. **0045 — sealift/fleet authority.** Hull buckets, cohorts, return pipeline and escort ammunition;
   reconcile exact BN ids with the force authority. Eliminate temporarily invalid fleet state between
   loss booking and projection.
5. **0046 — IJFS authority.** Persistent targets, munition inventory, squadrons, typed MANPADS stock,
   carry-over and cumulative writeback. Preserve every conditional RNG draw.
6. **0047 — map/infrastructure authorities.** FEBA, sticky ownership, seizure, repair and JLSF node
   lifecycle. Preserve current zero-ashore territorial-control behavior and phase timing.
7. **0048 — reinforcement-state authorities.** Mobilization pending/released state and air-insertion
   capacity/history, coordinated with force and IJFS authorities.
8. **0049 — accounting and turn lifecycle.** Supply balance/history, order buffers, legal phase/turn
   transitions, victory latches and result application. It invokes domain reset APIs rather than
   editing their fields.
9. **0050 — hard enforcement and closeout.** Independent source/runtime/contract sweep, remove all
   legacy-writer allowances, run multi-scenario deterministic games, obtain two read-only external
   reviews, update canonical docs, and archive the campaign.

### Interaction with existing plans

- **0039 is superseded by 0044.** Do not implement its derived-ledger step.
- **0033 brigade organization** should wait for 0044 or add no new Brigade writer.
- **0002 per-hull escort magazines** is UNBLOCKED: 0043 and 0045 both shipped, so the aggregate per-type magazine now has one named writer (`SealiftTransitions`) to grow per-hull granularity behind.
- **0031 graduated port suppression** should wait for 0047 unless the USER explicitly prioritizes
  the mechanic first; otherwise both plans would redesign the same node transitions.
- **0036 airborne balance** may proceed as data/balance work, but any new air-state mutation waits for
  0048.
- **0041 autoload access** remains independent low-priority filler; it does not substitute for this
  campaign's mutation enforcement.
- Plans 0030 and other observability-only work may proceed if they do not add protected state writers.

### Serial-agent execution protocol

The campaign is designed for a succession of cold-start agents. Each agent:

1. reads `AGENTS.md`, `docs/STATUS.md`, this sequence, the active plan, and the canonical skills named
   by AGENTS for that task;
2. verifies every preceding campaign step is shipped/green before taking the next one—no parallel
   aggregate migrations and no coding from a later plan against provisional APIs;
3. implements one numbered migration family or one mechanical destination-directory move per commit;
4. updates `tools/mutation_authority_manifest.json` in the same commit as the writer it adds/removes;
5. before adding an authority dependency to a ceilinged file, records the dependency removed in the
   same commit; if no one-for-one swap exists, lands a prior green application-coordinator extraction
   instead—never raises the ceiling to fit;
6. preserves RNG order, JSON records, class names during path-only moves, and each script's `.gd.uid`;
7. re-imports after class/path changes, runs focused tests twice where required, then judges the full
   gate by marker lines; and
8. leaves the active plan checklist/progress and canonical closeout homes current before handoff.

Stop and surface to the USER rather than improvising when alias detection is incomplete, a
cross-authority operation can fail after its first write, a dependency ceiling would need to rise, a
path-only commit moves a fixture/golden, or a new behavior/storage decision appears. Builders are
exact construction exceptions for fresh unpublished objects, not alternate runtime authorities.

**Change-control rule:** 0042, role-directory moves, and authority-only migration commits are
byte-stable refactors. Plan 0043 contains one separately committed, USER-approved behavior change and
may deliberately move only reachable anti-ship outcomes/fixtures. No later plan may rebaseline to make
an architectural migration pass. Mutable `GameData` storage consolidation is not a campaign end-state;
it requires a separate measured, USER-ratified plan if authority work proves it necessary.

**Standing research caveats:** studies before the landed-only/census corrections over-state Red, and
studies before 0043 will also reflect resurrecting launch-attrition losses. Records remain identified
by commit/version; do not combine pre/post populations without naming the behavior boundary.

## Archived

See [ARCHIVE.md](ARCHIVE.md) for the list of completed and superseded plans, as well as parked refinements.

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
