---
title: "0043: Anti-ship mutation authority and permanent launch destruction"
status: "In progress"
created: "2026-07-26"
---

# Plan 0043: Anti-ship mutation authority and permanent launch destruction

## Goal

Make the Green anti-ship establishment the first complete vertical slice of the mutation-authority
architecture, while implementing the USER's settled behavior: launchers/platforms destroyed during
launch attrition remain destroyed across later crossings, in addition to permanent IJFS destruction
and temporary suppression.

This is both an architectural change and a deliberate game-behavior correction. The controller
boundary should become the pattern later plans copy; the changed campaign outcomes must be measured,
not hidden inside a refactor commit.

## Settled USER calls — do not relitigate

- IJFS destruction is permanent.
- Pre-launch and post-launch destruction reported by launch attrition is also permanent.
- Suppression is temporary and must not be folded into permanent destruction.
- Use one mutation authority, not several writers of `AntishipSystem` fields.
- Do not wire `AntishipMagazine` in this plan. Persistent launcher ammunition is a separate mechanic.
- Off-island strikes remain independent rows and are not part of the on-island establishment.

The archival port record maps TIV `Total_Destroyed_Cumulative` to
`AntishipSystem.destroyed`; current resurrection is therefore not a semantic model to preserve.

## Current contradiction

Three paths write overlapping state:

- `AntishipCalculator.resolve_launch_attrition` decrements `quantity` and increments `destroyed`,
  `destroyed_this_turn`, `fired`, and `expended`.
- `AntishipResolver._apply_writeback_to_systems` reconstructs `quantity` from
  `original_quantity - cumulative IJFS destroyed` and overwrites `destroyed`, erasing launch losses
  on the next crossing.
- `CleanupResolver.resolve` resets transient flags.

`fired` and `expended` currently receive the same increments and have no distinct consumer.
`quantity` alternates between “surviving establishment” and “not yet attempted this crossing.” No
checked establishment equation defines the fields.

## Target state semantics

`AntishipSystem` must make each fact unambiguous. Exact field names may change during implementation,
but the concepts are fixed:

| Concept | Lifetime | Rule |
|---|---|---|
| Original establishment | immutable | loaded once from scenario/catalog expansion |
| IJFS destroyed cumulative | campaign | authoritative cumulative writeback from persistent IJFS targets |
| Launch destroyed cumulative | campaign | sum of pre- and post-launch destruction applied once per crossing |
| Total destroyed | derived or controller-written projection | IJFS cumulative + launch cumulative, clamped to establishment |
| Surviving quantity | derived or controller-written projection | original − total destroyed |
| Suppressed now | current IJFS cycle/crossing | limits firing but does not reduce surviving quantity |
| Fired/attempted/launched | per crossing | reporting counters, reset at cleanup or overwritten by the next result |

If both component destruction fields are stored, `destroyed` should either be removed or be a checked
projection. Do not retain three independently writable totals.

Attempting to fire does not permanently consume a launcher. The calculator may report attempted and
launched counts, but only reported destruction changes surviving establishment. This separates TIV's
moved/unavailable idea from permanent losses without adding a second same-turn firing mechanic.

## Target architecture

### Pure calculation

`AntishipCalculator.resolve_launch_attrition` becomes mutation-free. It preserves the existing Dice
draw order and returns typed or strongly validated outcome rows containing attempted, launched,
pre-launch destroyed, and post-launch destroyed counts by system identity.

`AntishipResolver` remains responsible for computing target areas, firing percentages, crossing
results, mine results, and summaries. It reads an immutable typed snapshot or owned copy of current
anti-ship availability supplied after IJFS effects are applied; it does not receive a live mutable
alias and does not assign protected system fields.

### Mutation authority

Add `AntishipTransitions` at `scripts/transitions/AntishipTransitions.gd`. It is the exact and only
production writer for protected `AntishipSystem` campaign fields; neighboring files under
`scripts/transitions/` receive no permission to write them. Its API should be job-shaped:

- initialize establishment from loader-built rows;
- apply cumulative IJFS destruction and current suppression;
- apply one launch-attrition result exactly once;
- reset or replace transient crossing flags;
- validate establishment equations and bounds;
- expose a read-only firing snapshot if passing Resources directly would permit accidental writes.

