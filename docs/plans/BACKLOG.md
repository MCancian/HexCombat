# HexCombat — Tech Debt & Hygiene Backlog

> **Read budget.** `grep -n '^- \[ \]' docs/plans/BACKLOG.md` lists every OPEN item's headline.
> That grep is now exact: every open item carries a checkbox and nothing else in this file does.
> (Before the 2026-08-01 triage it undercounted by four — items written as bare `- **Bold.**` were
> invisible to the documented command, and two sub-items were malformed as `-[ ]` / `- [ ]Text`.)
> Read an item's body only if you are about to act on it.
>
> **Items under "Standing limits & blocked" are deliberately NOT checkboxed.** They are notes, not
> work: each is either a rule to follow rather than a defect to fix, or is waiting on something that
> does not yet exist. Each says what would turn it into work. Do not open a plan for one without
> that precondition.

This document is strictly a place for agents to dump observations of tech debt, hygiene issues, and necessary refactors encountered during development.

Focused multi-session efforts (features, content, balancing) get a numbered plan in the `docs/plans/` directory and are tracked in [README.md](README.md).

## Items that travel together

Bundled 2026-08-01. These are not dependencies — each item stands alone — but doing a bundle's
members separately means editing the same file, schema or gate two and three times, and in one case
means writing prose you then have to un-write.

## Deferred Debt & Hygiene Items

*(Agents: append new technical debt and hygiene observations here. One `- [ ]` per item — the read
budget above depends on it. If the observation is a standing rule or is blocked on something absent,
put it in the section below WITHOUT a checkbox and say what would unblock it.)*

- [ ] **Validator harness: `_fail` / `_finish` / asserts are copy-pasted across the validators.**
  Found 2026-07-25, refactor review. Measured: `func _fail` in **30 of 36** `tools/validate_*.gd`,
  `_finish` in 31, `_assert_equal_int` in 12, `_assert_true` in 11. A `tools/ValidatorHarness.gd`
  owning the assert vocabulary would remove the duplication. **Note the claim that failed review:**
  this does NOT fix the gate-hang class — a script that fails to COMPILE never runs, harness included
  (caught by agy-explore; two other models wrongly agreed it would). That hole is closed separately by
  `--quit-after` in `run_all_tests.py`. So this is deduplication only, worth doing when validators are
  being touched anyway, in slices of 5-6 with the gate green between. Good `opencode` delegation.
- [ ] **Nothing enforces `sweepable`, so the flag records intent and no more.**
  Measured 2026-08-01 while marking the combat advantage ratios `false`. `tools/run_sweep.py` never consults the knob registry;
  the only code that touches the field is `tools/validate_knob_registry.gd`, which checks it is a bool
  and that a `kind` knob is not sweepable. So a `sweepable:false` knob can still be swept via
  `DataOverrides` and nothing complains. Two checks are wanted and they are NOT the same:
  (a) **a `sweepable:true` knob whose override does not actually apply should fail** — this is the
  original 2026-07-23 item, and it would have caught the phantom `offload_beach_base_rate` path;
  (b) **a `sweepable:false` knob that is swept anyway should be refused** — which is what would make
  the advantage-ratio decision real rather than advisory.
  **Note (a) would NOT have caught the advantage ratios**, which is why both checks are listed: their
  override *does* apply — it changes the `result` label in the record. A check that only asks "did
  anything move?" sees them move and passes. Only (b) expresses "this knob must not be a study
  variable".
- [ ] **`UnitStats.FALLBACK_CATEGORY_DEFS` reachability is unknown.**
  90 entries, and NO composition entry in either OOB declares a `category` — the table is reachable only through `_fallback_category_for_type`'s
  type-name heuristics. Plan 0032 anchored two new airborne strengths on entries that were dead until
  then. Instrument `_fallback_category_for_type` over both OOBs, list the keys actually hit, and delete
  or document the rest. Do NOT delete on inspection alone; the matching is indirect.
- [ ] **A typed turn-resolution outcome carrying all phase reports — MEASURED DOWN rather than adopted (2026-08-01).**
  Proposed by the tier-1 reviewer during plan 0059's review.
  The idea: instead of each phase writing a report onto `GameStateData` and `GameState.play_turn` reading eleven fields back out,
  `TurnConductor` returns one typed outcome carrying them all. It is a genuinely better shape in the
  abstract, and it is **not worth doing here** for a reason that only shows up when you count the
  fields. Of the eleven `phase_output` fields on `GameStateData`:

  - **Five are read by `LLMGameAPI` at PLANNING time, between turns** — `last_ijfs_summary`, `last_antiship_summary`, `last_combat_summaries`, `last_contested_hexes`, `last_ijfs_writeback`.
    A resolution outcome exists only from resolve until `play_turn` returns; these are read long after
    that, when a seat builds its next observation. **They must stay on the state whatever happens**, so
    a typed outcome cannot replace them — it runs in parallel with them.
  - **Seven are read by a later phase**, which is genuine cross-phase state; the architecture contract
    routes exactly that through `GameStateData` fields on purpose.
  - **Three are transport-only** — `last_offload_summary` (read by nothing but `play_turn`),
    `last_air_insertion_summary` and `last_mobilization_summary` (read only by `TurnEventLog`).
    So the refactor cleans up three fields, cannot touch five, and adds a second transport mechanism
    alongside the one it failed to remove — across every phase, `TurnConductor` and `play_turn`.
    **Unblocks when:** the transport-only set grows materially (say past half), or the observation API
    stops reading phase reports off the state between turns. Plan 0059's `last_ijfs_air_oob` is a twelfth
    field in the transport-only group; it does not make this refactor harder, and folds into it if it is
    ever built.
