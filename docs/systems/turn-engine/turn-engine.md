# Turn Engine & Data Services

## 1. Purpose

The turn engine is the game's runtime spine — four autoloads that together manage every
gameplay-relevant cycle:

| Autoload | Role | Node |
|---|---|---|
| `GameData` | **Static data service** — loads JSON (hexes, OOBs, scenario, beaches, ships, theaters) into typed `Resource` objects once at startup. Holds all lookups (`hex_lookup`, `neighbor_lookup`, `brigades_by_hex`, etc.). | `scripts/GameData.gd` |
| `GameState` | **Runtime turn/phase state** — a thin autoload shell (plan 0014): the state itself lives in `GameStateData`, the resolution in `TurnConductor` + `FiresPhases` + `ReinforcementPhases` + `TurnClosure`, and this autoload keeps the typed forwarding properties, the delegating wrappers external callers use, and the lifecycle (`reset_to_scenario`, `begin_next_turn`, `play_turn`). | `scripts/GameState.gd` |
| `EventBus` | **Signal hub** — decouples subsystems via typed Godot signals (`phase_changed`, `turn_resolved`, `combat_resolved`, etc.). | `scripts/EventBus.gd` |
| `Dice` / `SeededDice` | **Injectable RNG abstraction** — base `Dice` (abstract, `RefCounted`), `SeededDice` (deterministic via `RandomNumberGenerator` with seeded `derive()` sub-streams). | `scripts/Dice.gd`, `scripts/SeededDice.gd` |

## 2. Files & Responsibilities

| File | Lines | Role |
|---|---|---|
| `scripts/GameState.gd` | 394 | Autoload shell: `Phase` enum (PLANNING/RESOLUTION/END) re-export, typed forwarding properties onto `data: GameStateData`, delegating wrappers (`resolve_turn()`, `resolve_offload_turn()`, …), lifecycle `reset_to_scenario()` / `begin_next_turn()` / `play_turn()` |
| `scripts/phases/TurnConductor.gd` | 321 | Turn orchestration proper: `resolve_turn()` holds the ordered phase list (§4), plus the phases whose application interleaves with it — movement, ground combat, FEBA retreats — and the façade-only front-line phase |
| `scripts/phases/FiresPhases.gd` | 191 | The fires phases (plan 0038): IJFS joint/air-missile fires and the Green anti-ship + mine defence of the crossing, which share the anti-ship firing systems |
| `scripts/phases/ReinforcementPhases.gd` | 345 | The four "force arrives" phases (plan 0038): sealift, amphibious offload, ROC mobilization, air insertion, and their arrival-site rules |
| `scripts/phases/TurnClosure.gd` | 81 | The end-of-turn accounting pair (plan 0038): supply bills who fought, cleanup censuses who is left and decides victory |
| `scripts/transitions/ForceTransitions.gd` | current | Force mutation authority (plan 0044): applies Brigade/Battalion roster, placement, destruction, activity, and organization writes through typed requests/receipts; ownership facts live only in `tools/mutation_authority_manifest.json` |
| `scripts/GameData.gd` | current | Data loading: `load_hex_grid()`, `load_brigades()`, `load_scenario()`, `load_theaters()`, `load_beaches()`, `load_ships()`. Indexes: `brigades`, `brigades_by_hex`, `hex_lookup`, `neighbor_lookup`, `hex_states`, `ship_defs`, `beaches`, `active_tos`, `to_adjacency`, `beach_to_to` |
| `scripts/Dice.gd` | 37 | Abstract base: `roll_d100()`, `choose_indices()`, `randf()`, `weighted_choice()`, `weighted_choices()`, `shuffle_indices()`, `derive()` |
| `scripts/SeededDice.gd` | 96 | Concrete: wraps Godot `RandomNumberGenerator` with a fixed seed. `derive(label)` creates an independent sub-stream via `hash(str(seed) + ":" + label)` |
| `scripts/EventBus.gd` | 21 | Signals: `phase_changed`, `turn_resolved`, `combat_resolved`, `offload_resolved`, `supply_updated`, `ijfs_resolved`, `antiship_resolved`, `frontline_resolved`, `cleanup_resolved` |
| `scripts/transitions/AntishipTransitions.gd` | 188 | The Green anti-ship establishment's mutation authority (plan 0043): the only writer of the `AntishipSystem` rows — builds/resets the arsenal, applies IJFS effects and one crossing's launch destruction, clears the per-turn flags |
| `scripts/transitions/SealiftTransitions.gd` | current | The sealift/fleet mutation authority (plan 0045): the only writer of the `ShipState` fleet projection and of `SealiftState`'s hull queues — pipeline/reload ticks, cohort hull losses and legs, escort magazines, and the fleet projection every phase closes with |
| `scripts/TurnEventLog.gd` | 70 | Pure function `build(state)` → `Array[TurnEvent]` — non-invasive log derived from GameState buffers post-resolve |
| `scripts/model/TurnResult.gd` | 33 | Typed result resource: `turn_number`, `contested_hexes`, `combat_summaries`, `ijfs_summary`, `antiship_summary`, `events`, `game_over`, `winner` |
| `scripts/model/TurnEvent.gd` | 11 | Single event resource: `seq`, `kind`, `hex_id`, `team`, `data` |
| `scripts/model/MoveOrder.gd` | 6 | `brigade_id`, `target_hex`, `mode` ("tactical"/"administrative") |
| `scripts/model/CommitOrder.gd` | 5 | `brigade_id`, `target_hex` |

