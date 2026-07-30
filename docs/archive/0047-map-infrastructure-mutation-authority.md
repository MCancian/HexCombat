---
title: "0047: Map and infrastructure mutation authority"
status: "✅ Shipped"
created: "2026-07-26"
shipped: "2026-07-30"
---

> **✅ SHIPPED 2026-07-30.** All 8 steps done; gate ALL PHASES GREEN at each step, golden byte-stable,
> no pin or fixture movement, three full dependency ceilings held.
> Facts landed in: `docs/systems/hex-grid/hex-grid.md` §8 (the `map` aggregate and the sticky rule),
> `docs/systems/amphibious-offload/amphibious-offload.md` §9–10 (the `infrastructure` aggregate and the
> calculate/apply split), `docs/systems/mutation-authority/mutation-authority.md` §4–6 (the two new
> ordering traps and the enforce-by-absence shape), `docs/systems/turn-engine/turn-engine.md`,
> `docs/systems/terrain/terrain.md` §9, `docs/systems/frontline-cleanup-victory/frontline-cleanup-victory.md`,
> `docs/STATUS.md`, `docs/DECISIONS.md`, `tools/mutation_authority_manifest.json`, and the
> `MapTransitions` / `InfrastructureTransitions` headers.

# Plan 0047: Map and infrastructure mutation authority

## Goal

Give hex ownership/FEBA and infrastructure node lifecycle explicit mutation authorities, registered
and enforced by `tools/validate_mutation_authority.gd`. Remove every direct `HexState` and nested
`InfrastructureState.nodes` write while preserving sticky territorial ownership, seizure persistence,
repair timing, and all current combat/offload behaviour. No behaviour, RNG or golden change.

## Settled behaviour — do not change here

- Empty hexes keep their previous owner (the missing `else` branch in `recompute_hex_ownership` is
  load-bearing: it is what keeps a port seized after Red moves inland).
- Brigade *presence*, not landed battalion count, determines occupied/contested ownership.
- Infrastructure seizure persists after Red moves inland; operational contribution is gated by
  current ownership at read time in `red_offload_nodes`.
- Repair requires the hex still Red-held; status never regresses on recapture.
- **A node can be seized AND begin repair in the same `tick`** (see the same-tick rule below).
- FEBA math, the retreat threshold, and the ownership-recompute call ORDER are unchanged.
- Hex definitions/geometry/terrain are immutable content; only `HexState` is runtime state.

## Measured mutation surface (preflight, HEAD `6a610a3`)

Three independent sweeps agree on the list below (own greps, plus the `agy` and `deepseek` passes of
the plan-review round — both returned "TABLES COMPLETE"). The surface is **much smaller than the
original Sketch implies**: 7 production field writes in **2** files for the map, 13 across 5 files
for infrastructure.

### `HexState.owner` / `HexState.feba_km` — production writers

| file:line | function | line |
|---|---|---|
| `scripts/GameData.gd:600` | `recompute_hex_ownership` | `hex_states[hex_id].owner = HexOwner.CONTESTED` |
| `scripts/GameData.gd:602` | `recompute_hex_ownership` | `hex_states[hex_id].owner = HexOwner.RED` |
| `scripts/GameData.gd:604` | `recompute_hex_ownership` | `hex_states[hex_id].owner = HexOwner.GREEN` |
| `scripts/GameData.gd:609` | `set_hex_owner` | `hex_states[hex_id].owner = owner` |
| `scripts/GameData.gd:614` | `set_hex_feba` | `hex_states[hex_id].feba_km = feba_km` |
| `scripts/phases/TurnConductor.gd:223` | `resolve_combat_at` | `GameData.hex_states[hex_id].feba_km = GameData.hex_states[hex_id].feba_km + result.feba_movement_km` |
| `scripts/phases/TurnConductor.gd:292` | `apply_feba_retreats` | `GameData.hex_states[hex_id].feba_km = 0.0` |

Container writers of `GameDataStore.hex_states`: `GameData.gd:151` (`hex_states.clear()`),
`GameData.gd:186` (`hex_states[hex.id] = HexState.new()`), `GameData.gd:218`
(`hex_states[hex_id] = HexState.new()` in `reset_hex_states`). Nothing else touches the dict.

`recompute_hex_ownership` is called at five seams and the order is behaviour:
`TurnConductor.gd:90` (post-combat), `ReinforcementPhases.gd:138` (post-offload), `:232`
(post-mobilization), `:293` (post-air-insertion), `TurnClosure.gd:65` (cleanup).

