---
title: "0049: Accounting and turn-lifecycle mutation authority"
status: "Shipped"
created: "2026-07-26"
preflighted: "2026-07-31"
---

# Plan 0049: Accounting and turn-lifecycle mutation authority

> **CLOSED OUT 2026-07-31.** Shipped as four commits (`0a6a6d5` characterization, `8900a4f` supply,
> `3f02d15` order buffers, `968a1ff` turn lifecycle). Durable facts live in
> `tools/mutation_authority_manifest.json` (ownership), `docs/STATUS.md` (the aggregate table),
> `docs/systems/supply-dos/supply-dos.md` §8, `docs/systems/turn-engine/turn-engine.md`, and
> `docs/systems/mutation-authority/mutation-authority.md` §6 (the two generalizable lessons).
> Nothing here is a reference — this file is kept for the reasoning, not the facts.

## Goal

Finish domain migration for mutable runtime state that is not a physical force/platform aggregate:
DOS supply balance/history, order buffers, turn/phase lifecycle, and victory latches. Preserve
`GameStateData` as a plain value object and `TurnConductor` as the sole owner of phase order while
giving these fields named mutation APIs.

Eighth of the 0042–0050 campaign. It claims the **last ten** `GameStateData` fields that
`tools/mutation_authority_manifest.json` promised to plan 0049; the three orphans it leaves
(`sealift_state`, `lost_at_sea_accumulator`, `pending_lost_at_sea`) belong to 0050.

## Preflight (measured 2026-07-31, against `4021fb6`)

Three of the Sketch's claims did not survive contact with the tree. All three are settled below; the
rest of the Sketch stands.

### 1. Step 6 (summary projections) is already decided — it dissolves

