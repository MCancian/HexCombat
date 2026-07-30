---
title: "0045: Sealift and fleet mutation authority"
status: "Active"
created: "2026-07-26"
updated: "2026-07-29"
---

# Plan 0045: Sealift and fleet mutation authority

## Goal

Make one authority responsible for every hull transition and every persistent sealift queue change:
ready, sent, offloading, returning, destroyed, escort screening/reload, cohort hulls, and the return
pipeline. Remove the current split in which `SealiftResolver` mutates queues, `FiresPhases` books
losses, `ForceTransitions` appends return slots, and `ReinforcementPhases` reprojects `ShipState`
afterward.

The result must preserve current ship-count behavior and RNG exactly. This is an architectural
migration, not a fleet rebalance.

## Settled constraints

- `SealiftState` is authoritative for cohorts, return queues, and escort ammunition.
- `ShipState` is the checked fleet projection used by consumers and reports.
- Troop existence and casualty state belong to `ForceTransitions`; hull state belongs here.
- Crossings and offload coordinate force and sealift authorities using exact manifest ids.
- Aggregate ship counts remain valid; do not introduce `IndividualShip` or per-hull readiness.
- `AntishipMagazine` and per-hull escort magazines remain out of scope.
- `ShipState.sent_original` is removed — preflight found no consumer (see D5).

## Preflight: what 0044 already moved, and what is actually left

Plan 0044 shipped first, so the starting position is NOT the one the sketch described. Measured on
`90c85b0`:

Already routed through `ForceTransitions` (troop-side, correct there):
`apply_embark`, `apply_sent_cohort`, `apply_crossing_loss`, `apply_offload`, `apply_queue_jlsf`,
`free_emptied_cohorts`, `apply_sent_to_offloading`. `SealiftResolver.drain_bn_ids` no longer exists.
`SealiftResolver` already returns typed force plans instead of writing `mainland_pool` / `cohorts`.

The complete remaining writer inventory of hull state — every one of these is retired by this plan:

| # | Site | Writes |
|---|---|---|
| 1 | `scripts/builders/FleetBuilder.gd:19-26` | fresh `ShipState` (construction) |
| 2 | `tools/validate_ship_data.gd:100-109` | hand-built `ShipState` duplicating FleetBuilder's arithmetic |
| 3 | `scripts/phases/ReinforcementPhases.gd:109-113` | `ShipState` projection (`surviving_sent/sent_original/offloading/returning/ready`) |
| 4 | `scripts/phases/FiresPhases.gd:175-176` | `ship_state.destroyed +=`, `fleet_surviving_total -=` |
| 5 | `scripts/GameState.gd:339` | `data.fleet = GameStateBuilder.build_fleet(...)` (scenario reset) |
| 6 | `scripts/resolvers/SealiftResolver.gd:119,123` | `return_pipeline` tick |
| 7 | `scripts/resolvers/SealiftResolver.gd:243,251` | `escort_sam`, `escort_reload` (consumption/divert) |
| 8 | `scripts/resolvers/SealiftResolver.gd:261,264,266` | `escort_sam`, `escort_reload` (reload tick/refill) |
| 9 | `scripts/resolvers/SealiftResolver.gd:297` | cohort `hulls_by_type` decrement (`remove_carrier_hulls`) |
| 10 | `scripts/resolvers/SealiftResolver.gd:303-306` | cohort `state` flip (`flip_sent_to_offloading`) — **dead in production**, only `tests/sealift_resolver_test.gd:264` calls it |
| 11 | `scripts/transitions/ForceTransitions.gd:493-498` | `return_pipeline` slot append inside `free_emptied_cohorts` |
| 12 | `scripts/transitions/ForceTransitions.gd:401` | cohort `state` flip (`apply_sent_to_offloading`) |
| 13 | `scripts/builders/SealiftStateBuilder.gd:36-38` | `escort_sam` / `_max` / `_threshold` (construction) |
| 14 | `scripts/builders/SealiftStateBuilder.gd:53-57` | hull-less offloading cohort for the unopposed-offload façade (construction) |

Consumers of the projection are few, which is what makes the migration cheap:
`ReinforcementPhases.resolve_sealift_turn` reads `.ready`; `FiresPhases.apply_crossing_hull_losses`
and `project_sealift_onto_fleet` read `.fleet_surviving_total`;
`tools/validate_headless_antiship.gd:68` iterates `GameState.fleet`. Nothing serializes `ShipState`,
so the fleet projection is NOT part of any golden/observation fixture. `SealiftState.to_dict()` IS a
fixture contract (key order and value types).

