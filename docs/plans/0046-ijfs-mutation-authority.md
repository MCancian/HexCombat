---
title: "0046: IJFS mutation authority"
status: "Sketch"
created: "2026-07-26"
---

# Plan 0046: IJFS mutation authority

## Goal

Put persistent IJFS targets, munition inventory, squadron strength, MANPADS stocks, daily carry-over,
and force/anti-ship writeback behind one explicit IJFS mutation authority. Preserve the six-stage
calculation pipeline and every Dice draw while eliminating direct campaign-state mutation throughout
`IjfsEngine`, `IjfsStrike`, `IjfsEngagement`, and `IjfsResolver`.

## Settled constraints

- IJFS remains a persistent-entity model with daily ephemeral budgets; it is not converted into fleet-
  style closed buckets.
- Munition exhaustion is normal and causes a skipped attack, not an assertion failure.
- Destroyed targets remain destroyed; suppression is temporary according to existing carry-over rules.
- Green maneuver casualties are applied by `ForceTransitions`, not by IJFS editing brigade
  composition.
- Anti-ship writeback is cumulative for destruction and current-cycle for suppression; plan 0043's
  authority consumes it.
- The warmup/day pipeline and RNG draw order are immutable during this architecture work.
- Untyped IJFS summary output remains deliberately untyped at the JSON boundary.

## Current mutation surface

Persistent changes occur in several algorithm classes:

- target detection, suppression, destruction, posture, and metadata stocks;
- munition `inventory_remaining` decrements from multiple strike/intercept paths;
- squadron `alive`, `losses_today`, and RTB state;
- MANPADS `metadata.systems_remaining` hidden inside target metadata;
- daily reset/carry-over flags;
- maneuver target synchronization and direct brigade casualty application.

These writes are close to the math, which helps fidelity, but no single API can state or validate the
campaign transition. The target metadata dictionary also hides authoritative mutable quantities.

## Aggregate boundary

`IjfsTransitions` at `scripts/transitions/IjfsTransitions.gd` owns persistent IJFS campaign state
as its exact sanctioned writer; no other file gains permission by sharing the directory:

- `IjfsTarget` lifecycle and typed mutable stocks;
- `IjfsMunition` remaining inventory;
- `IjfsSquadron` current strength and daily flags;
- day advancement/carry-over;
- target additions for mobilized formations and downward synchronization after force casualties.

Daily firing-capacity budget objects remain ephemeral calculators with their own `try_consume`
prevention API. Scenario definitions, pairings, and doctrine rules remain immutable data.

Cross-aggregate writes are not owned here:

- maneuver casualty receipts go to `ForceTransitions`;
- anti-ship cumulative/suppression writeback goes to `AntishipTransitions`;
- activity posture reads force receipts/state but does not edit force state.

## Target calculation/application split

The IJFS engine continues to own deterministic stage order and Dice. Each stage returns typed outcome
facts or calls narrowly named authority methods at the exact current draw point. Prefer calculating a
rolled result first and applying it immediately afterward so later stage selection sees updated state
without changing draw order.

Required authority operations include:

- mark detection/intel lock/posture for a target;
- apply target destruction or suppression with source munition and day identity;
- consume munition rounds after verifying sufficiency;
- apply squadron losses/RTB and reset daily flags;
- consume typed MANPADS stock;
- add/synchronize maneuver targets through explicit force receipts;
- carry state to the next day;
- validate target ids, inventory bounds, squadron bounds, and monotonic destruction.

Do not introduce one generic `set_target_field` method. A method name must reveal the domain event.

## Model hardening

- Replace authoritative `metadata.systems_remaining` with a typed field or typed sub-resource while
  preserving `metadata` serialization compatibility at the boundary.
- Store an initial munition inventory only if needed to validate/report conservation. If added, it is
  immutable reference state, not a second remaining total.
- Validate `0 <= alive <= initial` for squadrons and nonnegative inventories/stocks.
- Generated target and squadron ids must be unique at construction; changing their current formats is
  out of scope.
- A destroyed target cannot resurrect. Suppression reset must not alter destruction.

## Commit sequence

