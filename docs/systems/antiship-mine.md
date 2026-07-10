# Anti-ship & Mine Warfare (D3)

## 1. Purpose

Resolves **Green coastal anti-ship missile strikes** against the **Red amphibious crossing fleet**, then applies **mine losses** as ships transit approach lanes. Output: ship hulls sunk/damaged per type, which propagates to BN-equivalent losses at sea (`pending_lost_at_sea`). Runs each turn after IJFS (Green systems suppressed/destroyed first) and before offload (only survivors land).

## 2. Files & Responsibilities

| File | Role |
|---|---|
| `scripts/resolvers/AntishipResolver.gd` | Pure resolver (Phase C): `resolve()` — applies the IJFS writeback, builds the firing plan, resolves launch attrition/crossing/mines, converts ship losses to BNs lost at sea. Read its header for the purity boundary with `GameState`. |
| `scripts/GameState.gd` | Thin wrapper: `resolve_antiship_turn(dice)` derives the independent substream, materializes the TO-adjacency map, delegates to `AntishipResolver.resolve()`, then assigns `ship_reserve`/`fleet` fields, calls `register_ship_losses`, and owns the `EventBus.antiship_resolved` emit. |
| `scripts/AntishipCalculator.gd` | D3-B2 firing-plan + launch attrition |
| `scripts/AntishipCrossing.gd` | D3-B3 6-stage crossing-damage model |
| `scripts/AntishipMagazine.gd` | Magazine/ammo reservation + deduction |
| `scripts/AntishipLoaders.gd` | Loads all `data/antiship/*.json` |
| `scripts/MineWarfareService.gd` | D3-C geometric mine danger model |
| `scripts/ShipLoadingModel.gd` | `resolve_bn_losses` — ship hulls → BN losses |
| `scripts/model/ShipDef.gd` | Ship template (capacity, category, is_decoy) |
| `scripts/model/ShipState.gd` | Runtime fleet counts (ready/sent/surviving/etc) |
| `scripts/model/IndividualShip.gd` | Per-hull state (unused by crossing; deferred) |
| `scripts/model/Minefield.gd` | One beach minefield (config + runtime fields) |
| `scripts/model/AntishipSystem.gd` | One anti-ship launcher row (TO,type,quantity) |
| `data/antiship/*.json` | 6 data files (see §7) |

## 3. Crossing Damage Model (D3-B3)

**Entrypoint**: `AntishipCrossing.resolve_crossing_damage`.

Six RNG-consuming stages, each consuming injected `Dice` in sorted order so results are seed-independent:

1. **Launches** (`_resolve_launches`): For each `systems_fired` row, look up the launcher's `missiles_per_launcher` × `missiles` loadout in the combat catalog. Draw each munition from its per-munition pool (or shared `store_group` pool). Range tier gates: `own_to` / `neighboring` / `whole_island` via `_reachable_tos`. Half of any unfillable shortfall still launches (partial fire).
2. **In-flight failures** (`_apply_in_flight_failures`): Per-munition `in_flight_failure_rate` Bernoulli draw.
3. **Escort interception** (`_apply_interception`): Flatten surviving missiles, shuffle, group by `missile_group_size` (default 4). Each group picks one random escort defender (weighted uniform); defender attempts decrement. Group-wide `success_prob` determines leakers. Count-based (not per-hull magazine).
4. **Homing** (`_apply_homing`): Each leaker rolls discrimination against its munition's `discrimination_ability`. Discriminating missiles target real ships weighted by `target_value * count`; non-discriminating hit all ships (including decoys). Screen preference multiplier (`screen_target_preference`, default 3.0) biases toward escorts + decoys.
5. **Terminal defense** (`_apply_terminal_defense`): Per (ship_type, munition) defense probability computed from `base_probability` + susceptibility/capability adjustments.
6. **Damage resolution** (`_resolve_damage`): Hits → shuffled order → random hull assignment. Fresh hull → damaged (p_neut hit) or sunk; damaged hull re-hit → sunk at `damaged_hull_neut_multiplier` (1.5×). Sunk-hull overkill → `wasted_hits`.

