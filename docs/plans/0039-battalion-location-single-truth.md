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

- `RosterMutations.pending_pool_roster_violations` — end-of-turn, debug builds only.
- `GameData.validate_runtime_indexes` (`GameData.gd:805`) — end-of-turn, debug builds only.
- `tools/validate_pool_enumeration.gd` — catches a pool missing from the *enumeration*, not a pool
  that disagrees with the roster.

All three are **detectors**. None is a preventer. They fire after a turn has already resolved wrongly.

## This is not a new pattern — it is the one place the house pattern is missing

Established 2026-07-26 by survey, and it changes what this plan should build.

HexCombat already has a convention for exactly this problem: **a model Resource owns every bucket its
quantity can occupy, and carries a `validate()` conservation invariant that is asserted at construction
and after mutation.** It is live in four places:

| Model | Invariant | Asserted at |
|---|---|---|
| `ShipState` | `ready + surviving_sent + offloading + returning + destroyed == fleet_total` | `FleetBuilder.gd:27`, `ReinforcementPhases.gd:106`, `tools/validate_ship_data.gd` |
| `SealiftState` | `validate()` | `SealiftStateBuilder.gd:39` |
| `AirInsertionState` | `validate()` | `AirInsertionStateBuilder.gd:75`, `tools/validate_headless_antiship.gd` |
| `InfrastructureState` | `validate()` | `tests/infrastructure_resolver_test.gd` |

**`ShipState` is the model case, and it is still COUNTS, not instances.** A hull is not an object with a
location field; it is a tally in one of five buckets. That works — and battalions do not — for one
reason: every bucket lives in ONE object with a known total, so conservation is checkable in a single
place. A battalion's buckets are spread across three modules (`Brigade.composition`,
`SealiftState.mainland_pool`, `AirInsertionState.pool`) with no owning object and no total, so **no
single object is in a position to validate it.** That is why battalions get end-of-turn tripwires and
ships get a constructor assert.

Two consequences for this plan:

- **The instance roster in "The rule this should become" is not required by the evidence.** It is one way
  to get a checkable invariant; owning the buckets is another, and it is the one this codebase already
  uses and tests. Instances buy per-battalion identity, which matters only if something needs to name an
  individual battalion — and the BN ids that appear in fixtures are a *serialization* concern the counts
  model already satisfies. Do not adopt instances just because they sound more correct.
- **Other entities do not need this work.** A hex has a single `owner` field (`HexState.gd:8`) and cannot
  disagree with itself. `GameData.brigades_by_hex` is a derived *index* over one authoritative source
  (`Brigade.hex_id`), already funnelled through one mutator and guarded by `validate_runtime_indexes` —
  a cache-coherency problem, not a competing truth. Generalising this plan to them would be ceremony with
  no bug behind it. (The broader survey is a separate exercise; this plan stays about battalions.)

## The rule this should become

**Every battalion is in exactly one place, one object knows all the places, and that object can prove
nothing has been lost.** Asking where a battalion is becomes a lookup against that object rather than an
arithmetic reconciliation between modules that do not know about each other.

Then:
- "landed" is a lookup, not a subtraction, and cannot go negative or disagree.
- A casualty moves a battalion between buckets in one object. It cannot desync a pool, because the pool
  is a bucket in the same object, and the move is conservation-checked.
- A new off-map mechanic adds a bucket to that object — and the conservation check fails immediately if
  the bucket is not accounted for, rather than requiring someone to remember to enumerate it.
- The two tripwires become assertions of something structurally impossible, and can be deleted or
  demoted.

**Two representations satisfy this rule**, and the plan deliberately does not pre-commit to the larger
one:

1. **Counts in one owning object with a conservation invariant** — what `ShipState` does. Smaller, and
   the pattern the gate and the tests already understand. **Start here (step 1).**
2. **A roster of battalion instances each carrying a `location` enum** (ASHORE / AT_SEA / MAINLAND /
   AWAITING_LIFT / DEAD), or pools holding references into that roster. Strictly more expressive; buys
   per-battalion identity. Adopt **only** if a concrete need for identity appears, and record what it was.

Option 2 was this plan's original single proposal. It is retained as the escalation path, not the
default, because nothing measured so far requires identity — and it is a data-model change with a
serialization boundary, which is the most expensive kind of change available here.

## Why this is big, and why it is still worth doing

`{type, qty}` is load-bearing far beyond combat: manifests (`PendingBattalions.instances`), BN ids
that appear in **game records and fixtures**, `OffloadCalculator` weights, `ShipLoadingModel`, the
census, the LLM observation. Battalion ids are a serialized contract — renaming or re-deriving them is
fixture-visible.

So this is **not** a mechanical refactor. It is a data-model change with a serialization boundary, and
it must not be attempted as one commit.

## Suggested sequencing (each step independently gated and byte-stable)

