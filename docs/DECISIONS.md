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

- **2026-07-30 — Map and infrastructure mutation authorities shipped; an invariant enforced by
  ABSENCE (agent, plan 0047).** `MapTransitions` is the sole writer of `HexState.hex_owner`/`feba_km`
  and the `hex_states` container; `InfrastructureTransitions` is the sole writer of the port/airbridge
  lifecycle, the `nodes` container and the `infrastructure_state` handle. The map aggregate ships with
  **zero allowances** and deliberately has **no owner setter**: ownership is derived by
  `HexOwnershipCalculator` and applied by iterating only the occupied hexes, so the sticky rule that
  keeps a seized port seized after Red moves inland can no longer be defaulted away — it was a missing
  `else` branch before. `GameData.set_hex_owner`/`set_hex_feba` and both `HexMap` stubs were deleted
  rather than migrated; the one caller that wanted them (`tools/validate_headless_infrastructure.gd`)
  now places a real brigade and recomputes. `InfrastructureResolver.tick` became the pure `plan_tick`,
  whose plan carries an ORDERED event list because one node can legitimately emit `seized` and
  `degraded` in the same tick. No behaviour, RNG or golden change; three full dependency ceilings held
  by façades and a one-for-one swap. Facts: `docs/systems/hex-grid/hex-grid.md` §8,
  `docs/systems/amphibious-offload/amphibious-offload.md` §9–10,
  `docs/systems/mutation-authority/mutation-authority.md` §5–6, `tools/mutation_authority_manifest.json`,
  the two authority headers.

- **2026-07-30 — IJFS mutation authority shipped; an authority that applies INSIDE its stages
  (agent, plan 0046).** `IjfsTransitions` is the sole writer of `IjfsTarget` / `IjfsMunition` /
  `IjfsSquadron`, the three `IjfsDailyState` containers that persist across days, and the
  `ijfs_state` / `_ijfs_day` handles. Unlike the first three aggregates it is called from within the
  pipeline stages rather than once from a coordinator, because IJFS consumes dice conditionally on
  state an earlier stage just wrote and later stages select targets by reading it — deferring
  application would change the draw count. That forced a new directory claim for `scripts/ijfs/`
  rather than widening `scripts/calc/`'s "writes nothing" claim to accommodate one subsystem.
  MANPADS stock moved from a free-form `metadata` key to a typed field first, with the key kept as a
  serialization mirror because `metadata` is aliased live into the ledger rows. Also folded in the
  `IjfsEngine._run_strike_phase` parameter-ceiling paydown (11 params, plus two more functions), which
  the BACKLOG flagged as colliding with this plan. Facts: `docs/systems/ijfs/ijfs.md` §9,
  `docs/STATUS.md` (aggregate list + directory table), `tools/mutation_authority_manifest.json`,
  `scripts/transitions/IjfsTransitions.gd` header.

- **2026-07-30 — Reviewer tiers, one canonical home, and a fan-out launcher (USER call + agent, plan 0054).**
  The USER set a reviewer hierarchy — tier 1 GPT-5.6 Sol (peer), tier 2 the agy wrappers and DeepSeek V4
  Flash, tier 3 MiniMax M3 and Nemotron Ultra (bonus roles only, never quorum) — and made a round a fixed
  fan-out of three with a **2-of-3 quorum binding the IMPLEMENTATION of a numbered plan**, not plan
  documents or smaller work; two rounds per unit of work, with review-tooling findings going to BACKLOG
  rather than re-opening a round. Reviewer facts had spread over eight homes and diverged badly enough
  that both review skills listed a two-model roster with no tier-1 reviewer in it. `.claude/REVIEWERS.md`
  is now canonical, `tools/review_fanout.sh` is its executable copy, and `tools/validate_reviewer_facts.gd`
  fails the gate on any invocation or model id outside the roster and on any drift between the roster's
  round and the launcher's manifest. Facts: `.claude/REVIEWERS.md`, `hexcombat-failure-archaeology`
  ("frozen artifact that was a token-compacted summary"), the two tools' headers.

- **2026-07-29 — Sealift/fleet mutation authority shipped, and one object now belongs to two aggregates
  (agent, plan 0045).** `SealiftTransitions` is the sole writer of the `ShipState` fleet projection, the
  cohort hull counts and legs, the return/reload pipeline, and the escort SAM magazines; hull losses and
  the reprojection that keeps the conservation equation true happen in ONE checked call instead of being
  booked in `FiresPhases` and repaired in `ReinforcementPhases`. A sealift cohort binds troops to hulls,
  so it became a typed `SealiftCohort` split by field between `force` (`bn_ids`) and `sealift_fleet`
  (`hulls_by_type`, `cohort_state`) — as a dictionary neither half was enforceable. `ShipState.sent_original`
  was deleted (assigned `= surviving_sent` every turn, invariant vacuous, no consumer). No behavior, RNG
  or golden change. Facts: `docs/STATUS.md`, `docs/systems/amphibious-offload/amphibious-offload.md` §10,
  `docs/systems/antiship-mine/antiship-mine.md` §10, `tools/mutation_authority_manifest.json`.

