# Amphibious offload (D1)

## 1. Purpose

Resolve the landing of Red (PLA) brigades from the ship reserve onto beach hexes. Day 1
implements a "redesign" where maneuver battalions bypass throughput limits (brigade-slot
gated), support battalions wait, and all BNs are counted as "sent". Subsequent days use
greedy per-BN throughput allocation. The subsystem also derives the sent fleet for the D3
anti-ship crossing model and converts ship losses into BN casualties.

## 2. Files & responsibilities

| File | Responsibility |
|---|---|
| `scripts/OffloadCalculator.gd` | Day-1 and Day-N offload resolution; maneuver-BN detection; beach-capacity math |
| `scripts/OffloadRates.gd` | Throughput constants (tons/day per infrastructure type); TONS_PER_BN |
| `scripts/ShipLoadingModel.gd` | BN-to-ship fleet derivation (forward) and ship-loss-to-BN-casualty (backward) |
| `scripts/GameState.gd` | `resolve_offload_turn()` orchestrator; `ship_reserve` state; `_rebuild_ship_reserve()` expansion |
| `scripts/model/BeachDef.gd` | Beach `Resource` — offload_rate, floating_piers, jackup_barge, lat/lng, advance_direction |
| `data/beaches.json` | 9 beach sites with offload_rate in short tons/day and infrastructure counts |
| `data/offload_rates.json` | Base rates: beach_base=4400, jackup_barge=4400, floating_pier=2200, port/airbridge variants |
| `data/scenario_default.json` | `red_ship_reserve` block mapping 4 PLA brigades to their locked beaches |
| `tools/validate_offload_data.gd` | Asserts JSON keys match `OffloadRates.REQUIRED_RATE_KEYS` and constants agree |
| `tools/validate_headless_offload.gd` | Headless gate: runs one offload turn, asserts >=1 brigade lands |
| `tests/offload_calculator_test.gd` | 54 GdUnit4 tests for day-1, day-N, edge cases |

## 3. Constants

- **`OffloadRates.TONS_PER_BN := 2200.0`** — `scripts/OffloadRates.gd:9`
- **Maneuver BN whitelist** — `scripts/OffloadCalculator.gd:15`:
  ```
  "Combined Arms Battalion", "Amphibious Infantry Battalion",
  "Mechanized Infantry Battalion", "Air Assault Infantry Battalion",
  "Special Forces Battalion"
  ```

## 4. Day-1 offload model

All BNs counted as "sent" (`bns_sent = sum of all bn entries`).

- **Maneuver BNs** bypass per-BN throughput cost. They land in brigade-sized groups, limited by
  beach brigade slots = `floor(beach_capacity_bns)` per beach, where
  `beach_capacity_bns = (offload_rate + floating_piers*pier_rate + jackup_barge*barge_rate) / TONS_PER_BN`
  (mirrors TIV `BeachThroughputService`; pier/barge infrastructure adds capacity beyond the base rate).
- **Support BNs** wait on ships (deferred with reason `"day1_support_waiting"`).
- `bns_waiting = bns_sent - bns_landed - lost_at_sea` (line 111).
- **Day 2+:** all BNs (support + un-landed maneuver) compete for per-BN throughput
  (greedy, priority-order, each BN costs `TONS_PER_BN` tons from the beach budget).

## 5. Key functions

```gdscript
# OffloadCalculator (scripts/OffloadCalculator.gd)
static func is_maneuver_bn(bn_type: String) -> bool          # line 24
static func beach_capacity_bns(active_beach_ids, beach_lookup,
  floating_pier_rate, jackup_barge_rate) -> Dictionary       # line 32
static func resolve_offload_day(current_day, beach_capacity,
  brigades_at_sea, priority_order) -> Dictionary             # line 76
static func _resolve_day1(...) -> void                       # line 126
static func _resolve_day_n(...) -> void                      # line 199

# OffloadRates (scripts/OffloadRates.gd) — pure constants     # line 9-24

# ShipLoadingModel (scripts/ShipLoadingModel.gd)
static func build_sent_snapshots(bn_count, carriers, screen) -> Dictionary   # line 46
static func resolve_bn_losses(destroyed_by_ship_type, capacity_by_type,
  bns_at_sea, accumulator, dice) -> Dictionary                               # line 119

# GameState (scripts/GameState.gd)
func ship_reserve_priority_order() -> Array[String]          # line 295
func resolve_offload_turn(dice: Dice) -> Dictionary          # line 303
func register_ship_losses(bn_equiv_lost: int) -> void        # line 998
func _rebuild_ship_reserve() -> void                         # line 961
func _rebuild_fleet() -> void                                # line 1002
```