## Design decisions

### D1 — the `cohorts` ownership split, and why cohorts become typed

`SealiftState.cohorts` is one field holding untyped dictionaries that mix two aggregates' facts:
`bn_ids` (troops — force) with `hulls_by_type` + `state` (hulls — sealift).
`tools/validate_mutation_authority.gd` fails `E_DUPLICATE_CLAIM` if two aggregates claim one field
(the check is on the merged `protected` map, not per section — validator:250-254), so `cohorts` cannot
be claimed by both. Today it is claimed by `force`, and the hull facts inside each dictionary are in
the validator's documented blind spot (an untyped `Dictionary` alias — validator:71-77): nothing stops
any file writing them.

**Decision: make a cohort a typed Resource `SealiftCohort` and register its fields to the two
aggregates separately** (`hulls_by_type`, `state` → `sealift_fleet`; `bn_ids` → `force`), as
`hosted_fields` on both sides. `hosted_fields` exists for exactly this ("fields this aggregate owns on
a model SHARED with other aggregates" — the precedent is `GameStateData`, shared by antiship and
force), and `E_UNCLASSIFIED_FIELD` only applies to `owned_models`, so a split registration is legal.

This is the harder up-front option and it is the one worth paying for: `SealiftState.cohorts` becomes
`Array[SealiftCohort]`, which the validator's element-type rule resolves
(`for cohort in state.cohorts` where the declaration is `Array[T]` — validator:26-29), so cohort hull
writes AND cohort `bn_ids` writes both become gate-visible everywhere in `scripts/` and `tools/`. The
alternative (keep dictionaries, hold the hull side by convention) leaves the plan's central ownership
claim unenforceable and silently weakens 0044's boundary too.

Serialization is the risk and the acceptance test: `SealiftState.to_dict()` currently does
`cohorts.duplicate(true)`, which on Resources would serialize as object references. It becomes an
explicit per-cohort `to_dict()` emitting the SAME key order `{hulls_by_type, bn_ids, state}`. Golden
byte-stability is the proof.

Cohort *creation* stays in `ForceTransitions` (it binds ids to hulls in one all-or-nothing
transaction); the hull dictionary it stores comes from a plan the caller obtained from the sealift
side, and construction of a fresh cohort is registered as a construction allowance.

### D2 — builders keep constructing; the authority owns every runtime transition

The sketch said to move builder initialization behind the authority. The house pattern set by
0042-0044 is the opposite and is better: fresh, unpublished state is built by a builder registered as
a `construction_writer` with a `why` (`SealiftStateBuilder`, `AirInsertionStateBuilder`,
`MobilizationStateBuilder` are all registered that way today). `FleetBuilder` and
`SealiftStateBuilder` therefore stay, registered as construction writers. Duplicating their arithmetic
inside `SealiftTransitions` would create the second writer this plan exists to remove.

