# Supply (D2 — Red DOS Consumption)

## 1. Purpose

Red DOS (Days Of Supply) models consumable supply for PLA brigades that have **landed** on Taiwan. Each turn, every landed Red battalion adds to a tonnage burden based on **activity**: mechanized vs foot, whether it moved this turn, and whether it fought. Resulting tons are deducted from the Red supply pool; exhaustion triggers a `supply_effectiveness` combat modifier (deferred to later phases).

## 2. Files & responsibilities

| File | Role |
|---|---|
| `scripts/DosConsumption.gd` | `DosConsumption` (RefCounted). Constants, mechanized classification, per-unit tonnage, full-turn consumption summary. Pure logic; no Node/scene dependency. |
| `scripts/model/SupplyState.gd` | `SupplyState` (Resource). Holds `current_dos_tons: float` and `day_history: Array[Dictionary]`. Lightweight model object. |
| `scripts/GameState.gd` | Autoload runtime state. Holds `supply_state: SupplyState` (line 48). `resolve_supply_turn()` (line 384) drives consumption each combat turn. `_rebuild_supply_state()` (line 992) initialises the pool. |
| `scripts/GameData.gd` | Autoload. `red_dos_start: int` (line 18) loaded from scenario JSON (line 176). |
| `scripts/CombatCalculator.gd` | Reads `supply_effectiveness` from unit dict (line 227–229) — this is where a depleted pool would penalise combat. |
| `scripts/model/Brigade.gd` | Model class. Initialises each BN's `supply_effectiveness: 1.0` (line 42). |
| `scripts/EventBus.gd` | Fires `supply_updated(summary: Dictionary)` (line 17) so views/logs can react. |
| `scripts/LLMGameAPI.gd` | Exposes `supply_state` in `get_observation()` (line 32) via `_supply_state_observation()` (line 229). |

## 3. Constants (`DosConsumption.gd`)

```gdscript
const BASE_MECHANIZED_TONS: int = 300        # line 4
const BASE_NON_MECHANIZED_TONS: int = 150     # line 5
const TONS_PER_DOS: int = 150                 # line 6
```

`MECHANIZED_TYPE_HINTS` (line 27): `["mechanized", "tank", "armor", "combined arms", "amphibious"]`

`KNOWN_MECHANIZED_BATTALION_TYPES` (line 8): explicit whitelist — Combined Arms, Mechanized Infantry, Mechanized Artillery, Tank, Amphibious Infantry.

`KNOWN_NON_MECHANIZED_BATTALION_TYPES` (line 15): explicit blacklist — Air Assault, Special Forces, Field/Rocket Artillery, Air Defense, Reconnaissance, Service/Support, Attack/Utility Helicopter.

`BRIGADE_TYPE_HINTS` (line 28): `["mech", "armor", "amphibious"]` — fallback brigade-level check.

## 4. Activity formula

### Classification — `is_mechanized_bn(unit_type, brigade_type)` (line 31)

1. Whitelist check — if `unit_type` is in `KNOWN_MECHANIZED_BATTALION_TYPES` → mechanized.
2. Blacklist check — if in `KNOWN_NON_MECHANIZED_BATTALION_TYPES` → non-mechanized.
3. Substring hints against `unit_type` → mechanized if any `MECHANIZED_TYPE_HINTS` match.
4. Brigade fallback — if `brigade_type` matches any `BRIGADE_TYPE_HINTS` → mechanized.
5. Otherwise → non-mechanized.

### Tons — `compute_unit_tons(mechanized, moved, in_combat)` (line 54)

```
base = mechanized ? 300 : 150
reduction = 0
reduction += base / 3   if NOT moved
reduction += base / 3   if NOT in_combat
tons = base - reduction
```

A unit that **both moved and fought** burns the full base (300 or 150). Each omitted activity (idle or out of combat) reduces consumption by 1/3 of base. Integer division truncates.

### Examples (mechanized, base=300)

| moved | in_combat | reduction | tons |
|---|---|---|---|
| true | true | 0 | 300 |
| true | false | 100 | 200 |
| false | true | 100 | 200 |
| false | false | 200 | 100 |

## 5. Consumption summary — `calculate_consumption(units, moved_brigade_ids, engaged_brigade_ids, day)` (line 68)

Iterates all landed Red battalions (`_active_red_battalion_units()` — `GameState.gd:944`), classifies each, sums per-unit tons, and builds a by-brigade breakdown.

Returns a Dictionary with fields (see lines 127–142):

| Key | Type | Meaning |
|---|---|---|
| `applied` | bool | false until `resolve_supply_turn` sets it true |
| `day` | int | turn number |
| `unit_count` | int | total landed Red battalions |
| `red_dos_consumed_tons` | int | total tons consumed this turn |
| `baseline_dos_equivalent` | int | unit_count (naive 1 DOS/BN/day at 150t) |
| `activity_dos_equivalent_exact` | float | total_tons / TONS_PER_DOS |
| `activity_delta_exact` | float | activity − baseline |
| `activity_delta_rounded` | int | ceil of delta |
| `by_brigade` | Dictionary | per-brigade count, mech/non-mech split, moved flag, in_combat flag, tons |
| `mechanized_unit_count` / `non_mechanized_unit_count` | int | classification breakdown |
| `moved_unit_count` / `combat_unit_count` | int | activity breakdown |

