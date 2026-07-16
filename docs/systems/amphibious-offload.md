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
| `scripts/OffloadCalculator.gd` | Day-1 and Day-N offload resolution; maneuver-BN detection; beach-capacity math; day-N infra routing + carry-over |
| `scripts/OffloadRates.gd` | Throughput constants (tons/day per infrastructure type); TONS_PER_BN |
| `scripts/OffloadCostModel.gd` | Per-BN day-N offload cost: transport weight × bn_class/ship_category multiplier (plan 0006) |
| `scripts/model/InfrastructureDef.gd` / `InfrastructureState.gd` | Port/airbridge node defs + per-node lifecycle state |
| `scripts/resolvers/InfrastructureResolver.gd` | Pure seizure + JLSF repair clock; `red_offload_nodes` throughput feed |
| `scripts/JlsfCargo.gd` | JLSF pseudo pool-entry builder (rides the 0004 sealift pipeline) |
| `data/infrastructure.json` | 5 ports + 8 main-island airbridges (explicit `hex_id` + `to_number`) |
| `data/offload_weights.json` | Per-BN-type transport weights + bn_class map + multiplier matrix |
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

- **`OffloadRates.TONS_PER_BN := 2200.0`** — `scripts/OffloadRates.gd`
- **Maneuver BN whitelist** — `scripts/OffloadCalculator.gd`:
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
`docs/archive/port_audit.md`), not bugs.

- **Oracle source:** `TaiwanInvasionViewer/src/services/offload_calculator.py`,
  `src/services/offload/beach_throughput.py`, `src/services/offload/beach_throughput_factory.py`,
  `src/services/offload/_rates.py`, `src/contracts/units.py` (TONS_PER_BN=2200, verified matching),
  `defaults/offload_rates.json`, `defaults/beaches.json`.
- **Tests mirrored:** `test_offload_day1_redesign.py`, `test_offload_brigade_priority.py`,
  `test_offload_brigade_spacing.py`, `test_offload_calculator_init.py`.
- **Status per ROADMAP.md:143:** D1 is **COMPLETE** (2026-06-24) with 8 validators + 54 GdUnit4 tests.
- **Known simplifications (logged in PLAN.md):**
  - `ShipLoadingModel` ignores per-type transport weight for **lift packing** (every BN = 1.0
    BN-equiv aboard ship; TIV uses `configurator.get_unit_transport_weight()`). Documented at
    `ShipLoadingModel.gd`. Since plan 0006, per-type weights DO drive day-N **offload cost**
    (§9 cost matrix) — the simplification is now lift-side only.
  - `ShipLoadingModel` drops the amphibious-vs-cargo ship-eligibility split (TIV's
    `_ship_can_carry_battalion`; HexCombat: any carrier ships any BN). Line 17-19.
  - ~~HexCombat has no ship-cycle~~ **(superseded 2026-07-12, plan 0004 — see §8 Sealift lifecycle).**
    Ships now cycle ready→sent→offloading→returning→ready and the amphibious-vs-cargo eligibility
    split is reintroduced for follow-on lift.
- **Resolved design decision (per PLAN.md:873):** Red starts at sea via `red_ship_reserve` in
  `scenario_default.json` (removed previous beach-hex placement). Four PLA amphibious brigades
  land Day 1 via offload.
- `lost_at_sea` is threaded through `pending_lost_at_sea` (D3-F writes, D0-C reads) but the
  ship-loss-to-BN-casualty wiring is deferred pending the D3 crossing model integration.

## 8. Sealift lifecycle (plan 0004, 2026-07-12)

Sustained amphibious lift across the game. Replaces the pre-0004 one-shot `ship_reserve` (built once
at load, only ever shrunk) + same-turn ship round-trip. **Source oracle:** TIV
`ship_state_service.py`, `ship_transition_service.py`, `ship_readiness_policy.py`, `ship_ammo.py`,
`manifest_allocator.py` (per-hull SQLite lifecycle, adapted here to per-type aggregate state).

