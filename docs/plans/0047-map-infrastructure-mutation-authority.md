---
title: "0047: Map and infrastructure mutation authority"
status: "Sketch"
created: "2026-07-26"
---

# Plan 0047: Map and infrastructure mutation authority

## Goal

Give hex ownership, FEBA, and infrastructure/JLSF lifecycle state explicit mutation authorities.
Remove direct `HexState` and nested `InfrastructureState.nodes` writes while preserving sticky
territorial ownership, seizure persistence, repair timing, and all current combat/offload behavior.

## Settled behavior — do not change here

- Empty hexes keep their previous owner.
- Brigade presence, not landed battalion count, currently determines occupied/contested ownership.
  Changing zero-ashore control is a separate USER mechanic decision.
- Infrastructure seizure persists after Red moves inland; operational contribution is gated by
  current ownership at read time.
- JLSF repair requires existing arrival/ownership rules and current stage timing.
- FEBA math, retreat threshold, and ownership recompute order remain unchanged.
- Hex definitions/geometry/terrain are immutable content; only `HexState` is runtime state.

## Aggregate boundaries

### MapTransitions

`MapTransitions` lives at `scripts/transitions/MapTransitions.gd` and is the exact only writer for:

- `HexState.owner`;
- `HexState.feba_km`;
- reset of runtime hex state;
- bulk ownership recomputation from an explicit occupancy snapshot;
- explicit scenario/test overrides through a clearly named API.

It does not move brigades; `ForceTransitions` supplies placement receipts or an occupancy projection.

### InfrastructureTransitions

`InfrastructureTransitions` lives at `scripts/transitions/InfrastructureTransitions.gd` and is the
exact only writer for:

- node status;
- repair timer;
- JLSF queued/enroute/arrived/none lifecycle;
- scenario reset/build initialization.

`InfrastructureResolver` becomes a calculator of seizure/repair transition plans from current node
snapshots and owner-by-hex input. JLSF cargo movement remains coordinated with force/sealift
controllers; this authority applies only node lifecycle effects.

Keep map and infrastructure as separate authorities. `ReinforcementPhases` or a smaller application
coordinator may call both because ownership feeds infrastructure, but neither authority may mutate the
other aggregate.

## Target APIs

Map operations should be job-shaped:

- apply FEBA delta/result for a combat hex;
- reset FEBA according to current combat/retreat rules;
- recompute ownership from typed/validated occupancy;
- apply explicit owner override with an audited cause;
- reset scenario runtime map state.

Infrastructure operations should include:

- apply ownership-driven seizure plan;
- queue JLSF deployment;
- mark cargo enroute/arrived/lost;
- advance repair plan;
- validate legal status/JLSF transitions and timer bounds.

No caller may receive a mutable node Dictionary and edit its keys. Introduce a typed
`InfrastructureNodeState` Resource or controller-owned accessors before strict enforcement; preserving
`to_dict` output shape is required.

## Commit sequence

1. **Inventory and characterize.** Register all `HexState` and infrastructure node writers. Add tests
   for sticky ownership, contested ownership, scenario reset, FEBA accumulation/retreat, seizure,
   recapture gating, JLSF queue/enroute/loss/arrival, and two-stage repair.
2. **Type infrastructure nodes.** Replace nested mutable dictionaries with typed node state behind
   stable `InfrastructureState.to_dict` serialization. Builders validate every definition/state key.
3. **Infrastructure authority.** Move queueing, cargo marker changes, seizure, repair, and reset behind
   `InfrastructureTransitions`; assert `InfrastructureState.validate` after every applied transition.
4. **Pure infrastructure plans.** Make `InfrastructureResolver` return transition plans and throughput
   projections without writing protected state.
5. **Map authority.** Move owner override, FEBA writes, reset, and ownership recomputation behind
   `MapTransitions`; retain `GameData` methods only as read/query façades or remove them after callers
   migrate.
6. **Force/map coordination.** Feed placement receipts or a read-only occupancy snapshot from
   `ForceTransitions`; prove map recomputation never repairs a stale brigade index implicitly.
7. **Infrastructure/map coordination.** Apply ownership before seizure/throughput at the existing turn
   seam and preserve current one-turn producer/consumer timing.
8. **Role placement.** Move ownership/FEBA and infrastructure planning logic into `scripts/calc/`
   only after it accepts snapshots and returns plans without live protected aliases. Split
   `InfrastructureResolver`, `JlsfCargo`, and mutable `GameData` helpers by effect rather than moving
   them by name. Preserve script UIDs and update manifest/path anchors mechanically.
9. **Close the gate.** Remove legacy writers and prove direct owner, FEBA, node-status, timer, JLSF,
   `GameData` façade/helper bypass, mutable-query-alias, and wrong-authority assignments fail.

## Tests and validation

Required authority tests under `tests/transitions/`:

- RED/GREEN/CONTESTED recomputation and sticky empty ownership;
- explicit owner override validation and unknown owner rejection;
- FEBA positive/negative accumulation and unchanged retreat outcomes;
- reset across multiple games in one process;
- infrastructure legal transition matrix, illegal regressions, and negative timers;
- ownership loss pauses throughput/repair according to current rules without erasing seizure status;
- JLSF cargo loss returns marker to the correct state and permits redeployment;
- typed-node serialization matches existing fixtures exactly;
- force move/retreat/landing followed by ownership recompute and infrastructure read;
- zero-ashore brigade behavior remains byte-identical.

Verification:

- terrain/hex/runtime-index validators;
- infrastructure and offload suites;
- headless turn, cleanup/victory, and deep-pool smoke;
- full gate with no pin or fixture movement;
- mutation-authority deliberate red tests for direct fields and nested node writes.

## Out of scope

- Changing sticky ownership, zero-ashore territorial control, neutral hex rules, or capture timing.
- Changing port throughput, repair rates, JLSF competition, or graduated suppression (plan 0031).
- Moving brigade placement ownership away from `ForceTransitions`.
- Terrain/geometry data changes.
- Front-line UI work.

## Risks and stop conditions

- **Behavior hidden in timing:** ownership is recomputed at several phase boundaries. Preserve call
  order exactly; an authority does not justify deduplicating recomputations without a separate proof.
- **Typed-node fixture churn:** internal typing must keep serialized key names/order/value types.
- **Cross-controller cycles:** Map reads force occupancy; infrastructure reads map ownership. Neither
  controller may import/call the other. Coordinators pass snapshots/receipts explicitly.
- **GameData role:** mutable hex state currently lives beside static data. Moving storage is optional
  and out of scope; do not combine it with writer migration or describe consolidation as a settled
  architecture end-state. Open a later Sketch only if authority measurements show a concrete problem.
- Stop if plan 0031 begins first and changes node semantics; rebase this plan's transition matrix on
  the USER-approved mechanic before implementation.

## Closeout homes

On shipment: `docs/STATUS.md`; `docs/systems/hex-grid.md`, `terrain.md` only if their runtime-state
claims change, `docs/systems/frontline-cleanup-victory.md`, `docs/systems/amphibious-offload.md`, and
`docs/systems/turn-engine.md`; authority headers and architecture skill; `docs/DECISIONS.md`; plan
archived. Owning docs update their short numbered **State & authority** section with aggregate,
authority, operation-specific outcome/receipt types, and manifest link only. Immutable/view-only docs
state explicitly that they own no protected runtime aggregate instead of inventing an authority.

## Dependencies

Requires 0042 and 0044's force placement API. It should follow 0046 in the campaign's one-aggregate-
at-a-time order. Plan 0031 should wait for this authority unless the USER explicitly prioritizes its
new mechanic first.