- **2026-07-29 — Documentation hierarchy refactor (hub-and-spoke) shipped (USER call, plan 0053).**
  Monolithic `docs/STATUS.md` and `docs/RETROSPECTIVES.md` fragmented into module-specific `STATUS.md` and `RETRO.md` files under `docs/systems/<module>/`, reducing agent orientation tokens by ~85%. `docs/STATUS.md` trimmed to executive summary hub for cross-cutting engine/turn-model/gate facts. Dedicated `docs/systems/research-harness/` directory created for batch runner and sweep tools. Facts: `docs/STATUS.md`, `docs/systems/<module>/STATUS.md`, `AGENTS.md`.

- **2026-07-29 — Force mutation authority campaign completed (plan 0044).**
  The `force` aggregate migration is complete. `ForceTransitions` is the sole sanctioned mutation authority for brigade placement, battalion roster counts, casualties, transfers, and transport manifests. The facade `RosterMutations` has been eliminated and `GameData` indexes are consistently protected. Facts: `docs/STATUS.md`, `docs/systems/*.md` state & authority sections, `tools/mutation_authority_manifest.json`.

- **2026-07-27 — Force mutations get their first enforced authority slice (agent, plan 0044).**
  `ForceTransitions` now applies protected Brigade runtime-field writes and `Battalion.qty` roster
  decrements through typed requests/receipts; production placement, activity, ground/IJFS/crossing/air
  casualty seams route through it with no golden pin movement. The transport dictionary-storage and
  `brigades_by_hex` source-gate closeout remain in the in-progress plan. Facts: `docs/STATUS.md`,
  `docs/systems/turn-engine.md`, `tools/mutation_authority_manifest.json`.

- **2026-07-27 — Anti-ship crossing uses a typed context (agent, 0052 follow-up).**
  `AntishipCrossing.resolve_crossing_damage` now takes `AntishipCrossingContext` plus explicit
  `Dice`; its launch helper reads the same context instead of carrying a 9-parameter signature.
  The two anti-ship crossing grandfather entries were removed from `PARAM_CEILINGS`; no gameplay or
  RNG order changed. Facts: `scripts/model/AntishipCrossingContext.gd`,
  `docs/systems/antiship-mine.md`, `docs/plans/BACKLOG.md`.

- **2026-07-27 — Post-0052 quick hygiene follow-up (agent).** `gd_metrics.py` gained a fixture
  validator in the gate, and the remaining test/tool-only private `GameState` façades were retired in
  favor of direct calls to `FiresPhases`, `TurnClosure`, and `TurnConductor`. Follow-up planning was
  filed into 0044/0045 plus `BACKLOG.md`; no gameplay behavior changed. Evidence: full gate.

- **2026-07-27 — Legibility sweep made the parameter budget enforceable (agent, plan 0052).**
  `tools/gd_metrics.py --check-ceiling` now counts wrapped signatures and gates per-function
  parameter ceilings; `AntishipResolver.resolve` pays down its breach with a typed context. Dead
  `HexGrid`, `launch_attrition`, and test-only GameState/FiresPhases façades were removed, and the
  role layout now includes `scripts/calc/` and `scripts/loaders/`. Facts: `docs/STATUS.md`,
  `.claude/skills/hexcombat-code-quality/SKILL.md`, affected `docs/systems/*`.

- **2026-07-27 — Launchers destroyed during launch attrition stay destroyed (USER call, plan 0043).**
  They used to come back on the next crossing: the firing plan rebuilt `quantity` from
  `original_quantity` minus cumulative IJFS kills alone, overwriting the launch losses. The
  establishment now keeps the two loss sources as separate cumulative totals and derives `destroyed` /
  `quantity` from both, clamping their sum (the IJFS bombs containers, launch attrition kills deployed
  launchers — two projections of one arsenal, so the sum may double-count and must not be asserted).
  Attempting to fire no longer consumes a launcher. Measured over 12 common seeds: Green shots fall
  (mean −5.4/campaign, never rise), Red losses do not move materially, no pin moved — no rebalance.
  Facts: `docs/STATUS.md` (D3), `docs/systems/antiship-mine.md` §10,
  `docs/reports/2026-07-27-antiship-permanent-launch-destruction.md`.