**State — `SealiftState` (`scripts/model/SealiftState.gd`), owned by `GameState`, built by
`SealiftStateBuilder` at scenario load:**
- `mainland_pool` — follow-on brigades waiting to embark (same entry shape as `ship_reserve`).
  Source: an explicit scenario `red_followon_reserve` (curated echelon, e.g. `roc_full_defense`), OR,
  when `auto_seed_followon_pool: true`, **auto-seeded from the OOB** — every RED brigade not in the
  first wave, round-robin across the first-wave beaches, in OOB order (deterministic; a brigade is
  atomic). `SealiftStateBuilder.resolve_followon_reserve`. The pool is intentionally far larger than
  any turn can lift, so *amphibious lift capacity* (not pool size) sets the tempo. Absent flag + no
  explicit echelon ⇒ empty pool = one-shot assault (the golden fixture / minimal scenarios).
- `cohorts` — in-transit ship groups, each binding the specific hulls loaded in one embark to the
  BN ids they carry (`state` ∈ `sent`/`offloading`). This binding makes hull-freeing unambiguous.
- `return_pipeline` — per-ship-type queue of `{count, turns_remaining}`; freed amphibious hulls
  return to `ready` after `amphibious_return_time_turns`.
- `escort_sam` / `escort_sam_max` / `escort_sam_threshold` / `escort_reload` — the escort SAM
  magazine (§ below).

**Turn flow — `SealiftResolver` (`scripts/resolvers/SealiftResolver.gd`), pure + dice-free, runs in
`GameState.resolve_sealift_turn()` BEFORE the crossing:**
1. Tick the return/reload pipelines; hulls whose timer hits 0 rejoin `ready`.
2. **Adopt** any at-sea BN not yet in a cohort (the programmed first echelon on turn 1) into a
   `sent` cohort via the existing minimum-lift derivation (`ShipLoadingModel.build_sent_snapshots`
   over the full carrier set — preserves the pre-0004 sent fleet for the default scenario).
3. **Embark** follow-on BNs onto remaining ready **amphibious** capacity
   (`ShipLoadingModel.pack_bns_into_hulls`), departed-brigades-first then new brigades in pool
   order; escorts (capacity 0) always screen and stay `ready` until they reload. "Amphibious lift"
   is classified by `ShipDef.is_amphibious_lift()` — exact category membership
   (`Military_Amphibious` / `Civilian_Amphibious`), **not** a substring match (a `.contains(
   "Amphibious")` test wrongly admitted `Civilian_Non_Amphibious`; see failure-archaeology).
   `pack_bns_into_hulls` **aggregates** capacity across a type's ready hulls before flooring
   (`floor(N·C)`, so 24 LCU @0.1 lift 2 BNs), matching `build_sent_snapshots` — per-hull flooring
   would zero every sub-1.0 hull and stall lift once the big hulls were sunk/busy.

The crossing (`AntishipResolver` / `AntishipCrossing`) attrits exactly the sailing cohorts; losses
are reported back and `GameState` routes carrier losses to the cohorts and escort losses to the
ready screen, then reprojects the `ShipState` bins (`ready/surviving_sent/offloading/returning`)
from `SealiftState` — the single source of truth for where hulls are. Offload drains landed/lost BN
ids from cohorts; a fully-drained cohort frees its hulls into the return pipeline.

**Cross-once semantics (behavior change vs pre-0004).** A BN now takes anti-ship attrition **once**,
on its crossing turn, then sits safe in an offloading cohort until beach capacity lands it — instead
of the old model re-attriting every still-at-sea BN every turn. `scenario_default`'s crossing golden
was re-baselined accordingly.

**Escort SAM magazine + reload cycle.** Each interception attempt in the crossing consumes one SAM
from the escort type's magazine (`AntishipCrossing._apply_interception` threads a per-type budget);
a type at/below its `sam_reload_threshold` diverts to reload for `escort_reload_time_turns` (away
from the screen — projected as `returning`, `ready = 0`) until refilled to `sam_loadout`. **Off by
default:** `escort_sam` is seeded only when a scenario sets `escort_reload_time_turns > 0`; an empty
magazine means unlimited interception (pre-0004 behavior), keeping `scenario_default` byte-stable.
Loadout/threshold are in `data/antiship/antiship_crossing_config.json` (`escort_interception`).