## 3. The WeGo Turn Model

HexCombat uses a **WeGo** (write-orders-then-resolve) turn model with three phases:

```
PLANNING  ── resolve_turn() ──►  RESOLUTION  ── begin_next_turn() ──►  END ──► PLANNING
```

**Planning phase** (`Phase.PLANNING`, GameState.gd):
- `GameState.add_move_order()` — validates brigade exists, team matches, hex exists, within movement allowance, no double-order; returns a typed `OrderResult` (`ok`/`code`/`message`, plan 0017) — rejections are values, not `push_error`
- `GameState.add_commit_order()` — validates adjacency, not destroyed/admin-moved, no double-order; also returns `OrderResult`
- `GameState.eligible_commit_brigades()` — returns brigades adjacent to a hex that can commit
- Orders are stored in `orders[team]` / `commitments[team]` as `Array[MoveOrder]` / `Array[CommitOrder]`

**Resolution phase** (`Phase.RESOLUTION`, triggered by `GameState.resolve_turn(dice)`):
- Runs the full ordered pipeline (see §4)
- Sets phase to `Phase.END`, emits `phase_changed`, `combat_resolved`, `turn_resolved`

**End → next turn** (`GameState.begin_next_turn()`):
- Resets per-turn brigade flags (`moved_this_turn`, `moved_admin_this_turn`, `fought_this_turn`)
- Clears both order and commitment buffers for both teams
- Increments `turn_number`, sets phase to `PLANNING`, emits `phase_changed`

## 4. `resolve_turn` Stage Order (TurnConductor.gd)

`TurnConductor.resolve_turn` is the ONE place the order is written down; the phase modules own how a
phase resolves, never when it runs. The resolution runs exactly this pipeline:

1. **IJFS** — `FiresPhases.resolve_ijfs_turn(dice)` — Red joint/air-missile fires: multi-day pre-invasion warmup on first call, single-day cycles thereafter. Builds/strikes anti-ship targets, SAMs, and maneuver units. Sub-stream: `dice.derive("ijfs:<turn>:<day>")`.
2. **IJFS maneuver casualties** — `FiresPhases.apply_ijfs_maneuver_casualties()` — the warmup's writeback reduces the ground OOB before combat. Deterministic, no dice.
3. **Sealift** — `ReinforcementPhases.resolve_sealift_turn()` — `SealiftTransitions` ticks the ship return/reload pipeline, then `SealiftResolver` plans this turn's wave and the two authorities apply it (troops via `ForceTransitions`, hulls via `SealiftTransitions`), all BEFORE the crossing, so anti-ship attrits exactly the hulls that sail. Dice-free.
4. **Anti-ship** — `FiresPhases.resolve_antiship_turn(dice)` — Green coastal anti-ship fires + mine warfare against the Red crossing. Applies IJFS writeback (destroyed/suppressed launchers), resolves firing plan, crossing damage, mine losses; drowned BNs leave their rosters via `RosterMutations.apply_crossing_casualties`. Sub-stream: `dice.derive("antiship:<turn>")`.
5. **Offload** — `ReinforcementPhases.resolve_offload_turn(dice)` — surviving BNs land at beaches/ports; infrastructure lifecycle ticks every turn. Applies `pending_lost_at_sea` from the crossing.
6. **ROC mobilization** — `ReinforcementPhases.resolve_mobilization_turn()` — Green's reinforcement step at the same seam as Red's. Dice-free.
7. **Air insertion** — `ReinforcementPhases.resolve_air_insertion_turn(dice)` — Red's non-amphibious arrival path, after IJFS because the drop's attrition reads the air-defence picture those fires produced. Own sub-stream.
8. **Movement** — `apply_move_orders(RED)` then `apply_move_orders(GREEN)`. `ForceTransitions` moves the brigade and applies `moved_this_turn` / organization cost. Skipped when `disabled_phases` contains `movement` (plan 0012).
9. **Contested hexes** — `find_contested_hexes()` scans every hex for both teams present. Skipped (buffer cleared) when `disabled_phases` contains `ground_combat`.
10. **Combat-loop snapshots** — `ReinforcementPhases.isolated_air_landed_brigades()` and `GameStateData.refresh_not_ashore_by_type()` are computed ONCE here so no two hexes disagree about supply corridors or who is ashore (plans 0032, 0037).
11. **Ground combat** — for each contested hex, `resolve_combat_at(hex_id, dice.derive("combat:<turn>:<hex>"))` runs `CombatResolver.resolve_at()`, applies casualties through `RosterMutations.apply_casualty` → `ForceTransitions`, accumulates FEBA movement.
12. **FEBA retreats** — `apply_feba_retreats()` pushes retreating brigades out of hexes where `|feba_km| ≥ 10km`; placement updates go through `ForceTransitions`.
13. **Hex ownership** — `GameData.recompute_hex_ownership()` → `MapTransitions`: RED-only → RED, GREEN-only → GREEN, both → CONTESTED, and a hex with no live brigade is left ALONE (it keeps its last owner). Each combat summary is then annotated with `owner_after`.
14. **Supply** — `TurnClosure.resolve_supply_turn()`: `SupplyResolver.resolve` bills every LANDED Red battalion, decrements `supply_state.current_dos_tons`. Runs after combat so the bill covers who actually fought.
15. **Cleanup** — `TurnClosure.resolve_cleanup_phase()`: recomputes hex ownership a second time (retreats in step 12 can have moved brigades since step 13), resets `antiship_system` per-turn flags, runs the Taiwan battalion census, evaluates victory for game-over.
16. **End-of-turn tripwires** (debug builds only) — `GameData.validate_runtime_indexes()` and `RosterMutations.pending_pool_roster_violations()` assert at the settled boundary.

`resolve_frontline_phase` is **not** in this pipeline: it takes operator-drawn polyline coordinates
and is called only through the `GameState` façade.

## 5. `play_turn` / TurnResult / Event Log

**AI-readiness entrypoint** — `GameState.play_turn(red_orders, green_orders, dice)`:

```gdscript
func play_turn(red_orders: Array, green_orders: Array, dice: Dice = null) -> TurnResult
```

- Accepts bulk order arrays (dicts with `kind`, `brigade_id`, `target_hex`, `mode`)
- Buffers all orders via `add_move_order` / `add_commit_order`
- Calls `resolve_turn(dice)`
- Builds and returns a typed `TurnResult` resource