The Sketch's step 6 wanted `last_*` slots routed through a projection writer. The manifest already
classifies **all eleven** `last_*` fields as `phase_output` with **no plan promise attached** — i.e.
they were deliberately excluded from the campaign, not deferred to it. Claiming them now would mean
deleting eleven settled exclusions to buy exactly what the Sketch's own stop condition already
permits ("acceptable to register a phase coordinator as the sole projection writer when the state is
purely `last_*` output"). It is also measurably false that they are write-only: **six of eleven are
read back in-turn**, three by the function that just wrote them.

**Step 6 is deleted.** The eleven `last_*` slots stay exactly as they are: excluded from the
campaign and **intentionally writable**, including through their `GameState` façade setters. Do not
claim otherwise — a review of this plan's first draft caught the wording "phase coordinators remain
their sole writers" and disproved it: `tools/validate_headless_antiship.gd:122` sets
`GameState.last_ijfs_writeback` to inject a fixture, and `tests/ijfs/ijfs_maneuver_consume_test.gd`
does the same. Because `phase_output` is an exclusion, the gate protects none of these routes, and
this plan does not change that.

### 2. Every coordinator this plan touches sits at EXACTLY its dependency ceiling

`python3 tools/gd_metrics.py . m.json --check-ceiling`, measured:

| File | ndeps | ceiling | headroom |
|---|---|---|---|
| `scripts/GameState.gd` | 29 | 29 | **0** |
| `scripts/phases/TurnConductor.gd` | 18 | 18 | **0** |
| `scripts/phases/ReinforcementPhases.gd` | 22 | 22 | **0** |
| `scripts/phases/TurnClosure.gd` | 7 | 7 | **0** |

Three new authorities must be named from all four. Every one of them must be **paid for**, not
bumped. The budget is in §Dependency budget below and each payment is a real simplification, not a
laundering hop.

### 3. `SupplyResolver` has nothing left to be

`SupplyResolver.resolve` (25 lines) is `DosConsumption.calculate_consumption(...)` — already a pure
calc under `scripts/calc/` — plus five lines of application. Once application moves to the authority,
the class is an empty shell. The Sketch's step 8 ("move supply calculation to `scripts/calc/`") has
therefore **already happened**; what is left is to **delete** `SupplyResolver`, not move it. The
gathering that `TurnClosure` does inline (who is ashore, who moved, who fought) is the only supply
*calculation* not yet in `scripts/calc/`, and it becomes `scripts/calc/SupplyBill.gd`.

Same shape as 0048, whose preflight dissolved `MobilizationTransitions`, and 0045 before it.

## Writer inventory (measured; this is the artifact the migration is checked against)

Ten protected fields, plus the two `SupplyState` fields. `tests/` is out of the gate's scan scope but
still needs updating. Nothing else in `scripts/` or `tools/` writes any of these.

### Supply — `SupplyState.current_dos_tons`, `SupplyState.day_history`

| file:line | line | enclosing |
|---|---|---|
| `scripts/resolvers/SupplyResolver.gd:18` | `supply_state.current_dos_tons = maxf(0.0, pool_before - consumed)` | `resolve` |
| `scripts/resolvers/SupplyResolver.gd:24` | `supply_state.day_history.append(summary)` | `resolve` |
| `scripts/builders/SupplyStateBuilder.gd:14-15` | `supply_state.current_dos_tons = …` / `day_history = []` | `build` — **construction writer** |
| `tools/validate_dos_consumption.gd:95` | `GameState.supply_state.current_dos_tons = 10.0` | clamp-at-zero test |

### Supply handle — `GameStateData.supply_state`

| file:line | line | enclosing |
|---|---|---|
| `scripts/GameState.gd:76` | `set(value): data.supply_state = value` | façade setter — **delete** |
| `scripts/GameState.gd:340` | `data.supply_state = GameStateBuilder.build_supply_state(…)` | `_rebuild_supply_state` |

### Order buffers — `orders`, `commitments`, `air_insert_orders`, `jlsf_orders`

| file:line | line | enclosing |
|---|---|---|
| `scripts/resolvers/OrderValidator.gd:47` | `state.orders[team].append(order)` | `add_move_order` |
| `scripts/resolvers/OrderValidator.gd:78` | `state.commitments[team].append(order)` | `add_commit_order` |
| `scripts/resolvers/OrderValidator.gd:127` | `state.air_insert_orders.append({…})` | `add_air_insert_order` |
| `scripts/GameState.gd:49,52,70,136` | four façade setters | **delete** |
| `scripts/GameState.gd:165-172` | `data.orders = {…}` / `data.commitments = {…}` | `reset_to_scenario` |
| `scripts/GameState.gd:200` | `data.air_insert_orders = []` | `reset_to_scenario` |
| `scripts/GameState.gd:237-240` | four `.clear()` | `begin_next_turn` |
| `scripts/GameState.gd:265` | `data.jlsf_orders.clear()` | `_rebuild_infrastructure_state` |
| `scripts/GameState.gd:390` | `data.jlsf_orders.append(…)` | `_apply_order` |
| `scripts/phases/ReinforcementPhases.gd:108,113` | `state.jlsf_orders.clear()` | `consume_jlsf_orders` |
| `scripts/phases/ReinforcementPhases.gd:297` | `state.air_insert_orders = []` | `resolve_air_insertion_turn` |

### Lifecycle — `turn_number`, `phase`

| file:line | line | enclosing |
|---|---|---|
| `scripts/GameState.gd:40,43` | two façade setters | **delete** |
| `scripts/GameState.gd:159-160` | `data.turn_number = 1` / `data.phase = Phase.PLANNING` | `reset_to_scenario` |
| `scripts/GameState.gd:241-242` | `data.turn_number += 1` / `data.phase = Phase.PLANNING` | `begin_next_turn` |
| `scripts/phases/TurnConductor.gd:32` | `state.phase = …RESOLUTION` | `resolve_turn` |
| `scripts/phases/TurnConductor.gd:107` | `state.phase = …END` | `resolve_turn` |
| `tools/validate_headless_antiship.gd` ×6, `validate_headless_ijfs.gd` ×5, `validate_headless_offload.gd` ×1, `validate_cleanup.gd` ×4, `validate_dos_consumption.gd` ×1 | `GameState.turn_number = N` / `+= 1` | via the façade setter |

### Victory latches — `game_over`, `winner`, `_china_has_landed`

| file:line | line | enclosing |
|---|---|---|
| `scripts/GameState.gd:139,142` | two façade setters | **delete** |
| `scripts/GameState.gd:201-203` | three resets | `reset_to_scenario` |
| `scripts/phases/TurnClosure.gd:71` | `state._china_has_landed = bool(outcome["china_has_landed"])` | `resolve_cleanup_phase` |
| `scripts/phases/TurnClosure.gd:73-74` | `state.game_over = …` / `state.winner = …` | `resolve_cleanup_phase` |

### The façade is the real hole

Fifteen `tools/validate_*.gd` lines write `GameState.turn_number` and one writes
`GameState.supply_state.current_dos_tons`. **The gate cannot see any of them**: the receiver resolves
to `GameStateType`, not `GameStateData`, so a forwarding setter is an unpoliced public door onto a
protected field. Removing those setters is not cleanup at the end — it is the only thing that makes
the claim mean anything, so it lands in the same commit as each claim.

### Protected-name collision audit (§4 of the procedure doc)

`turn_number`, `phase`, `orders`, `winner`, `game_over` are generic names; a protected name is
claimed repo-wide and an **unresolvable** receiver writing one fails as `E_UNRESOLVED_WRITE` (the
`IjfsMunition.name` trap, 22 false failures). Measured — every other writer of these names is a
`var x := SomeClass.new()` local, which the scanner's `_infer_from_calls` resolves:

`ForceMobilizationRequest.turn_number`, `AirLiftRequest.turn_number`,
`ForceAirInsertionRequest.turn_number`, `AirInsertionResolutionPlan.turn_number`/`.orders`,
`TurnResult.turn_number`/`.game_over`/`.winner`, `ForcePlacementRequest.phase`,
`ForcePlacementReceipt.phase`, `CleanupSummary.game_over`/`.winner`.

These names cannot be renamed anyway — they are the public `GameState.*` API. **The first commit that
claims one runs the gate and confirms zero `E_UNRESOLVED_WRITE`; if any appears, annotate the
receiver rather than dropping the claim.**

## Settled constraints

- `GameStateData` remains data-only; no gameplay methods.
- `GameState` remains the autoload façade/lifecycle entrypoint; no new autoloads.
- `TurnConductor.resolve_turn` remains the only full phase-order list.
- Orders enter through validation APIs; external action `type` and internal order `kind` remain
  separate boundaries.
- `SupplyState.current_dos_tons` is authoritative; `day_history` is its audit ledger.
- Victory census is derived fresh; `game_over`, `winner` and `_china_has_landed` are latches applied
  together from one cleanup result.
- Summary/observation Dictionaries are serialized projections, not writable state authorities.
- **Public shapes are byte-stable**: `OrderResult` codes/messages, `TurnResult`, the supply summary
  Dictionary's key **insertion order** (`day_history` rows and `EventBus.supply_updated` are
  serialized from it), observation and action-response shapes.