**Result**: `missile_stage_totals` (missile counts) + `casualty_totals` (hull counts) — deliberately separate units, never summed. Full ledgers: `destroyed_by_ship_type`, `damaged_by_ship_type`, per-stage munition counts.

**Per-hull divergence**: TIV's `resolve_crossing_damage` dispatches per-hull variants (`_apply_interception_per_hull`, `_apply_terminal_defense_and_resolve_damage_per_hull`) tracking escort magazines (hq10/hhq9) and damage-status combat multipliers. This port uses count-based equivalents (also present in TIV source). Per-hull escort-magazine depletion is deferred.

## 4. Mine Warfare (D3-C)

**Entrypoint**: `MineWarfareService.resolve_ship_losses`.

**Geometric model — a port of `TaiwanDefenseRefactor/mine_warfare.py`** (the Python sister repo:
`create_minefield`, `calculate_ship_path`, `count_dangerous_mines(... danger_radius=50)`,
`process_mine_hits`), adapted to HexCombat's count-based per-turn fleet. (Confirmed against
`C:/Users/mdogg/My Drive/Projects/TaiwanDefenseRefactor/mine_warfare.py`.) The TaiwanDefenseRefactor
source is ALSO a flat-Cartesian length×width path model — so HexCombat's flat geometry matches its
actual source. **Note:** this is a *different* source from TIV's own `services/antiship/mine_warfare_service.py`,
which is a separate sweep-based beach model (`hits = dangerous_after_sweep`); HexCombat deliberately
sourced the richer geometric model from the sister repo instead (see the design premise documented
in `MineWarfareService.gd`'s header). The decoy-sponge / ascending-value transit ordering is
HexCombat's adaptation of that premise.

1. **Geometry** (`_count_dangerous_mines`): `num_mines` scattered uniformly in a `length × width` field. Fleet takes a randomized straight approach path (random incident angle [30–60°] + entry point [0.3–0.7]). Only mines within `danger_radius` (50 m) of the path line are **dangerous** — typically a handful, not all `num_mines`. Each encounter re-rolls layout + path via the injected Dice.
2. **Pre-landing clearing**: `assigned_sweepers × prelanding_clear_per_sweeper` dangerous mines cleared. Default `prelanding_clear_per_sweeper = 1` → mainly locates the field, not open the lane.
3. **Transit**: Surviving crossing fleet runs the lane — **decoys first** (each detonates mines until neutralized, acting as sponges), then real ships by ascending value. Each ship detonates one dangerous mine; neutralization probability from `neutralization_probabilities` keyed by the ship's likelihood label. The label is resolved in `AntishipResolver.mine_ship_meta` (called via `GameState._mine_ship_meta`) with precedence **decoy override > per-hull `ShipDef.mine_neutralization_likelihood` (optional, from `ships.json`) > the transit `neutralization_likelihood_by_category` table** (the fallback; no production hull overrides yet, so today it's purely category-driven). Lane opens after first transit (`lane_cleared`); later waves are safe.

**Config knobs** in `data/antiship/minefields.json`: `geometry.{minefield_length, minefield_width, danger_radius, incident_angle_min_deg, incident_angle_max_deg, entry_point_min, entry_point_max}` and `transit.{prelanding_clear_per_sweeper, neutralization_probabilities, neutralization_likelihood_by_category, decoy_neutralization_likelihood}`.

**Adaptation note**: the ported source (`TaiwanDefenseRefactor/mine_warfare.py`) operates on a
flotilla DataFrame (`process_mine_hits`); HexCombat re-expresses it over its per-turn count-based fleet
pool and re-rolls the path/layout each encounter via the injected Dice (no persistent per-beach seed).
TIV's separate `mine_warfare_service.py` (great-circle `offset_coordinate_meters` + per-seed
`_dangerous_mine_order`) is a different model and is not the source here.