**TurnResult** (`scripts/model/TurnResult.gd`):
- Snapshot of all per-turn summaries: `combat_summaries`, `ijfs_summary`, `ijfs_writeback`, `antiship_summary`, `frontline_summary`, `cleanup_summary`
- `contested_hexes` — which hexes saw combat
- `events` — `Array[TurnEvent]` built by `TurnEventLog.build(self)`
- `game_over` / `winner` — from end-of-turn victory census
- `to_dict()` for JSON serialization (LLM API output)

**TurnEventLog** (`scripts/TurnEventLog.gd`):
- Pure derivation from GameState's post-resolve buffers (reads order buffers, last_* summaries)
- Ordered sequence: IJFS → anti-ship → moves → commits → combats → frontline → cleanup
- Events are `TurnEvent` resources with `seq`, `kind`, `hex_id`, `team`, `data`
- Must run BEFORE `begin_next_turn()` clears order buffers (guaranteed by `play_turn()`)

**Important**: The caller remains in `Phase.END` after `play_turn()` and must call `begin_next_turn()` separately to advance.

## 6. Determinism

Every pure-logic path must receive an injected `Dice` instance — no calls to global `randi()`/`randf()`.

- **`Dice`** (abstract): interface with `roll_d100()`, `choose_indices()`, `randf()`, `weighted_choice()`, `weighted_choices()`, `shuffle_indices()`, `derive()`.
- **`SeededDice`**: wraps Godot `RandomNumberGenerator` with a fixed seed in `_init(seed_value)`. `derive(label)` returns a new `SeededDice` with `hash(str(seed) + ":" + label)` for independent sub-streams (IJFS, anti-ship, combat are all isolated).
- **Enforcement**: `tools/validate_no_global_rng.gd` runs as part of `run_all_tests.ps1` and greps for `randi()`/`randf()` outside test files.
- **Seed required**: the `end_turn` action in the LLM API rejects missing `seed` — no implicit global fallback.

## 7. GameData — What It Loads

GameData autoloads in `_ready()` → `load_all()` (line 40–52):

| Source | Method | Key lookups |
|---|---|---|
| `data/taiwan_hex_grid.json` | `load_hex_grid()` | `hex_lookup` (id→Hex), `coord_lookup` (Vector2i→id), `hex_states` (id→`HexState`, filled by `MapTransitions` after a successful parse) |
| \(neighbors via HexMath\) | `build_neighbor_lookup()` | `neighbor_lookup` (id→Array[String]) |
| `data/pla_ground_forces.json` + `roc_ground_forces.json` | `load_brigades()` | `brigades` (id→Brigade), `brigades_by_hex` (hex→Array[id]) |
| `data/scenarios/scenario_default.json` | `load_scenario()` | `turn_length_days`, `red_dos_start`, `stacking_soft_cap`, `victory_config`, `red_ship_reserve`, placements → `set_brigade_hex` |
| `data/theaters.json` | `load_theaters()` | `active_tos`, `to_adjacency`, `beach_to_to` |
| `data/beaches.json` | `load_beaches()` | `beaches` (id→BeachDef: capacity, offload_rate, category, etc.) |
| `data/ships.json` | `load_ships()` | `ship_defs` (id→ShipDef: capacity, category, decoy flag, etc.) |

Key helpers: `set_brigade_hex()` delegates position + `brigades_by_hex` index updates to `ForceTransitions`; `recompute_hex_ownership()` / `apply_feba_delta()` / `clear_feba()` delegate per-hex runtime state to `MapTransitions` — ownership is derived from brigade presence for OCCUPIED hexes only, never reset across the whole map; `snapshot_state(pending_pools)` returns a deterministic key-sorted dict for golden testing; the pools
argument is required and makes it report battalions ashore rather than whole rosters (plan 0037).

## 8. TIV Relationship

HexCombat's turn engine is an **adaptation**, not a port. TIV (`TaiwanInvasionViewer/src/models/game_state.py`) uses a **Flask/SQLite phase-driven view model** — each phase (IJFS → Antiship → Offload → BOOTS → Cleanup) is a `GameView` enum value, persisted to SQLite, and advanced via UI navigation (`GameView` sequence at TIV `game_state.py:18–25`).