- **2026-07-27 — The anti-ship establishment is the first ENFORCED mutation aggregate (agent, plan
  0043).** `scripts/transitions/AntishipTransitions.gd` is its only writer; the calculator went pure
  and returns typed `AntishipLaunchOutcome` receipts. All five legacy-writer exceptions were removed
  and each former writer re-tested with a deliberate direct write. `FiresPhases` held its dependency
  ceiling by a one-for-one swap rather than a bump: `Theaters` was deleted (its last caller was
  re-deriving a map `GameData` already held). Facts: `tools/mutation_authority_manifest.json`, header
  of `scripts/transitions/AntishipTransitions.gd`, `docs/systems/antiship-mine.md` §10.

- **2026-07-26 — Correction to the entry below (agent).** That entry says `GameData` reuses `entry`
  for four types; it is **two** — `Dictionary` (`GameData.load_scenario`) and `InfrastructureDef`
  (`GameData.load_infrastructure`). The conclusion is unchanged: a file-global type map called both
  ambiguous and reported a write it should have cleared, which is why resolution is per-function.
  Corrected in the header of `tools/validate_mutation_authority.gd`.

- **2026-07-26 — Mutation authority is enforced by receiver-TYPE resolution, not field names (agent
  judgment, plan 0042 step 2).** A name-only scan was not viable: `destroyed` belongs to
  `AntishipSystem`, `IjfsTarget`, `ShipState` and `Brigade`, so it flags four aggregates at once. The
  gate resolves each write's receiver type first (spike: 591 receiver-chain assignments in `scripts/`,
  19 unannotated), scoped per function because `GameData` reuses `entry` for four types. Untypable
  receivers writing a protected field name fail loudly rather than passing unseen. Facts:
  `tools/mutation_authority_manifest.json`, header of `tools/validate_mutation_authority.gd`, current
  state in `docs/STATUS.md`, convention in `hexcombat-architecture-contract`.

- **2026-07-26 — Mutation enforcement is proved before the role-directory split (USER).** Plan 0042
  keeps production paths stable while an exact-file, alias-aware gate and
  `tools/mutation_authority_manifest.json` are established; the anti-ship pilot in 0043 proves the
  pattern before separate mechanical role moves. Directory placement never grants write authority,
  and mutable `GameData` consolidation remains an optional later decision. Execution: plans 0042–0050
  and `docs/plans/README.md` → “Mutation-authority campaign”.

- **2026-07-26 — Every mutable gameplay aggregate will have one enforced mutation authority;
  anti-ship launch destruction will persist (USER).** Calculators/resolvers compute outcomes, domain
  `*Transitions` APIs alone apply protected state, and cross-aggregate operations prove exact deltas;
  this is shared mutation discipline, not one God controller/universal state shape. Sequence:
  `docs/plans/README.md` → “Mutation-authority campaign”, plans 0042–0050; current behavior is unchanged until shipment.

- **2026-07-26 — Skills are now gated against dead `.gd` citations; the fixture-drift references they
  carried are corrected (agent judgment, from a refactor review the USER asked for).**
  - **What**: `tools/validate_skill_references.gd` fails when a skill cites a fully concrete
    `` `tools/…gd` `` path that does not exist. Four skills named `tools/validate_fixtures.gd`, deleted
    some time ago — fixture drift is now the gate's regenerate-then-`git diff --exit-code docs/examples/`
    phase. One was a `hexcombat-debugging-playbook` triage row keyed on that validator going red, i.e. an
    instruction to debug a state that can no longer occur. All four corrected; the orphan
    `tools/validate_fixtures.gd.uid` deleted.
  - **Why gate skills at all**: a skill is the first thing an agent reads and is read as instruction, not
    description. `validate_doc_anchors.gd` guards `docs/systems` only, so nothing watched them.
  - **Deliberately narrow, because a reviewer was right that this could be a trap**: skills legitimately
    write `validate_<thing>.gd`, `validate_*.gd`, `<Phase>Resolver.gd`. Tokens carrying a glob or a
    placeholder are skipped, and `(historical)` exempts a line. Measured before writing it: over the whole
    skill tree the rule produced exactly one hit — the real one — and no false positives.
  - **Gate**: ALL PHASES GREEN, no pin moved. Four mutations proved it: a reintroduced dead citation
    fails, placeholders and globs do not, `(historical)` suppresses, and a broken scan root fails loudly
    rather than passing vacuously.
  - **Pointers**: `.claude/skills/hexcombat-validation-and-qa` §Fixtures; remaining gap (`docs/*.md` and
    `docs/plans/*.md` are still ungated) in `docs/plans/BACKLOG.md`.