`GameState.gd:339` is NOT construction of unpublished state — it replaces a live fleet on scenario
reset — so it routes through `SealiftTransitions.rebuild_fleet`, mirroring
`AntishipTransitions.reset_establishment` (writer #5 disappears rather than earning an exemption).

`tools/validate_ship_data.gd` (writer #2) is the third copy of the fresh-fleet arithmetic. It builds
`ShipDef`s from the JSON rows it already parsed and calls `FleetBuilder.build`, then validates the
result: the duplicate arithmetic goes away instead of being registered.

### D3 — the tick moves out of the resolver, so the resolver is mutation-free

`SealiftResolver.resolve` currently ticks the return pipeline and escort reloads as its step 1 because
the released hulls join the local ready pool the embark planner packs against. After the migration the
coordinator ticks first through the authority and passes the result in:

```
ReinforcementPhases.resolve_sealift_turn:
    consume_jlsf_orders(state)                                  # unchanged position
    returned := SealiftTransitions.tick_returns(state.sealift_state)
    SealiftTransitions.tick_escort_reload(state.sealift_state)
    outcome := SealiftResolver.resolve(sealift_state, ship_reserve, ready_by_type, returned, ship_defs)
```

`ready_by_type` is still read from `ShipState.ready` before the call and is unaffected by the tick
(the fleet is only reprojected at the end of the phase), so the local ready pool the packer sees is
byte-identical to today's. The tick calls sit exactly where `SealiftResolver.resolve` used to be
called, so no observable order changes.

### D4 — `free_emptied_cohorts` splits at the aggregate boundary

It is one mixed transaction today: drop drained cohorts (force) + append return slots (sealift). It
becomes `ForceTransitions.free_emptied_cohorts` → returns `freed_by_type` (it already does) and
`SealiftTransitions.release_hulls(sealift_state, freed_by_type, return_time)` appends the pipeline
slots. Both call sites (`FiresPhases.resolve_antiship_turn`, `ReinforcementPhases.resolve_offload_turn`)
chain the two, and both receipts are asserted.

### D5 — `sent_original` is deleted

Preflight found no consumer. It is written to `0` by two builders and assigned `= surviving_sent` by
the projection (`ReinforcementPhases.gd:110`), which makes `ShipState.validate`'s
`sent_original < surviving_sent` check vacuous by construction. Nothing reads it: no serializer, no
report, no UI, no exporter. One test asserts the constructed `0`
(`tests/state_builders_test.gd:96`). It is removed together with its invariant.

### D6 — where the equations live

`ShipState.validate()` keeps its per-hull equations. The cross-cutting equations the sketch lists are
enforced by `SealiftTransitions._validate_fleet(...)`, called before every public return of the
authority, so an error is reported at the transition that created it rather than at the next
projection. Failures `push_error` (never `assert(false)`): a research batch must not die on one bad
row, and a `push_error` guard is testable via `assert_error(...).is_push_error(...)` — the same
rationale as `AntishipTransitions`.

Checked after every authority call:

- every surviving hull is in exactly one of ready, sent, offloading, returning/reloading;
- surviving buckets + destroyed = original fleet total, per ship type;
- the `ShipState` projection equals cohort/pipeline/escort-reload state;
- no cohort hull count, return slot, reload timer, or magazine count is negative;
- escort current ammunition is bounded by max, with matching key sets;
- a BN id is bound to at most one cohort (already enforced force-side; re-checked here);
- cohort state is legal, and a drained cohort is either freed or absent;
- requested carrier losses cannot be booked against escorts or absent cohorts;
- a loss request larger than the eligible bucket is CAPPED, and the receipt reports requested vs
  applied. This preserves today's behavior (`FiresPhases.gd:174`, `remove_carrier_hulls`'s cap) — the
  crossing calculator can legitimately report more kills than the bucket holds. Changing it to a
  refusal is a behavior change and out of scope.

## Review findings (round 1, 2026-07-29)

`agy-explore` was out of quota and `opencode/deepseek-v4-flash-free` flaked (no output in 10 minutes).
`opencode/nemotron-3-ultra-free` returned a substantive review; its findings, judged against the tree:

**Accepted:**

1. **No test pins `SealiftState.to_dict()`.** Verified and worse than reported: `to_dict()` has ZERO
   consumers anywhere — no production call, no fixture, no test, no observation schema. The model header
   claiming it is "the JSON-serialization boundary (golden / observation fixtures)" was simply false.
   D1's "golden byte-stability is the proof" was therefore unprovable. Fixed both ways: the header now
   says what is true, and a test pins the serialized shape so the typed cohorts cannot start emitting
   object references.
2. **`AntishipCrossing` reads `escort_sam`, and the LLM API plus two validators read
   `mainland_pool`.** All read-only, and `AntishipCrossing.gd:268` duplicates the magazine before
   spending it, so no calculator holds a live alias. Recorded here rather than changed.

**Rejected, with evidence:**

3. **"`tests/combat_resolution_test.gd` and `tests/victory_present_census_test.gd` mutate cohorts
   directly, so the gate will fail" (called a blocker, twice).** False: the validator's `scan_roots` are
   `res://scripts` and `res://tools`; `tests/` is deliberately excluded because suites legitimately
   build their own fixture rows (`tools/validate_mutation_authority.gd:82-83`). Both suites are green.
4. **"The conservation check will fire false errors at three mid-turn points" (called a blocker).**
   Wrong as built, for a reason worth writing down: staleness is not invalidity. Between a queue move
   and the phase's closing projection, `ShipState`'s equation
   `ready + surviving_sent + offloading + returning + destroyed = fleet_total` remains TRUE — nothing on
   `ShipState` changed, its bins are merely out of date. The only operation that breaks the equation is
   loss booking, and that one reprojects before returning. The authority therefore never asserts
   "projection equals cohort state" as a strict mid-turn equality, and a later commit must not add it;
   the checks that DO run are staleness-invariant (unknown hull type, magazine bounds and key sets, one
   cohort per BN).

## Commit sequence

Each commit ends with `bash tools/run_all_tests.sh` → ALL PHASES GREEN, no golden or fixture drift.

1. **`SealiftTransitions` + fleet projection and hull losses.** New
   `scripts/transitions/SealiftTransitions.gd` with `rebuild_fleet`, `project_fleet`,
   `apply_hull_losses` (absorbing `FiresPhases.apply_crossing_hull_losses` and
   `SealiftResolver.remove_carrier_hulls`), `_validate_fleet`. Delete
   `ReinforcementPhases.project_sealift_onto_fleet` and repoint its two call sites (this REMOVES a
   dependency from the ceilinged `ReinforcementPhases`; it must not gain one). Drop `sent_original`
   (D5). Refactor `tools/validate_ship_data.gd` onto `FleetBuilder` (D2). Register the `sealift_fleet`
   aggregate: `owned_models` = `ShipState` (every field classified), `hosted_fields` =
   `GameStateData.fleet`, `construction_writers` = `FleetBuilder`. Typed receipt
   `SealiftHullLossReceipt` (requested/applied/source bucket per type).
2. **Pipeline and escort magazine ownership.** Move writers #6-#8 out of `SealiftResolver` into
   `SealiftTransitions.tick_returns` / `tick_escort_reload` / `apply_escort_consumption`; move #11 out
   of `ForceTransitions` into `release_hulls` (D4); thread `returned_by_type` into
   `SealiftResolver.resolve` (D3). Register the five companion `SealiftState` fields and
   `SealiftStateBuilder` as a construction writer. `SealiftResolver` now writes no campaign state.
3. **Typed cohorts.** Introduce `SealiftCohort` (D1); `SealiftState.cohorts: Array[SealiftCohort]`;
   `to_dict` emits the same dictionary shape and key order. Move the `sent → offloading` flip (#12,
   and delete the dead #10) into `SealiftTransitions.apply_sent_to_offloading`. Register
   `SealiftCohort.hulls_by_type`/`state` to `sealift_fleet` and `SealiftCohort.bn_ids` to `force`,
   with cohort construction registered where it happens. Update `ForceTransitions`,
   `ForceValidationHelper`, `SealiftResolver`, both phase modules, `SealiftStateBuilder` and the three
   affected suites to field access.
4. **Close the gate and document.** No `legacy_writers` entries for this aggregate at any point — each
   commit above moves its writers rather than registering them. Prove unauthorized writes fail
   (red-test each write form against the new fields). Closeout per the homes below.

Deferred deliberately, and reported as deferred: the sketch's step 10 (relocating `SealiftResolver`
into `scripts/calc/`). Post-migration it is a pure planner and belongs there, but the rename touches
every call site, three suites and the doc anchors for zero behavioral gain; it is a mechanical commit
worth doing only once the ownership work is green, and only if the gate stays green afterwards.

### What actually shipped (2026-07-29)

Three commits, each ending ALL PHASES GREEN with no golden or fixture drift:

1. **Authority + fleet projection + hull losses.** `SealiftTransitions` with `rebuild_fleet`,
   `ready_by_type`, `apply_hull_losses` (absorbing `FiresPhases.apply_crossing_hull_losses` and
   `SealiftResolver.remove_carrier_hulls`, reprojecting before it returns), `project_fleet` and the
   invariant checks. `SealiftHullLossReceipt` records requested/applied/source per type.
   `ReinforcementPhases.project_sealift_onto_fleet` deleted; `sent_original` deleted;
   `GameStateBuilder.build_fleet` deleted as dead; `GameState.fleet` became a read-only façade;
   `tools/validate_ship_data.gd` now proves the fresh-fleet invariant through `FleetBuilder` instead of a
   third copy of the bin arithmetic.
2. **Hull queues.** Pipeline tick, escort consumption/divert and reload tick moved out of
   `SealiftResolver`; the return-slot append moved out of `ForceTransitions.free_emptied_cohorts`, which
   now returns a `SealiftHullReleasePlan` (one batch per freed cohort, so slot granularity is unchanged)
   and no longer takes the scenario's return time. `SealiftResolver.resolve` takes `returned_by_type` and
   writes no campaign state at all.
3. **Typed cohorts.** `SealiftCohort` with the two-aggregate field split (D1), the sent→offloading flip
   moved to the fleet authority, and `SealiftState.cohorts: Array[SealiftCohort]`.

Ceiling effects, measured: `FiresPhases` 15 → 12 dependencies; `ReinforcementPhases` unchanged at its
ceiling of 22 (it lost `ShipState`, gained `SealiftTransitions`); `GameState` unchanged at 29 — the fleet
rebuild reaches its authority through a `ReinforcementPhases` pass-through, mirroring
`FiresPhases.reset_antiship_establishment`, precisely because a direct call would have breached it.

**The enforcement was red-tested, not assumed.** A temporary probe writing all nine forms
(`cohort.hulls_by_type[k] =`, `cohort.cohort_state =`, `cohort.bn_ids.append`, `ship_state.destroyed +=`,
`ship_state.ready =`, `return_pipeline[k] =`, `escort_sam[k] =`, `escort_reload.erase`, `state.fleet =`)
from a non-authority file produced exactly nine `E_UNAUTHORIZED_WRITE` failures naming file, line and
write form, then was reverted. That is the evidence that the typed-cohort step bought real enforcement
rather than a convention.

## Tests and validation

New `tests/transitions/sealift_transitions_test.gd`:

- ready → sent → offloading → returning → ready conservation across a full cycle;
- carrier loss from a sent cohort and escort loss from the eligible screen;
- a loss request larger than the eligible bucket returns a capped receipt (D6);
- duplicate hull in cohort/pipeline and duplicate BN id across cohorts fail;
- partial offload keeps hulls busy; the final drain frees them exactly once;
- zero return time and positive return time;
- escort SAM depletion, threshold diversion, reload, max refill, and mismatched key sets;
- JLSF cargo cohorts remain visible and do not enter the force census;
- no-wave and empty-pool no-ops change nothing;
- each `_validate_fleet` guard is exercised via `assert_error(...).is_push_error(...)`.

Existing suites that must stay green unmodified except for API renames:
`tests/sealift_resolver_test.gd`, `tests/transitions/force_transitions_test.gd`,
`tests/jlsf_pipeline_test.gd`, `tests/state_builders_test.gd`, `tests/victory_present_census_test.gd`.

Verification: `tools/validate_ship_data.gd`, `tools/validate_headless_antiship.gd`,
`tools/validate_deep_pool_smoke.gd` (the multi-turn full-hull-cycle proof — with `_validate_fleet`
running inside the authority, the deep-pool game becomes a continuous conservation check), the
mutation-authority validator, and the full gate with no golden or fixture drift.

## Out of scope

- Per-hull `IndividualShip` activation.
- Per-hull escort magazines or Green launcher magazines.
- Lift packing rebalance, transport-weight changes, return-time changes, ship eligibility changes.
- Turning the capped loss request into a refusal (D6).
- JLSF behavior/observability work from plans 0030/0031 except preserving its existing transitions.
- Battalion casualty or placement authority except reconciliation with 0044.
- Splitting `OffloadCalculator` (sketch step 3's caveat): 0044 already settled its live writes, and
  nothing in this plan needs it moved.

## Risks and stop conditions

- **Mixed aggregate transaction:** force ids and hull cohorts move together. Preflight both
  authorities before either writes, and assert both receipts after application (D4).
- **Cohort serialization drift:** the typed-cohort commit (D1) must not change `to_dict()`'s bytes.
  If golden or observation fixtures drift there, it is a bug in the shim, not a re-baseline.
- **Dictionary aliasing:** many resolver inputs alias arrays inside Resources. Calculators receive
  read-only snapshots or prove they do not mutate aliases.
- **RNG/iteration drift:** packing order and casualty selection are deterministic contracts. Any
  fixture drift in a pure ownership commit is a bug.
- **Dependency ceilings:** `ReinforcementPhases` is ceilinged. Commit 1 removes a dependency from it;
  never raise its ceiling to accommodate a new one.
- Stop if the controller must become a generic force+fleet object to complete a transaction; keep
  authorities separate and improve the coordinator contract instead.

## Closeout homes

On shipment: `docs/STATUS.md`; `docs/systems/amphibious-offload/amphibious-offload.md` for
lifecycle/data flow; `docs/systems/antiship-mine/` for crossing-loss application;
`docs/systems/turn-engine/turn-engine.md` for coordination; authority code headers and the
architecture skill; `docs/DECISIONS.md`; plan archived. Owning docs update their short numbered
**State & authority** section with aggregate, authority, operation-specific outcome/receipt types, and
the manifest link — never a duplicate writer/field list.

## Dependencies

Requires 0042; follows 0044 (shipped 2026-07-29), so troop-manifest reconciliation calls the force
authority rather than a temporary API. Plan 0030 may ship before or after if it remains behavior-free;
plan 0002 should wait until this aggregate boundary is stable.
