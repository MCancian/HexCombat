---
title: "0039: One truth about where a battalion is"
status: "Sketch"
created: "2026-07-25"
---

# Plan 0039: One truth about where a battalion is

**This is the highest-value risk buydown available in the codebase.** Two bug families have already
come out of this seam, both silent, both in Red's favour, both found by looking rather than by any
gate. The current defence is two tripwires that detect the damage after the fact.

## The problem

A battalion's location is asserted in **three independent places** that must agree, and nothing makes
them agree:

| Truth | Where | Says |
|---|---|---|
| Roster | `Brigade.composition` (`Array[Battalion]`, each `{type, qty}`) | this battalion EXISTS |
| Off-map | `ship_reserve`, `SealiftState.mainland_pool`, `AirInsertionState.pool` | this battalion is NOT on Taiwan |
| On-map | `Brigade.hex_id` + `GameData.brigades_by_hex` | this BRIGADE is at this hex |

"Ashore" is not stored anywhere. It is **derived by subtraction** —
`Brigade.landed_qty()` = `composition.qty(type)` − `pool_count(brigade, type)` — and that subtraction
is only correct if the two sides were maintained in lockstep by whoever last edited them.

`composition` is shrunk by four independent paths (`apply_casualty`,
`apply_crossing_casualties`, air-insertion losses, `IjfsResolver.apply_maneuver_casualties`); the pools
are drained by three more. Each pairing is correct today for its own reason, documented one by one in
plan 0037. That is seven paths held consistent by seven separate arguments.

### What it has already cost

- **Ghost landing** (2026-07-24, `bff4a1c`): drowned crossing battalions were removed from the pool
  but not the roster, so dead battalions counted as ashore. Flip threshold inflated 30–60×.
- **Mainland pool** (2026-07-25, `5f79317`): `SealiftResolver._embark_followon` drains a pool entry
  **partially**, so a brigade could be ashore with battalions still on the mainland — and the census
  never subtracted that pool. Red's `scenario_default` turn-20 census ran 57 where it should have run
  49. **The full gate was green before and after.**
- **Landed-only combat** (2026-07-25, plan 0037): the same latent split meant a brigade with 4 of 8
  battalions ashore *fought* with 8, and *ate* for 8.

Every study measured before 2026-07-25 over-states Red because of these.

### What guards it now

- `TurnConductor.pending_pool_roster_violations` (`:915`) — end-of-turn, debug builds only.
- `GameData.validate_runtime_indexes` (`GameData.gd:805`) — end-of-turn, debug builds only.
- `tools/validate_pool_enumeration.gd` — catches a pool missing from the *enumeration*, not a pool
  that disagrees with the roster.

All three are **detectors**. None is a preventer. They fire after a turn has already resolved wrongly.

## The rule this should become

A battalion instance has **exactly one location**, and asking for it is a lookup, not an arithmetic
reconciliation. Concretely: `composition` stops being `{type, qty}` counts and becomes a roster of
battalion instances each carrying `location` (ASHORE / AT_SEA / MAINLAND / AWAITING_LIFT / DEAD), or
equivalently the pools stop holding copies and hold references into the roster.

Then:
- "landed" is a filter, not a subtraction, and cannot go negative or disagree.
- A casualty sets one field. It cannot desync a pool, because there is no second list.
- A new off-map mechanic adds an enum value, not a pool that someone must remember to enumerate.
- The two tripwires become assertions of something structurally impossible, and can be deleted or
  demoted.

## Why this is big, and why it is still worth doing

`{type, qty}` is load-bearing far beyond combat: manifests (`PendingBattalions.instances`), BN ids
that appear in **game records and fixtures**, `OffloadCalculator` weights, `ShipLoadingModel`, the
census, the LLM observation. Battalion ids are a serialized contract — renaming or re-deriving them is
fixture-visible.

So this is **not** a mechanical refactor. It is a data-model change with a serialization boundary, and
it must not be attempted as one commit.

## Suggested sequencing (each step independently gated and byte-stable)

1. **Introduce the instance roster alongside the counts, derived, not authoritative.** Build it at
   scenario load, assert it agrees with `composition` + pools at every turn boundary. Changes nothing;
   proves the model can be constructed and stays consistent for a full 40-turn game.
2. **Move readers over one at a time** — census first (smallest, already centralised), then supply,
   then combat, then the observation. Each is one commit; each must be byte-identical.
3. **Flip authority**: instances become the truth, `composition.qty` becomes a derived view for the
   remaining `{type, qty}` consumers (offload weights, ship loading).
4. **Delete the subtraction path** — `Brigade.landed_qty`, `PendingBattalions.by_brigade_and_type`,
   and the two tripwires, once nothing reads them.

**Stop after step 1 if it does not go green cheaply.** Step 1 alone is worth shipping: it converts an
undetectable desync into a loud one at every turn boundary, which is most of the risk for a fraction of
the work.

## Verification

- Golden byte-stability throughout. **No pin may move at any step.** If one does, the model is not
  equivalent and the step is wrong — revert, do not re-baseline.
- Step 1's consistency assertion must run over a full `scenario_default` 40-turn game AND
  `red_airborne`, not just the golden (the golden has no follow-on pool — that is exactly why it never
  caught the mainland bug).
- Fixture check: `docs/examples/*.json` and any BN id in a game record must be unchanged.
- The four composition-shrinking paths each need a test that the roster and the location agree
  afterwards.

## Design calls for the USER — none expected

Pure internal representation. If a step forces a visible change to BN ids or the observation contract,
**stop and ask** rather than absorbing it.

## Risks

- **Serialization boundary.** BN ids appear in committed fixtures and research records. A change that
  alters them is not byte-stable in the sense that matters.
- **Scope creep into offload/ship-loading.** Those read `{type, qty}` for weight, not location. Leave
  them on the derived view; do not convert them in the same plan.
- **This is the plan most likely to be abandoned halfway.** Hence step 1 being independently valuable.

## Dependencies / notes

- Builds on plans 0034 and 0037, which centralised the subtraction. Do not start this before reading
  both closeouts in `docs/archive/`.
- Prerequisite: **plan 0038** (TurnConductor extraction). Not logical — practical. This plan touches
  `TurnConductor` repeatedly and that file is at its dependency ceiling, so any addition there is
  currently blocked.
