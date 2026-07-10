# Turn Engine & Data Services

## 1. Purpose

The turn engine is the game's runtime spine — four autoloads that together manage every
gameplay-relevant cycle:

| Autoload | Role | Node |
|---|---|---|
| `GameData` | **Static data service** — loads JSON (hexes, OOBs, scenario, beaches, ships, theaters) into typed `Resource` objects once at startup. Holds all lookups (`hex_lookup`, `neighbor_lookup`, `brigades_by_hex`, etc.). | `scripts/GameData.gd` |
| `GameState` | **Runtime turn/phase state** — owns the WeGo turn model (plan orders → resolve → next turn), order buffers, per-turn phase, IJFS/anti-ship/offload/supply/frontline sub-states, victory census. | `scripts/GameState.gd` (1261 lines) |
| `EventBus` | **Signal hub** — decouples subsystems via typed Godot signals (`phase_changed`, `turn_resolved`, `combat_resolved`, etc.). | `scripts/EventBus.gd` |
| `Dice` / `SeededDice` | **Injectable RNG abstraction** — base `Dice` (abstract, `RefCounted`), `SeededDice` (deterministic via `RandomNumberGenerator` with seeded `derive()` sub-streams). | `scripts/Dice.gd`, `scripts/SeededDice.gd` |

## 2. Files & Responsibilities

| File | Lines | Role |
|---|---|---|
| `scripts/GameState.gd` | 1261 | Turn orchestration: `Phase` enum (PLANNING/RESOLUTION/END), order buffers, `resolve_turn()`, `play_turn()`, `begin_next_turn()`, IJFS/anti-ship/offload/supply/frontline/cleanup sub-phases, FEBA retreats, victory census |
| `scripts/GameData.gd` | 546 | Data loading: `load_hex_grid()`, `load_brigades()`, `load_scenario()`, `load_theaters()`, `load_beaches()`, `load_ships()`. Indexes: `brigades`, `brigades_by_hex`, `hex_lookup`, `neighbor_lookup`, `hex_states`, `ship_defs`, `beaches`, `active_tos`, `to_adjacency`, `beach_to_to` |
| `scripts/Dice.gd` | 37 | Abstract base: `roll_d100()`, `choose_indices()`, `randf()`, `weighted_choice()`, `weighted_choices()`, `shuffle_indices()`, `derive()` |
| `scripts/SeededDice.gd` | 96 | Concrete: wraps Godot `RandomNumberGenerator` with a fixed seed. `derive(label)` creates an independent sub-stream via `hash(str(seed) + ":" + label)` |
| `scripts/EventBus.gd` | 21 | Signals: `phase_changed`, `turn_resolved`, `combat_resolved`, `offload_resolved`, `supply_updated`, `ijfs_resolved`, `antiship_resolved`, `frontline_resolved`, `cleanup_resolved` |
| `scripts/Theaters.gd` | 42 | Static TO helpers: `to_for_beach()`, `adjacent_tos()`, `all_tos()`, `are_adjacent()` — proxied via `GameData.beach_to_to` and `GameData.to_adjacency` |
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
- `add_move_order()` (line 119) — validates brigade exists, team matches, hex exists, within movement allowance, no double-order
- `add_commit_order()` (line 203) — validates adjacency, not destroyed/admin-moved, no double-order
- `eligible_commit_brigades()` (line 248) — returns brigades adjacent to a hex that can commit
- Orders are stored in `orders[team]` / `commitments[team]` as `Array[MoveOrder]` / `Array[CommitOrder]`

**Resolution phase** (`Phase.RESOLUTION`, triggered by `resolve_turn(dice)`, line 162):
- Runs the full ordered pipeline (see §4)
- Sets phase to `Phase.END` (line 197), emits `phase_changed`, `combat_resolved`, `turn_resolved`

**End → next turn** (`begin_next_turn()`, line 268):
- Resets per-turn brigade flags (`moved_this_turn`, `moved_admin_this_turn`, `fought_this_turn`)
- Clears both order and commitment buffers for both teams
- Increments `turn_number`, sets phase to `PLANNING`, emits `phase_changed`

