# Supply (D2 — Red DOS Consumption)

## 1. Purpose

Red DOS (Days Of Supply) models consumable supply for PLA brigades that have **landed** on Taiwan. Each turn, every landed Red battalion adds to a tonnage burden based on **activity**: mechanized vs foot, whether it moved this turn, and whether it fought. Resulting tons are deducted from the Red supply pool; exhaustion triggers a `supply_effectiveness` combat modifier (deferred to later phases).

## 2. Files & responsibilities

| File | Role |
|---|---|
| `scripts/calc/SupplyBill.gd` | Pure calculator: decides which Red battalions are ashore and active, and returns the day's consumption row. Writes nothing. |
| `scripts/transitions/SupplyTransitions.gd` | The `supply` mutation authority (plan 0049) — the only writer of the pool and the ledger. |
| `scripts/GameState.gd` | Autoload runtime state. Holds `supply_state: SupplyState` (read-only façade). `_rebuild_supply_state()` initialises the pool through `TurnClosure`. |
| `scripts/GameData.gd` | Autoload. `red_dos_start: int` loaded from scenario JSON. |
| `scripts/calc/CombatCalculator.gd` | Reads `supply_effectiveness` from unit dict — this is where a depleted pool would penalise combat. |
| `scripts/model/Brigade.gd` | Model class. Initialises each BN's `supply_effectiveness: 1.0`. |
| `scripts/EventBus.gd` | Fires `supply_updated(summary: Dictionary)` so views/logs can react. |
| `scripts/api/LLMGameAPI.gd` | Exposes `supply_state` in `get_observation()` via `_supply_state_observation()`. |

## 3. Constants (`scripts/calc/DosConsumption.gd`)

```gdscript
const BASE_MECHANIZED_TONS: int = 300
const BASE_NON_MECHANIZED_TONS: int = 150
const TONS_PER_DOS: int = 150
```

`MECHANIZED_TYPE_HINTS`: `["mechanized", "tank", "armor", "combined arms", "amphibious"]`

`KNOWN_MECHANIZED_BATTALION_TYPES`: explicit whitelist — Combined Arms, Mechanized Infantry, Mechanized Artillery, Tank, Amphibious Infantry.

`KNOWN_NON_MECHANIZED_BATTALION_TYPES`: explicit blacklist — Air Assault, Special Forces, Field/Rocket Artillery, Air Defense, Reconnaissance, Service/Support, Attack/Utility Helicopter.

`BRIGADE_TYPE_HINTS`: `["mech", "armor", "amphibious"]` — fallback brigade-level check.

## 4. Activity formula

### Classification — `is_mechanized_bn(unit_type, brigade_type)`

1. Whitelist check — if `unit_type` is in `KNOWN_MECHANIZED_BATTALION_TYPES` → mechanized.
2. Blacklist check — if in `KNOWN_NON_MECHANIZED_BATTALION_TYPES` → non-mechanized.
3. Substring hints against `unit_type` → mechanized if any `MECHANIZED_TYPE_HINTS` match.
4. Brigade fallback — if `brigade_type` matches any `BRIGADE_TYPE_HINTS` → mechanized.
5. Otherwise → non-mechanized.

### Tons — `compute_unit_tons(mechanized, moved, in_combat)`

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

## 5. Consumption summary — `calculate_consumption(units, moved_brigade_ids, engaged_brigade_ids, day)`

Iterates all landed Red battalions (`SupplyBill.active_red_battalion_units()`), classifies each, sums per-unit tons, and builds a by-brigade breakdown. Only battalions ASHORE are billed (plan 0037): the function subtracts the off-map pools, so a brigade's ration bill and its fighting strength always name the same battalions.

Returns a Dictionary with fields:

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

## 6. Wiring — `SupplyBill` + `SupplyTransitions` via `TurnClosure`

Called at the end of each combat turn, coordinated by `TurnConductor` delegating to `TurnClosure`, which asks the calculator for the day's bill and hands it to the authority.

