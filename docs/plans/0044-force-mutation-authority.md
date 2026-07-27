---
title: "0044: Force mutation authority"
status: "In progress"
created: "2026-07-26"
---

# Plan 0044: Force mutation authority for brigades and battalions

## Goal

Give brigade placement, brigade lifecycle, battalion casualties, and battalion location transfers one
sanctioned mutation API. Eliminate the seven-path convention that currently keeps
`Brigade.composition`, off-map manifests, `Brigade.hex_id`, and `GameData.brigades_by_hex` aligned.

This plan supersedes plan 0039. It does **not** begin with a derived `BattalionLedger`: rebuilding a
ledger from roster and pools cannot detect a pool that shrank while the roster did not—it merely
labels the unexplained battalion “ashore.” The first useful invariant is the intended transition's
exact delta, applied and checked by one authority.

## Settled constraints

- The brigade remains the atomic on-map unit. Battalions are not independently positioned on hexes.
- Counts remain the core combat representation; do not introduce persistent battalion instances
  solely because transport manifests have ids.
- Existing per-game BN ids and JSON output remain byte-stable during the authority migration.
- Only landed battalions fight, consume DOS, and count in the observation/census.
- A zero-ashore brigade's territorial-control behavior is unchanged; that remains a separate USER
  mechanic call.
- All force mutations go through one authority, including IJFS maneuver casualties, ground combat,
  crossing losses, air-insertion losses, embark/offload transfers, mobilization placement, movement,
  retreat, and destruction/removal.

## Aggregate boundary

The **force aggregate** includes the facts that must agree for one formation:

- `Brigade.composition`: surviving battalion counts by type;
- brigade lifecycle flags, organization, team, and runtime placement;
- `GameData.brigades_by_hex`: projection of brigade placement;
- troop entries in `ship_reserve`, `SealiftState.mainland_pool`, and `AirInsertionState.pool`;
- troop BN ids bound to sealift cohorts;
- mobilization pending/released placement state where a brigade crosses onto the map.

Fleet hull counts, lift caps, infrastructure/JLSF pseudo-cargo, and IJFS target flags remain separate
aggregates. Their controllers participate in cross-aggregate transitions but do not write force
state.

## Target authority

Add `ForceTransitions` at `scripts/transitions/ForceTransitions.gd` as a pure `RefCounted`
authority with explicit access to the runtime force state and required indexes. It is the exact and
only production writer for protected Brigade fields and troop manifest membership; directory
co-location grants no other authority permission.

The API should be operation-shaped, not a generic patch function:

- `place_brigade` / `move_brigade` / `remove_brigade_from_map`;
- `apply_battalion_casualties` with cause and expected source location;
- `transfer_battalions` between named locations without changing the surviving roster;
- `release_mobilized_brigade`;
- `apply_activity` and `apply_organization_change`;
- `validate_force_state` at settled boundaries.

Exact signatures must stay within the parameter budget by using typed request/context Resources. A
request identifies brigade, battalion type or manifest ids, source, destination, cause, turn/phase,
and expected counts. Typed operation-specific receipts report exactly what changed and are suitable
for summaries and future narratives; do not force unrelated operations into one optional-field-heavy
`ForceTransitionReceipt` merely for naming uniformity.

### Location vocabulary

Use a closed typed vocabulary for transition requests, even if storage remains in existing arrays:

- mainland;
- at sea / offloading;
- awaiting air insertion;
- ashore at a brigade hex;
- mobilizing;
- dead.

Do not expose these as hand-typed strings at call sites. JLSF pseudo-BNs are cargo, not force, and
must not enter this vocabulary accidentally.

### Authority without immediate storage rewrite

The first migration may leave `Brigade` objects in `GameData` and manifests in `GameStateData`.
Authority means one write path, not necessarily one physical Resource. Once every caller goes through
`ForceTransitions`, a later storage move can happen behind that API if measurements justify it.
Do not combine runtime-state relocation with the mutation migration.

Post-0052 clarification: typed **request/receipt** Resources belong in this plan, but typed
`ship_reserve` **storage** does not. Keep the existing dictionary arrays byte-stable while write paths
move behind `ForceTransitions`; a physical storage rewrite waits until after the 0044–0050 authority
campaign unless a later plan explicitly re-sequences it.