1. **Mutation inventory and characterization.** Register every direct writer and pin stage-specific
   outcomes with `ScriptedDice`, including warmup carry-over, inventory exhaustion, MANPADS, and
   squadron loss.
2. **Typed hidden stocks.** Move MANPADS remaining stock out of free-form metadata behind a typed
   model while keeping `to_dict` output byte-stable. Add uniqueness/bounds validation.
3. **Inventory authority.** Route every munition decrement through `IjfsTransitions`; preserve normal
   insufficient-inventory skips and exact rounds-expended reporting.
4. **Squadron authority.** Route losses, RTB, and daily reset through checked transitions.
5. **Target authority.** Route detection, suppression, destruction, intel lock, and carry-over through
   named methods, one IJFS stage per commit.
6. **Maneuver synchronization.** Consume force transition receipts/current authoritative counts;
   remove direct brigade composition mutation and duplicate target-state guesses.
7. **Writeback boundary.** Build cumulative anti-ship and force casualty receipts from authoritative
   target state; apply them only through plans 0043/0044 authorities.
8. **Role placement.** Move `IjfsDailyState` into `scripts/model/` (preserving `class_name`, UID,
   serialization, and class-cache import) because it is persistent state, not a calculator. Move each
   IJFS algorithm to `scripts/calc/` only after it returns outcomes or calls the authority at the exact
   existing semantic point without retaining a protected write. Split mixed files rather than moving
   them by dominant role.
9. **Close the gate.** Remove all IJFS legacy writer exceptions and prove direct, nested metadata,
   model-mutator, dynamic, and wrong-authority writes to target, munition, squadron, and stock state
   fail.

## Tests and validation

Required authority tests under `tests/transitions/`:

- successful and insufficient munition consumption across both decrement paths;
- no negative inventory and exact rounds-expended reconciliation;
- target destroyed persistence and suppression carry-over/reset;
- multi-day warmup continuity and first normal turn continuity;
- squadron losses bounded by initial/alive with daily counters reset correctly;
- MANPADS typed stock serialize → deserialize/duplicate cycle if mid-campaign persistence supports it;
- maneuver target addition, casualty synchronization, and no resurrection;
- cumulative anti-ship writeback remains cumulative across days and composes with plan 0043;
- duplicate generated ids fail at build;
- ScriptedDice draw order unchanged at each stage.

Verification:

- all IJFS GdUnit suites and relevant headless validators;
- standalone cumulative writeback and warmup validators twice;
- full gate, no golden/fixture drift for authority-only commits;
- mutation-authority deliberate red tests;
- one multi-turn game proving inventory, target, and squadron continuity.

## Out of scope

- IJFS probability, doctrine, capacity, release-rule, warmup, or inventory balance changes.
- Changing target, squadron, or battalion id formats.
- Making every ephemeral firing-budget object part of campaign state.
- Typing the full IJFS summary Dictionary.
- Launcher magazine or minefield persistence.

## Risks and stop conditions

- **RNG coupling:** IJFS has many conditional draws. Never batch/reorder outcomes merely to make the
  controller API cleaner.
- **Mid-stage visibility:** later target selection may depend on an earlier mutation. Apply at the
  same semantic point, not only at end-of-day.
- **Metadata compatibility:** preserve output shape while moving internal authority; stop if a hidden
  external consumer requires a migration decision.
- **Performance:** avoid deep-copying the entire IJFS state per strike. Snapshot only fields needed to
  prove each delta.
- **Over-centralization:** `IjfsTransitions` may use focused helpers, but there remains one sanctioned
  writer boundary and one manifest owner.

## Closeout homes

On shipment: `docs/STATUS.md`; `docs/systems/ijfs.md`; anti-ship/force cross-seam pointers in their
systems docs if behavior descriptions changed; phase wiring in `docs/systems/turn-engine.md`;
authority code headers and architecture skill; `docs/DECISIONS.md`; plan archived. Owning docs update
their short numbered **State & authority** section with aggregate, authority, operation-specific
outcome/receipt types, and manifest link only.

## Dependencies

Requires 0042, 0043, and 0044 so writeback has authoritative consumers. It is independent of the
fleet migration after those interfaces are stable, but should execute after 0045 to keep the campaign
strictly one aggregate at a time.