## 5. Magazine / Ammo (D3-B2.5)

**Entrypoint**: `AntishipMagazine`.

- **Shared pool**: 8 magazine keys (e.g. `block_i`, `hf_ii`, `block_ii_aircraft`) with initial counts from `data/antiship/antiship_magazine_defaults.json`.
- **Three modes** (per type_id loadout): `additive` (consume every entry), `cross_draw` (consume from any entry, primary first), `aircraft_pool` (per-entry `platform_cap`; aircraft exempt from on-kill deduction).
- **`cap_launcher_count`**: How many launchers the remaining pool can support (aircraft_pool only; non-aircraft uncapped).
- **`reserve_full_volley`**: Full-volley-or-nothing — on shortfall returns 0 without mutating counts.
- **`deduct_launcher_kills`**: On-kill deduction for ground launchers. Aircraft exempt.
- Deterministic — no RNG.

**Current wiring**: `AntishipResolver.resolve` passes `null` for magazine to `AntishipCalculator.build_firing_plan`. Rebuilt-per-turn it would start full and never bind. Meaningful gating needs persistent cross-turn state (logged as follow-up; plan 0001, docs/plans/).

## 6. Ship Loss → BN Lost-at-Sea

**Entrypoint**: `ShipLoadingModel.resolve_bn_losses`.

- Compute `capacity_lost = Σ(destroyed[type] × capacity[type])`.
- `bn_equiv_lost = floor(capacity_lost + accumulator)`. Fractional remainder carried to next turn via `accumulator`.
- BNs at sea are shuffled via `dice.shuffle_indices`; the first N are lost.
- If the pool is exhausted, unrealized capacity stays in the accumulator (not silently dropped).
- `AntishipResolver.resolve` applies the accumulator and computes the surviving `ship_reserve` (via `remaining_reserve_after_losses`); `GameState.resolve_antiship_turn` assigns the returned reserve/accumulator and calls `register_ship_losses`.

## 7. Data Files

| File | Holds |
|---|---|
| `data/antiship/antiship_combat_catalog.json` | Munition properties (quantity, failure rate, lethality, discrimination, susceptibility) + launcher specs (missiles_per_launcher, range_tier, loadout) + store_groups (shared pools) |
| `data/antiship/antiship_crossing_config.json` | Escort interception (attempts/success_prob per type), discrimination probabilities, terminal defense (base + adjustments), neutralization likelihoods, lethality multipliers, ship profiles (target_value, vulnerability, terminal_defense_capability, is_decoy), launch_attrition params |
| `data/antiship/antiship_magazine_defaults.json` | Magazines (key → initial count) + per-type_id loadout (mode, entries, is_aircraft) |
| `data/antiship/minefields.json` | `available_minesweepers`, geometry knobs, transit config, per-beach minefield blocks (beach_id, name, to_number, num_mines, mines_per_sweeper_per_day) |
| `data/antiship/antiship_systems_consolidated.json` | System type definitions (id, name, detectability, deprecated, special flag) |
| `data/antiship/antiship_grouping_spec.json` | Platform groups → group_sizes × to_assignments → container rows (type_id, ijfs_profile, detectability) |
| `data/ships.json` | Ship definitions (category, carrying_capacity_bn_equiv, is_decoy, infrastructure, etc) — shared with D0 offload |

## 8. Key Functions