## Required transition contracts

### Casualty while ashore

- roster decreases by the exact requested type counts;
- no off-map pool changes;
- brigade is marked destroyed and removed from the map iff no surviving battalions remain;
- IJFS target synchronization consumes the receipt rather than independently guessing the change.

### Crossing casualty

For every lost BN id:

- it existed exactly once in the crossing reserve and exactly once in a sent cohort;
- its matching roster type decreases exactly once;
- it disappears from reserve and cohort;
- no unrelated BN id or roster type changes.

This must catch the historical ghost-landing shape immediately.

### Air-insertion casualty

- every sent BN leaves the air pool;
- survivors become ashore; losses decrease the matching roster types;
- lift-cap loss remains the air-insertion authority's companion transition and is reconciled by the
  phase coordinator;
- first placement occurs only if at least one BN lands.

### Embark and offload

- embark moves exact ids mainland → reserve + sent cohort, with no roster change;
- offload moves exact ids reserve + cohort → ashore, with no roster change;
- partial movement is valid and proven by id-set equality;
- a new pool/location cannot be introduced without extending the closed vocabulary and authority
  validation.

### Brigade movement and retreat

- `Brigade.hex_id` and `brigades_by_hex` change in one call;
- old and new index buckets reconcile bidirectionally before return;
- movement/organization/activity flags are applied through the same authority or a tightly scoped
  force-activity sub-authority, never direct writes in `TurnConductor`.

## Implementation progress

- First enforced slice is live: `ForceTransitions` owns protected Brigade runtime fields and
  `Battalion.qty` roster decrements via typed location/cause/request/receipt Resources. Production
  placement, movement/activity, ground-combat casualty, IJFS maneuver casualty, crossing roster loss,
  air-insertion casualty, retreat, cleanup-latch, and next-turn flag reset call the authority.
- `RosterMutations` remains temporarily as a compatibility façade plus the pool/roster tripwire; it
  no longer writes protected roster fields itself.
- Transport manifest storage (`ship_reserve`, `SealiftState.mainland_pool`, `AirInsertionState.pool`)
  remains dictionary-shaped and is not yet registered as protected storage. `GameData.brigades_by_hex`
  is mutated by the authority but not yet source-gated because the current scanner treats hosted
  owner paths too broadly for `GameData.gd`; closeout still requires that gap to be closed.
- No legacy writers remain for the protected first slice; the DOS-consumption validator now marks
  movement through the same authority façade as production movement.
- Remaining 0044 work includes deciding where `ForcePlacementReceipt` / casualty / activity receipts
  are consumed. The current `GameData` façades preserve legacy void surfaces, so receipts mostly prove
  transitions in tests; before closeout, thread them into summaries/narratives or record an explicit
  reason they remain internal-only.

## Commit sequence

1. **Characterize every writer.** Build a source inventory and tests for the historical crossing
   bug, mainland partial embark, air loss, ground casualty, IJFS casualty, movement, retreat, and
   mobilization release. Update the plan-0042 manifest with every temporary writer.
2. **Typed transition vocabulary and requests.** Add location/cause types and force transition
   request/receipt Resources without changing live writes. Import class cache and keep fixtures stable.
3. **Brigade placement first.** Move `set_brigade_hex`, removal, movement, retreat, and mobilization
   placement behind `ForceTransitions`; preserve `GameData` read helpers as delegating façades if
   external callers require them.
4. **Casualty authority.** Replace `RosterMutations.apply_casualty` and IJFS's independent
   composition mutation with one typed casualty application. Keep source-specific calculators pure.
5. **Crossing transaction.** Apply roster/reserve/cohort loss as one checked operation coordinated
   with the sealift authority if 0045 is not yet shipped. Add deliberate one-side-omitted red tests.
6. **Embark/offload transfer authority.** Route exact manifest moves through the API; prove roster
   stability and id-set equality. The troop side of `OffloadCalculator` purity work starts here only
   after `ForceTransitions` can receive and validate the resulting manifest plan.
7. **Air insertion and mobilization.** Route pool, casualty, placement, landed/released projections,
   and corresponding receipts through the force authority while preserving Dice order.