```
1. TurnClosure refreshes the not-ashore map (it writes a cache, so a calculator may not do it).
2. SupplyBill collects landed Red battalions, moved_brigade_ids and engaged_brigade_ids,
   and calls DosConsumption.calculate_consumption(...) -> the consumption row.
3. SupplyTransitions.apply_daily_bill DERIVES the new balance from that row:
   pool_after = max(0, pool_before - red_dos_consumed_tons).
4. It stamps applied / pool_before / pool_after onto the row, in that order.
5. It appends the row to supply_state.day_history.
6. TurnClosure emits EventBus.supply_updated.
```

**Initial pool:** `_rebuild_supply_state()` sets `current_dos_tons = GameData.red_dos_start * TONS_PER_DOS` (100 × 150 = 15 000 tons in `scenario_default.json`).

**Supply effectiveness — LIVE, not deferred.** `CombatCalculator._unit_supply_effectiveness()` reads `supply_effectiveness` from the unit Dictionary (defaults to 1.0), and `CombatResolver.inject_supply_effectiveness` (called from `TurnConductor.resolve_combat_at`) sets it: Red maneuver and support units fight at 1.0 while `red_supply_pool > 0.0`, and at `GameData.red_out_of_supply_effectiveness` (**0.5** by default, scenario-overridable) once the pool is exhausted. Green has no DOS model, so its effectiveness is always 1.0.

A second driver was added by plan 0032: `CombatRules.isolated_red_brigade_ids` forces the out-of-supply value for any air-landed brigade with no Red corridor back to a lodgement, regardless of how full the theatre pool is — the tonnage exists, it just cannot reach a battalion behind enemy lines.

**Flow summary:**

```
TurnConductor.resolve_turn()
  → (resolve combats, FEBA, ownership)
  → TurnClosure.resolve_supply_turn()
      → state.refresh_not_ashore_by_type()
      → SupplyBill.for_turn()
          → SupplyBill.active_red_battalion_units()
          → DosConsumption.calculate_consumption()
      → SupplyTransitions.apply_daily_bill()   # the ONLY writer
      → EventBus.supply_updated.emit()
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

**✅ Supply now feeds combat (2026-06-29).** `CombatResolver.inject_supply_effectiveness(...)`,
threaded by `TurnConductor`, sets each Red maneuver unit's `supply_effectiveness` before
`resolve_map_attack` — `1.0` while the Red DOS
pool is positive, and `GameData.red_out_of_supply_effectiveness` (scenario knob, default `0.5`) once
exhausted (≤0); Green is unaffected (no DOS model). This mirrors TIV
`boots_combat_service._inject_supply_effectiveness`, adapted to HexCombat's single pool (TIV is
per-brigade). `CombatCalculator` multiplies maneuver strength by the field. Tests:
`tests/supply_combat_effectiveness_test.gd`. The golden 1-turn scenario never exhausts the pool, so the
golden invariant is unchanged. v1 is binary-at-exhaustion; a graded ramp is a future refinement.

**Cosmetic:** `GameState.gd` aliases the preload as `SupplyStateResource` while the class is
`SupplyState`; the typed `supply_state: SupplyState` is correct — alias inconsistency only.

**Name mismatch:** `GameState.gd` uses `const SupplyStateResource = preload(...)` but the class is named `SupplyState`. The declared type `supply_state: SupplyState` is correct; the preload alias is a cosmetic inconsistency only.

## 8. State & authority

| Aggregate | Authority | Owns | Operation |
|---|---|---|---|
| `supply` | `SupplyTransitions` | `SupplyState.current_dos_tons`, `SupplyState.day_history`, and the `GameStateData.supply_state` handle | `apply_daily_bill(supply_state, consumption)` → the completed ledger row; `rebuild_supply_state(state, red_dos_start)` |

- **Manifest:** [tools/mutation_authority_manifest.json](../../../tools/mutation_authority_manifest.json) — the field lists live there and are deliberately not repeated here.

**Rules:**
- The pool is spent only by billing a day; there is no setter, so it cannot rise mid-campaign.
- The new balance is DERIVED from the consumption row, never supplied by a caller — so a ledger row
  that disagrees with the pool is unexpressible, and the chain needs no guard.
- `day_history` is append-only, one row per billed day, including days that bill nothing.
- `SupplyStateBuilder` fills a fresh, unpublished state and holds a construction allowance.