The controller must fail on unknown `(TO,type)` keys, negative deltas, cumulative IJFS totals moving
backward, duplicate application of the same crossing result, or total destruction above
establishment. Use turn/crossing identity in the typed application request or state if needed to make
idempotency explicit.

`FiresPhases` remains the cross-phase coordinator: apply IJFS effects through the authority, invoke
the pure anti-ship calculation, then apply launch destruction through the authority. EventBus emits
and `last_antiship_summary` assignment remain outside the authority.

## Commit sequence

1. **Characterization tests.** Pin the current one-crossing draw order and reports, then add a
   two-crossing test that demonstrates resurrection under the current code. The second test is
   expected red until the behavior commit.
2. **Model semantics, no behavior change yet.** Add explicit cumulative component fields and an
   establishment validator. Build/load them without changing availability. Update the mutation
   manifest from plan 0042.
3. **Extract calculation from mutation.** Make launch attrition return outcomes without writing
   protected fields; apply the old same-crossing effects through `AntishipTransitions` so existing
   one-crossing output remains byte-stable. Preserve Dice draw order exactly.
4. **Permanent-destruction behavior commit.** Derive surviving quantity from original minus both
   cumulative loss categories. Make the two-crossing test green. Remove the resurrection writer.
5. **Transient cleanup.** Give `fired`, `attempted`, `launched`, `expended`, and suppression one
   meaning each; remove dead duplicates rather than maintaining aliases. Keep serialized output
   stable unless a clearly additive field is approved and fixture-reviewed.
   **Confirmed from source (plan 0042 refactor sweep):** `AntishipCalculator.gd:193-194` increments
   `fired` and `expended` by the identical `launched` value on the same pass, and nothing reads them
   apart. This step owns that removal — it was deliberately left alone in 0042 because it is
   golden-adjacent. Both fields are classified `transient` in the manifest; deleting one is a manifest
   edit as well as a code edit, and the gate will fail on the stale field until the manifest follows.
6. **Close the gate.** Remove every anti-ship legacy writer exception from the mutation-authority
   manifest. Deliberately add a direct write in each former writer and confirm the validator fails.
7. **Measure behavior.** Re-run the accepted crossing calibration and at least one sustained
   follow-on scenario across multiple seeds. Report the direction and magnitude before considering
   any rebalance; do not automatically retune to the old result.
8. **Pilot pattern review.** Before any repository-wide move, review the shipped authority API,
   manifest entry, snapshots, receipts, diagnostics, and public-method count. Update the architecture
   and code-quality skills from evidence. Any authority method-count guidance is a soft threshold on
   public mutation operations, not a hard total-method cap that would force multiple writers.
   **Fold in the two validator cleanups deferred from 0042** (both are internal to
   `tools/validate_mutation_authority.gd`, neither changes what it detects, and this step is the first
   point where their shape is settled by evidence):
   - *Split the scan result from the usage record.* `_apply_allowances` currently both filters
     violations and writes `allowance_used` / `authority_used` back into the `Ownership` object as a
     side effect. The cost is already visible: `_check_inert_authority_fixture` has to hand-build a
     stripped `Ownership` to exercise the failing direction. Return a scan result carrying both, so
     `_report_stale_allowances` and `_report_inert_authorities` become pure functions of it.
   - *Type the findings.* A finding is an untyped `Dictionary` assembled in three passes — `_finding`
     builds it, `_scan` bolts on `path`/`line`, and `_match_dynamic_sets` overwrites `symbol` after
     construction — then read by string key in ~12 places, against `AGENTS.md`'s preference for typed
     fields over Dictionary blobs. An inner `class Finding` removes the post-hoc mutation and makes
     the dynamic-set case a constructor argument. Do this second: it is easier once findings already
     flow through a result object.

   Validation for both: the fixture self-test compares found-vs-expected **exactly** (21 expectations
   at 0042 close), so any shape regression fails as a false negative rather than silently. Re-run the
   deliberate stale-allowance experiment as well — remove `system.active = false` from
   `CleanupResolver` and confirm `E_STALE_ALLOWANCE`.