## Aggregate authorities

### `SupplyTransitions` — `scripts/transitions/SupplyTransitions.gd`

Owns `SupplyState` (both fields) and hosts `GameStateData.supply_state`.

- `rebuild_supply_state(state, red_dos_start)` — scenario reset; calls `SupplyStateBuilder.build`
  and replaces the handle. Replacing a LIVE handle is a scenario reset that routes through the
  authority, exactly as `AirInsertionTransitions.rebuild_air_insertion_state` and
  `InfrastructureTransitions.rebuild_infrastructure` already do — **and, like them,
  `SupplyStateBuilder` survives and is registered as a `construction_writers` allowance** (it fills a
  FRESH, unpublished `SupplyState`). Folding the builder INTO the authority was the first draft's
  plan and is wrong: it would delete a class `tests/state_builders_test.gd:46,52` calls directly, for
  no gain. `GameStateBuilder.build_supply_state` — a one-line pass-through whose only caller moves —
  is deleted instead.
- `apply_daily_bill(supply_state, consumption) -> Dictionary` — takes the **consumption row**
  `DosConsumption` produced and **derives** the new balance itself:
  `pool_after = maxf(0.0, pool_before - consumed)`, then stamps `applied`/`pool_before`/`pool_after`
  onto the row in that order and appends it. Returns the completed row.

