---
title: "0045: Sealift and fleet mutation authority"
status: "Sketch"
created: "2026-07-26"
---

# Plan 0045: Sealift and fleet mutation authority

## Goal

Make one authority responsible for every hull transition and every persistent sealift queue change:
ready, sent, offloading, returning, destroyed, escort screening/reload, cohorts, and return pipeline.
Remove the current split in which `SealiftResolver` mutates queues, `FiresPhases` books losses, and
`ReinforcementPhases` reprojects `ShipState` afterward.

The result must preserve current ship-count behavior and RNG exactly. This is an architectural
migration, not a fleet rebalance.

## Settled constraints

- `SealiftState` is authoritative for cohorts, return queues, and escort ammunition.
- `ShipState` is the checked fleet projection used by consumers and reports.
- Troop existence and casualty state belong to `ForceTransitions`; hull state belongs here.
- Crossings and offload coordinate force and sealift authorities using exact manifest ids.
- Aggregate ship counts remain valid; do not introduce `IndividualShip` or per-hull readiness.
- `AntishipMagazine` and per-hull escort magazines remain out of scope.
- `ShipState.sent_original` is removed unless a real immutable wave-size fact and consumer are
  defined during factual preflight. It must not remain a tautological alias for survivors.

## Current split

- `SealiftResolver.resolve`, `drain_bn_ids`, `remove_carrier_hulls`,
  `apply_escort_consumption`, and pipeline helpers mutate `SealiftState` directly.
- `FiresPhases.apply_crossing_hull_losses` mutates `ShipState.destroyed` and
  `fleet_surviving_total`, temporarily breaking its conservation equation.
- `ReinforcementPhases.project_sealift_onto_fleet` repairs/recomputes bins and asserts
  `ShipState.validate`.
- `SealiftState.validate` is structural and normally runs only at construction.

The sanctioned result depends on wrapper ordering. A future return between loss booking and
projection can leave an invalid fleet.

## Aggregate and target authority

Add `SealiftTransitions` as the only writer of protected `SealiftState` and runtime `ShipState`
fields. It owns:

- return/reload tick;
- adoption of first-wave/orphan manifests into cohorts;
- follow-on embark hull allocation application;
- sent → offloading cohort transition;
- landed/drowned BN-id drain and hull release;
- carrier and escort hull destruction;
- escort SAM consumption, diversion, refill, and key-set invariants;
- fleet projection and validation before every public return.

`SealiftResolver`, `ShipLoadingModel`, `AntishipCrossing`, and offload calculators compute plans and
losses without mutating protected campaign state. Packing and casualty randomness stay where they are
now; the authority only applies already-computed results.

### Required equations and structural checks

After every authority call:

- every surviving hull is in exactly one of ready, sent, offloading, returning/reloading;
- surviving buckets + destroyed = original fleet total;
- `ShipState` projection equals cohort/pipeline/escort state;
- no cohort hull count, return slot, reload timer, or magazine count is negative;
- escort current ammunition is bounded by max and uses matching key sets;
- a BN id is bound to at most one cohort;
- cohort state is legal and empty cohorts are either freed or absent;
- requested carrier losses cannot be booked against escorts or absent cohorts;
- requested escort losses cannot consume busy/reloading hulls unless that rule is explicitly added
  by a later USER decision.

The current `ShipState.validate` equations remain useful but are insufficient alone; errors should be
reported at the transition that created them, not only during projection.

## Typed plans and receipts

Use job-specific Resources where parameter counts would otherwise exceed budget:

- embark plan: exact hulls and BN ids entering a cohort;
- hull-loss plan: ship type, requested/applied count, source bucket, cause;
- cohort-drain plan: ids and destination/cause;
- escort-ammunition plan: consumed rounds and reload transitions;
- receipt: pre/post bucket totals and affected cohort ids for phase summaries/reconciliation.

Do not pass a generic Dictionary patch. Existing serialized cohort dictionaries may remain during the
first migration, but controller input must validate their full required shape before mutation.

## Commit sequence

1. **Characterize and inventory.** Pin current lifecycle tests across embark, crossing loss,
   offload, return, escort consumption/reload, and no-wave turns. Register all legacy writers in the
   mutation manifest.