| Function | One-liner |
|---|---|
| `AntishipCalculator.build_firing_plan(systems, ijfs, targets, fire_pcts, destroyed_pcts, mag)` → `{allocation_plan, destroyed_firing_plan}` | Build row-level intended firing allocations capped by availability + magazine |
| `AntishipCalculator.resolve_launch_attrition(systems, plan, destroyed, config, dice)` → `{systems_fired, launch_attrition}` | Per-launcher detect/destroy/intercept draw, mutates system rows |
| `AntishipCalculator.allocate_firing_to_rows(qty_list, total)` → `int[]` | Proportional largest-remainder allocation across availability rows |
| `AntishipCrossing.resolve_crossing_damage(systems_fired, ship_snaps, catalog, config, targets, dice, [active_tos, to_adj])` → `Dict` | 6-stage crossing pipeline (launches → failures → intercept → home → terminal → damage) |
| `AntishipMagazine.reserve_full_volley(type_id, count)` → `int` | Full-volley-or-nothing: reserve magazines; 0 on shortfall |
| `AntishipMagazine.deduct_launcher_kills(type_id, destroyed)` → `void` | On-kill magazine deduction (aircraft exempt) |
| `MineWarfareService.resolve_ship_losses(fields, beaches, assignments, fleet, dice, meta, config)` → `Array[Dict]` | Geometric mine danger: path RNG → dangerous count → clearing → transit |
| `MineWarfareService._count_dangerous_mines(n, len, wid, radius, angle_min, angle_max, entry_min, entry_max, dice)` → `int` | Scatter n mines, random path, count within danger_radius |
| `ShipLoadingModel.resolve_bn_losses(destroyed, capacities, at_sea, acc, dice)` → `{bns_lost, lost_ids, bn_equiv_lost, capacity_lost, accumulator}` | Ship hull losses → BN-equiv losses with fractional carry |
| `AntishipLoaders.load_combat_catalog(path)` → `Dict` | Load & validate antiship combat catalog JSON |
| `AntishipLoaders.load_crossing_config(path)` → `Dict` | Load & validate crossing config JSON |
| `AntishipLoaders.load_minefields(path)` → `Array[Minefield]` | Parse beach minefield blocks into Runtime resources |
| `AntishipLoaders.load_systems(grouping_path, types)` → `Array[AntishipSystem]` | Aggregate platform groups into per-(TO, type) rows |

## 9. Turn Flow (`AntishipResolver.resolve`, called by `GameState.resolve_antiship_turn`)

The pipeline runs inside the pure resolver `scripts/resolvers/AntishipResolver.gd` (Phase C of the
GameState decomposition — read its header for the full purity boundary). `GameState.resolve_antiship_turn`
is now a thin wrapper: derive the independent `"antiship:<turn>"` substream, materialize the
TO-adjacency map (Theaters reads the GameData autoload internally, so this must happen in the
wrapper), call `AntishipResolver.resolve()`, then assign the returned `ship_reserve`/`fleet`
fields, call `register_ship_losses`, and emit `EventBus.antiship_resolved`.

```
IJFS writeback (destroyed/suppressed) ──┐
                                          v
  AntishipResolver.resolve(...)
    │
    ├─1. Gather BNs at sea → target beaches → target TOs
    │
    ├─2. Build firing_percentages from IJFS writeback + C2 suppression
    │
    ├─3. AntishipCalculator.build_firing_plan()  ← ── magazine=null (not wired)
    │      → allocation_plan
    │
    ├─4. AntishipCalculator.resolve_launch_attrition()
    │      → systems_fired, launch_attrition
    │
    ├─5. build_sent_fleet() → sent snapshots (crossing wave)
    │
    ├─6. AntishipCrossing.resolve_crossing_damage()
    │      → crossing result (destroyed/damaged by ship type)
    │
    ├─7. apply_ship_losses_to_fleet() → deduct crossing losses from fleet_pool
    │
    ├─8. MineWarfareService.resolve_ship_losses()
    │      → per-beach mine resolutions
    │
    ├─9. Combine crossing + mine destroyed_by_type
    │
    ├─10. ShipLoadingModel.resolve_bn_losses()
    │       → lost_ids, accumulator, bn_equiv_lost
    │       → remaining_reserve_after_losses()
    │
    └─11. Return {summary, remaining_ship_reserve, bn_equiv_lost, accumulator} to the
          GameState wrapper, which assigns fields, calls register_ship_losses, and emits
          EventBus.antiship_resolved
```

Feeds from: IJFS (Green system destroyed/suppressed writeback). Feeds into: offload (survivors land; `pending_lost_at_sea` threads BN losses to the D0-C seam).

