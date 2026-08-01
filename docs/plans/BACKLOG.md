# HexCombat — Tech Debt & Hygiene Backlog

> **Read budget — 260 lines of unordered items.** Nothing here is scheduled and nothing here is a
> dependency. `grep -n '^- \[ \]' docs/plans/BACKLOG.md` gives you every open item's headline; read
> the body of one only if you are about to act on it.

This document is strictly a place for agents to dump observations of tech debt, hygiene issues, and necessary refactors encountered during development.

Focused multi-session efforts (features, content, balancing) get a numbered plan in the `docs/plans/` directory and are tracked in [README.md](README.md).

## Deferred Debt & Hygiene Items

*(Agents: append new technical debt and hygiene observations here)*

- [ ] **Mutation-authority protection reaches only TYPED receivers, so state passed through an untyped
  `Dictionary`/`Array` is unprotected and the gate cannot say so (standing limit, restated 2026-07-31;
  NOT a defect to fix, a rule to follow).** The enforcement gate judges a write by resolving the
  receiver's type; a value reached through an untyped container has no type to resolve, so the write is
  neither permitted nor refused — it is invisible. The manifest's `_schema_rules` documents this as the
  "aliased-container blind spot", and it is not theoretical: `SealiftResolver`'s last illegal write was a
  `ship_category` stamp put into force-owned reserve rows through exactly such an alias, found by hand in
  plan 0045, not by the gate. **Deliberately not opened as a plan.** The fix is "make shared state a typed
  `Resource` before registering its fields", which is what plans 0042–0050 already did aggregate by
  aggregate — there is no bounded remaining unit of work, only a standing rule for new code. What would
  make this actionable is a *measurement* nobody has: how much live campaign state still travels through
  untyped containers. If someone produces that number and it is large, this becomes a plan; until then,
  opening one would be scheduling an unbounded refactor. Adjacent, already logged separately:
  `E_STALE_ALLOWANCE` is the one manifest check with no proof surface.

- [ ] **`docs/plans/` is excluded from the doc-anchor gate, so an ACTIVE plan's code references rot
  silently (found 2026-07-31 while widening the gate; accepted trade-off, not an oversight).** Plans are
  excluded because a proposal legitimately names classes it intends to CREATE — failing a plan for
  describing its own work would make the gate an obstacle to planning. The cost is the other half: a
  Sketch that cites six real files (0055 does) rots the moment one is renamed, and the agent who picks
  it up follows a dead reference. The symmetric fix is a `(planned)` line marker beside `(historical)`
  and `(upstream)`, then removing the exclusion — but turning it on means triaging every active Sketch
  at once, several of which predate two refactor campaigns. Do it as its own unit of work, not as a
  rider on something else.

- [ ] **A Green LLM seat can deploy Red JLSF cargo (found 2026-07-31 by the Sol diff-review role on
  plan 0049 commit 3; PRE-EXISTING, not a regression).** `deploy_jlsf` has no team in the action
  schema (`schemas/llm_action_response.schema.json`), `LLMGameAPI._apply_deploy_jlsf_action` parses
  none, and the façade `GameState.add_jlsf_order` hardcodes `Brigade.Team.RED` — exactly as the
  pre-0049 code hardcoded it when calling the private `_apply_order`. `OrderValidator.check_jlsf_order`
  now HAS a `TEAM_MISMATCH` arm, but nothing on the LLM path can ever reach it, and both seats buffer
  through the same unlabelled path in `SelfPlayRunner`. Plan 0049 deliberately did not fix it: the fix
  requires adding `"team"` to the action schema, which is "new action-schema vocabulary" and explicitly
  out of that plan's scope. Fixing it means threading seat identity through `SelfPlayRunner` so a Green
  seat cannot claim Red. Worth doing before any research run where both seats are live LLMs.

- [ ] **Should a duplicate `deploy_jlsf` order be rejected? (USER design call, raised 2026-07-31.)**
  Two buffered orders for one port emit exactly ONE pool entry — `InfrastructureTransitions.queue_jlsf`
  refuses the second occurrence — so accepting duplicates is harmless, and plan 0049 kept accepting
  them only to preserve pre-existing behaviour. Rejecting them at planning time would be an equivalent
  outcome with a clearer contract (and a `DUPLICATE_JLSF` code, matching `DUPLICATE_MOVE`/
  `DUPLICATE_COMMIT`/`DUPLICATE_AIR_INSERT`). Proof both ways:
  `tests/transitions/accounting_authority_characterization_test.gd::test_two_buffered_jlsf_orders_emit_exactly_one_pool_entry`.