**Config knobs** (see `hexcombat-config-and-knobs`): scenario `red_followon_reserve`,
`auto_seed_followon_pool`, `amphibious_return_time_turns`, `escort_reload_time_turns`; crossing-config
`sam_loadout` / `sam_reload_threshold` per escort type. `roc_full_defense` uses an explicit
10-brigade follow-on (return_time 3, escort reload_time 4).

**Research default vs golden fixture (2026-07-12).** `data/scenario_default.json` is the **research
default** — `auto_seed_followon_pool: true` + `amphibious_return_time_turns: 3`, so a naked run /
self-play gets the realistic deep-pool sustained invasion. The pinned **gate does not run it**:
`tools/run_all_tests.sh`/`.ps1` export `HEXCOMBAT_SCENARIO=res://data/scenario_golden.json`, a frozen
one-shot assault laydown (byte-identical to the pre-deep-pool default), so every golden pin stays
stable while `scenario_default` evolves. Deep-pool coverage rides `tools/validate_deep_pool_smoke.gd`
(auto-seed + sustained crossing + determinism), which loads `scenario_default` explicitly via
`GameData.load_all(path)`. To run a golden validator by hand, export the same env var.

**TIV divergences (intentional):** TIV tracks per-hull `IndividualShip` entities in SQLite with
per-hull ammo/repair/reload timers; HexCombat models the same lifecycle at the **per-ship-type
aggregate** level (a whole escort type reloads as a group when its pooled SAM crosses the threshold).
Damage-driven repair delay is not modelled (freed hulls use a flat return time).

## 9. Offload capacity gate (plan 0006)

Shore offload capacity is the second gate on Red buildup (USER call 2026-07-12): ship lift (§8)
sets how much can cross; held/operational infrastructure sets how much can come ashore. All 0006
features are **default-off knobs** — `scenario_golden` never sees them; `scenario_default` turns
them on (`use_offload_weight_matrix`, `auto_jlsf`). Knob table: `hexcombat-config-and-knobs`.

**Infrastructure nodes.** `data/infrastructure.json` seeds 5 ports + 8 main-island airbridges
(TIV `defaults/infrastructure.json` lineage), each with explicit `hex_id`/`to_number`
(precomputed offline; asserted by `tools/validate_infrastructure_data.gd`). Loaded into
`GameData.infrastructure` as `InfrastructureDef`; per-node lifecycle lives in
`InfrastructureState` (owned by `GameState`, rebuilt by `InfrastructureStateBuilder` on scenario
reset): `status ∈ taiwanese|seized|degraded|operational`, `jlsf ∈ none|queued|enroute|arrived`.

**Lifecycle — `InfrastructureResolver` (pure, dice-free), ticked at the top of
`GameState.resolve_offload_turn` even when the reserve is empty (ground combat can seize a port
long after the last landing).** A `taiwanese` node on a Red-owned hex becomes `seized`
(0 throughput — TIV: capture wrecks the facility until logistics troops restore it). With a JLSF
`arrived` and the hex still Red-held, repair advances one stage per turn
(`repair_turns_per_stage`, default 1): `seized → degraded → operational`. Status never regresses
on recapture; instead `red_offload_nodes` gates *contribution* on ownership at read time —
a Green-retaken port contributes nothing but keeps its repair state if Red retakes it.
**Ownership-semantics dependency:** seizure persistence relies on
`GameData.recompute_hex_ownership` having no else-branch — a vacated hex keeps its last owner,
so a Red column can take a port hex and move on without the node reverting. Ownership fed to the tick is
last turn's post-combat state (producer→consumer edge: combat ownership → next offload).