8. **Activity and organization.** Move remaining direct Brigade runtime writes behind the authority.
9. **Readers and backstops.** Keep `Brigade.landed_qty` and pending-pool enumeration as projections
   until all transfers are authoritative. Demote/delete old tripwires only after equivalent
   authority checks have been seen red.
10. **Role placement.** Move force calculators/query helpers to `scripts/calc/` only after they no
    longer mutate protected state. `OffloadCalculator` stays outside `scripts/calc/` until its
    `offload_progress_tons` and manifest-membership mutations have moved behind authorities. Replace
    `RosterMutations` with `ForceTransitions`; do not preserve
    it as a second authority. Keep the pending-pool tripwire as an independent query/backstop, either
    private to the authority or in a clearly read-only calculator. Move `.gd.uid` files with scripts
    and update manifest/path anchors in the same mechanical commit.
11. **Close the gate.** Remove every force legacy-writer exception and prove direct writes, model
    mutator bypasses, `GameState` façade setters, and writes from a wrong transitions file fail.

Each numbered migration is its own commit and must be golden/fixture byte-stable. Do not migrate two
transition families in one commit.

## Tests and validation

Dedicated authority suites under `tests/transitions/` must cover:

- all four casualty producers with typed causes;
- both historical bugs reintroduced one side at a time and caught before the wrapper returns;
- partial mainland embark and partial offload;
- duplicate, missing, and wrong-type BN ids fail loud;
- map placement/index forward and reverse consistency after move, retreat, arrival, and destruction;
- zero-survivor destruction versus zero-ashore-but-surviving behavior;
- JLSF pseudo entries ignored by force validation;
- default, sustained follow-on, and `red_airborne` scenarios for enough turns to exercise every
  location;
- committed BN ids and observation fixtures unchanged.

Verification after every commit:

- relevant focused suite twice;
- `tools/validate_runtime_indexes.gd`, `tools/validate_pool_enumeration.gd`, census/cleanup validators;
- canonical full gate with no pin movement;
- authority validator negative mutation for the migrated writer.

A full 40-turn `scenario_default` and a `red_airborne` run are required before closeout. The golden
fixture alone does not exercise mainland follow-on or air insertion.

## Out of scope

- Persistent battalion instance identities or per-BN on-map positions.
- Changing combat, census, supply, zero-ashore ownership, or transport priority rules.
- Moving all mutable Brigade storage out of `GameData`.
- Fleet hull, lift-cap, infrastructure, or IJFS target-state authority except at explicit
  cross-aggregate coordinator seams.
- Serialization format changes.

## Risks and stop conditions

- **Cross-aggregate partial mutation:** preflight all ids/counts before the first write; stop if a
  proposed ordering can fail after one aggregate has changed.
- **Ceiling pressure:** `TurnConductor`, `FiresPhases`, and `ReinforcementPhases` have no headroom.
  Controller calls must replace existing dependencies or use a prior extraction; never raise a
  ceiling to fit.
- **JLSF shape collision:** structural pool scanners see JLSF pseudo entries. Force authority must
  distinguish cargo explicitly, not by unknown-brigade fallback.
- **Identity churn:** if a step changes manifest ids, stop and redesign rather than re-baseline.
- **God controller growth:** split read/query helpers from mutation only if metrics require it; do not
  split writers by phase and recreate multiple authorities.

## Closeout homes

On shipment: current behavior in `docs/STATUS.md`; combat/landed facts in
`docs/systems/ground-combat.md`; arrival flows in `docs/systems/amphibious-offload.md` and
`docs/systems/air-insertion.md`; census in `docs/systems/frontline-cleanup-victory.md`; phase wiring
in `docs/systems/turn-engine.md`; controller boundary in code headers and architecture skill;
`docs/DECISIONS.md`; plan archived. Each owning systems doc gains/updates the short numbered **State
& authority** section (aggregate, authority, outcome/receipt types, manifest link only); exhaustive
protected fields and writer lists remain solely in the manifest.

## Dependencies

Requires 0042 and should follow the 0043 pilot. It supersedes plan 0039. Plan 0033 (brigade
organization) should not add more direct Brigade writers before this ships; plan 0036 may change data
or balance independently but any new air-insertion mutation must use this authority.
