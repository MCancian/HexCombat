# 0014 — GameState Dependency Ceiling (via genuine decoupling)

> **CLOSEOUT (2026-07-19).** ✅ Shipped. All 5 phases landed byte-stable green (commits
> `db95b33`→`06a8d55`). Runtime state extracted to `scripts/model/GameStateData.gd`; orchestration
> / construction / order-validation moved to `static` services `TurnConductor` / `GameStateBuilder`
> / `OrderValidator` (`scripts/resolvers/`) that take a `GameStateData`, never the autoload —
> genuine decoupling (verified: no autoload `self` passed in; three correctness-review angles clean).
> `GameState` deps 48→24; ceiling enforced in the gate (`gd_metrics.py --check-ceiling`: GameState
> 27, TurnConductor 36). USER accepted 24 as the genuine typed-API floor (2026-07-19). Absorbed
> plan 0016. Durable facts: `docs/DECISIONS.md` (2026-07-19), `docs/STATUS.md` (Engine), class
> headers.

**Status:** ✅ Shipped 2026-07-19
**Priority:** Medium (Tech Debt / Architecture; unblocks future refactors)
**Absorbs:** Plan 0016 (Separate State Data from Autoload) — folded in as Phase 1. 0016 is
marked *Superseded by 0014*.

## Goal

`scripts/GameState.gd` (autoload `class_name GameStateType`) currently has **48 class
references** — the next-worst file is `GameData` at 18. It is both the mutable runtime-state
container *and* the turn conductor *and* the order validator. This plan reduces its dependency
count to **≤ 20** (target ~10) by genuinely decoupling those three roles, then enforces the
ceiling in the gate.

## Non-negotiable: this is GENUINE decoupling, not laundering

A prior attempt (reverted 2026-07-19) created `TurnConductor`/`OrderValidator` that took the
GameState autoload as `self` and reached back into its members. That only *relocated* the class
references to satisfy the metric — `TurnConductor` ended at 29 deps and coupling was unchanged.
**Do not do that.** The rule for this plan:

> Resolvers and builders are `static` and depend on the **`GameStateData` value type**, never on
> the `GameState` autoload singleton. They take typed inputs (`GameStateData`, `Dice`, plain
> values), mutate the passed `GameStateData` and/or return typed outputs. Reading the `GameData`
> content autoload (map/OOB/scenario content) is allowed — it is the universal read-only content
> source, not runtime state.

The distinction: a resolver signed `resolve(state: GameStateData, dice: Dice)` can be unit-tested
by constructing a `GameStateData` in isolation. A resolver signed `resolve(gs)` where `gs` is the
autoload cannot. The first is the target; the second is the rejected anti-pattern.

## Placement & naming conventions (match existing repo layout)

- State value classes live in `scripts/model/` (e.g. `SealiftState.gd`, `SupplyState.gd`). →
  **`GameStateData` goes in `scripts/model/GameStateData.gd`**, `extends RefCounted`,
  `class_name GameStateData`.
- Pure resolver/builder classes live in `scripts/resolvers/` (e.g. `SealiftStateBuilder.gd`). →
  the new `GameStateBuilder`, `TurnConductor`, `OrderValidator` go there,
  `extends RefCounted`, all methods `static`.

## The invariant that gates every phase

Every phase below must end **byte-stable**: `bash tools/run_all_tests.sh` → **ALL PHASES GREEN**
with zero golden drift and zero fixture drift. The golden gate exports
`HEXCOMBAT_SCENARIO=res://data/scenarios/scenario_golden.json` — the scripted beach-1 fight is pinned. If a
phase changes any pinned value, you did more than move code; stop and find what you changed.
Commit after each green phase (one phase = one commit).

---

## Phase 1 — Extract `GameStateData` (foundation; was plan 0016)

Move all **mutable runtime state** out of the autoload into a plain value object. The autoload
keeps a single reference to it and forwards the fields that external callers read.

### 1a. Create `scripts/model/GameStateData.gd`

```gdscript
extends RefCounted
class_name GameStateData

enum Phase { PLANNING, RESOLUTION, END }   # moved here with the `phase` field it types
```

Move these fields verbatim (names + types + comments) from `GameState.gd` lines 15–55 into
`GameStateData`:

| field | type |
|---|---|
| `turn_number` | `int` |
| `phase` | `Phase` |
| `turn_length_days` | `int` |
| `orders` | `Dictionary` |
| `commitments` | `Dictionary` |
| `ship_reserve` | `Array` |
| `fleet` | `Dictionary` |
| `sealift_state` | `SealiftState` |
| `infrastructure_state` | `InfrastructureState` |
| `jlsf_orders` | `Array[String]` |
| `pending_lost_at_sea` | `int` |
| `supply_state` | `SupplyState` |
| `last_contested_hexes` | `Array[String]` |
| `last_combat_summaries` | `Array[CombatSummary]` |
| `ijfs_state` | `IjfsDailyState` |
| `_ijfs_day` | `int` |
| `last_ijfs_summary` | `Dictionary` |
| `last_ijfs_writeback` | `IjfsWriteback` |
| `antiship_systems` | `Array` |
| `antiship_containers` | `Array` |
| `_antiship_built` | `bool` |
| `lost_at_sea_accumulator` | `float` |
| `last_antiship_summary` | `AntishipSummary` |
| `last_offload_summary` | `Dictionary` |
| `last_sealift_sent_by_type` | `Dictionary` |
| `last_frontline_summary` | `FrontlineSummary` |
| `last_cleanup_summary` | `CleanupSummary` |
| `game_over` | `bool` |
| `winner` | `String` |
| `_china_has_landed` | `bool` |

The typed-state class deps (`SealiftState`, `InfrastructureState`, `SupplyState`,
`IjfsDailyState`, `CombatSummary`, `IjfsWriteback`, `AntishipSummary`, `FrontlineSummary`,
`CleanupSummary`) **move with the fields** — this is the bulk of the dependency drop.

### 1b. Rewire the autoload

In `GameState.gd`:
- Replace all those `var` lines with `var data := GameStateData.new()`.
- Keep the constants that stay in the autoload for now (`MoveOrderResource`,
  `CommitOrderResource`, `FEBA_RETREAT_THRESHOLD_KM`) — they leave in Phases 3–4 with their logic.
- Every internal reference to a moved field becomes `data.<field>` (e.g. `turn_number` →
  `data.turn_number`, `phase` → `data.phase`). Mechanical, repo-wide within this file only.
- `reset_to_scenario()` (line 62) resets `data` fields the same way; keep the lazy-load comments.

### 1c. Preserve external callers with forwarding accessors

External code reads a **small** set of fields/methods directly (see map below). Keep them working
by giving `GameState` forwarding property getters/setters backed by `data`, so **no external file
changes**:

- Fields read externally: `turn_number`, `phase`, `ship_reserve`, `fleet`, `sealift_state`,
  `supply_state`. Add e.g. `var turn_number: int : get = _get_turn, set = _set_turn` forwarding
  to `data.turn_number` (or the cleanest GDScript idiom for property forwarding).
- Methods that just read fields (`orders_for`, `commitments_for`,
  `ship_reserve_priority_order`) stay on the autoload, now reading `data.*`.
- The `Phase` enum was on `GameStateType`; some code may reference `GameState.Phase.PLANNING` /
  `GameStateType.Phase`. **Grep first:** `grep -rn "\.Phase\b\|Phase\.PLANNING\|Phase\.RESOLUTION\|Phase\.END" scripts tests tools`. Re-expose the enum from the autoload (`const Phase = GameStateData.Phase`) so those references keep resolving, OR migrate them. Pick the option that leaves the fewest dangling refs.

### 1d. Gate → green (byte-stable). Commit: "Plan 0014 P1: extract GameStateData value object".

---

## Phase 2 — Extract builders → `GameStateBuilder` (returns typed values)

Create `scripts/resolvers/GameStateBuilder.gd` (static). Move the `_rebuild_*` bodies out of
`GameState.gd`; each becomes a static function that **takes explicit `GameData` fields and returns
the built typed object** (no `GameStateData`, no autoload):

