---
title: "0048: Reinforcement-state mutation authority"
status: "Sketch"
created: "2026-07-26"
---

# Plan 0048: Reinforcement-state mutation authority

## Goal

Put ROC mobilization schedules and PLAAF air-insertion capacity/history behind explicit mutation
authorities. Coordinate their force-placement/casualty effects through `ForceTransitions` rather than
letting reinforcement resolvers and wrappers each edit part of the transition.

## Settled behavior

- Mobilization phases in existing Green brigades; it does not create a second OOB.
- Pending brigades remain off-map until their scheduled release and first take orders next turn.
- Air insertion drains ordered packets from its pool up to current per-class cap.
- Every insertion casualty permanently removes one battalion of lift from that class.
- Airborne and air-assault threat formulas, first-turn gate, target legality, locked follow-up hex,
  supply isolation, and RNG substream are unchanged.
- Troop roster/location changes belong to `ForceTransitions`; this plan owns schedules, lift
  capacity, order consumption, and reinforcement-specific ledgers.

## Aggregate boundaries

### MobilizationTransitions

`MobilizationTransitions` lives at `scripts/transitions/MobilizationTransitions.gd` and is the exact
only writer for `MobilizationState.pending`, `released`, and schedule advancement. It validates:

- every brigade id exists and appears in at most one pending/released bucket;
- release is due and applied once;
- garrison/source placement data is valid;
- a force-placement receipt accompanies a release before the transition returns.

### AirInsertionTransitions

`AirInsertionTransitions` lives at `scripts/transitions/AirInsertionTransitions.gd` and is the exact
only writer for:

- air insertion pool membership as the transport queue view coordinated with force manifests;
- current and initial lift caps;
- per-game `landed` projection;
- insertion history;
- pending order consumption/reset if retained in this aggregate.

`AirInsertionResolver` computes packet selection and attrition with the existing derived Dice
substream, returning an outcome. `AirInsertionTransitions` applies cap/history/pool effects and
coordinates roster loss/placement through `ForceTransitions`.

If 0044 already owns air-pool membership to guarantee battalion location, keep one physical writer:
`ForceTransitions` applies exact BN movement while `AirInsertionTransitions` owns capacity/history.
The coordinator preflights both and proves their receipts agree. Do not let both controllers remove
pool entries.

## Required equations and checks

- `0 <= current cap <= initial cap` for every known lift class;
- cap decreases exactly by reported insertion losses and never rises;
- sent = landed + lost for each packet;
- every sent BN leaves the waiting pool exactly once;
- lost BN ids match force casualty receipts; landed ids match force placement/transfer receipts;
- `landed` contains unique brigade ids and only brigades with at least one successful landing;
- history chains in resolution order and agrees with the applied packet receipt;
- mobilization pending/released sets are disjoint and placement occurs exactly once.

## Commit sequence

1. **Inventory and characterize.** Register all mobilization/air state writers; pin no-order,
   rejected-order, partial packet, total-loss, first landing, follow-up, and release behavior.
2. **Typed packet/release outcomes.** Add typed request/outcome/receipt Resources around existing
   calculators without moving writes.
3. **Mobilization authority.** Move pending/released mutation and release bookkeeping behind
   `MobilizationTransitions`; coordinate placement with `ForceTransitions`.
4. **Air capacity/history authority.** Move caps, landed projection, and history writes behind
   `AirInsertionTransitions`; add local validation after every packet.
5. **Pool coordination.** Ensure exactly one authority removes BN ids from the air pool and reconcile
   its receipt with roster casualties/landings.
6. **Order-buffer seam.** Route air-insert order consumption/clear through the established order or
   lifecycle authority from plan 0049; until then retain one documented temporary writer.
7. **Role placement.** Move mobilization and air-insertion calculations to `scripts/calc/` only
   after they consume snapshots and return typed outcomes without draining live state. Split the
   current mixed resolvers; preserve `.gd.uid` files and update manifest/path anchors mechanically.
8. **Close the gate.** Remove reinforcement-state legacy writers and prove unauthorized pool, cap,
   history, landed, pending, released, mutable-alias, and wrong-authority mutations fail.

## Tests and validation

Required authority tests under `tests/transitions/`:

- mobilization release once, not before due turn, and no pending/released duplication;
- blocked garrison fallback placement unchanged;
- air packet sent = landed + lost with exact ids;
- cap loss permanent across turns and bounded by initial;
- first landing versus total packet loss;
- follow-up packet locked to existing brigade hex;
- rejected/no-order paths do not consume Dice or mutate state;
- history/landed projections reconcile with force receipts;
- serialize/observation output remains byte-stable for authority-only commits;
- deliberate direct mutation caught by the authority gate.

Verification:

- mobilization and air-insertion GdUnit suites;
- air-insertion headless validator and `red_airborne` multi-turn run;
- IJFS/air-threat integration tests;
- runtime-index, pool-enumeration, census, and cleanup validators;
- full gate with no pin/fixture drift.

## Out of scope

- Air insertion balance from plan 0036.
- New lift classes, recovery/replacement, sortie cadence, or cost mechanics.
- Changing mobilization force structure or release policy.
- Force casualty/placement implementation owned by 0044.
- IJFS threat calculation owned by 0046.

## Risks and stop conditions

- **Two owners for the air pool:** settle this explicitly during preflight. The force authority must
  own BN location truth; the air authority may request/record movement but must not independently
  remove the same ids.
- **Conditional Dice:** preserve derive/draw timing exactly; application must not recalculate losses.
- **Summary drift:** typed receipts should feed existing summaries without changing public keys.
- **Cross-controller partial write:** validate force ids, capacity, target hex, and packet size before
  either controller mutates.
- **Dependency ceiling:** `ReinforcementPhases` has no headroom. Before it names either new authority,
  identify the direct dependency removed in the same commit; if no swap exists, first land a separate
  green application coordinator rather than raising the ceiling.
- Stop if plan 0036 changes packet/cadence semantics first; rebase characterization on that approved
  behavior rather than mixing balance and authority migration.

## Closeout homes

On shipment: `docs/STATUS.md`; `docs/systems/air-insertion/air-insertion.md`; `docs/systems/roc-mobilization/roc-mobilization.md`;
mobilization and phase flow in `docs/systems/turn-engine/turn-engine.md`; force cross-seam pointers where needed;
authority headers and architecture skill; `docs/DECISIONS.md`; plan archived. Owning docs update their
short numbered **State & authority** section with aggregate, authority, operation-specific
outcome/receipt types, and manifest link only.

## Dependencies

Requires 0042, 0044, and 0046; should follow 0047 under the campaign's serial execution rule. Plan
0036 may be implemented before this only if it does not add new unsanctioned mutation paths.