- **2026-07-26 — The combat-knob correspondence is gated; plan 0040 lands option (c) only (agent
  judgment, on the USER's own sequencing note).**
  - **Who**: agent, following the execution order in `docs/plans/README.md` for the risk-buydown group.
  - **What**: `tools/validate_combat_rules_threading.gd` — a pure static-analysis validator, **no
    production code touched**. It fails if a `CombatRules` field is declared but never assigned in
    `TurnConductor.resolve_combat_at`, is assigned but not declared, is assigned twice, is fed from a
    differently-named `GameData` property (or one that no longer exists there), is computed locally
    without being a documented exception, is written anywhere else, or is never read. The reader set and
    the local variable name are **derived from the source**, not hand-listed, and check 0 fails if its
    own anchors stop resolving — so a file move like plan 0038's cannot turn it into a vacuous PASS.
  - **Why (c) and not (a)**: the risk was the silent no-op knob, not the verbosity, and the verbosity is
    at least honest and greppable. Option (a) touches the combat path for no behavioural gain, so it
    stays **deferred indefinitely** per `docs/plans/README.md` — revisit only when a knob is actually
    added and the hand-threading is felt. Option (b) remains blocked by the tool-purity rule.
  - **Gate**: ALL PHASES GREEN, no pin moved (nothing in `scripts/` changed). Ten deliberate mutations
    were applied to the real tree and reverted to prove the validator goes red for each failure it
    claims to catch, and stays green when the local variable is merely renamed.
  - **Pointers**: `docs/systems/ground-combat.md` §"The combat-knob correspondence", `docs/STATUS.md`
    (gate anti-silence properties), `docs/archive/0040-combatrules-threading.md` (closeout, incl. the
    reviewer findings accepted and rejected).

- **2026-07-25 — TurnConductor phase extraction COMPLETE, step 3 (plan 0038; agent judgment).**
  Supply + cleanup — the end-of-turn accounting pair — moved to `TurnClosure`, finishing the plan:
  `TurnConductor` is now the turn's ORDER plus the phases whose application interleaves with it
  (movement, ground combat, FEBA retreats), at **ndeps 20 of a former 38** and 347 of a former 957
  loc. `GameState.gd` held at 28 (`_brigade_ids` routed through `TurnConductor`, the combat owner).
  Pure move, no pin moved, gate green. **Deliberately left:** the front-line phase, which is not in
  the turn pipeline at all — both diff reviewers flagged it, and it is now a BACKLOG item rather than
  scope creep. Facts: `docs/archive/0038-turnconductor-phase-extraction.md` (closeout),
  `docs/systems/turn-engine.md` §2/§4, module headers.

- **2026-07-25 — TurnConductor phase extraction, step 2 (plan 0038; agent judgment).** The fires
  phases — IJFS and the Green anti-ship/mine defence of the crossing, which share the anti-ship
  firing systems — moved to `FiresPhases`, together with the crossing's output application
  (`apply_crossing_hull_losses`, `register_ship_losses`). `TurnConductor` 28 → 22 and `GameState.gd`
  29 → **28**, both ceilings lowered: the façade's two IJFS/anti-ship test surfaces
  (`_build_warmup_context`, `_mine_ship_meta`) now route through `FiresPhases`, trading two resolver
  deps for one module dep. Pure move — every moved body verified byte-identical, no pin moved, gate
  green. Facts: `docs/systems/turn-engine.md` §2/§4, `ijfs.md`, `antiship-mine.md`, module headers.

- **2026-07-25 — TurnConductor phase extraction, step 1 (plan 0038; agent judgment).** The four
  arrival phases (sealift, amphibious offload, ROC mobilization, air insertion) moved to
  `ReinforcementPhases`; `TurnConductor.resolve_turn` keeps the whole ordered call list, so modules
  own how a phase resolves and never when it runs. `ndeps` 38 → 28 with the ceiling **lowered** to 28
  in the same commit (`tools/gd_metrics.py`); `GameState.gd` held at 29 of 29 because
  `ship_reserve_priority_order` moved with the offload group, swapping one dep for another.
  **Deviation from the plan:** `RosterMutations` (`apply_casualty` + `apply_crossing_casualties` +
  the pool/roster tripwire) was not optional — combat and air insertion both call `apply_casualty`,
  so leaving it in `TurnConductor` would have made the two modules a reference cycle; the plan had
  filed it as a separate cohesion-only change that buys no headroom (still true: it costs +1).
  Pure move — every moved body verified byte-identical, no pin moved, gate green.
  Facts: `docs/systems/turn-engine.md` §2/§4, `docs/STATUS.md`, module headers.

- **2026-07-25 — Gate hardening: the two silent-failure holes this session fell into are now gated.**
  - **Who**: agent, from a refactor review the USER asked to be run past `agy-explore` and `opencode`.
  - **What**: (1) `tools/validate_tool_script_purity.gd` replaces `validate_llm_api_purity.gd` — the
    guarded set is now the **transitive compile-time closure of `tools/*.gd`** — by `class_name` or by
    literal `preload` path — not one hand-picked file; `SelfPlayRunner` was outside the old gate and broke exactly there. (2)
    `run_all_tests.py` passes `--quit-after` to every validator, so a dependency that fails to compile
    degrades from an unbounded hang to a named failure (verified: plain run hangs, `--quit-after`
    exits). (3) A validator that exits 0 while printing **no PASS marker** is now a failure, not an OK.
    (4) New `tools/validate_pool_enumeration.gd` walks live state for anything shaped like an off-map
    battalion pool and fails if `pending_battalion_pools()` does not return it — a **structural** check,
    so it finds a pool nobody registered. Verified against the real 0034 bug.
  - **Also**: `CombatForces.maneuver_units`/`support_units` were byte-identical but for one `not`;
    both are now views on `split_units`. `GameData.snapshot_state`'s `pending_pools` default was
    removed (defaulting to `[]` silently returned whole rosters — the 0034/0037 bug).
  - **Gate**: ALL PHASES GREEN, **no pin moved** — the combat refactor is byte-stable.
  - **Pointers**: `docs/archive/0038-turnconductor-phase-extraction.md` (the ceiling problem this review
    surfaced and did NOT fix); `hexcombat-failure-archaeology` → "The gate 'hang' that was two separate
    illusions"; `docs/plans/BACKLOG.md` for three items deliberately deferred.
  - **Rejected on measurement**: extracting `TurnConductor`'s roster-mutation trio to buy ceiling
    headroom — it references only deps the file keeps, so it buys none. Recorded in plan 0038 so it is
    not re-proposed.

- **2026-07-25 — Only battalions that have LANDED fight, eat, and are reported.**
  - **Who**: USER, twice — *"only the battalions that have landed in a brigade should count for
    combat. The LLMs should only account for those too"*, and separately *"yes — only landed eat"*
    for supply. This deliberately diverges from the TIV port, which counts whole compositions.
  - **What**: `Brigade.landed_qty` is now the single home of the rule (`composition.qty` minus the
    off-map pool count for that type, clamped at 0). `CombatForces`, `TurnConductor.active_red_
    battalion_units`, `LLMGameAPI._brigade_observations` and `GameData.snapshot_state` all read
    through it. A brigade with **nothing** ashore is no longer a combat contributor at all —
    `CombatCalculator` floors a zero-strength side to `combat_min_effective_strength`, so leaving it
    in would have let a formation with nobody on the island inflict real casualties.
  - **Gate**: ALL PHASES GREEN after a **deliberate re-baseline** of two pins (change-control:
    ported combat math changed on USER instruction). `validate_dos_consumption` 36 → 16 units
    (2800 → 1600 t idle, 5600 → 3200 t moved); `validate_cleanup` `casualties=5, feba=-0.72` →
    `casualties=3, feba=-2.66`. Direction is the expected one — Red is the side with pools, so Red
    fights weaker early. `validate_golden_victory`, `validate_headless_turn` and
    `validate_air_insertion` did **not** move (their scenarios land whole formations).
  - **Pointers**: `docs/systems/ground-combat.md` → DIVERGENCE 5; `docs/systems/air-insertion.md` §9
    (the "consumes full DOS" note was reversed); `docs/archive/0037-landed-battalions-only.md`;
    `tests/landed_battalions_test.gd`.
  - **Open**: this compounds the 0034 census correction and bites harder — it changes the fighting,
    not just the counting. Every study measured before today over-states Red. Re-running them is
    still a USER call.

- **2026-07-25 — One home for "battalions not ashore"; it uncovered a live census over-count.**
  - **Who**: agent (plan 0034, a refactor the USER queued). The bug was not the plan's premise — the
    plan called the missing-pool failure hypothetical; a probe found it happening.
  - **What**: `GameStateData.pending_battalion_pools()` is now the sole enumeration of the three
    off-map pools and `CleanupResolver.census` takes that list (`PendingBattalions.by_brigade` sums
    it; `.instances` de-dupes the two manifest builders, both id conventions kept verbatim).
    `SealiftState.mainland_pool` was never subtracted, and `SealiftResolver._embark_followon` drains
    entries **partially**, so a brigade ashore with battalions still awaiting a hull had those
    battalions counted as on Taiwan — always in Red's favour. Measured on `scenario_default`
    (seed 20260624, `selfplay_default` both seats): Red's turn-20 census 57 → **49**, Green unchanged.
  - **Gate**: ALL PHASES GREEN with **no pin moved** — no validator was watching this, which is the
    real finding. `scenario_golden` has no follow-on pool, so the golden was never exposed.
  - **Pointers**: `docs/systems/frontline-cleanup-victory.md` → "Not-ashore pools";
    `docs/archive/0034-pending-battalion-pools.md`; `tests/victory_present_census_test.gd`.
  - **Open**: published studies built on the `scenario_default` census (the 100%-Red Monte Carlo
    distribution, plan 0029's 83.3%, plan 0032's 97%) were all measured with the inflated count. The
    correction weakens Red. Re-running them is a USER call on compute, not a technical one.

- **2026-07-24 — Red gets an air path onto Taiwan, and the PLAAF Airborne Corps gets built to fly it.**
  - **Who**: USER (force structure + attrition model, plan 0032), after the agent found the plan's
    premise was false: the OOB had 945 PLA battalions and **zero** airborne. USER supplied the corps'
    real composition and split it 3 light airborne / 2 mechanized airborne / 1 air assault, leaving
    brigade numbering to the agent (130th takes air assault on the 2024 Taiwan pub; which two are
    mechanized is a modelling choice, flagged as unsourced).
  - **What**: 6 brigades / 50 BNs appended to the OOB, flown onto any passable hex under a per-turn
    cap per lift class. USER calls: attrition keyed on Taiwan's air defence (intact = 75% of the
    packet, ~15% typical after the 3-day warmup — which the linear `0.75 × effective_ad_health`
    reproduces without a fudge, since measured post-warmup AD health is 0.244); MANPADS hits the
    rotary-wing lift on top; cap loss is **permanent**; dropped BNs are **out of supply** until
    connected to the beach; drops are a real order in the contract, not a scenario script. Absent
    scenario block ⇒ inert ⇒ golden byte-stable.
  - **Pointers**: `docs/systems/air-insertion.md`; `docs/archive/0032-airborne-insertion.md`; knobs in
    `data/knobs/registry.json` group `air_insertion` (registry version 1 → 2).
  - **Measured** (30 seeds/cell): against the plan-0029 mobilizing defender that had held Red to
    83%, the air path restores Red to 97% and halves median decision (21 → 11 turns). Lift quantity
    saturates — 3 BN/turn ≈ 14 BN/turn. The permanent-airframe brake barely engages because the IJFS
    warmup clears the sky before Red wants to drop.
    `docs/reports/2026-07-24-airborne-insertion-sweep.md`.