### `InfrastructureState.nodes` — production writers

| file:line | function | line |
|---|---|---|
| `scripts/builders/InfrastructureStateBuilder.gd:16` | `build` | `state.nodes[id] = { … }` (construction) |
| `scripts/JlsfCargo.gd:101` | `queue_deployments` | `node["jlsf"] = InfrastructureState.JLSF_QUEUED` |
| `scripts/phases/ReinforcementPhases.gd:73` | `resolve_sealift_turn` | `…nodes[port_id]["jlsf"] = …JLSF_ENROUTE` |
| `scripts/phases/ReinforcementPhases.gd:145` | `resolve_offload_turn` | `…nodes[port_id]["jlsf"] = …JLSF_ARRIVED` |
| `scripts/phases/ReinforcementPhases.gd:184` | `reconcile_lost_jlsf` | `node["jlsf"] = …JLSF_NONE` |
| `scripts/resolvers/InfrastructureResolver.gd:30,31` | `tick` | seizure: `status = SEIZED`, `repair_turns_remaining = 0` |
| `scripts/resolvers/InfrastructureResolver.gd:40,41,44,47` | `tick` | repair clock + `DEGRADED` / `OPERATIONAL` |
| `tools/validate_headless_infrastructure.gd:68,70,81` | scripted validator | forces `status` / `jlsf` directly |

Plus one **container** writer the original Sketch missed: `scripts/GameState.gd:260`
(`data.infrastructure_state = GameStateBuilder.build_infrastructure_state(...)`) replaces the whole
aggregate at scenario reset. `GameStateData.infrastructure_state` is registered to no aggregate today.

### The 14 aliased node locals that must be retyped

Typing the node turns every `var node: Dictionary = …nodes[id]` into a runtime type error if missed.
The complete list (`agy` pass, verbatim): `scripts/JlsfCargo.gd:92,98`; `scripts/LLMGameAPI.gd:229`;
`scripts/model/InfrastructureState.gd:36,37`; `scripts/phases/ReinforcementPhases.gd:178`;
`scripts/resolvers/InfrastructureResolver.gd:24,25,67,68`;
`tools/validate_headless_infrastructure.gd:46,57,67,79`.

`scripts/AirAssaultPolicy.gd:79` and `scripts/resolvers/OffloadResolver.gd` also declare
`var node: Dictionary`, but they read an **LLM observation dict** and the `red_offload_nodes`
throughput array respectively — neither touches live node state, and neither changes.

### Six Sketch premises the tree contradicts or under-states

1. **`tools/validate_headless_infrastructure.gd` is a writer, and `tools/` is in `scan_roots`.** It
   forces node status/JLSF (`:68,70,81`) and calls `GameData.set_hex_owner` (`:54,75`). It must
   migrate; it cannot be an allowance, because it mutates *live published* state.
