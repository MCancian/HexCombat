---
title: "0043: Anti-ship mutation authority and permanent launch destruction"
status: "Sketch"
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
results, mine results, and summaries. It reads an immutable snapshot of current anti-ship
availability supplied after IJFS effects are applied; it does not assign protected system fields.

### Mutation authority

Add `AntishipTransitions` under the pure logic/state layer. It is the only production writer for
protected `AntishipSystem` campaign fields. Its API should be job-shaped:

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
6. **Close the gate.** Remove every anti-ship legacy writer exception from the mutation-authority
   manifest. Deliberately add a direct write in each former writer and confirm the validator fails.
7. **Measure behavior.** Re-run the accepted crossing calibration and at least one sustained
   follow-on scenario across multiple seeds. Report the direction and magnitude before considering
   any rebalance; do not automatically retune to the old result.

## Tests and validation

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
- **Dependency ceilings:** `FiresPhases` is ceilinged. Use classes it already names where possible,
  or extract a prior application seam without raising a ceiling.
- Stop if stable system identity cannot be established from `(to_number,type_id)` without changing
  serialized ids; resolve identity before applying cumulative transitions.

## Closeout homes

On shipment: current behavior in `docs/STATUS.md`; data flow and TIV divergence in
`docs/systems/antiship-mine.md`; orchestration changes in `docs/systems/turn-engine.md`; the authority
boundary in code headers and the architecture skill; USER call and measured consequence in
`docs/DECISIONS.md`; plan archived.

## Dependencies

Requires plan 0042. Establishes the concrete controller pattern every later campaign plan must review
before copying. Plan 0002 (per-hull escort magazines) and any future launcher-magazine work should
wait for this plan, but are not part of it.