- **2026-07-24 — ROC gets a mobilization phase-in: model (b), phase in EXISTING brigades; no Green win arm.**
  - **Who**: USER (force-structure call, plan 0029 Tier A2), asked with three models on the table
    (new reserve OOB brigades / hold existing brigades back / battalion regeneration rate).
  - **What**: a scenario may hold eligible Green brigades (default: the OOB's 12 `reserve` infantry
    brigades, 36 of 124 BNs) off-map and release them on a schedule. Nothing is invented — the lever
    is exposure timing, since off-map battalions are outside the census and outside IJFS targeting.
    Victory stays PLA-decisive-or-nothing (USER: deny-only); a successful defense reads as "no
    decision in the horizon" plus the census curve. Default `held_back_brigades: 0` ⇒ golden
    byte-stable.
  - **Pointers**: `docs/systems/roc-mobilization.md`; `docs/plans/0029-dynamic-roc-defense.md`
    (Tier A2); knobs in `data/knobs/registry.json` group `mobilization`.
  - **Measured** (30 seeds/cell): holding 0/4/8/12 reserve brigades back → Red win rate
    100%/93.3%/90.0%/83.3%. First defender-side lever to move it off 100%, but it does not flip the
    median game (finite reserve vs bottomless follow-on pool).
    `docs/reports/2026-07-24-roc-mobilization-sweep.md`.