- [ ] **`E_STALE_ALLOWANCE` is the one mutation-manifest check with no proof surface (found 2026-07-30
  by the DeepSeek enumeration role; pre-existing, not a regression).** Every other manifest-check code
  is either declared by a `bad_manifest_*.json` fixture or perturbed by a `_capture_failures`
  self-test. `tools/validate_mutation_authority.gd`'s `_report_stale_allowances` is not: it is the
  only emission site, and nothing exercises it. So if a construction or legacy writer outlives its
  last write, nothing proves the gate would say so. It cannot use the existing broken-manifest harness
  — `_check_manifest_error_fixtures` runs only `_check_manifest` + `_build_ownership`, never `_scan`,
  and a stale allowance is only visible after a scan produces a Verdict. It needs the same treatment
  `_check_inert_authority_fixture` got: re-judge the fixture findings against a doctored usage record.

- [x] ~~**Three `GameStateData` fields are real mutable state that no aggregate owns and no plan
  names**~~ **(found 2026-07-30; RESOLVED by plan 0050, 2026-07-31).** `sealift_state`,
  `pending_lost_at_sea` and `lost_at_sea_accumulator` all joined the `sealift_fleet` aggregate —
  `SealiftTransitions` owns the handle and the crossing's BN-equivalent ledger. `shared_model_policies`
  now carries **no promise classification at all**, which is what let 0050 be archived: an exclusion
  naming an archived plan is designed to fail `E_STALE_POLICY_PLAN`, and that is the mechanism that
  made resolving these three non-optional. Rationale in
  `docs/archive/0050-mutation-authority-enforcement-closeout.md`.

- [ ] **Reviewer read-only is still a prompt, not a sandbox — opencode can enforce it (found 2026-07-30,
  plan 0054; USER raised the config route).** `opencode` supports per-agent permissions
  (`opencode.json` → `agent.plan.permission`), so `"edit": "deny"` would make read-only ENFORCED for the
  DeepSeek route instead of merely requested in prose — the hole `.claude/REVIEWERS.md` § Safety
  currently just warns about. Measured context: `external_directory` defaults to `ask`, and an "ask" in
  a non-interactive opencode invocation is auto-rejected, which is why that reviewer read no artifact for
  four rounds. **Do NOT use opencode's `--auto` flag** as the fix: it approves everything not explicitly denied,
  including `edit`, and these models have been measured announcing a fallback from the read-only agent to
  the writing `build` agent. Verify any change by having the `plan` agent attempt an edit and watching it
  be denied. Global `~/.config/opencode/opencode.json` currently has no `permission` block at all.
- [ ] **A reviewer brief should demand NUMBERED findings from every role, including nil returns
  (found 2026-07-30, plan 0047 steps 4-7 round).** `tools/review_fanout.sh --report` scores a return
  `FLAKE` on "no numbered findings", which is right as a default — a died-early route is
  indistinguishable from approval. But that round produced two genuine returns it could not count: the
  tier-1 reviewer's 342-byte "no actionable findings" (a real read: it named a non-equivalence and two
  ABSENT determinations) and the enumerator's 34 KB of correct verbatim lists (an enumeration role
  produces lists, not findings). Auto-count said 1 of 2 and "hold uncommitted"; the quorum was in fact
  met, on content. **The cheap fix is in the BRIEF, not the launcher:** require every role to answer as
  a numbered list, with "1. No defect found — here is what I checked and what I concluded" as a legal
  entry, and require an enumeration role to number its lists. Then the mechanical count matches reality
  and no agent has to reason its way past a `QUORUM NOT MET` line. Pairs with the `--format json` item
  below; do them together if either is touched.