9. **Post-pilot role-directory checkpoint — mechanical commits only.** Once steps 1–8 are green:
   - create/use `scripts/phases/` and move the clear coordinators (`TurnConductor`, `FiresPhases`,
     `ReinforcementPhases`, `TurnClosure`, `FrontlinePhase`) with their `.gd.uid` files in one commit;
   - create/use `scripts/builders/` and move the clear fresh-state builders with their `.gd.uid` files
     in a second commit: `AirInsertionStateBuilder`, `AntishipSystemsBuilder`, `FleetBuilder`,
     `GameStateBuilder`, `IjfsStateBuilder`, `InfrastructureStateBuilder`,
     `MobilizationStateBuilder`, `SealiftStateBuilder`, `ShipReserveBuilder`, and
     `SupplyStateBuilder`; construction allowances move with them;
   - move only anti-ship files proven free of protected campaign writes (`AntishipResolver`,
     `AntishipCalculator`, `AntishipCrossing`, `MineWarfareService`) into `scripts/calc/` in a third
     commit. Re-scan `AntishipResolver` first: it qualifies only if it still returns hull-loss outcomes
     without writing live `ShipState`/`SealiftState`; otherwise it stays mixed until plan 0045. Any
     mixed file stays where it is until its owning campaign plan splits it.

   Each commit updates manifest paths, `gd_metrics.py` ceiling keys, validator path constants, live
   docs/skills, and concrete path citations; runs `godot --headless --path . --import`; and finishes
   with the full byte-stable gate green. Keep class names unchanged during path-only moves. Phase
   coordinators may remain exact temporary legacy writers for later aggregates, but their manifest
   exceptions must name the plan that removes each write.

   **Optional fourth commit — split `tools/validate_mutation_authority.gd`.** It closed 0042 at ~1050
   lines and 61 functions, 2.4x the next-largest validator (`validate_combat_rules_threading.gd`, 431).
   Every per-function budget is met (max CC 9, max length 31, no parameter breaches), so this is file
   size alone — which is why it is optional and last. If the pilot has made it grow further, extract
   `RefCounted` helpers under `tools/mutation_authority/` along the seams already named in the file:
   corpus + type resolution, manifest → ownership + manifest checks, matchers + verdict + self-test.
   Precedent: `tools/ValidatorHarness.gd`.

   Two traps specific to this split, both verified against the current runners:
   - `run_all_tests.py` globs `tools/validate_*.gd` **non-recursively**, so helpers in a subdirectory
     are safe under any name — but a helper left at `tools/` top level matching `validate_*` would
     silently run as its own gate phase and report a vacuous pass.
   - `validate_tool_script_purity.gd` seeds from top-level `tools/*.gd` and follows references only
     into `res://scripts`, so helpers under `tools/` fall **outside** its compile-closure scan. They
     must not name `GameData`/`GameState`/`EventBus`; nothing will catch it if they do.

## Tests and validation

Required dedicated tests live under `tests/transitions/`; static forbidden-write fixtures remain
under `tools/fixtures/mutation_authority/` and are consumed only by the validator.

Required dedicated tests:

- two crossings with deterministic pre/post-launch destruction: losses remain absent on crossing 2;
- cumulative IJFS losses plus cumulative launch losses add without double-counting;
- suppression clears on schedule while both destruction categories persist;
- repeated application of the same transition fails or is explicitly idempotent, never double-kills;
- total losses clamp/fail according to establishment, with a negative test seen red;
- no-wave turns do not erase or reapply state;
- C2 and off-island rows retain their existing special behavior;
- ScriptedDice draw count/order remains unchanged for one crossing.

Verification:

- import after any new `class_name`;
- standalone anti-ship unit suites and `tools/validate_headless_antiship.gd`;
- canonical full gate, judged by marker lines;
- deliberate mutation-authority red tests;
- fixture diff reviewed key-by-key;
- calibration/research report committed under `docs/reports/` if outcomes move materially.

The golden scenario may or may not cross often enough to move. A pin change is allowed only where the
new permanent-destruction behavior actually reaches the fixture, and must follow deliberate
re-baseline change control. Do not move unrelated pins.

## Review findings folded in (2026-07-26/27)

From the pre-implementation design review (`gem-explore`, `nemotron-3-ultra-free`; deepseek flaked
twice with tool traces and no answer):