## 4. `resolve_turn` Stage Order (GameState.gd)

The resolution runs exactly this pipeline:

1. **IJFS** (line 176) — `resolve_ijfs_turn(dice)` — Red joint/air-missile fires: multi-day pre-invasion warmup on first call, single-day cycles thereafter. Builds/strikes anti-ship targets, SAMs, and maneuver units. Sub-stream: `dice.derive("ijfs:<turn>:<day>")`.
2. **Anti-ship** (line 177) — `resolve_antiship_turn(dice)` — Green coastal anti-ship fires + mine warfare against the Red amphibious crossing. Applies IJFS writeback (destroyed/suppressed launchers), resolves firing plan, crossing damage, mine losses. Sub-stream: `dice.derive("antiship:<turn>")`.
3. **Offload** (line 178) — `resolve_offload_turn(dice)` — Surviving BNs land at locked beaches. Applies `pending_lost_at_sea` from anti-ship losses. Calls `OffloadCalculator.resolve_offload_day`.
4. **Movement** (lines 180–181) — `_apply_move_orders(RED)` then `_apply_move_orders(GREEN)`. Sets `moved_this_turn`, applies organization cost.
5. **Contested hexes** (line 182) — `_find_contested_hexes()` scans every hex for both teams present.
6. **Ground combat** (lines 183–187) — for each contested hex, `_resolve_combat_at(hex_id, dice)` runs `CombatCalculator.resolve_map_attack()`, applies casualties, FEBA movement.
7. **FEBA retreats** (line 188) — `_apply_feba_retreats()` pushes retreating brigades out of hexes where `|feba_km| ≥ 10km`.
8. **Hex ownership** (line 189) — `GameData.recompute_hex_ownership()`: RED-only → RED, GREEN-only → GREEN, both → CONTESTED.
9. **Combat summary ownership** (lines 190–193) — annotates each summary with `owner_after`.
10. **Supply** (line 194) — `resolve_supply_turn()`: `DosConsumption.calculate_consumption` for all active Red battalions, decrements `supply_state.current_dos_tons`.
11. **Cleanup** (line 195) — `resolve_cleanup_phase()`: resets `antiship_system` per-turn flags, runs Taiwan battalion census, evaluates `VictoryConditions.evaluate()` for game-over.

## 5. `play_turn` / TurnResult / Event Log

**AI-readiness entrypoint** — `play_turn(red_orders, green_orders, dice)` at line 1217:

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
| `data/taiwan_hex_grid.json` | `load_hex_grid()` | `hex_lookup` (id→Hex), `coord_lookup` (Vector2i→id), `hex_states` (id→{owner,feba_km}) |
| \(neighbors via HexMath\) | `build_neighbor_lookup()` | `neighbor_lookup` (id→Array[String]) |
| `data/pla_ground_forces.json` + `roc_ground_forces.json` | `load_brigades()` | `brigades` (id→Brigade), `brigades_by_hex` (hex→Array[id]) |
| `data/scenario_default.json` | `load_scenario()` | `turn_length_days`, `red_dos_start`, `stacking_soft_cap`, `victory_config`, `red_ship_reserve`, placements → `set_brigade_hex` |
| `data/theaters.json` | `load_theaters()` | `active_tos`, `to_adjacency`, `beach_to_to` |
| `data/beaches.json` | `load_beaches()` | `beaches` (id→BeachDef: capacity, offload_rate, category, etc.) |
| `data/ships.json` | `load_ships()` | `ship_defs` (id→ShipDef: capacity, category, decoy flag, etc.) |

Key helpers: `set_brigade_hex()` (line 273) mutates position + updates `brigades_by_hex` index; `recompute_hex_ownership()` (line 290) resets every hex's owner from brigade presence; `snapshot_state()` (line 514) returns a deterministic key-sorted dict for golden testing.

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