**Derive, don't accept** (procedure §6): the authority is never handed a `pool_after`. A row whose
`pool_after` disagrees with the balance, or a balance that rises, is *unexpressible* rather than
guarded — so "history chains and matches `current_dos_tons`" is true by construction and needs no
second total.

Absent by design: no `set_pool`, no way to append a row without applying it, no way to raise the
balance outside `rebuild_supply_state`.

New calc `scripts/calc/SupplyBill.gd`: the gathering `TurnClosure` does inline today — which Red
battalions are ashore, which brigades moved, which fought. Reads `GameData` (precedent: `JlsfCargo`,
`SealiftResolver` in the same directory), calls `DosConsumption`, returns the consumption row.

**It must not call `state.refresh_not_ashore_by_type()`.** That method assigns the persistent
`not_ashore_by_type` cache (`GameStateData.gd:108-109`), and `AGENTS.md` is explicit that a
calculator writes nothing that outlives the call — a review caught the first draft calling it while
describing the class as "pure". The refresh **stays in `TurnClosure`**, exactly where it is today,
and the resulting map is passed in as an argument: `SupplyBill.for_turn(store, not_ashore,
turn_number)`. Note the alternative the reviewer proposed — recomputing a local map inside the calc
and dropping the refresh — is rejected: it would change the cache's end-of-turn value and is a
behaviour change this plan is not entitled to make. Keeping the refresh at the coordinator is
byte-identical *and* leaves the calc pure. Costs `TurnClosure` no dependency (the call names no
class).

### `OrderTransitions` — `scripts/transitions/OrderTransitions.gd`

Hosts `GameStateData.orders`, `commitments`, `air_insert_orders`, `jlsf_orders`. The **single public
door** to the order aggregate; `OrderValidator` moves to `scripts/calc/OrderValidator.gd` and keeps
only pure legality/eligibility (it appends nothing).

**The content store is passed in, never read.** `OrderValidator` reads the `GameData` autoload on
about a dozen lines today (`:24,29,39,55,64,68,102,109,112,137`, …). Moving it under `scripts/calc/`
does not remove that — and an authority that calls it would then read an autoload transitively, which
the house shape forbids. A review caught this. So every method here takes `store: GameDataStore`
explicitly and passes it down, and the callers hand it `GameData` — the identical shape
`ForceTransitions.apply_battalion_casualties(GameData, request)` and `MapTransitions` already use.
`OrderValidator` loses its `autoload:GameData` dependency and becomes genuinely pure.

- `add_move_order(state, store, team, order: MoveOrder)` /
  `add_commit_order(state, store, team, order: CommitOrder)` /
  `add_air_insert_order(state, store, team, brigade_id, target_hex)` /
  `add_jlsf_order(state, store, port_id)` → `OrderResult`. Each asks the calc for legality and
  appends only on accept, so a rejection cannot partially append.
  The existing `MoveOrder` / `CommitOrder` resources ARE the request types — they already carry
  exactly `brigade_id`/`target_hex`/`mode`, so no new model classes are needed, and their factories
  (`OrderTransitions.move_order(...)`, `.commit_order(...)`) live here so a caller never names them
  (the free-request-type rule, procedure §5). Every signature is ≤ 5 params, the hard cap.
- `apply_bulk_order(state, store, order: Dictionary, team) -> OrderResult` — the `kind` dispatcher
  that is `GameState._apply_order` today, so the bulk path and the per-order path share one
  implementation.
- `eligible_commit_brigades` / `eligible_air_insert_brigades` — queries, delegating to the calc. They
  sit on the authority rather than the calc only so that `GameState` keeps naming one class instead
  of two; they mutate nothing.
- `clear_turn_buffers(state)` — `orders` + `commitments`, at begin-next-turn.
- `reset_buffers(state)` — all four, at scenario reset.
- `consume_air_insert_orders(state)` / `consume_jlsf_orders(state)` — post-resolution clearing.

**`add_jlsf_order` closes a live defect.** `deploy_jlsf` is the only order that never went through a
validation API: `GameState._apply_order:380-390` appends the port id raw, so a JLSF order is accepted
**outside PLANNING** and with an unknown port id, and `LLMGameAPI:211-216` reaches it by calling the
private `_game_state()._apply_order(...)`. It gains the same phase check and typed `OrderResult` as
the other three, and `LLMGameAPI` gets a public path.