- **Accepted — the sum of the two loss categories must be CLAMPED, never asserted.** The IJFS bombs
  container bins while launch attrition kills deployed launchers; they are two projections of one
  arsenal, so `ijfs_cum + launch_cum` can legitimately exceed the establishment in a sustained
  campaign and a fail-loud assert there would crash normal play. Each source is individually bounded
  and checked; only the sum is clamped.
- **Accepted — the idempotency key belongs to the aggregate, not the row.** One crossing resolves per
  turn, so `GameStateData._antiship_launch_turn` carries it; stamping ~100 rows was redundant and
  inflated the serialised Resource.
- **Accepted — a `suppressed` BOOL cannot carry the mechanic.** Firing capacity falls in PROPORTION to
  the number of launchers suppressed, so the field is an int count (`suppressed_now`). Storing it also
  let the resolver drop its `IjfsWriteback` parameter: it now reads the establishment after the
  authority has written it, which is what the target architecture asks for.
- **Accepted — delete `Theaters` rather than leave it dead.** After the `GameData.to_adjacency` swap it
  had zero callers in `scripts/`, `tools/` and `tests/`. Leaving a dead file to buy ceiling headroom
  would be the dodge; deleting it is the actual removal of coupling that earns the headroom.
- **Accepted — `tests/antiship_firing_plan_test.gd` is not byte-stable across the extraction.** Its
  row-mutation assertions became assertions on the returned outcome. "Byte-stable" in the commit
  sequence means the golden fingerprints, not the unit tests that pin the seam being moved.

## Explicitly out of scope (checked, don't re-raise)

- **Passing `ijfs_destroyed` into `build_firing_plan` to revive the "destroyed systems still fire"
  mechanic.** `nemotron` called this a blocker. It is real — the mechanic IS inert today, because the
  resolver passes `{}` for both `ijfs_destroyed` and `destroyed_fire_percentages` — but enabling it is
  a BEHAVIOUR change that would raise Green's shot count under suppression (`initial_system_count =
  available + destroyed` feeds `intended_to_fire`). It is not a mutation-authority question and this
  plan owes byte-stability across the extraction. Backlog it; do not fold it in here.
- **Why no second wave sails in some harness configurations.** Under the `noop` matchup the campaign
  contains exactly one crossing; under `selfplay_default` it contains 4–8. That difference is sealift's
  business, not this aggregate's.

## Out of scope

- Green launcher magazine persistence (`AntishipMagazine`).
- Per-hull ships or per-hull escort ammunition.
- Minefield persistence.
- Off-island shooter attrition.
- Rebalancing IJFS or launch-attrition probabilities to recover old outcome rates.
- A generic mutation-controller base class.

## Risks and stop conditions

- **Double counting:** IJFS target containers and anti-ship system rows are different projections of
  the same arsenal. Keep source-specific cumulative fields and prove their sum.
- **Result drift hidden in architecture work:** separate extraction commits from the deliberate
  behavior commit.
- **RNG drift:** if a refactor changes any ScriptedDice draw sequence, revert and redesign the
  calculation boundary.
- **Dependency ceilings:** `FiresPhases` is ceilinged. Before it names `AntishipTransitions`, record
  the direct dependency that leaves in the same commit. If no one-for-one swap is available, first
  land a separate green application coordinator that is not ceilinged; never raise the ceiling.
- Stop if stable system identity cannot be established from `(to_number,type_id)` without changing
  serialized ids; resolve identity before applying cumulative transitions.

## Closeout homes

On shipment: current behavior in `docs/STATUS.md`; data flow and TIV divergence in
`docs/systems/antiship-mine.md`; orchestration changes in `docs/systems/turn-engine.md`; the authority
boundary in code headers and the architecture skill; USER call and measured consequence in
`docs/DECISIONS.md`; plan archived. The two systems docs gain a short numbered **State & authority**
section naming the aggregate, authority, operation-specific outcome/receipt types, and manifest link;
they do not duplicate protected fields or writer lists. `docs/systems/README.md` explains this section
convention once rather than repeating an authority inventory in its index table.

## Dependencies

Requires plan 0042. Establishes the concrete controller pattern every later campaign plan must review
before copying. Plan 0002 (per-hull escort magazines) and any future launcher-magazine work should
wait for this plan, but are not part of it.