2. **Strengthen local validation.** Add unique cohort BN ids, complete escort key sets, current ≤ max,
   legal source-bucket loss checks, and deliberate negative tests. Assert validation at settled wrapper
   exits before changing ownership.
3. **Make calculators return plans.** Separate packing, tick decisions, cohort drain decisions, and
   loss calculations from campaign-state writes while preserving deterministic iteration and Dice
   topology.
4. **Centralize fleet projection.** Move all `ShipState` writes, including builder initialization,
   behind `SealiftTransitions`; remove the temporarily invalid between-loss-and-projection state.
5. **Migrate embark and return.** Authority applies exact hull/BN cohort creation and pipeline ticks.
   Reconcile BN movement receipts with `ForceTransitions` from 0044.
6. **Migrate crossing losses.** Apply carrier/escort destruction to source buckets and fleet totals in
   one checked call, then coordinate drowned manifests with the force authority.
7. **Migrate offload/drain.** Exact landed ids drain cohorts and release hulls through one call.
8. **Migrate escort ammunition.** Consumption/reload/refill becomes authority-only and validates
   magazines after every transition.
9. **Delete misleading state.** Remove `sent_original` and its vacuous invariant unless preflight
   found a real consumer; if retained, initialize once from a true pre-loss wave and never overwrite it
   during projection.
10. **Close the gate.** Remove all sealift/fleet legacy writers and prove unauthorized queue,
    dictionary, and field writes fail.

## Tests and validation

Required coverage:

- ready → sent → offloading → returning → ready conservation;
- carrier loss from a sent cohort and escort loss from the eligible screen;
- loss request larger than eligible bucket fails or returns an explicitly capped receipt according to
  the settled current rule;
- duplicate hull in cohort/pipeline and duplicate BN id across cohorts fail;
- partial offload keeps hulls busy; final drain frees them exactly once;
- zero return time and positive return time;
- escort SAM depletion, threshold diversion, reload, max refill, and invalid key sets;
- JLSF cargo cohorts remain visible and do not enter force census;
- no-wave and empty-pool no-ops change nothing;
- multi-turn deep-pool game preserves deterministic records.

Verification:

- focused sealift, ship, offload, anti-ship, and JLSF suites;
- `tools/validate_ship_data.gd`, `tools/validate_headless_antiship.gd`, deep-pool smoke;
- full gate with no golden or fixture drift;
- authority validator red tests for field and nested-container writes;
- at least one sustained game long enough to complete a full hull cycle.

## Out of scope

- Per-hull `IndividualShip` activation.
- Per-hull escort magazines or Green launcher magazines.
- Lift packing rebalance, transport-weight changes, return-time changes, or ship eligibility changes.
- JLSF behavior/observability work from plans 0030/0031 except preserving its existing transitions.
- Battalion casualty or placement authority except reconciliation with 0044.

## Risks and stop conditions

- **Mixed aggregate transaction:** force ids and hull cohorts move together. Preflight both authorities
  before either writes, and assert both receipts after application.
- **Dictionary aliasing:** many resolver inputs alias arrays inside Resources. Calculators must receive
  read-only snapshots or prove they do not mutate aliases.
- **RNG/iteration drift:** packing order and casualty selection are deterministic contracts. Any
  fixture drift in a pure ownership commit is a bug.
- **Dependency ceilings:** `ReinforcementPhases` is ceilinged. Replace dependencies or extract an
  application coordinator first; never raise its ceiling.
- Stop if the controller must become a generic force+fleet object to complete a transaction; keep
  authorities separate and improve the coordinator contract instead.

## Closeout homes

On shipment: `docs/STATUS.md`; `docs/systems/amphibious-offload.md` for lifecycle/data flow;
`docs/systems/antiship-mine.md` for crossing-loss application; `docs/systems/turn-engine.md` for
coordination; authority code headers and architecture skill; `docs/DECISIONS.md`; plan archived.

## Dependencies

Requires 0042 and should follow 0044 so troop-manifest reconciliation calls the force authority
rather than another temporary API. Plan 0030 may ship before or after if it remains behavior-free;
plan 0002 should wait until this aggregate boundary is stable.
