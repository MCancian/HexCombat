# HexCombat — Tech Debt & Hygiene Backlog

This document is strictly a place for agents to dump observations of tech debt, hygiene issues, and necessary refactors encountered during development.

Focused multi-session efforts (features, content, balancing) get a numbered plan in the `docs/plans/` directory and are tracked in [README.md](README.md).

## Deferred Debt & Hygiene Items

*(Agents: append new technical debt and hygiene observations here)*

- [ ] **Pay down remaining parameter-ceiling contexts after plan 0052.** `tools/gd_metrics.py` now
  enforces real wrapped-signature counts. Anti-ship crossing was paid down with
  `AntishipCrossingContext`; the remaining high-value grandfathered production function is
  `IjfsEngine._run_strike_phase` (11 params), which is context-shaped rather than behavior-shaped.
  Follow the `AntishipResolutionContext` pattern: typed Resource in `scripts/model/`, keep `Dice`
  explicit, remove each fixed function from `PARAM_CEILINGS`, and prove golden byte-stability. Watch
  plan conflicts: 0046 will touch IJFS internals.

- [ ] **Validator harness: `_fail` / `_finish` / asserts are copy-pasted across the validators
  (found 2026-07-25, refactor review).** Measured: `func _fail` in **30 of 36** `tools/validate_*.gd`,
  `_finish` in 31, `_assert_equal_int` in 12, `_assert_true` in 11. A `tools/ValidatorHarness.gd`
  owning the assert vocabulary would remove the duplication. **Note the claim that failed review:**
  this does NOT fix the gate-hang class — a script that fails to COMPILE never runs, harness included
  (caught by agy-explore; two other models wrongly agreed it would). That hole is closed separately by
  `--quit-after` in `run_all_tests.py`. So this is deduplication only, worth doing when validators are
  being touched anyway, in slices of 5-6 with the gate green between. Good `opencode` delegation.
- [ ] **Doc-anchor validator checks links, not symbols (found 2026-07-25).** `tools/validate_doc_anchors.gd`
  matches `ClassName.member` in backticks, so a doc naming a bare `CONSTANT` that no longer exists
  passes — `docs/systems/ground-combat.md` described `CombatCalculator.TERRAIN_MODIFIERS` as "dead code,
  left untouched" long after the symbol was deleted (fixed 2026-07-25). Extending the check to bare
  backticked ALL_CAPS identifiers was considered and **deferred deliberately**: `PI`, `INFINITY` and
  ordinary prose constants would false-positive, and neither reviewer had a scoping rule that survived
  scrutiny. Needs a real rule before it is built.
- [ ] **Combat-loop caches live as mutable fields on `GameStateData` (found 2026-07-25).**
  `isolated_air_landed_brigades` (`:43`) and `not_ashore_by_type` (`:49`) are both computed once per
  turn at `TurnConductor:65`/`:70` and read by every contested hex; nothing enforces that a third such
  cache follows the rule or that either is cleared between turns. A `begin_combat_loop(state)`
  returning a context value object would make staleness impossible by construction. **Deferred:**
  reviewers split on risk/reward — the caches are correct today and the change touches
  `CombatResolver.resolve_at`'s signature for no behavioural gain. Do it when that seam is open anyway.
- [ ] **Inert knob-registry entries (found 2026-07-23, MC sweep investigation).** Two knobs are
  dumped into every record but do NOT affect the sim (overriding them yields byte-identical games),
  so a sweep on either silently reports false robustness:

  - `combat_defender_advantage_ratio` / `combat_attacker_advantage_ratio` — recorded but never reach
    `CombatResolver`. Either wire them into the combat math or drop them from `data/knobs/registry.json`.
  - `offload_operational_port_rate` — **now owned by plan 0031 (Objective 0, USER 2026-07-24)**: port
    throughput is the `OffloadRates.OPERATIONAL_PORT` GDScript constant, not loaded from
    `offload_rates.json`, so it's not DataOverrides-sweepable (now marked `sweepable:false`). To make
    it a real lever, load `offload_rates.json` through `GameData._read_json` (routes through
    DataOverrides) and have `InfrastructureResolver` read the loaded rate. Same applies to the other
    `OffloadRates` constants (beach base uses `beaches.json:offload_rate` and already works).
  - Consider a gate check that fails when a `sweepable:true` registry knob's override doesn't actually
    apply (would have caught the phantom `offload_beach_base_rate` path).

- 
- **The 2 PLAA air assault brigades are unmodelled (plan 0032).** The USER's source gives the PLAA 15
  aviation brigades, two of them air assault (6 transport + up to 3 infantry BN each); the OOB has 13,
  none air assault. Today only the Airborne Corps' own 130th feeds the rotary-wing lift cap. Adding
  them is an OOB change plus a `nato_type` retag — add-2 vs convert-2 was put to the USER 2026-07-25
  and the call was **leave unmodelled for now**; re-ask before touching the OOB.
- **Order-kind dispatch lives in three places.** `GameState._apply_order`, `LLMGameAPI.apply_agent_response`
  and `schemas/llm_action_response.schema.json` each enumerate the order kinds independently. Adding
  `air_insert` (plan 0032) meant editing all three, and the duplication had already rotted: `deploy_jlsf`
  was missing from the schema until 2026-07-24. Give the kinds one home and derive the dispatch (or at
  minimum add a gate check that every dispatch arm has a schema variant and vice versa).