**Throughput.** `red_offload_nodes` returns Red-held degraded/operational nodes with rates from
`OffloadRates` (port 11,000/2,200 t/d operational/degraded ≈ 5.0/1.0 BN-equiv; airbridge
2,200/1,100) — finally wiring the constants that sat unreferenced since D1. Day-N routing per
BN (TIV `manifest_allocator` order): locked beach → same-TO port → same-TO airbridge → any-TO
port → any-TO airbridge → defer `throughput_limited`. A brigade whose first landed BN came
through a node lands at the node's hex, not a beach.

**Cost matrix (`use_offload_weight_matrix`).** Day-N per-BN cost =
`weights[bn_type] × multipliers[node_kind][bn_class][ship_category]` from
`data/offload_weights.json` via `OffloadCostModel` (flat `TONS_PER_BN` when the knob is off —
the golden path). TIV values at beaches (amphibious BN on Military_Amphibious 0.5×; standard BN
on civilian hulls 2.0×; else 1.0×); ports/airbridges always 1.0×. `ship_category` is stamped on
each BN dict at embark/adopt time (`ShipLoadingModel.pack_bns_into_hulls` / the adopt path) —
per-cohort hull binding from §8 makes it derivable. New ship categories or cargo classes are
data additions (USER flexibility requirement 2026-07-15).

**Carry-over (TIV fractional flow).** A BN whose beach cost exceeds its locked beach's leftover
tons banks those tons (`offload_progress_tons` on the bn dict, deferred reason
`offload_in_progress`) and lands once banked progress covers the cost. Port/airbridge routing is
tried at full price first; progress never subsidizes a node landing; a valve-closed beach banks
nothing. Without this, a heavy BN on civilian lift (e.g. 3300 t × 2.0 = 6600 t vs a 4400 t/d
beach) deferred forever and its cohort's hulls never returned — freezing ALL sealift
(see `hexcombat-failure-archaeology`, sealift livelock).

**Beach occupancy valve.** Per-beach `depth` in `data/beaches.json` (`BeachDef.depth`, default
2): when ≥depth landed RED brigades stand on the beach hex, that beach contributes 0 tons until
they move inland. Day-1 assault parks 2 brigades per beach, so an empty-orders run hard-plateaus
BY DESIGN (~turn 2); the land→vacate→land loop is the intended tempo and is what
`tools/validate_deep_pool_smoke.gd` exercises with inland move orders.

**JLSF pipeline.** A seized node repairs only after a Joint Logistics Support Force deployment:
an explicit Red order `{"kind": "deploy_jlsf", "port_id": ...}` or the `auto_jlsf` scenario
policy (auto-queue for every newly seized node). `GameState._consume_jlsf_orders` pushes a
`JlsfCargo` pseudo pool entry (`brigade_id "JLSF:<id>"`, `cargo: "jlsf"`,
`jlsf_lift_bn_equiv` pseudo-BNs, a real locked beach in the node's TO) to the FRONT of the
mainland pool; it rides the §8 pipeline unchanged — consumes ready amphibious lift, takes real
crossing attrition, frees its hulls on delivery. `OffloadResolver` lands it tons-free when the
node hex is Red-held (else defers `jlsf_waiting_port`); arrival flips the node's `jlsf` marker
to `arrived` and starts the repair clock. A deployment lost whole at sea is reconciled by
`GameState._reconcile_lost_jlsf` (marker back to `none`; auto-policy may re-queue). The JLSF is
never a `Brigade` — invisible to census/combat/movement. LLM surface: `deploy_jlsf` action +
`infrastructure` observation block (schema + fixtures regenerated).

**Measured behavior (research runs, 2026-07-15, 3 seeds × 40 turns, `scenario_default`):**
empty orders plateau at peak 31–35 Red BNs (no overrun, was turn-17 `china_majority` before
0006); with inland-clearing orders Red sustains ~5 BN/turn over beaches alone; seizing Taichung
port (JLSF repair seized→operational in 3–5 turns) lifts the landing rate to ~7–9 BN/turn and
ends the game 2–5 turns earlier. Ports are also the only way ashore for BNs whose beach cost
exceeds every beach's daily rate in one lump (heavy equipment on civilian hulls offloads at 1.0×
alongside a pier instead of 2.0× over the beach).