- **2026-07-24 — validate_cleanup's golden pin was corrected: it had been re-baselined in the wrong scenario.**
  - **Who**: Agent (Opus 5), found by the plan-0029 gate run.
  - **What**: the same-day `bff4a1c` re-baseline (crossing-drowning roster fix) measured the
    fingerprint with NO scenario selected (⇒ `scenario_default`), but `run_all_tests` exports
    `HEXCOMBAT_SCENARIO=scenario_golden`, so the pin never matched the gate and `validate_cleanup`
    was red on `main`. Re-measured under the gate's scenario: `casualties=5, feba=-0.72`. No
    behaviour change — the drowning fix ships exactly as before; only the pin's measurement
    environment is corrected. Same trap already recorded for `validate_golden_victory`.
  - **Pointers**: `tools/validate_cleanup.gd` (comment block above `EXPECTED_COMBAT_FINGERPRINT`).

- **2026-07-24 — 2-D map of the two interdiction levers (strikes × beach throttle × port); they are substitutes.**
  - **Who**: Agent (Opus 4.8), USER request (two heatmaps).
  - **What**: `off_island_offload_heat` sweep (7×7×2, 20 seeds, 1,960 games). PLA win % shows (1) beach
    offload ≤ ~1,600 t/day is a PLA shutout regardless of strikes — the throttle is the decisive lever;
    (2) off-island strikes only bite in the high-throughput band, and denying the port (`auto_jlsf false`)
    > port-intact PLA win % there — verified as a **crowding-out** effect (JLSF logistics cargo displaces
    combat BNs in the scarce crossing/offload pipeline; +18 combat BNs on a traced flip seed, drownings
    equal), NOT sinking and NOT the census bug. The levers are substitutes. Added `mc_chart.py --heat` +
    `tools/make_heat_spec.py`.
  - **Pointers**: `docs/plans/0028-sustained-followon-interdiction.md` ("2-D map"); charts `docs/reports/assets/off_island_offload_heat.svg`
    (spec `.heat.json`).