1. **Give battalions the `ShipState` treatment: one object that owns every bucket, with a conservation
   `validate()`.** A `BattalionLedger` (name it what you like) per brigade holding
   `ashore / at_sea / mainland / awaiting_lift / dead` counts per battalion type, whose `validate()`
   asserts they sum to the scenario's establishment for that brigade. Built at scenario load,
   `validate()` asserted there and after each of the seven mutating paths — **not only at the turn
   boundary**. That is the whole difference between the current tripwires and a real invariant: ships
   catch a bad projection at the moment it happens (`ReinforcementPhases.gd:106`), battalions currently
   discover it a whole turn later, after it has already changed a result.

   Derived and non-authoritative at this step — `composition` and the pools stay the truth, the ledger
   is rebuilt from them and merely has to agree. Changes no behaviour; proves the model constructs and
   survives a full 40-turn game.

   **This step is deliberately smaller than the earlier draft of this plan**, which proposed a parallel
   roster of battalion *instances*. Instances are a bigger change that buys per-battalion identity this
   codebase has not been shown to need. Counts-plus-conservation is what `ShipState` does, what the gate
   already knows how to check, and enough to make the desync impossible to hide. If a later step proves
   identity is genuinely required, escalate to instances then, with the reason recorded.
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
- **Step 1 must be seen to fail.** A conservation invariant nobody has watched go red proves nothing —
  the lesson from plan 0040, where a check that looked correct silently missed two write shapes until it
  was deliberately broken. Re-introduce each of the two historical bugs against the new ledger and
  confirm it fires: the ghost landing (drain the pool, leave the roster) and the mainland partial drain
  (`SealiftResolver._embark_followon`). Both are in `git log` — `bff4a1c` and `5f79317` — so the exact
  shape is recoverable rather than guessed.
- Step 1 asserts at construction and after each mutating path, following `ShipState`. If that proves too
  noisy in the hot path, fall back to turn-boundary **plus** the mutators that historically broke it —
  not to turn-boundary alone, which is what already exists and is what failed.
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
- **Dependency ceilings at steps 2-3** — see the measured table under Dependencies. Every ceilinged file
  is at zero headroom and the ceiling may not be raised to fit this work.
- **Over-building on the strength of the diagnosis.** The problem statement below is vivid and true, and
  the temptation is to conclude that the biggest available fix is the right one. Step 1 is a conservation
  invariant on counts, in an unceilinged file, that makes the failure loud at the moment it happens.
  Ships have run on exactly that for the whole project. Reach for instances only against a stated need.

## Dependencies / notes

- Builds on plans 0034 and 0037, which centralised the subtraction. Do not start this before reading
  both closeouts in `docs/archive/`.
- Prerequisite **plan 0038 is DONE (2026-07-25)** — but the reason recorded here for needing it was
  wrong, and the correction matters before anyone starts.

  **Measured 2026-07-26, after 0038 and 0040 shipped:**

  | File | ndeps | ceiling | headroom |
  |---|---|---|---|
  | `scripts/resolvers/TurnConductor.gd` | 20 | 20 | **0** |
  | `scripts/GameState.gd` | 28 | 28 | **0** |
  | `scripts/resolvers/ReinforcementPhases.gd` | 22 | 22 | **0** |
  | `scripts/resolvers/FiresPhases.gd` | 14 | 14 | **0** |
  | `scripts/resolvers/TurnClosure.gd` | 7 | 7 | **0** |

  This plan said 0038 would give it "room to work in that file". **It did not, and could not.** The
  ceiling policy in `tools/gd_metrics.py` sets each ceiling to the measured count at the commit that set
  it, so an extraction that removes deps also lowers the bar behind itself. Every ceilinged file now sits
  at exactly zero headroom, and raising a ceiling to admit a change is explicitly forbidden. Plan 0038's
  own retrospective flagged this shape: *"a per-commit ceiling rule can make a two-part change
  unsplittable."*

  **Why this is a correction and not a blocker:** step 1 as now written does not belong in
  `TurnConductor` at all. Its home is `scripts/resolvers/RosterMutations.gd` — **ndeps 4, no ceiling
  entry**, and already the owner of `pending_pool_roster_violations`, the very tripwire step 1 upgrades
  into a real invariant. Step 1 is therefore buildable today without touching a ceilinged file's dep
  count.

  The ceiling bites at **steps 2-3**, where readers move over and authority flips — which is also where
  this plan is least certain, and where its own "stop after step 1" guidance already points. Budget for
  it there: either a phase module absorbs the new dep, or the extraction that pays for it is a separate,
  prior commit. Do not discover this mid-step.
- **Still unreviewed.** Status is `Sketch` and no independent model has read it. Per the standing USER
  instruction, it gets a plan-review round before any code — and note that this plan is exactly the kind
  (a premise about the current tree) that review has caught before.