The exact contract, because "preserve `OrderResult` codes" is not enough guidance when the codes do
not exist yet (`OrderResult.Code` has neither an unknown-infrastructure nor a duplicate-JLSF member):

| Case | Result |
|---|---|
| outside PLANNING | reject `WRONG_PHASE` (existing member), message in the house format |
| unknown port id | reject with a NEW `UNKNOWN_INFRASTRUCTURE` member |
| Green issues it | reject `TEAM_MISMATCH` (existing; today it is a bare `push_error`) |
| duplicate port id | **accepted** — no new code |

Duplicates stay legal deliberately: `InfrastructureTransitions`' header records that
`JlsfCargo.queue_deployments` depends on its second pass over a duplicate explicit order observing
the `QUEUED` the first one wrote. Rejecting duplicates here would silently change that mechanic.
`LLMGameAPI` already rejects unknown ids itself, so its observable behaviour changes only for the
wrong-phase case. Test all three entry paths (public, bulk, LLM).

### `TurnLifecycleTransitions` — `scripts/transitions/TurnLifecycleTransitions.gd`

Hosts `GameStateData.turn_number`, `phase`, `game_over`, `winner`, `_china_has_landed`.

- `begin_resolution(state) -> bool` — PLANNING → RESOLUTION.
- `end_resolution(state) -> bool` — RESOLUTION → END.
- `begin_next_turn(state) -> bool` — END → PLANNING, `turn_number += 1`.
- `reset_to_turn_one(state)` — turn 1, PLANNING, all three latches false.
- `apply_cleanup_verdict(state, summary: CleanupSummary)` — the whole latch set from **one**
  receipt: `game_over` and `winner` read off the summary, and
  `_china_has_landed = state._china_has_landed or summary.china_battalions_on_taiwan > 0`.

**It calls no other authority.** The Sketch had lifecycle invoking `OrderTransitions` for per-turn
buffer reset; a review pointed at `AGENTS.md`'s rule that *a coordinator may call two authorities; it
writes neither's fields itself* — cross-authority orchestration is the coordinator's job, not an
authority's. `GameState` therefore calls both, which costs nothing because it already names
`OrderTransitions` for order entry. Nor does it name `SupplyTransitions`: supply reset goes
`GameState._rebuild_supply_state` → `TurnClosure.rebuild_supply_state` → `SupplyTransitions`,
matching the existing `GameState._rebuild_infrastructure_state →
ReinforcementPhases.rebuild_infrastructure → InfrastructureTransitions` chain exactly.

**`apply_cleanup_verdict` derives the landing latch; it does not accept one.** The first draft took
`china_has_landed: bool` as a parameter. Deriving it from `summary.china_battalions_on_taiwan`
instead means the whole latch set comes from a single receipt and cannot disagree with itself
(procedure §6). `CleanupResolver` still computes its own copy for `VictoryConditions.evaluate`; that
becomes report-only, and a test pins that the two agree.

**Enforce by absence** (procedure §6): there is no `set_phase`, no `set_turn_number`, no `set_winner`.
Precisely: **an arbitrary phase assignment is inexpressible** — no method takes a destination phase —
while a legal-transition method called from the wrong source phase is **refused without mutating
anything**. (The first draft claimed illegal transitions were "inexpressible" full stop; calling
`begin_resolution` from END is obviously expressible, and its guard is what refuses it. Test every
wrong source phase.) The monotone landing latch is an `or`, not a guard. It decides no phase order —
`TurnConductor` still holds the ordered list and calls `begin_resolution` / `end_resolution` where
its two assignments are today. It consumes no dice.

## Dependency budget

Every payment below is a simplification that stands on its own; none is a hop invented to launder a
token.