## 6. Data flow

1. `data/beaches.json` → `GameData.beaches` (`Dictionary[int, BeachDef]`).
2. `data/offload_rates.json` → `OffloadRates` constants (verified by `validate_offload_data.gd`).
3. `data/scenario_default.json["red_ship_reserve"]` → `GameData.red_ship_reserve` (bare entries:
   `{brigade_id, locked_beach, beach_hex, offset_bearing}`).
4. `GameState._rebuild_ship_reserve()` (line 961) expands each brigade's OOB `composition` into
   per-BN entries: `{brigade_id, locked_beach, beach_hex, offset_bearing, bns: [{id, type}]}`.
5. `GameState.resolve_offload_turn(dice)` (line 303):
   - Collects `active_beach_ids` from `ship_reserve` locked_beach values.
   - Calls `OffloadCalculator.beach_capacity_bns()` → tonnage-derived BN slots.
   - Calls `OffloadCalculator.resolve_offload_day(turn_number, ...)` → manifest dict.
   - For each landed BN in `manifest["manifest_landed"]`: removes the BN from its ship_reserve entry.
   - When a brigade's first BN lands: calls `GameData.set_brigade_hex(brigade_id, beach_hex)` and
     sets `brigade.entry_bearing` from `offset_bearing` (line 355).
    - Brigade leaves `ship_reserve` only when all its BNs have landed (`bns` array empty, line 358).
    - `ShipLoadingModel.build_sent_snapshots()` (called from `_build_sent_fleet`, line 676)
      derives the crossing fleet from remaining at-sea BNs for D3 anti-ship resolution.
    - `ShipLoadingModel.resolve_bn_losses()` converts D3 crossing ship losses into BN
      casualties via `pending_lost_at_sea` → `GameState.register_ship_losses()` (line 998).
    - Emits `EventBus.offload_resolved` (line 368).

## 7. TIV-port fidelity notes

**✅ Verified faithful (orchestrator audit, 2026-06-29).** Cross-checked against the oracle:
`TONS_PER_BN = 2200.0` matches `src/contracts/units.py`; the beach-throughput formula (base +
`floating_pier` + `jackup_barge` contributions) matches `BeachThroughputService`; and the maneuver-BN
whitelist is **identical** to TIV's `maneuver_bn_types` set in `beach_throughput_factory.py` (same 5
types). The day-1 redesign behavior is mirrored by 54 GdUnit4 tests against the TIV pytests. Only the
two `ShipLoadingModel` simplifications below diverge, and both are intentional/code-documented (→
`docs/plans/port_audit.md`), not bugs.

- **Oracle source:** `TaiwanInvasionViewer/src/services/offload_calculator.py`,
  `src/services/offload/beach_throughput.py`, `src/services/offload/beach_throughput_factory.py`,
  `src/services/offload/_rates.py`, `src/contracts/units.py` (TONS_PER_BN=2200, verified matching),
  `defaults/offload_rates.json`, `defaults/beaches.json`.
- **Tests mirrored:** `test_offload_day1_redesign.py`, `test_offload_brigade_priority.py`,
  `test_offload_brigade_spacing.py`, `test_offload_calculator_init.py`.
- **Status per ROADMAP.md:143:** D1 is **COMPLETE** (2026-06-24) with 8 validators + 54 GdUnit4 tests.
- **Known simplifications (logged in PLAN.md):**
  - `ShipLoadingModel` ignores per-type transport weight (every BN = 1.0 BN-equiv; TIV uses
    `configurator.get_unit_transport_weight()`). Documented at `ShipLoadingModel.gd:14-16`.
  - `ShipLoadingModel` drops the amphibious-vs-cargo ship-eligibility split (TIV's
    `_ship_can_carry_battalion`; HexCombat: any carrier ships any BN). Line 17-19.
  - HexCombat has no ship-cycle (no ready/offloading/returning state machine); fleet derivation
    is a static minimum-lift calculation rather than TIV's live sailing-set assignment.
- **Resolved design decision (per PLAN.md:873):** Red starts at sea via `red_ship_reserve` in
  `scenario_default.json` (removed previous beach-hex placement). Four PLA amphibious brigades
  land Day 1 via offload.
- `lost_at_sea` is threaded through `pending_lost_at_sea` (D3-F writes, D0-C reads) but the
  ship-loss-to-BN-casualty wiring is deferred pending the D3 crossing model integration.