## 6. Wiring — `GameState.resolve_supply_turn()` (line 384)

Called at the end of each combat turn (line 194, after `_apply_feba_retreats()` and `recompute_hex_ownership()`).

```
1. Collect landed Red battalions via _active_red_battalion_units().
2. Build moved_brigade_ids (brigade.moved_this_turn) and engaged_brigade_ids (brigade.fought_this_turn).
3. Call DosConsumption.calculate_consumption(...).
4. Deduct red_dos_consumed_tons from supply_state.current_dos_tons (clamped to 0).
5. Set summary.applied = true, record pool_before/pool_after.
6. Append to supply_state.day_history.
7. Emit EventBus.supply_updated.
```

**Initial pool:** `_rebuild_supply_state()` (line 992) sets `current_dos_tons = GameData.red_dos_start * TONS_PER_DOS` (100 × 150 = 15 000 tons in `scenario_default.json` line 5).

**Supply effectiveness:** `CombatCalculator._unit_supply_effectiveness()` (line 227) reads `supply_effectiveness` from the unit Dictionary (defaults to 1.0). Currently, `supply_effectiveness` is **always 1.0** — the pool-depletion → modifier linkage is deferred to the D4 IJFS phase (see comment at `GameState.gd:405`). The field is present on every BN (`Brigade.gd:42`, `UnitManager.gd:31`, `CombatForces.gd:20`) but currently unused in resolution.

**Flow summary (GameState.gd):**

```
resolve_combat_turn()
  → (resolve combats, FEBA, ownership)
  → resolve_supply_turn()          [line 194]
    → _active_red_battalion_units() [line 944]
    → DosConsumption.calculate_consumption() [line 398]
    → supply_state.current_dos_tons -= consumed [line 401]
    → EventBus.supply_updated.emit() [line 407]
```

## 7. TIV-port fidelity notes

**Oracle:** `TaiwanInvasionViewer/TaiwanInvasionViewer/src/services/red_dos_consumption.py`
(`calculate_red_dos_consumption`, `is_mechanized_red_unit`, `_compute_unit_tons`). (Note the source
tree is *nested* one level: `…/TaiwanInvasionViewer/TaiwanInvasionViewer/src/…`.)

**✅ Verified faithful (orchestrator, 2026-06-29) — near-exact port.** Confirmed directly against the
oracle:
- Constants identical: `BASE_MECHANIZED_TONS=300`, `BASE_NON_MECHANIZED_TONS=150`, `TONS_PER_DOS=150`.
- `MECHANIZED_TYPE_HINTS` identical: `("mechanized","tank","armor","combined arms","amphibious")`.
- Activity formula identical: `base − (base/3 if not moved) − (base/3 if not in_combat)` (GDScript
  `int/3` == TIV's `// 3`).
- `calculate_consumption` summary matches `calculate_red_dos_consumption` field-for-field:
  `baseline_dos_equivalent = unit_count`, `activity_dos_equivalent_exact = total_tons/TONS_PER_DOS`,
  `activity_delta_rounded = ceil(delta)` (conservative rounding), same `by_brigade` shape. (HexCombat
  sets per-brigade `moved`/`in_combat` from the brigade's flag rather than OR-accumulating across its
  BNs as TIV does — functionally identical, since the flag is per-brigade.)

**✅ Supply now feeds combat (2026-06-29).** `GameState._inject_supply_effectiveness(units, team)` sets
each Red maneuver unit's `supply_effectiveness` before `resolve_map_attack` — `1.0` while the Red DOS
pool is positive, and `GameData.red_out_of_supply_effectiveness` (scenario knob, default `0.5`) once
exhausted (≤0); Green is unaffected (no DOS model). This mirrors TIV
`boots_combat_service._inject_supply_effectiveness`, adapted to HexCombat's single pool (TIV is
per-brigade). `CombatCalculator` multiplies maneuver strength by the field. Tests:
`tests/supply_combat_effectiveness_test.gd`. The golden 1-turn scenario never exhausts the pool, so the
golden invariant is unchanged. v1 is binary-at-exhaustion; a graded ramp is a future refinement.

**Cosmetic:** `GameState.gd:7` aliases the preload as `SupplyStateResource` while the class is
`SupplyState`; the typed `supply_state: SupplyState` is correct — alias inconsistency only.

**Name mismatch:** `GameState.gd:7` uses `const SupplyStateResource = preload(...)` but the class is named `SupplyState` (line 2 of its file). The declared type `supply_state: SupplyState` (line 48) is correct; the preload alias is a cosmetic inconsistency only.