| File | Change | ndeps |
|---|---|---|
| `TurnClosure` | −`SupplyResolver` +`SupplyTransitions`; −`Battalion` −`Brigade` +`SupplyBill` (the gathering loops leave); +`TurnLifecycleTransitions` | 7 → **7** |
| `TurnConductor` | −`Movement` (its one use, `mode == Movement.MODE_ADMINISTRATIVE`, becomes `MoveOrder.is_administrative()` — the predicate belongs on the order); +`TurnLifecycleTransitions` | 18 → **18** |
| `ReinforcementPhases` | −`HexState` (three duplicated `GameData.hex_states.get(…) as HexState` null-guarded casts collapse into one `GameData.hex_owner_of(hex_id) -> String` query); +`OrderTransitions` | 22 → **22** |
| `GameState` | −`OrderValidator` +`OrderTransitions` (the authority is the door); −`Movement` (`_apply_order` moves to `OrderTransitions.apply_bulk_order`); +`TurnLifecycleTransitions` | 29 → **29** |

`SupplyTransitions` is never named by `GameState` — it is reached through `TurnClosure`, whose ceiling
already absorbs it. `OrderValidator` (uncapped) gains nothing; it *loses* its writes and its
`autoload:GameData` dependency. `GameState` naming `OrderTransitions` for order entry is what makes
it free for `GameState` to also drive the per-turn buffer reset the lifecycle authority no longer
does.

Independently re-derived by review: "`TurnClosure` uses `Battalion`/`Brigade` only in the extracted
gathering loops; `TurnConductor` names `Movement` once; `ReinforcementPhases` names `HexState`
exactly three times; `GameState` has four executable `OrderValidator` references and one `Movement`
reference. No arithmetic double-count was found."

**`GameData.hex_owner_of(hex_id) -> String` must reject the absent hex explicitly.** The three sites
are not symmetric: `owner_by_hex` iterates existing keys and the corridor predicate treats `""` as
not-Red, both safe — but `hex_can_receive_mobilized` (`ReinforcementPhases.gd:264-269`) *currently
rejects a missing `HexState` before it ever consults terrain*, so if `""` merely fails the
RED/CONTESTED comparisons, a hex with terrain but no runtime state silently becomes a legal
mobilization site. Return `""` for an absent hex, reject on `""` at that site, and test it. This is
the same class of error `HexOwnershipCalculator`'s header warns about at length: absence carries
meaning here and must never be defaulted.

Each payment lands in the commit that needs it, and `--check-ceiling` runs in the gate every time.
**If a ceiling breaches, the fix is a different payment, never a bump.**

## Required invariants

- legal phase transitions only: PLANNING → RESOLUTION → END → PLANNING, and illegal ones are
  inexpressible rather than refused;
- turn increments exactly once, on END → PLANNING;
- no order accepted outside PLANNING (now including `deploy_jlsf`), and no buffer survives
  begin-next-turn;
- rejection never partially appends;
- supply history forms a chain and matches `current_dos_tons` after every applied row, by
  construction;
- `game_over`/`winner`/`_china_has_landed` update from one cleanup receipt;
- `_china_has_landed` is monotone;
- lifecycle operations consume no Dice and cannot change phase ordering;
- the supply summary Dictionary's key insertion order is unchanged.

## Commit sequence

Each of commits 2–4 is **atomic** per procedure §3.5: authority class + manifest entry + every writer
migration + the updated `real_claims_pin.json` + the ceiling payment. Full gate green after every
commit.

**Exclusions are deleted per-commit, by the commit that claims the field — never in a batch.** A
review flagged the first draft's "commits 2–4 delete all ten" as an instruction a careless
implementer turns red either way: delete all ten in commit 2 and the nine still-unclaimed fields fail
`E_UNCLASSIFIED_FIELD`; defer all ten to commit 4 and commit 2 fails `E_CLAIMED_AND_EXCLUDED` on
`supply_state`. The mapping is therefore fixed here:

| Commit | `shared_model_policies` exclusions deleted from `GameStateData` |
|---|---|
| 2 | `supply_state` |
| 3 | `orders`, `commitments`, `air_insert_orders`, `jlsf_orders` |
| 4 | `turn_number`, `phase`, `game_over`, `winner`, `_china_has_landed` |

Ten total, so commit 5 has none left to clear — which matters because archiving this plan breaks any
exclusion still pointing at it under `plan_dir`.