**What maps:**
- The **phase-run order** is the same: IJFS → Anti-ship → Offload → BOOTS (ground combat) → Cleanup.
- Each phase's data inputs and outputs (manifests, strike logs, supply ledgers) are conceptually equivalent.
- `GameView.IJFS` / `ANTISHIP` / `OFFLOAD` / `BOOTS` / `CLEANUP` → HexCombat's `resolve_ijfs_turn`, `resolve_antiship_turn`, `resolve_offload_turn`, etc.

**What is HexCombat-original:**
- **WeGo planning layer** — TIV has no order buffers; each phase is a full-run-you're-done view. HexCombat's `Phase.PLANNING`, `add_move_order()`, `add_commit_order()`, `commitments[]` and `orders[]` are entirely new.
- **Godot autoload architecture** — `GameData`/`GameState`/`EventBus` replace TIV's SQLite persistence + DataManager.
- **Injectible Dice & determinism** — TIV uses Python `random` without seed management. HexCombat's `SeededDice`/`derive()` sub-streams enforce reproducibility.
- **`play_turn()` / LLM API** — the bulk-order → `TurnResult` entrypoint is built for headless AI play; TIV has no equivalent.
- **FEBA retreats, victory census, frontline phase** — HexCombat adds these as post-combat cleanup stages absent from TIV's view model.
- **Signal/event bus** — `EventBus` signals replace TIV's Tornado/HTTP event model.

## 9. State & authority

This subsystem mutates the **`force`** aggregate through phase transitions. Its designated authority is `ForceTransitions`.
- **Outcome/receipt types:** `ForceActivityRequest`, `ForcePlacementReceipt`.
- **Manifest:** [tools/mutation_authority_manifest.json](../../../tools/mutation_authority_manifest.json).

The transport phases also drive the **`sealift_fleet`** aggregate (`SealiftTransitions`, plan 0045),
the anti-ship establishment (`AntishipTransitions`, plan 0043), and — since plan 0047 — the **`map`**
aggregate (`MapTransitions`, reached through the `GameData` façades at five ownership seams plus the
two FEBA sites in `TurnConductor`) and the **`infrastructure`** aggregate (`InfrastructureTransitions`,
applied inside the offload phase). The rule the turn loop enforces is
ordering, not ownership: a phase that moves troops AND hulls calls each authority in turn and asserts
both receipts, and the phase closes with `SealiftTransitions.project_fleet` so no later phase reads a
fleet whose bins are stale. Rules per aggregate live in the owning system docs.

Since plan 0049 the turn loop also owns three aggregates of its own:

| Aggregate | Authority | Owns | Operations |
|---|---|---|---|
| `turn_lifecycle` | `TurnLifecycleTransitions` | `turn_number`, `phase`, `game_over`, `winner`, `_china_has_landed` | `begin_resolution` / `end_resolution` / `begin_next_turn` (the three legal edges), `reset_to_turn_one`, `apply_cleanup_verdict(state, CleanupSummary)` |
| `order_buffers` | `OrderTransitions` | `orders`, `commitments`, `air_insert_orders`, `jlsf_orders` | `add_*` per order kind, `apply_bulk_order`, `clear_turn_buffers`, `reset_buffers`, `consume_*` |
| `supply` | `SupplyTransitions` | see `docs/systems/supply-dos/supply-dos.md` §8 | reached from `TurnClosure` |

**Rules:**
- Every brigade placement, activity write, and protected roster shrink uses the `ForceTransitions` API.
- **There is no phase setter.** `TurnConductor` still owns the phase ORDER and asks the lifecycle
  authority for the two edges around its call list; an illegal transition is inexpressible rather than
  refused, and a legal edge from the wrong source phase is refused without mutating anything.
- The turn counter moves on exactly one edge (`begin_next_turn`).
- Order legality lives in `OrderValidator` (`scripts/calc/`), which appends nothing; the authority
  asks it and appends only on accept, so a rejection cannot half-apply.
- Ownership facts live only in the manifest.