- **`UnitStats.FALLBACK_CATEGORY_DEFS` reachability is unknown.** 90 entries, and NO composition entry in
  either OOB declares a `category` — the table is reachable only through `_fallback_category_for_type`'s
  type-name heuristics. Plan 0032 anchored two new airborne strengths on entries that were dead until
  then. Instrument `_fallback_category_for_type` over both OOBs, list the keys actually hit, and delete
  or document the rest. Do NOT delete on inspection alone; the matching is indirect.
- **`CombatResolver` assumes attacker=Red / defender=Green.** `resolve_at` hardcodes it — the two
  defender-side `inject_supply_effectiveness` calls were no-ops for exactly this reason and were removed
  2026-07-24, leaving a comment. If Green ever counterattacks (plan 0029 Tier B), supply injection and
  anything else keyed on side must be driven by each side's actual team, not its role. Ported combat
  semantics, so a USER-aware change, not a refactor.
- **`docs/*.md` and `docs/plans/*.md` have no anchor gate.** `tools/validate_doc_anchors.gd` scans
  `res://docs/systems` only, and `tools/validate_skill_references.gd` scans `.claude/skills` only, so
  `STATUS.md`, `DECISIONS.md`, `RETROSPECTIVES.md` and every plan can cite a dead path unnoticed —
  which is how four skills came to point at a validator that had been deleted. Extending one of the two
  to cover them is cheap; the obstacle is that those files legitimately DISCUSS dead paths, so they need
  the `(historical)` escape marker applied first or the gate will fire on the record of the very cleanup
  that removed them.
- 
- **Four `tools/` validators duplicate a comment/string stripper and a `.gd` directory walker — decided
  2026-07-26 NOT to unify, revisit only with new evidence.** `validate_tool_script_purity.gd`,
  `validate_no_global_rng.gd`, `validate_doc_anchors.gd` and `validate_combat_rules_threading.gd` each
  carry their own, with differing semantics. The tempting reason to unify was to fix the shared
  escaped-quote hole (`"say \"hi\""` ends the string match early and exposes the middle as code) in one
  place instead of four. Rejected on two measurements: (1) that hole fails in the LOUD direction —
  blanking leaves more text exposed, not less, so it yields a spurious FAIL, never a silent pass, in
  every current consumer; (2) `validate_tool_script_purity.gd` needs TWO stripper modes, not one — it
  finds `preload("res://…")` paths with a comments-only pass that deliberately PRESERVES strings, so a
  naive unification would silently stop finding preloads, turning a gate into a false negative. That is a
  worse outcome than the duplication. If unified later, the acceptance test is per-validator stdout
  byte-identical AND each still FINDING what it found — a validator that finds fewer things is not
  output-neutral even when its wording is unchanged. Note this is a DIFFERENT item from the
  `_fail`/`_finish` harness dedup above, which remains worth doing on its own terms — a reviewer proposed
  the harness migration as a substitute for this one, and it is not: it addresses different duplication,
  and doing it wholesale would change output (27 of 38 validators still have their own helpers, and
  `ValidatorHarness`'s docstring records that several deviate deliberately), which is why that item
  correctly says slices-with-the-gate-green rather than a sweep.

- **The "destroyed systems still fire" mechanic is inert in production — now planned as
  [0051](0051-destroyed-systems-still-fire.md) (promoted 2026-07-27).** The code change is small but
  it needs a per-cycle IJFS destruction delta that does not exist in the tree yet, a new content knob,
  a USER balance call, and a re-run of the accepted 32.9% crossing calibration. The plan also records
  why feeding `ijfs_destroyed` naively would partly UNDO IJFS suppression: HexCombat's `fire_pct` is
  survivor-relative where TIV's is establishment-relative, so the port's
  `initial_system_count = survivors + destroyed` double-counts here. Read the plan, not this line.

- **`IjfsResolver.apply_maneuver_casualties` bypasses the roster-shrinking seam — belongs to plan
  0044, recorded 2026-07-27 so it does not have to be rediscovered.** `RosterMutations.apply_casualty`
  is the sanctioned path and does three things; the IJFS path does only the first: it decrements
  `battalion.qty`, but it never `composition.remove_at(index)` when a battalion hits zero, and never
  calls `GameData.remove_brigade_from_map(brigade_id)` when a brigade is wiped out. So an IJFS-killed
  brigade is flagged `destroyed` while remaining in the map index, and zero-qty battalions linger in
  compositions — the roster/pool desync family the `RosterMutations` header warns about.
  `docs/plans/0044-force-mutation-authority.md` already claims this by name ("Replace
  `RosterMutations.apply_casualty` and IJFS's independent…"), so this line is evidence, not a new item.
  **Two things 0044 must know.** (1) It is a BEHAVIOUR change — removing zero-qty entries and
  de-indexing destroyed brigades moves combat contributor sets and the census, so golden pins will
  move and it needs deliberate re-baseline change control; it cannot ride along in a refactor.
  (2) The obvious fix of calling `RosterMutations.apply_casualty` from inside `IjfsResolver` would
  break that resolver's purity — it is a pure resolver that receives `brigades` as a parameter and
  never touches the `GameData` autoload, whereas `RosterMutations` is GameData-only. The seam that
  already holds `GameData.brigades` is `FiresPhases.apply_ijfs_maneuver_casualties`.