1. **Characterize.** `tests/transitions/accounting_authority_characterization_test.gd` and
   `lifecycle_authority_characterization_test.gd`: current supply drain / zero clamp / no-consumption
   day / multi-day chain; legal and illegal phase transitions; begin-next-turn increments and clears
   once; duplicate and invalid order rejection leaving buffers unchanged; bulk vs LLM paths producing
   identical buffers; cleanup latch trio and landing monotonicity; disabled-phase outputs. Tests only.
2. **Supply.** `SupplyBill` + `SupplyTransitions`; keep `SupplyStateBuilder` (register it as a
   `construction_writers` allowance) and delete the now-orphaned `GameStateBuilder.build_supply_state`;
   delete `SupplyResolver`; rewire `TurnClosure` and `GameState._rebuild_supply_state`; drop the
   `supply_state` façade setter; fix `validate_dos_consumption.gd:95` to reach zero by a real drain
   rather than by assignment. **Migrate `tests/resolvers_test.gd:20,37`** — they call
   `SupplyResolver.resolve` directly and are the reason deleting the class is not a silent no-op;
   they become `DosConsumption` + `SupplyTransitions` calls in this same commit. Claims
   `SupplyState.current_dos_tons`, `SupplyState.day_history`, `GameStateData.supply_state`.