2. **The gate cannot see any of the infrastructure writes today.** `nodes` is an untyped
   `Dictionary` of untyped `Dictionary`, so `node["status"] = …` names no type at all — the
   validator header's aliased-container blind spot. Typing the node is the precondition for
   enforcement, not polish. (Same lesson as plan 0045's `SealiftCohort`.)
3. **`InfrastructureResolver.tick`'s returned `events` are dead in production.** Only
   `tests/infrastructure_resolver_test.gd` reads them; `ReinforcementPhases.gd:115` discards the
   return.
4. **`HexMap.set_hex_owner` / `HexMap.set_hex_feba` are dead code** — zero callers in `scripts/`,
   `tools/`, `tests/`, or any `.tscn`. Delete rather than migrate (0046 precedent). Once the
   validator stops calling them (below), **`GameData.set_hex_owner` and `GameData.set_hex_feba` are
   dead too** and go with them.
5. **No cross-controller cycle exists to break.** `recompute_hex_ownership` reads the force
   placement index through `GameDataStore`'s public queries and writes only `HexState`; it never
   repairs `brigades_by_hex`.
6. **`InfrastructureState.to_dict()` has zero callers anywhere** — not in `scripts/`, `tools/` or
   `tests/`. Its shape is therefore not a fixture *risk*; preserving it is a cheap forward-compat
   choice (plan 0031 will likely serialize nodes), not a mitigation. `HexState.to_dict()` is
   different: it is live via `GameData.snapshot_state` → `final_snapshot`.

### Two field names must be chosen against the 0046 collision lesson

A protected field NAME is claimed repo-wide, and an unresolvable receiver writing that name is
reported as a backstop failure. `IjfsMunition.name` cost plan 0046 twenty-two false failures.

- **`HexState.owner` → `HexState.hex_owner`.** `owner` is a built-in `Node` property in Godot, so a
  future scene-building line `some_node.owner = x` would fail this gate falsely — structurally the
  same trap as `name`. Zero such writes exist today, which is exactly why renaming is cheap now.
  **`to_dict()` keeps the key `"owner"`**, so `final_snapshot` in every game record is
  byte-identical. `HexState` appears in no `.tscn`/`.tres`/`.res`, so `@export var owner` is not
  load-bearing for any persisted resource (verified in the review round).
- **The typed node's status field is `node_status`, not `status`.** Brand-new field, so a
  distinctive name is free. `to_dict()` keeps the key `"status"`. `jlsf` and
  `repair_turns_remaining` are already distinctive and keep their names.

## Aggregate boundaries

Two aggregates, kept separate. `ReinforcementPhases` may call both — ownership feeds infrastructure
— but neither authority may import or call the other.

### `map` — `scripts/transitions/MapTransitions.gd`

Exact and only production writer of `HexState.hex_owner`, `HexState.feba_km`, and the
`GameDataStore.hex_states` container. First argument `data_store: GameDataStore`, matching
`ForceTransitions`. Does not move brigades; it *reads* the placement index to derive occupancy.

```
static func clear_hex_states(data_store) -> void                        # load_hex_grid, pre-parse
static func initialize_hex_states(data_store, hex_ids: Array) -> void   # load_hex_grid, post-parse
static func reset_hex_states(data_store) -> void                        # scenario reset
static func recompute_ownership(data_store) -> void
static func apply_feba_delta(data_store, hex_id: String, delta_km: float) -> void
static func clear_feba(data_store, hex_id: String) -> void
```

**There is deliberately no `set_owner`.** Ownership is *derived* from occupancy, never asserted —
enforced by the absence of a way to express it, the same technique `IjfsTransitions` uses to make
destruction monotonic. The only caller that wanted one was the scripted validator, which is
rewritten below to place a Red brigade instead. This also disposes of the question of whether such a
setter should start validating its owner string: **it would be a behaviour change** (today
`GameData.set_hex_owner` silently accepts anything) and this plan may not make one.

Routing construction through the authority means the `map` aggregate ships with **zero** allowances.

**`clear_hex_states` is separate from `initialize_hex_states` on purpose.** `load_hex_grid` clears
at `:151` *before* reading the JSON and returns early at `:155` on a parse failure, so a failed load
leaves the map empty. Initialising only after a successful parse would let a repeated failed load
retain the previous map.

### `infrastructure` — `scripts/transitions/InfrastructureTransitions.gd`

Exact and only production writer of node status, repair timer, JLSF marker, and the
`GameStateData.infrastructure_state` handle.

```
static func rebuild_infrastructure(state: GameStateData, infra_defs: Dictionary) -> void
static func apply_node_plan(state: InfrastructureState, plan: InfrastructureTickPlan) -> void
static func queue_jlsf(state: InfrastructureState, port_id: String) -> bool
static func mark_jlsf_enroute(state: InfrastructureState, port_id: String) -> void
static func mark_jlsf_arrived(state: InfrastructureState, port_id: String) -> void
static func clear_jlsf(state: InfrastructureState, port_id: String) -> void
static func jlsf_in_transit_ids(state: InfrastructureState) -> Array[String]   # read query
```

`rebuild_infrastructure` mirrors `SealiftTransitions.rebuild_fleet` exactly: the builder assembles a
fresh state, the authority performs the assignment to the `GameStateData` handle.
`GameState.infrastructure_state` becomes a **read-only façade** like `fleet` and `ship_reserve`, and
`GameState._rebuild_infrastructure_state` routes through a `ReinforcementPhases.rebuild_infrastructure`
pass-through — the same shape as `ReinforcementPhases.rebuild_fleet`, which exists precisely so
`GameState` reaches a phase's authority without naming it (its dependency ceiling is 29 and it is at 29).

`jlsf_in_transit_ids` is a read query on the authority, matching `SealiftTransitions.ready_by_type`;
it is what lets `reconcile_lost_jlsf` stop naming `InfrastructureState` (see ceilings, below).

Every applied transition ends with `assert(state.validate())` in debug builds and refuses illegal
statuses/JLSF values/negative timers up front. Guards `push_error` and change nothing rather than
`assert(false)` — a research batch must not die on one bad row, and a `push_error` guard is directly
testable. **There is no `force_status`**: an authority method whose only caller is a validator,
taking an arbitrary status plus a free-form `cause` that nothing records, is an authority bypass in
sanctioned clothing.

`InfrastructureStateBuilder.build` stays a **construction writer** (manifest allowance, `IjfsStateBuilder`
and `FleetBuilder` precedent): it fills a fresh `InfrastructureState` that nothing holds until it
returns. The asymmetry with `map`'s zero allowances is deliberate and justified — infrastructure
construction mutates a local, unpublished aggregate, whereas hex construction writes straight into a
globally reachable autoload container, so the stricter rule is the right one there.

JLSF *cargo* movement stays with the force/sealift authorities; only the node marker is ours.
`GameStateData.jlsf_orders` is an order buffer, not node state, and stays unregistered like every
other order array.

## Model hardening

`scripts/model/InfrastructureNodeState.gd` — a typed `Resource` replacing the per-node dictionary:

```
@export var node_status: String = InfrastructureState.STATUS_TAIWANESE
@export var repair_turns_remaining: int = 0
@export var jlsf: String = InfrastructureState.JLSF_NONE

func to_dict() -> Dictionary:
    return {"status": node_status, "repair_turns_remaining": repair_turns_remaining, "jlsf": jlsf}
```

`InfrastructureState.nodes` becomes `Dictionary` of `infra_id -> InfrastructureNodeState` (insertion
order still sorted-by-id from the builder). `InfrastructureState.validate()` keeps its three checks
but reads typed fields. The status/JLSF constants stay on `InfrastructureState`: they are the
vocabulary of both objects, and moving them would churn ~40 call sites for nothing.

Consumers to update in the same commit: the 14 aliased locals listed above, plus
`LLMGameAPI._infrastructure_observations` (its emitted keys `"status"`/`"jlsf"` do **not** change).

## Calculation/application split

`InfrastructureResolver` stops mutating and returns a plan:

```
static func plan_tick(state, infra_defs, owner_by_hex, repair_turns_per_stage := 1) -> InfrastructureTickPlan
```

**The same-tick rule.** In today's `tick`, the seizure branch's write is READ by the repair branch a
few lines later *in the same iteration* (`InfrastructureResolver.gd:29-31` then `:35-48`). This is
production-reachable: an explicit `deploy_jlsf` order does **not** require a seized node
(`JlsfCargo.gd:82-86` queues any id whose marker is `none`), so a TAIWANESE node can carry
`jlsf == ARRIVED` and go TAIWANESE → SEIZED → DEGRADED within one tick. A planner that evaluated
both branches against the pre-tick snapshot would silently add a turn to that path.

`plan_tick` is nonetheless safe as a pure calculator, because **nodes never read each other and no
dice are involved** — unlike plan 0046, where deferral would have changed which draws were consumed.
The requirement is that `plan_tick` stage each node's transitions **sequentially in local
variables**, so the repair branch sees the seizure it just planned. Two consequences for the plan
object:

- it carries an **ordered Array of events per tick**, not one label per node — a single node can
  legitimately emit both `seized` and `degraded` in one tick;
- `apply_node_plan` runs **before** `red_offload_nodes` at the existing seam
  (`ReinforcementPhases.gd:115` then `:116`), preserving the current one-turn producer/consumer edge.

The existing `{"events": [...]}` shape is preserved on the plan as `events` so the suite's
assertions survive unchanged.

**`JlsfCargo.queue_deployments` does NOT become a snapshot planner.** Its loop currently relies on
its own in-loop marker write: duplicate explicit orders produce ONE entry because the second
iteration observes `QUEUED` (`JlsfCargo.gd:99-101`). It keeps its sequential loop and calls
`InfrastructureTransitions.queue_jlsf(state, port_id) -> bool` at the exact point it used to assign
— the 0046 shape, and for the same reason: the decision to emit a pool entry is conditional on state
the previous iteration just wrote.

Map ownership splits the same way. `scripts/calc/HexOwnershipCalculator.gd`:

```
## Occupancy of every hex that has at least one live brigade. A hex with no live brigade is ABSENT
## from the result, and that absence IS the sticky-ownership rule.
static func occupancy_from_placements(data_store, hex_ids: Array) -> Dictionary
## occupancy -> {hex_id: owner}. Only occupied hexes appear.
static func owners_from_occupancy(occupancy: Dictionary) -> Dictionary
```

`MapTransitions.recompute_ownership` calls both and applies. **Application must literally iterate
the returned entries** (`for hex_id in owners:`) and must never do
`owners.get(hex_id, HexOwner.GREEN)` over every hex — omission is only equivalent to the missing
`else` if omitted hexes are never visited. **The iteration source for building occupancy stays
`data_store.hex_lookup.keys()`**, exactly as today; iterating `brigades_by_hex` instead would be
faster but would change what happens when the index holds a hex `hex_states` does not, and this plan
does not buy behaviour changes with performance.

## Dependency and parameter ceilings

Measured at HEAD: `TurnConductor` 18/18 and `ReinforcementPhases` 22/22 — **both are exactly full**,
and `GameState` is 29/29. Naming the new authorities directly would breach all three. The ceilings
are held by shape, not by bumping (`hexcombat-architecture-contract`: "the ceiling is paid for, not
raised"):

- **`TurnConductor` (18) and `TurnClosure` (7):** map jobs stay on the existing `GameData` façade —
  `GameData.recompute_hex_ownership()`, and new `GameData.apply_feba_delta` / `GameData.clear_feba`
  forwarding to `MapTransitions`. Exactly the `GameData.set_brigade_hex → ForceTransitions` shape
  already shipped by plan 0044. Neither file gains a class reference. `GameData` itself is not
  ceilinged.
- **`ReinforcementPhases` (22): a one-for-one swap, not a bump.** `InfrastructureState` leaves (all
  four constant uses become authority calls, and `reconcile_lost_jlsf` iterates
  `InfrastructureTransitions.jlsf_in_transit_ids`), `InfrastructureTransitions` arrives. Same trick
  plan 0043 used to hold `FiresPhases` at 14. No node local survives in this file, so
  `InfrastructureNodeState` is never named here either.
- **`GameState` (29):** reaches both authorities through `ReinforcementPhases` pass-throughs and the
  `GameData` façade; gains nothing.
- **`tools/gd_metrics.py:93`** — `"scripts/JlsfCargo.gd::queue_deployments": 7` — must be re-keyed
  **in the same commit as the file move** (step 7) or the entry goes stale and fails the gate, and
  the moved 7-parameter function breaches the hard cap of 5.

## Commit sequence

Each step ends with a green `bash tools/run_all_tests.sh`.

**An authority file cannot be created before it is registered.**
`validate_mutation_authority.gd:850` fails `E_UNREGISTERED_AUTHORITY_FILE` for any file under
`scripts/transitions/` that no aggregate names as its `authority_path`. So each authority ships
**atomically** with its manifest entry and every writer migration for that aggregate — there is no
"add the file now, register it later" step. Per the 0046 finding, an aggregate goes straight to
`status: "enforced"`; a migration aggregate may not declare an `authority_path` at all.

1. **Characterize.** `tests/transitions/map_transitions_characterization_test.gd` and
   `tests/transitions/infrastructure_transitions_characterization_test.gd` pinning *current*
   behaviour: RED/GREEN/CONTESTED recompute, sticky empty ownership (including "empty previously-Red
   hex stays Red"), reset across two games in one process, FEBA accumulate/zero, seizure, repair at
   1 and 2 turns/stage, repair pause on a Green hex, no status regression on recapture,
   **TAIWANESE + ARRIVED + RED at stage lengths 1 and 2**, duplicate explicit `deploy_jlsf` orders
   and explicit-plus-auto overlap, JLSF queue→enroute→arrived→none, loss-and-redeploy, and `to_dict`
   shape for both models. These must pass BEFORE any refactor.
2. **Rename `HexState.owner` → `hex_owner`.** Mechanical, `to_dict` key unchanged. Own commit, so
   any golden movement is unambiguous. Readers to update include `scripts/InfoPanel.gd:48` and
   `scripts/LLMGameAPI.gd:297` alongside `HexMap`, `ReinforcementPhases`, `TurnConductor`,
   `GameData`, and the two `tools/` validators.
3. **Type the infrastructure node.** Introduce `InfrastructureNodeState`; convert the builder, the
   resolver, `JlsfCargo`, `ReinforcementPhases`, `LLMGameAPI`, the validator and both suites. All 14
   aliased locals retyped. Serialization byte-identical.

   > **Measured 2026-07-30, after implementing it:** naming `InfrastructureNodeState` in
   > `ReinforcementPhases` takes it to **ndeps 23 over its ceiling of 22** — the gate went red
   > exactly where the ceilings section predicted. The ceiling may not be raised, and the
   > one-for-one swap that pays for it (`InfrastructureState` out, `InfrastructureTransitions` in)
   > cannot happen until step 5, because an authority file may not exist unregistered. Resolved for
   > this step by two clearly-labelled TRANSITIONAL helpers, `ReinforcementPhases.jlsf_marker` /
   > `set_jlsf_marker`, which read and write the marker without naming the node type. **Step 5 must
   > delete both** and route those three call sites through the authority; that is when the swap
   > lands and the helpers stop being needed.
4. **Rewrite `tools/validate_headless_infrastructure.gd` onto domain operations.** Place
   `GoldenScript.RED_MOVER_ID` at `PORT_HEX` via `ForceTransitions` + ownership recompute instead of
   `set_hex_owner`; move the same brigade to `JLSF_PORT_HEX` for the second half, which additionally
   exercises sticky ownership and seizure persistence end-to-end. Delete `_validate_rates_by_status`
   (its rate matrix is already covered by `tests/infrastructure_resolver_test.gd::test_red_offload_rates`)
   and assert the DEGRADED rate mid-progression instead, so no end-to-end coverage is lost. Replace
   `node["jlsf"] = ARRIVED` with the authority's `mark_jlsf_arrived`. This step is what makes
   `GameData.set_hex_owner` dead.
5. **Infrastructure authority, atomically:** `InfrastructureTransitions` + `InfrastructureTickPlan` +
   `InfrastructureResolver.plan_tick` + the manifest aggregate (`enforced`, one construction
   allowance, zero legacy writers) + `GameStateData.infrastructure_state` registered and its rebuild
   routed + `GameState.infrastructure_state` made read-only + illegal fixtures.
6. **Map authority, atomically:** `MapTransitions` + `HexOwnershipCalculator` + the manifest
   aggregate (`enforced`, zero allowances, zero legacy writers) + `GameData` façades forwarding +
   deletion of `GameData.set_hex_owner` / `set_hex_feba` and both `HexMap` stubs + illegal fixtures.
7. **File placement.** `JlsfCargo.gd` moves from `scripts/` to `scripts/calc/`;
   `InfrastructureResolver.gd` stays in `scripts/resolvers/` (it resolves a phase, matching its
   siblings). Preserve `.uid` files; re-key `tools/gd_metrics.py:93`; update
   `docs/systems/amphibious-offload/amphibious-offload.md`'s path anchor. Paths only.
8. **Close out.** Docs per `hexcombat-docs-and-writing`.

Illegal fixtures under `tools/fixtures/mutation_authority/` must cover: a direct `hex_owner` write, a
direct `feba_km` write, a direct `node_status` write, a nested node write, a `hex_states` container
write, and a wrong-authority assignment. Prove each fails.

## Tests and validation

New, under `tests/transitions/`, beyond the step-1 characterization set:

- `recompute_ownership` leaves an empty previously-Red hex Red after a load/reset-adjacent recompute;
- FEBA positive/negative accumulation, `clear_feba`, and unchanged retreat outcomes;
- `reset_hex_states` across two games in one process (the 2026-07-09 divergence);
- a failed grid load leaves `hex_states` empty rather than retaining the previous map;
- infrastructure legal-transition matrix, illegal status/JLSF refusal, negative-timer refusal;
- ownership loss pauses repair without erasing seizure status;
- JLSF loss returns the marker to `none` and permits redeployment;
- `HexState.to_dict()` and the typed node's `to_dict()` match the pre-change output exactly.

Verification: full `bash tools/run_all_tests.sh` — ALL PHASES GREEN, **no pin or fixture movement**
at any step.

## Out of scope

- Changing sticky ownership, zero-ashore territorial control, neutral hex rules, or capture timing.
- **Validating owner strings on assignment.** Today's silent-accept is behaviour; changing it needs
  its own USER-approved decision. Resolved here by deleting the setter, not by tightening it.
- Changing port throughput, repair rates, JLSF competition, or graduated suppression (plan 0031).
- Moving brigade placement ownership away from `ForceTransitions`.
- Moving `hex_states` storage off `GameData`. Mutable hex state beside static content is a real
  smell, but relocating storage and migrating writers in one plan is how a refactor gets
  un-reviewable. Open a later Sketch only if the authority measurements show a concrete problem.
- Terrain/geometry data changes; front-line UI work.

## Explicitly checked, don't re-raise

- **"The validator's `set_hex_owner` calls are unmentioned"** (deepseek #3) — they were already named
  in the premise list and are now step 4's whole subject.
- **"`InfrastructureState.to_dict` shape need not be preserved because it is dead"** (agy #11) —
  correct that there is no fixture risk; the shape is kept anyway as cheap forward-compat for plan
  0031. Downgraded from a risk to a choice, not dropped.
- **`AirAssaultPolicy.gd:79` / `OffloadResolver.gd` `var node: Dictionary`** — observation and
  throughput dicts, not live node state. No change needed.

## Risks and stop conditions

- **Behaviour hidden in timing.** Ownership is recomputed at five seams. Preserve the call order
  exactly; an authority does not justify deduplicating recomputations without a separate proof.
- **The same-tick seizure→repair path** is the one place a "pure calculator" refactor can silently
  change results. Step 1 pins it before step 5 touches it.
- **The `hex_owner` rename touches ~22 sites**, confined to its own commit so golden movement is
  attributable.
- **Three dependency ceilings are exactly full.** Any deviation from the façade/swap shapes above
  will fail `--check-ceiling`, and raising a ceiling to pass is forbidden.
- Stop if plan 0031 begins first and changes node semantics; rebase the transition matrix on the
  USER-approved mechanic before implementing. **Checked 2026-07-30: 0031 is still a `Sketch` and has
  not started.**

## Closeout homes

On shipment: `docs/STATUS.md` (the aggregate table); **`docs/systems/mutation-authority/mutation-authority.md`
— add any ordering trap or authority shape this plan found that generalizes, per its §7**;
`docs/systems/hex-grid/hex-grid.md`,
`docs/systems/terrain/terrain.md` only if their runtime-state claims change,
`docs/systems/frontline-cleanup-victory/frontline-cleanup-victory.md`,
`docs/systems/amphibious-offload/amphibious-offload.md`, `docs/systems/turn-engine/turn-engine.md`;
authority headers and the architecture skill; `docs/DECISIONS.md`; plan archived. Owning docs update
their short numbered **State & authority** section with aggregate, authority, operation-specific
outcome/receipt types, and a manifest link only. Immutable/view-only docs state explicitly that they
own no protected runtime aggregate instead of inventing an authority.

## Plan review round (2026-07-30)

Fan-out via `tools/review_fanout.sh --freeze`; all three quorum reviewers returned substantive
findings (sol 10.2 KB/10, agy 6.0 KB/15, deepseek 23.6 KB/5 — the last `SUSPECT` on size from tool
traces, counted after reading). Tree verified clean afterwards.

**Accepted:** same-tick seizure→repair and ordered multi-events (sol #1, confirmed independently
before the round returned); iterate returned owner entries, never `.get(default)` (sol #2); authority
files cannot precede manifest registration — commit sequence restructured (sol #4, verified at
`validate_mutation_authority.gd:850`); all three dependency ceilings full plus the stale
`PARAM_CEILINGS` key (sol #5, measured independently); delete both generic setters and drive the
validator through domain operations (sol #6/#8); `queue_deployments` keeps its sequential in-loop
write (sol #9); clear `hex_states` before the JSON read (sol #10); register
`GameStateData.infrastructure_state` and route its rebuild (deepseek #1); make
`GameState.infrastructure_state` read-only like `fleet` (deepseek #5); the 14 aliased node locals
(agy #10); `InfoPanel.gd:48` in the rename list (agy, missed #2).

**Rejected:** deepseek #3 (already covered); agy #11 in part (see "explicitly checked" above).

## Diff review round — steps 1-3 (2026-07-30)

Fan-out on the frozen 24-file diff with the gate already green; all three quorum reviewers returned
(sol 5.3 KB/4, agy 2.6 KB/2, deepseek 14.7 KB/7 — `SUSPECT` on size from tool traces). Tree verified
clean afterwards.

**Accepted and fixed before committing:**

- `InfrastructureState.validate()` hard-cast a `nodes` value to `InfrastructureNodeState`, so a stray
  non-node value would crash *before* the diagnostic `false` the method's whole contract promises
  (sol #1). Now type-checked first, with `tests/infrastructure_resolver_test.gd::test_validate_rejects_a_non_node_value`.
- Both `to_dict` characterization tests serialized only DEFAULT state, so an implementation that
  hardcoded `taiwanese/0/none` or `green/0.0` would have passed them (sol #3). Both now set
  non-default values first, and the deep-copy test now also proves the snapshot cannot write back
  into the live Resource.
- The transitional-helper comment said step 5 "replaces both bodies", which is wrong: the ceiling is
  only repaid when the `InfrastructureState` constants at the CALL SITES leave too (sol #4). Comment
  corrected to say step 5 must delete both helpers.

**Confirmed, no action:** `to_dict` byte-equivalence including order and deep-copy semantics (sol
#2); the `hex_owner` sed sweep missed nothing and over-replaced nothing, including `.tscn`/`.tres`
and the `set_hex_owner` / `recompute_hex_ownership` identifiers (agy #1); the same-tick
seizure→repair test pins a genuinely production-reachable path (agy #2).

## Diff review round — steps 4-7 (2026-07-30)

Fan-out on the frozen 27-file diff with the gate already green. Returns: **agy 3.4 KB / 5 findings**
(fact-check role — all five premises VERIFIED, including that no writer was missed and that neither
serialized key moved); **deepseek 34.2 KB** (enumeration role — four verbatim, scoped lists; labelled
`FLAKE` by the launcher because an enumeration produces lists rather than numbered findings, counted
after reading per the roster's enumerator rule); **sol 342 B** (consequences role — "no actionable
findings", plus three specific ABSENT determinations). Tree verified clean afterwards; no strays.

**Acted on:** sol's one substantive observation, reached independently while implementing — a
nonpositive `repair_turns_per_stage` is NOT equivalent, because the old code wrote a negative timer
and `apply_node_plan` now refuses it. Both sol and I confirmed the path is unreachable (the sole
production caller passes no argument, and it is not a scenario knob). The divergence is now named
explicitly in `InfrastructureResolver.plan_tick`'s header rather than left to be re-derived.

**Verified independently, not taken on trust:** deepseek's load-bearing LIST 4 claim that the five
production ownership seams are unchanged — confirmed by diffing `git grep` at HEAD against the working
tree (5 before, 5 after, same files and functions). Its summary text said "4 production calls" while
listing 5, and several of its enclosing-function labels were wrong; the *line numbers* were right.
That is the roster's documented tier-2 counting hazard, and the reason its citations get checked.

**Illegal fixtures — the plan's requirement, met by measurement rather than by a second manifest.**
The plan asked for fixtures covering six illegal forms. Every one is already proven by the existing
abstract fixture world (`violations.gdfixture` + `transitions_dir/other_authority.gdfixture`), and
adding real class names would require copying the real manifest into `fixture_manifest.json` — which
§1 of the campaign doc forbids. Instead each form was proven against the REAL aggregates by injecting
and reverting it: direct `hex_owner` and `feba_km` writes and a `node_status`/`jlsf`/
`repair_turns_remaining` write (`E_UNAUTHORIZED_WRITE`), a `hex_states` and a `nodes` container write,
a nested `hex_states[id].hex_owner` and `nodes[id].jlsf` write (`E_UNRESOLVED_WRITE` backstop), a
`GameStateData.infrastructure_state` assignment, and a `HexState` write from `SealiftTransitions`
(wrong authority). All twelve were reported; the tree was restored and re-verified `PASS`.

## Progress

- **Steps 1-3 SHIPPED 2026-07-30**, gate green, golden byte-stable, no fixture movement.
- **Steps 4-8 SHIPPED 2026-07-30.** Each step was gated on its own before the next began. Step 5
  deleted `ReinforcementPhases.jlsf_marker` / `set_jlsf_marker` as required and paid the ceiling with
  the one-for-one swap (`InfrastructureState` out, `InfrastructureTransitions` in, 22/22).
  Measured after step 7: `ReinforcementPhases` 22/22, `TurnConductor` 18/18, `TurnClosure` 7/7,
  `GameState` 29/29 — `--check-ceiling` PASS, nothing raised.

## Dependencies

**Required reading before implementing:** `docs/systems/mutation-authority/mutation-authority.md`
(the campaign procedure — registration ordering, field naming, the authority shape),
`hexcombat-architecture-contract` (module boundaries and "the ceiling is paid for, not raised"),
`hexcombat-change-control` (this is Architectural + golden-touching), `hexcombat-code-quality`
(check dependency headroom while designing the call shape).

Requires 0042 and 0044's force placement API. Follows 0046 in the campaign's one-aggregate-at-a-time
order. Plan 0031 should wait for this authority unless the USER explicitly prioritizes its mechanic.