- [ ] **DeepSeek's return is unparseable by the byte band because its stdout is prompt echo + tool
  traces + report (found 2026-07-30, plan 0047; USER raised it).** Both plan-0047 rounds were
  substantive enumerations (23.6 KB and 14.7 KB) and both were labelled `SUSPECT` on size alone, so a
  future agent may discard a good return — one of them held the only catch of its round. **The fix is
  `--format json`** on the opencode route (it emits raw JSON events), plus a `tools/review_fanout.sh`
  change to extract the final assistant message, plus the gated invocation row in `.claude/REVIEWERS.md`
  updated in the same commit or `tools/validate_reviewer_facts.gd` goes red. **Do NOT instead ask the
  reviewer to write its report to a file:** it contradicts the `REVIEW ONLY` line the launcher prepends,
  `--agent plan` has been measured not honoured by some opencode models, and the only writable location
  is inside the worktree — which is the measured cross-contamination incident in `~/.claude/AGY.md`
  (one reviewer's artifact read off disk and returned verbatim by another as fake corroboration).
  Note an enumeration return is legitimately long even once the noise is stripped, so the 1–10 KB band
  needs a role-aware exception either way.
- [ ] **`tools/review_fanout.sh` residual hardening, all deliberately declined during plan 0054's review
  rounds — re-raise only with a failure to point at.** (a) A snapshot made with `git diff --binary` is
  rejected by the structural check; a stateful binary-patch parser was declined, and `--freeze` never
  passes `--binary`. (b) `--report`'s auto-count is a labelled lower bound rather than an explicit
  per-reviewer acceptance protocol; exit 3 covers the failure mode instead. (c) `_dirty_paths` does not
  handle paths containing a literal newline. (d) The gate cannot watch `~/.claude/*`, so the global agy
  contract and slash command are kept roster-free by convention only.

- [ ] **Seven summary headers promise byte-stability the gate does not check (found 2026-07-29,
  witness sweep).** `CleanupSummary`, `CombatSummary`, `FrontlineSummary`, `AntishipSummary`,
  `MobilizationSummary`, `AirInsertionSummary` and `IjfsWriteback` each say `to_dict()` is "the
  JSON-serialization boundary … so golden/observation fixtures stay byte-stable". The boundary half is
  TRUE — all seven land in `turn_result` in `docs/examples/llm_result_after_turn.json` (verified: that
  fixture's `turn_result` holds `air_insertion_summary`, `antiship_summary`, `cleanup_summary`,
  `combat_summaries`, `frontline_summary`, `ijfs_summary`, `ijfs_writeback`, `mobilization_summary`,
  `offload_summary`). The byte-stability half is NOT: `tools/validate_llm_api.gd:271-277` only checks the
  fixture HAS the required top-level keys — no value or key-order comparison. Fix: name the witness in
  each header per `hexcombat-docs-and-writing` ("pinned by: …, which checks key presence only").

- [ ] **The LLM result fixture is key-presence-checked, not drift-checked (found 2026-07-29).**
  `tools/LLMFixtures.gd:7` records "the rot that left `llm_result_after_turn.json` stale" as the reason
  that generator exists — but the current check (`validate_llm_api.gd:271-277`) cannot catch that rot
  returning: a fixture with all the right keys and stale VALUES passes. Adding a real drift comparison
  is a gate change with a re-baseline decision attached (the fixture would then move whenever any
  summary's payload legitimately changes). **USER call 2026-07-29: re-baselining is acceptable — build
  the real drift comparison.** So the trade is settled; what remains is implementation, and the fixture
  regenerator (`tools/LLMFixtures.gd`) is the intended way to move it rather than hand-editing.

- [ ] **Gate the `consumer:` / `pinned by:` witness convention once there is a corpus (opened
  2026-07-29).** `hexcombat-docs-and-writing` now requires a greppable witness for any claim that
  something is or is not consumed, serialized, pinned, or expensive, and the convention is seeded in
  `scripts/model/SealiftState.gd` and `SealiftHullLossReceipt.gd`. Extending
  `tools/validate_doc_anchors.gd` to resolve those witnesses (a named symbol must exist; a "none
  (checked <date>)" must not sit next to a live reference) was deliberately NOT done yet: with two
  usages the check would match almost nothing, and this repo's standard is that a detector is proven by
  fixtures or it is a false negative waiting to happen (see `validate_mutation_authority.gd`'s
  E_VACUOUS family). Do it when ~10 usages exist, and add fixtures that prove each direction fails.

- [x] **Pay down remaining parameter-ceiling contexts after plan 0052.** *(done 2026-07-30 inside plan
  0046, which is where the collision warning pointed.)* `IjfsStrikePhaseContext` took
  `IjfsEngine._run_strike_phase` from 11 params to 4, and `_append_final_skips` (6→2) and `_skip_log`
  (6→3) came with it since they consume the same bundle — one byte-stability proof for three
  functions. All three `PARAM_CEILINGS` entries removed rather than renumbered. Remaining
  grandfathered production functions are listed in `tools/gd_metrics.py`; none is currently
  context-shaped enough to be worth the same treatment.

- [ ] **`IjfsSquadron.losses_today` is campaign-cumulative, not per-day (found 2026-07-30, plan 0046
  preflight).** Nothing resets it — `carry_to_next_day` touches targets only — so a name that promises
  "today" reports the whole campaign, and it is serialized into the `air_oob_after` ledger and the
  daily summary's `red_air_losses`. Deliberately preserved by 0046, which was an authority migration
  with byte-stability as its acceptance test; changing it is a behaviour change needing a golden
  re-baseline and a USER call on which number the ledger should carry. `rtb_today` is the related
  oddity: no runtime writer at all, reported as a constant 0. Both are pinned as-is by
  `tests/ijfs/ijfs_authority_characterization_test.gd`, so a fix has to go through those tests
  deliberately rather than by accident.

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

- ~~**`IjfsResolver.apply_maneuver_casualties` bypasses the roster-shrinking seam.**~~ **RESOLVED by
  plan 0044; verified closed 2026-07-31 during the 0050 closeout audit.** The item (recorded
  2026-07-27) said the IJFS path decremented `battalion.qty` without removing a zero-qty battalion
  from `composition` or de-indexing a wiped-out brigade. `IjfsResolver.apply_maneuver_casualties` is
  now **ABSENT**: the path is `FiresPhases.apply_ijfs_maneuver_casualties` →
  `ForceTransitions.apply_battalion_casualties`, which does all three
  (`ForceTransitions.gd:78` roster loss via `_apply_roster_loss`, which does
  `composition.remove_at(index)` at `:605`; `:80-84` destroyed flag plus de-index). Kept as a
  crossed-out line rather than deleted because the item's own text was the evidence 0044 acted on.