3. **Orders.** `OrderTransitions` (store passed in; no autoload read); `OrderValidator` →
   `scripts/calc/` with the `.gd.uid` preserved, updating the two doc anchors — there are **no**
   `preload` paths to update, confirmed absent by review; every caller uses the global `class_name`,
   which is path-independent. `add_jlsf_order` with its phase check and the new
   `UNKNOWN_INFRASTRUCTURE` code; rewire `GameState` (four setters deleted, `_apply_order` moved),
   `ReinforcementPhases` (+`hex_owner_of` payment, including the absent-hex rejection) and
   `LLMGameAPI` (off the private `_apply_order`). **Migrate `tests/air_insertion_order_test.gd`** —
   its ~12 `OrderValidator.add_air_insert_order` calls rely on the append that moves, so its buffer
   assertions break unless they move to `OrderTransitions` in this commit. (Its two direct
   `state.phase` writes are fine and stay: `tests/` is outside the gate's scan roots.) Claims the
   four buffers.
4. **Lifecycle and latches.** `TurnLifecycleTransitions`; rewire `TurnConductor`
   (+`MoveOrder.is_administrative` payment), `TurnClosure`, `GameState`; delete the four remaining
   façade setters; migrate the seventeen `tools/validate_*.gd` writes. **The `= 2` cases cannot use
   `begin_next_turn`** — review caught this: `validate_headless_ijfs.gd:97` and
   `validate_headless_offload.gd:74` drive a single phase and are still in PLANNING, so
   `begin_next_turn`'s END guard would refuse and silently leave the turn number alone. They drive
   the full legal cycle instead (`begin_resolution` → `end_resolution` → `begin_next_turn`), which
   consumes no dice. The `= 1` cases sit immediately after `reset_to_scenario()`, which already sets
   1, and simply delete. `validate_dos_consumption.gd:82` (`+= 1`) takes the same full-cycle
   treatment; it only moves the `day` stamp on the summary, which that validator does not assert.
   Claims `turn_number`, `phase`, `game_over`, `winner`, `_china_has_landed`.
5. **Closeout.** Docs, `docs/STATUS.md` row, `DECISIONS`, retrospective, procedure doc §5/§6
   additions, plan archived.

## Tests and validation

Authority tests under `tests/transitions/`, beyond the characterization set:

- every legal and illegal phase transition, including that no method exists to express an illegal one;
- supply normal drain, zero clamp, no-consumption day, multi-day chain, and history-matches-balance
  after each row;
- a `pool_after` that disagrees with the balance is unexpressible (no API takes one);
- duplicate/invalid order rejection leaves every buffer unchanged;
- internal bulk and LLM action paths produce identical accepted buffers;
- `deploy_jlsf` outside PLANNING is rejected and appends nothing;
- cleanup verdict updates all three latches together; `_china_has_landed` cannot be un-latched;
- summaries/events are built before buffers clear, ordering retained;
- no lifecycle operation consumes or derives Dice;
- unauthorized field assignment caught by the authority gate (abstract fixtures + generated real
  probes + claim pin);
- `hex_can_receive_mobilized` still rejects a hex with terrain but no runtime `HexState`;
- `CleanupResolver`'s own `china_has_landed` agrees with the latch the authority derived.

Test files migrated by this plan (each in the commit that breaks it): `tests/resolvers_test.gd`
(commit 2), `tests/air_insertion_order_test.gd` (commit 3). `tests/state_builders_test.gd` and
`tests/supply_combat_effectiveness_test.gd` were checked and need no change — the builder survives,
and a test assigning through the `supply_state` getter still compiles.

## Plan review, round 1 (2026-07-31)

Three routes, all returned. Sol: 9 findings, all accepted — the lifecycle/order coupling, the
`SupplyBill` purity violation, the authority's transitive autoload read, the false "sole writers"
claim, the absent-hex hazard, the missing JLSF result contract, the `SupplyResolver` test surface,
the "inexpressible" overclaim, and the phantom `preload` paths. agy: the per-commit exclusion map,
the `begin_next_turn` recipe that cannot work, and the test fallout. DeepSeek and agy **independently
confirmed the writer inventory is complete**, and Sol independently re-derived the dependency
arithmetic.

Two findings were accepted with a different fix than proposed, both to avoid an unearned behaviour
change: `SupplyBill` takes the not-ashore map as an argument rather than recomputing it locally
(keeping the cache refresh at the coordinator, byte-identical), and `SupplyStateBuilder` survives as
a registered construction writer rather than being folded in. One agy claim was checked and
**rejected**: tests writing `state.phase` will not break, because `tests/` is outside the gate's scan
roots and GDScript has no access control.

Verification: order, supply, cleanup, victory, LLM API and turn-engine suites/validators; event and
fixture drift; canonical golden and the full gate after **every** commit; one multi-game same-process
reset test; `--check-ceiling` every commit; mutation-authority deliberate red tests.

## Out of scope

- New orders or action-schema vocabulary (`add_jlsf_order` wraps an existing order, adding no
  vocabulary).
- Victory-condition or supply-balance changes.
- Changing phase order or adding phases.
- Making `GameStateData` immutable or event-sourced.
- A universal transaction log, replay engine, or EventBus replacement.
- The three 0050 orphans: `sealift_state`, `lost_at_sea_accumulator`, `pending_lost_at_sea`.
- The eleven `last_*` projections (see Preflight §1).

## Risks and stop conditions

- **God lifecycle authority.** It applies already-decided transitions and nothing else. If it ever
  needs to calculate combat, supply, victory or phase outcomes, stop.
- **Event ordering.** Order buffers must still exist when `TurnEventLog.build` reads them —
  `GameState.play_turn` builds events *after* `resolve_turn` and *before* `begin_next_turn`, and
  `consume_jlsf_orders` / `consume_air_insert_orders` clear mid-turn as they do today. Pin it.
- **`add_jlsf_order`'s phase check is a behaviour change.** It is a defect fix, but any harness that
  queued JLSF outside PLANNING will now be rejected. Sweep the batch/sweep harnesses in commit 3.
- **Dependency ceilings.** All four coordinators are at exactly their ceiling; see the budget. A
  breach means finding a different payment.
- **Protected-name collisions.** See the audit above; check `E_UNRESOLVED_WRITE` on the first claiming
  commit.
- Stop if a payment starts to look like a laundering hop rather than a simplification — surface it
  instead of taking it.

## Closeout homes

`docs/STATUS.md`; `docs/systems/supply-dos/supply-dos.md`, `llm-api-selfplay.md`,
`frontline-cleanup-victory.md`, `turn-engine.md`; `docs/systems/mutation-authority/mutation-authority.md`
(§5/§6 additions only — no per-aggregate facts); authority headers; `docs/DECISIONS.md`;
`docs/RETROSPECTIVES.md`; plan archived. Owning docs update their numbered **State & authority**
section with aggregate, authority, operation-specific outcome/receipt types, and manifest link only.

## Dependencies

Requires all prior authority APIs, especially 0043 (anti-ship cleanup) and 0048 (reinforcement order
clearing). Execute after 0048 and before the repository-wide closeout in 0050.