- [ ] **Mutation-authority protection reaches only TYPED receivers.**
  State passed through an untyped `Dictionary`/`Array` is unprotected and the gate cannot say so (standing limit, restated 2026-07-31;
  NOT a defect to fix, a rule to follow).** The enforcement gate judges a write by resolving the
  receiver's type; a value reached through an untyped container has no type to resolve, so the write is
  neither permitted nor refused — it is invisible. The manifest's `_schema_rules` documents this as the
  "aliased-container blind spot", and it is not theoretical: `SealiftResolver`'s last illegal write was a
  `ship_category` stamp put into force-owned reserve rows through exactly such an alias, found by hand in
  plan 0045, not by the gate. **Deliberately not opened as a plan.** The fix is "make shared state a typed
  `Resource` before registering its fields", which is what plans 0042–0050 already did aggregate by
  aggregate — there is no bounded remaining unit of work, only a standing rule for new code.
  **Unblocks when:** someone produces the measurement nobody has — how much live campaign state still
  travels through untyped containers. If that number is large, this becomes a plan. The `OffloadCalculator`
  item above is the one bounded instance, and a data point toward that measurement.
- [ ] **`tools/review_fanout.sh` residual hardening, all deliberately declined during plan 0054's review rounds.**
  (a) A snapshot made with `git diff --binary` is rejected by the structural check; a stateful
  binary-patch parser was declined, and `--freeze` never passes `--binary`. (b) `--report`'s auto-count
  is a labelled lower bound rather than an explicit per-reviewer acceptance protocol; exit 3 covers the
  failure mode instead. (c) `_dirty_paths` does not handle paths containing a literal newline. (d) The
  gate cannot watch `~/.claude/*`, so the global agy contract and slash command are kept roster-free by
  convention only. **Unblocks when:** one of these produces an actual failure to point at. Re-raising
  without one re-opens a decision already made twice.
- [ ] **Gate the `consumer:` / `pinned by:` witness convention (opened 2026-07-29).**
  `hexcombat-docs-and-writing` now requires a greppable witness for any claim that something is or is
  not consumed, serialized, pinned, or expensive, and the convention is seeded in
  `scripts/model/SealiftState.gd` and `SealiftHullLossReceipt.gd`. Extending
  `tools/validate_doc_anchors.gd` to resolve those witnesses (a named symbol must exist; a "none
  (checked `<date>`)" must not sit next to a live reference) was deliberately NOT done yet: with two
  usages the check would match almost nothing, and this repo's standard is that a detector is proven by
  fixtures or it is a false negative waiting to happen (see `validate_mutation_authority.gd`'s
  E_VACUOUS family). **Unblocks when:** ~10 usages exist. Then add fixtures proving each direction fails.
- [ ] **Doc-anchor validator checks links, not bare symbols (found 2026-07-25).**
  `tools/validate_doc_anchors.gd` matches `ClassName.member` in backticks, so a doc naming a bare
  `CONSTANT` that no longer exists passes — `docs/systems/ground-combat.md` described
  `CombatCalculator.TERRAIN_MODIFIERS` as "dead code, left untouched" long after the symbol was deleted (historical)
  (fixed 2026-07-25). Extending the check to bare backticked ALL_CAPS identifiers was considered and
  **deferred deliberately**: `PI`, `INFINITY` and ordinary prose constants would false-positive.
  **Unblocks when:** someone has a scoping rule that survives scrutiny. Neither reviewer had one.
- [ ] **Combat-loop caches live as mutable fields on `GameStateData` (found 2026-07-25).**
  `isolated_air_landed_brigades` (`:43`) and `not_ashore_by_type` (`:49`) are both computed once per
  turn at `TurnConductor:65`/`:70` and read by every contested hex; nothing enforces that a third such
  cache follows the rule or that either is cleared between turns. A `begin_combat_loop(state)`
  returning a context value object would make staleness impossible by construction. **Deferred:**
  reviewers split on risk/reward — the caches are correct today and the change touches
  `CombatResolver.resolve_at`'s signature for no behavioural gain. **Unblocks when:** that seam is open
  for another reason, or a third such cache appears.
- [ ] **`CombatResolver` assumes attacker=Red / defender=Green.**
  `resolve_at` hardcodes it — the two
  defender-side `inject_supply_effectiveness` calls were no-ops for exactly this reason and were removed
  2026-07-24, leaving a comment. Supply injection and anything else keyed on side must be driven by each
  side's actual team, not its role. Ported combat semantics, so a USER-aware change, not a refactor.
  **Unblocks when:** Green counterattacks — i.e. plan 0029 Tier B. Until then there is no second case to
  generalize against.