| new static method | returns | delegates to | GameData fields read |
|---|---|---|---|
| `build_ship_reserve(red_ship_reserve, brigades)` | `Array` | `ShipReserveBuilder` | `red_ship_reserve`, `brigades` |
| `build_sealift_state(followon, red_ship_reserve, brigades, auto_seed, escort_reload_turns)` | `SealiftState` | `SealiftStateBuilder` (+ `AntishipLoaders.load_crossing_config`) | those + crossing config |
| `build_fleet(ship_defs)` | `Dictionary` | `FleetBuilder` | `ship_defs` |
| `build_supply_state(red_dos_start)` | `SupplyState` | `SupplyStateBuilder` | `red_dos_start` |
| `build_infrastructure_state(infrastructure)` | `InfrastructureState` | `InfrastructureStateBuilder` | `infrastructure` |
| `build_antiship_systems()` | `Dictionary`/`Array` pair — keep the current shape | `AntishipSystemsBuilder` | — |
| `build_ijfs_state(antiship_containers, brigades)` | `IjfsDailyState` | `IjfsStateBuilder` | `brigades` (filter GREEN, not destroyed) |

`reset_to_scenario()` and the lazy-build sites assign the results:
`data.sealift_state = GameStateBuilder.build_sealift_state(...)`, etc. This moves
`ShipReserveBuilder`, `SealiftStateBuilder`, `FleetBuilder`, `SupplyStateBuilder`,
`InfrastructureStateBuilder`, `IjfsStateBuilder`, `AntishipSystemsBuilder` (+ `AntishipLoaders`)
deps out of `GameState.gd`.

**Gate → green. Commit: "Plan 0014 P2: extract GameStateBuilder".**

---

## Phase 3 — Extract turn orchestration → `TurnConductor(state: GameStateData)`

Create `scripts/resolvers/TurnConductor.gd` (static). Move `resolve_turn` + every phase method +
`_resolve_combat_at` + their private helpers. **Every public method takes
`state: GameStateData` as the first arg** (plus `dice` where the current signature has it),
mutates `state`, and returns the same typed value the current method returns. Move
`FEBA_RETREAT_THRESHOLD_KM` here (its only consumer).

| autoload method (delegates) | conductor signature |
|---|---|
| `resolve_turn(dice=null)` | `resolve_turn(state, dice: Dice = null) -> void` |
| `resolve_ijfs_turn(dice)` | `resolve_ijfs_turn(state, dice) -> Dictionary` |
| `resolve_sealift_turn()` | `resolve_sealift_turn(state) -> void` |
| `resolve_antiship_turn(dice)` | `resolve_antiship_turn(state, dice) -> Dictionary` |
| `resolve_offload_turn(dice)` | `resolve_offload_turn(state, dice) -> Dictionary` |
| `resolve_supply_turn()` | `resolve_supply_turn(state) -> Dictionary` |
| `resolve_cleanup_phase()` | `resolve_cleanup_phase(state) -> Dictionary` |
| `resolve_frontline_phase(polyline)` | `resolve_frontline_phase(state, polyline) -> Dictionary` |
| `_resolve_combat_at(hex, dice)` | `_resolve_combat_at(state, hex, dice) -> CombatSummary` |

Each autoload method shrinks to one line, e.g.
`func resolve_turn(dice: Dice = null) -> void: TurnConductor.resolve_turn(data, dice)`.

Moves `IjfsResolver`, `SealiftResolver`, `AntishipResolver`, `OffloadResolver`,
`InfrastructureResolver`, `SupplyResolver`, `CleanupResolver`, `FrontlineResolver`,
`CombatResolver` (+ any summary/helper types now referenced only here) out of `GameState.gd`.

**Watch items:** the per-hex combat substream (`dice.derive("combat:<turn>:<hex>")`, plan 0010)
and the lazy IJFS/antiship build flags must behave identically — this is what the golden gate
protects. `EventBus.phase_changed.emit(...)` may need to stay on the autoload (signal owner) — if
so, have the conductor return enough for the autoload to emit, or pass the emit as the autoload's
responsibility. Decide for legibility; keep the emitted sequence identical.

**Gate → green (golden byte-stable). Commit: "Plan 0014 P3: extract TurnConductor".**

---

## Phase 4 — Extract order validation → `OrderValidator(state: GameStateData)`

Create `scripts/resolvers/OrderValidator.gd` (static). Move the four order methods; each takes
`state: GameStateData` first, reads `GameData`, mutates `state.orders` / `state.commitments`.
Move the `MoveOrderResource` / `CommitOrderResource` preloads here (their only consumers).