- **2026-07-24 — Q2 re-run on the fix: "Taipei port is a no-op" overturned; port aids the defender under interdiction.**
  - **Who**: Agent (Opus 4.8), continuing the ghost-landing-bug re-baselines.
  - **What**: Re-ran `off_island_flip_noport` on the fixed engine at the fine grid `[0…64]` (old
    `[0…2048]` grid saturates post-fix). At zero interdiction the port is still a wash (both 100% PLA),
    but under active off-island interdiction, denying the port (`auto_jlsf false`) *raises* PLA win%
    in the knife-edge band (16→60% vs 30%, 24→25% vs 15%). Traced mechanism = **crowding-out**: JLSF
    logistics cargo shares the scarce attritable crossing/offload pipeline with combat BNs and doesn't
    add combat census, so the port active lands fewer combat BNs (+18 on a traced flip seed; drownings
    equal — NOT sinking, NOT the census bug). Substitute family with off-island × offload-throttle.
    Added a general `--flip` multi-series mode to `tools/mc_chart.py`.
  - **Pointers**: full curves + mechanism in `docs/plans/0028-sustained-followon-interdiction.md`
    ("Q2 re-run on the fix"); deck chart `docs/reports/assets/off_island_flip_curve.svg` (spec
    `docs/reports/assets/off_island_flip_curve.flip.json`). Deck slide 6's "structural inevitability" framing now rests on
    a bug artifact — flagged to USER for an editorial call (not rewritten).