## 10. TIV-Port Fidelity Notes

**Orchestrator-verified (2026-06-29):** the crossing pipeline mirrors TIV `antiship_crossing.py`
stage-for-stage (`_resolve_launches`/`_apply_interception`/`_apply_homing`/`_resolve_damage`…), and the
mine model is a confirmed port of `TaiwanDefenseRefactor/mine_warfare.py` (functions verified present).
No new design decisions — the cross-repo mine-source choice and the count-based-vs-per-hull and
per-category-neutralization items are already settled/logged (`port_audit.md`, `PLAN.md` D3 decisions).
Two sources feed D3: **TIV** (`antiship_crossing.py`, `antiship_firing_plan.py`,
`antiship_launch_attrition.py`, `antiship_magazine_service.py`) for missiles/crossing; **TaiwanDefenseRefactor**
(`mine_warfare.py`) for mines.

| Component | Status |
|---|---|
| **`AntishipCalculator.build_firing_plan`** | **1:1 port** of `antiship_firing_plan.py` — allocation, destroyed-firing totals, type-key encoding adapted for GDScript dict limits (string `<to>:<type>` vs TIV's tuple keys). |
| **`AntishipCalculator.allocate_firing_to_rows`** | **1:1 port** of `antiship_allocation.allocate_firing_to_rows` — proportional largest-remainder. |
| **`AntishipCalculator.resolve_launch_attrition`** | **1:1 port** of `antiship_launch_attrition.py` — detect→destroy draw order, per-type config, `p_intercept_before_launch`. The `Final_Attrition_Pct` DB column not ported. |
| **`AntishipCrossing`** | **Count-based port** — all 6 stages match `antiship_crossing.py` count-based equivalents. Per-hull variants (escort magazine tracking, `ship_readiness_policy`) are **deferred** (PLAN.md Decision 2026-06-27 D3-B3). RNG formula + draw order mirrored but NOT Python's bitstream. |
| **`AntishipMagazine`** | **1:1 port** of calculator-pure parts of `antiship_magazine_service.py` (reserve, cap, deduct). DB seed/load/persist functions not ported. |
| **`MineWarfareService`** | **Port of `TaiwanDefenseRefactor/mine_warfare.py`** (geometric: `create_minefield`/`calculate_ship_path`/`count_dangerous_mines`(danger_radius=50)/`process_mine_hits`), adapted to the count-based per-turn fleet. The decoy-sponge / ascending-value transit ordering is HexCombat's adaptation of the user-requested "push a lane" premise (documented in `MineWarfareService.gd`'s header). **TIV's own `mine_warfare_service.py` (sweep-based, great-circle) is a different model and intentionally NOT the source** — a deliberate cross-repo design choice, not a discrepancy. Per-ship-type neutralization uses a per-category table (high/medium/low) → REFINE item in `port_audit.md`. |
| **`resolve_bn_losses`** | **1:1 port** of TIV `_apply_casualties` — capacity-weighted fractional accumulator. TIV's transport-weight BN sampling reduced to uniform shuffle (all BNs = 1.0 BN-equiv). |
| **Magazine in turn flow** | **Deferred**: `resolve_antiship_turn` passes `null` for magazine. Persistent cross-turn magazine state needed. |

**Mirrored tests**: `tests/antiship_firing_plan_test.gd`, `tests/antiship_crossing_test.gd`, `tests/antiship_magazine_test.gd`.

**Open questions**:
- Per-hull escort-magazine (hq10/hhq9) depletion is not modeled; ship-level terminal-defense combat modifiers deferred until `IndividualShip` readiness is wired.
- The mine model re-rolls geometry per call (no persistent per-beach seed); this means the same Dice call produces different dangerous-mine counts on re-run. Intentional for HexCombat's per-turn freshness, but TIV uses a fixed seed per beach.
- Magazine gating in the turn flow: `null` passed currently. When wired, `from_defaults` must be called once and state persisted across turns (not rebuilt each turn).