| autoload method (delegates) | validator signature |
|---|---|
| `add_move_order(team, brigade_id, target_hex, mode)` | `add_move_order(state, team, brigade_id, target_hex, mode) -> void` |
| `add_commit_order(team, brigade_id, target_hex)` | `add_commit_order(state, team, brigade_id, target_hex) -> void` |
| `eligible_commit_brigades(team, target_hex)` | `eligible_commit_brigades(state, team, target_hex) -> Array` |
| `_brigade_has_pending_order(team, brigade_id)` | `brigade_has_pending_order(state, team, brigade_id) -> bool` |

**Preserve `push_error` behavior EXACTLY.** Changing rejection to a `Result`/enum is **plan
0017's** job, not this one — the GdUnit tests still assert `assert_error().is_push_error(...)`.
Touch only the *location* of the logic, not its error semantics. Moves `MoveOrder`, `CommitOrder`,
`Movement` deps out of `GameState.gd`.

**Gate → green. Commit: "Plan 0014 P4: extract OrderValidator".**

---

## Phase 5 — Enforce the ceiling + closeout

1. **Measure** the new `GameState.gd` dep count:
   `python3 tools/gd_metrics.py . /tmp/m.json && python3 -c "import json;print(json.load(open('/tmp/m.json'))['files']['scripts/GameState.gd']['ndeps'])"`.
   Expect ~8–12. It should now be roughly: `GameStateData`, `GameStateBuilder`, `TurnConductor`,
   `OrderValidator`, `Brigade` (Team enum in signatures), `Dice`, `GameData`, `EventBus`.
2. **Add `--check-ceiling` to `tools/gd_metrics.py`** (a `ceilings` dict, exit 1 on breach). Set
   `{"scripts/GameState.gd": <measured + small headroom>}` — target ≤ 20, ideally ≤ 15.
   *Optional:* add a ceiling on `TurnConductor.gd` too, so it can't silently become the new
   god-object; if you do, set it at its genuine post-extraction count (it legitimately depends on
   all phase resolvers — that is cohesive, not laundered).
3. **Wire the check into the gate.** Re-add a "Metrics Validation" phase to
   `tools/run_all_tests.py` that runs `gd_metrics.py <root> <devnull> --check-ceiling` and fails
   on non-zero exit. (`.sh`/`.ps1` already wrap `run_all_tests.py` since plan 0015 — no change
   needed there.)
4. **Gate → green** with the ceiling active.
5. **Closeout** (per `hexcombat-docs-and-writing`):
   - Code headers on `GameStateData.gd`, `GameStateBuilder.gd`, `TurnConductor.gd`,
     `OrderValidator.gd` stating the purity boundary (static, takes `GameStateData`, no autoload).
   - `docs/DECISIONS.md`: 3–5-line entry — GameState split into value-data + three static
     services depending on the data type; ceiling enforced in the gate.
   - `docs/STATUS.md`: update the GameState/architecture bullet if one exists.
   - Update the plans README: move 0014 to Archived (real link to `docs/archive/`), and 0016 to
     `Superseded by 0014`.
   - Add closeout header, move this file to docs/archive (same basename) — not yet done as of this
     writing; a pre-existing `validate_doc_anchors.gd` dead-link false positive on the direct path
     citation was fixed by de-backticking this line (see plan-0014 branch P1 commit).

---

## Reference: exact structure (from the 2026-07-19 code map)

**External callers that must keep working (byte-stable API):**
- `resolve_turn`: `GameController.gd:105`, 7 test files, 5 `tools/validate_*.gd`.
- `add_move_order`: `GameController.gd:38`, `composition_test`, `game_state_test`,
  `movement_test`, 4 validators.
- `add_commit_order`: `GameController.gd:97`, `composition_test`, 2 validators.
- `eligible_commit_brigades`: `GameController.gd:141`, `composition_test:82`, 2 validators.
- Direct field reads: `turn_number`, `phase`, `ship_reserve`, `fleet`, `sealift_state`,
  `supply_state`, plus methods `orders_for` / `commitments_for` / `ship_reserve_priority_order`
  (in `GameController.gd` + tests). These are the only fields needing forwarding accessors.

## Deferred / out of scope
- **HexMap cosmetic literals** (Track F): deferred until Track D touches the view layer.
- **Const→data knob promotion** (Track F): blocked on a USER design call.
- **Order-rejection error type**: plan 0017 — keep `push_error` here.