- **2026-07-24 — Crossing-drowning roster fix: drowned BNs are now real casualties (correctness bug).**
  - **Who**: Agent (Opus 4.8), USER call to fix (found while investigating the off-island-strike flip).
  - **What**: Battalions that drown in the anti-ship crossing were removed from `ship_reserve` but
    left in `Brigade.composition`. The victory census (`CleanupResolver.census` = `get_battalion_count
    - at_sea`) therefore **ghost-landed** a partially-landed brigade's drowned BNs (they had left
    `at_sea` but not the roster), and ground combat over-counted the same brigade's strength. Fixed by
    deleting drowned BNs from their rosters at the crossing-loss application
    (`RosterMutations.apply_crossing_casualties`, mirrors ground `apply_casualty`; consumes no dice).
  - **Impact / re-baseline**: golden headless turn byte-stable (scripted fight is pre-placed, no
    crossing). Deliberate re-baselines: `validate_golden_victory` china 25→**12** (Taiwan 76 unchanged
    — Green never crosses), `validate_cleanup` `casualties=6/feba=0.34`→**`casualties=7/feba=2.24`**,
    fixture `docs/examples/llm_result_after_turn.json` regenerated (partially-landed Red brigades lose
    their drowned BNs). Facts: `docs/systems/amphibious-offload.md` → "Crossing losses are casualties";
    incident in `hexcombat-failure-archaeology`. All prior census-based research numbers (incl. plan
    0028's flip sweep) over-stated PLA strength and are being re-run.

- **2026-07-23 — Off-island fleet strikes (sustained interdiction) built; ROC OOB verified complete.**
  - **Who**: Agent (Opus 4.8), USER direction (verify ROC inventory incl. reservists; then focus on
    off-island strikes on the amphibious fleet).
  - **What**: Verified HexCombat's ROC OOB is byte-complete vs TIV `unit_hierarchy.json` — all 32
    brigades / 124 battalions incl. all 12 reserve infantry brigades, all placed in `scenario_default`.
    Built off-island fleet strikes: `off_island_strike.shooters[]` config + `AntishipResolver.
    _append_off_island_strikes` appends location-less (whole-strait, no-IJFS-suppression) firing rows
    every turn; registry knobs `off_island_{submarine,air}_strikes`, default 0 (golden byte-stable),
    test `tests/off_island_strike_test.gd`. It sustains the toll (late-turn drownings 1→18) and
    compresses the margin but doesn't flip alone (offload rate binds; reservoir bottomless); found it
    *antagonistic* with the offload throttle (sea losses thin the beach queue). Consistent with USER's
    "a knob needn't flip alone."
  - **Where the facts landed**: `docs/plans/0028-sustained-followon-interdiction.md` (progress + finding),
    `docs/STATUS.md` (D3 bullet), `data/knobs/registry.json`, `data/antiship/antiship_crossing_config.json`.

- **2026-07-23 — Invasion outcome is logistics-bound; found the flip lever + fixed a phantom knob.**
  - **Who**: Agent (Opus 4.8), driven by USER's "which dial flips it / isn't the follow-on
    throughput-limited" question.
  - **What**: Established the 100% PLA win is *structural* (bottomless `auto_seed_followon_pool` +
    no campaign clock), not scenario luck; 11 wave-level dials don't flip it. The plausible flip
    lever is **beach offload throughput** (`beaches[*].offload_rate`) — clean monotone crossing,
    invasion culminates below ~1,330 t/day. The PLA captures the Taipei port free (it's the assault
    beach hex) but denying its JLSF repair barely matters — the beach rate is the binding lever.
    Fixed the registry knob `offload_beach_base_rate` (was pointing at the never-loaded
    `offload_rates.json` phantom → repointed to the real `beaches[*].offload_rate`); marked
    `offload_operational_port_rate` `sweepable:false`. USER chose to pursue interdiction / bindable
    throughput / dynamic ROC defense next (no artificial clock).
  - **Where the facts landed**: report follow-up section
    `docs/reports/2026-07-23-monte-carlo-outcome-distribution.md`; `docs/STATUS.md` (MC bullet);
    deck **slide 7** "Where the Invasion Culminates"; `data/knobs/registry.json`;
    `tools/mc_chart.py --crossing`; `tools/sweeps/mc_offload_throughput.json`. Open backlog:
    `combat_{defender,attacker}_advantage_ratio` inert knobs; port-rate loadable wiring.

- **2026-07-23 — Monte Carlo outcome distribution shipped into deck slide 6.**
  - **Who**: Agent (Opus 4.8); policy/N/outcome-axis choices per the standing research-runs
    methodology (outcome axis was already defined = golden victory census, so no USER call needed).
  - **What**: Chose scripted `selfplay_default` (both seats) × 200 common seeds over LLM-small-N so
    the deck's "hundreds of seeds" claim is honest and re-runnable; outcome axis = victory census
    (`winner` + margin `census.red−census.green`). Finding: PLA wins 200/200 but by a stochastic,
    often razor-thin margin (median +6); beach-capacity and anti-ship-lethality sweeps don't flip it
    (structurally Red-favored). Dropped a second sweep chart — the honest sensitivity curve
    (crossing-loss) is counterintuitive and win rate is flat — folded it into an honest caption
    instead.
  - **Where the facts landed**: `docs/STATUS.md` (research-runs bullet), full report
    `docs/reports/2026-07-23-monte-carlo-outcome-distribution.md`; new stdlib tools
    `tools/mc_summarize.py` + `tools/mc_chart.py` + spec `tools/sweeps/mc_beach_capacity.json`; deck
    `docs/presentation.html` slide 6 (`#mc-distribution` → generated inline SVG, `data-status=ready`).

- **2026-07-23 — Plan 0023 reframed presentation-first; swarm dropped; front-view clustering + ship_stats shipped.**
  - **Who**: USER (reframe call + P1 greenlight against a real turn-15 fixture) and Agent (implementation).
  - **What**: Retired the Track D "swarm orchestration" draft; 0023 became *presentation visuals for
    headless LLM-vs-LLM games* (viewer only). Shipped P1 (front view frames the largest connected
    red/contested cluster — no more ocean-spanning bbox), P2 (canonical `ship_stats` bundle home +
    map crossing annotation, gate-guarded by `tools/validate_make_game_bundle.py`), P3 (projector
    header + legend). Live-facilitator components split into deferred plans 0024–0026; ocean-spanning
    per-beachhead pager deferred to 0027 (the precondition scan found only small, tight multi-cluster
    turns, never two beachheads across water).
  - **Where**: `docs/STATUS.md` viewer bullet; `docs/systems/llm-api-selfplay.md` §7;
    `tools/viewer/game_viewer.html`, `tools/make_game_bundle.py`, `tools/validate_make_game_bundle.py`;
    plan archived at `docs/archive/0023-track-d-orchestration.md`.
  - **Why**: Immediate need is talk visuals for finished headless games; the view layer is
    architectural (primary-agent-written), so the swarm loop was dropped.

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
