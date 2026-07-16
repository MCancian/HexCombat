class_name OffloadCalculator
extends RefCounted

# Port of TaiwanInvasionViewer offload system (Day 1 redesign behavior).
# Source oracles:
#   src/services/offload/beach_throughput.py
#   src/services/offload/beach_throughput_factory.py
#   tests/python/unit/test_offload_day1_redesign.py
#   tests/python/unit/test_offload_brigade_priority.py
#
# Pure RefCounted lib — no Node dependency, headless-testable.

# BN types whose landing counts as "maneuver" — bypass beach throughput on Day 1.
# Source: TaiwanInvasionViewer src/services/offload/beach_throughput_factory.py maneuver_bn_types.
const MANEUVER_BN_TYPES: Array[String] = [
	"Combined Arms Battalion",
	"Amphibious Infantry Battalion",
	"Mechanized Infantry Battalion",
	"Air Assault Infantry Battalion",
	"Special Forces Battalion",
]

const REASON_DAY1_NO_BEACH_SLOT := "day1_no_beach_slot"
const REASON_DAY1_SUPPORT_WAITING := "day1_support_waiting"
const REASON_OFFLOAD_IN_PROGRESS := "offload_in_progress"
const REASON_THROUGHPUT_LIMITED := "throughput_limited"


static func is_maneuver_bn(bn_type: String) -> bool:
	return bn_type in MANEUVER_BN_TYPES


# Calculate beach-level BN-slot capacity for a set of active beaches.
# Each beach contributes: (offload_rate + floating_piers * pier_rate + jackup_barge * barge_rate) / TONS_PER_BN.
# Returns: Dictionary {beach_id (int) -> float (BN-equivalent slots per day)}
# Source: BeachThroughputService.calculate_beach_throughput_remaining in beach_throughput.py.
static func beach_capacity_bns(
	active_beach_ids: Array,
	beach_lookup: Dictionary,
	floating_pier_rate: float = OffloadRates.FLOATING_PIER,
	jackup_barge_rate: float = OffloadRates.JACKUP_BARGE,
) -> Dictionary:
	var result: Dictionary = {}
	for beach_id_var in active_beach_ids:
		var beach_id := int(beach_id_var)
		var beach: BeachDef = beach_lookup.get(beach_id, null)
		if beach == null:
			push_warning("OffloadCalculator: unknown beach id %d" % beach_id)
			continue
		var tons_per_day := beach.offload_rate
		tons_per_day += beach.floating_piers * floating_pier_rate
		tons_per_day += beach.jackup_barge * jackup_barge_rate
		result[beach_id] = tons_per_day / OffloadRates.TONS_PER_BN
	return result


# Resolve one day of offload operations.
#
# Implements the "Day 1 redesign" behavior from test_offload_day1_redesign.py:
#   - current_day == 1 (first assault): all BNs are "sent"; maneuver BNs bypass throughput
#     and land at assigned beach; support BNs stay on ships (waiting).
#   - current_day >= 2: remaining BNs compete for throughput (greedy, priority order).
#
# Args:
#   current_day: int — 1 for first assault day; 2+ for subsequent days.
#   beach_capacity: Dictionary {beach_id (int) -> float slots} — from beach_capacity_bns().
#   brigades_at_sea: Array of Dictionary {
#       "brigade_id": String,
#       "locked_beach": int,  # 0 = no lock; brigade must use this beach if > 0
#       "bns": Array of Dictionary {"id": String, "type": String}
#   }
#   priority_order: Array[String] — brigade IDs ordered by landing priority (index 0 = highest).
#
# Returns Dictionary:
#   "bns_sent": int      — total BNs considered (all BNs of all at-sea brigades)
#   "bns_landed": int    — BNs that came ashore this day
#   "bns_waiting": int   — bns_sent - bns_landed - lost_at_sea
#   "lost_at_sea": int   — casualties (0 unless ship loss mechanic active)
#   "manifest_landed": Array — [{brigade_id, bn_id, bn_type, beach_id}]
#   "manifest_deferred": Array — [{brigade_id, bn_id, bn_type, reason}]
static func resolve_offload_day(
	current_day: int,
	beach_capacity: Dictionary,
	brigades_at_sea: Array,
	priority_order: Array,
	infra_nodes: Array = [],
	cost_config: Dictionary = {},
	beach_occupancy: Dictionary = {},
	beach_depth: Dictionary = {},
	beach_to_to: Dictionary = {},
) -> Dictionary:
	var manifest_landed: Array = []
	var manifest_deferred: Array = []

	# Index brigades by id for quick lookup.
	var brigade_map: Dictionary = {}
	for brigade in brigades_at_sea:
		var bid := String(brigade.get("brigade_id", ""))
		if bid != "":
			brigade_map[bid] = brigade

	# Build the ordered list (priority_order may not include all; extras go last).
	var ordered_ids: Array[String] = []
	for bid_var in priority_order:
		var bid := String(bid_var)
		if bid in brigade_map:
			ordered_ids.append(bid)
	for brigade in brigades_at_sea:
		var bid := String(brigade.get("brigade_id", ""))
		if bid != "" and bid not in ordered_ids:
			ordered_ids.append(bid)

	if current_day == 1:
		_resolve_day1(ordered_ids, brigade_map, beach_capacity, manifest_landed, manifest_deferred)
	else:
		_resolve_day_n(ordered_ids, brigade_map, beach_capacity, manifest_landed, manifest_deferred, infra_nodes, cost_config, beach_occupancy, beach_depth, beach_to_to)

	var bns_sent := manifest_landed.size() + manifest_deferred.size()
	var bns_landed := manifest_landed.size()
	var lost_at_sea := 0  # ship loss mechanic not yet wired
	var bns_waiting := bns_sent - bns_landed - lost_at_sea

	return {
		"bns_sent": bns_sent,
		"bns_landed": bns_landed,
		"bns_waiting": bns_waiting,
		"lost_at_sea": lost_at_sea,
		"manifest_landed": manifest_landed,
		"manifest_deferred": manifest_deferred,
	}


# Day 1 assault: maneuver BNs bypass throughput; support BNs wait.
# Beach slot capacity = floor(beach_capacity[beach_id]) brigade slots.
# Brigades are assigned to beaches in priority order (locked-beach first).
static func _resolve_day1(
	ordered_ids: Array[String],
	brigade_map: Dictionary,
	beach_capacity: Dictionary,
	manifest_landed: Array,
	manifest_deferred: Array,
) -> void:
	# Brigade slots per beach = floor(BN-slot capacity).
	# One brigade consumes one slot on Day 1 (it lands as a unit).
	var beach_slots: Dictionary = {}
	for beach_id_var in beach_capacity.keys():
		beach_slots[int(beach_id_var)] = int(floor(float(beach_capacity[beach_id_var])))

	# Assign brigades to beaches (locked-beach first, then first-available).
	var assignments: Dictionary = {}  # brigade_id -> beach_id (int)

	# Pass 1: locked-beach brigades.
	for bid in ordered_ids:
		var brigade: Dictionary = brigade_map[bid]
		var locked := int(brigade.get("locked_beach", 0))
		if locked > 0 and locked in beach_slots and beach_slots[locked] >= 1:
			assignments[bid] = locked
			beach_slots[locked] -= 1

	# Pass 2: unlocked brigades fill remaining slots.
	for bid in ordered_ids:
		if bid in assignments:
			continue
		var brigade: Dictionary = brigade_map[bid]
		var locked := int(brigade.get("locked_beach", 0))
		if locked > 0:
			continue  # locked to an unavailable beach; will be deferred
		for beach_id_var in beach_slots.keys():
			var beach_id := int(beach_id_var)
			if beach_slots[beach_id] >= 1:
				assignments[bid] = beach_id
				beach_slots[beach_id] -= 1
				break

	# Land maneuver BNs for assigned brigades; defer support BNs and unassigned brigades.
	for bid in ordered_ids:
		var brigade: Dictionary = brigade_map[bid]
		var bns: Array = brigade.get("bns", [])
		var assigned_beach: int = assignments.get(bid, -1)

		for bn in bns:
			var bn_id := String(bn.get("id", ""))
			var bn_type := String(bn.get("type", ""))
			if assigned_beach >= 0 and is_maneuver_bn(bn_type):
				manifest_landed.append({
					"brigade_id": bid,
					"bn_id": bn_id,
					"bn_type": bn_type,
					"beach_id": assigned_beach,
				})
			elif is_maneuver_bn(bn_type) and assigned_beach < 0:
				manifest_deferred.append({
					"brigade_id": bid,
					"bn_id": bn_id,
					"bn_type": bn_type,
					"reason": REASON_DAY1_NO_BEACH_SLOT,
				})
			else:
				manifest_deferred.append({
					"brigade_id": bid,
					"bn_id": bn_id,
					"bn_type": bn_type,
					"reason": REASON_DAY1_SUPPORT_WAITING,
				})


# Day 2+: all remaining BNs (support + any un-landed maneuver) compete for throughput.
# Greedy allocation in priority order; per-BN cost from OffloadCostModel.
# Supports infra routing fallback chain (port/airbridge) and occupancy valve.
# Routing order: locked beach -> same-TO port -> same-TO airbridge ->
# any-TO port -> any-TO airbridge -> defer.
# Source: TIV manifest_allocator._allocate_landing_destinations lines 774-811.
static func _resolve_day_n(
	ordered_ids: Array[String],
	brigade_map: Dictionary,
	beach_capacity: Dictionary,
	manifest_landed: Array,
	manifest_deferred: Array,
	infra_nodes: Array = [],
	cost_config: Dictionary = {},
	beach_occupancy: Dictionary = {},
	beach_depth: Dictionary = {},
	beach_to_to: Dictionary = {},
) -> void:
	var remaining_tons := _beach_budgets(beach_capacity, beach_occupancy, beach_depth)
	var infra_remaining := _infra_budgets(infra_nodes)

	for bid in ordered_ids:
		var brigade: Dictionary = brigade_map[bid]
		var locked: int = int(brigade.get("locked_beach", 0))
		var target_beach := _target_beach(locked, remaining_tons)

		for bn in brigade.get("bns", []):
			var bn_type: String = String(bn.get("type", ""))
			var ship_category: String = String(bn.get("ship_category", ""))
			var beach_cost: float = OffloadCostModel.bn_cost_tons(bn_type, ship_category, "beach", cost_config)
			# Carry-over (TIV fractional flow, build_offload_queue): tons already banked against
			# this BN's beach cost on previous turns reduce what it still needs today, so a BN
			# whose full cost exceeds its beach's per-day rate offloads across turns instead of
			# deferring forever (which would also deadlock its cohort's hulls — plan 0006 C8).
			var beach_need: float = maxf(beach_cost - float(bn.get("offload_progress_tons", 0.0)), 0.0)
			if target_beach >= 0 and remaining_tons.get(target_beach, 0.0) >= beach_need:
				remaining_tons[target_beach] -= beach_need
				bn.erase("offload_progress_tons")
				manifest_landed.append(_beach_landing(bid, bn, target_beach))
				continue

			# Infra chain at FULL price — banked progress never subsidizes a node landing.
			var to_num: int = int(beach_to_to.get(locked if locked > 0 else target_beach, -1))
			var infra_entry := _route_infra(infra_remaining, to_num, bn_type, ship_category, cost_config)
			if not infra_entry.is_empty():
				manifest_landed.append(_node_landing(bid, bn, infra_entry))
				continue

			# Bank whatever the beach can still give this turn toward the BN's beach cost;
			# a dry (or valve-closed) beach banks nothing.
			var leftover: float = remaining_tons.get(target_beach, 0.0) if target_beach >= 0 else 0.0
			if leftover > 0.0:
				bn["offload_progress_tons"] = float(bn.get("offload_progress_tons", 0.0)) + leftover
				remaining_tons[target_beach] = 0.0
				manifest_deferred.append(_deferral(bid, bn, REASON_OFFLOAD_IN_PROGRESS))
			else:
				manifest_deferred.append(_deferral(bid, bn, REASON_THROUGHPUT_LIMITED))


# Remaining capacity per beach in tons, with the occupancy valve applied (a beach at/over its
# depth contributes 0 this turn).
static func _beach_budgets(beach_capacity: Dictionary, beach_occupancy: Dictionary, beach_depth: Dictionary) -> Dictionary:
	var remaining_tons: Dictionary = {}
	for beach_id_var in beach_capacity.keys():
		var beach_id: int = int(beach_id_var)
		if beach_depth.has(beach_id) and beach_occupancy.get(beach_id, 0) >= int(beach_depth[beach_id]):
			remaining_tons[beach_id] = 0.0
		else:
			remaining_tons[beach_id] = float(beach_capacity[beach_id_var]) * OffloadRates.TONS_PER_BN
	return remaining_tons


# Per-node infra budgets: duplicates each node row with a mutable "remaining" field.
static func _infra_budgets(infra_nodes: Array) -> Array:
	var infra_remaining: Array = []
	for node in infra_nodes:
		var entry: Dictionary = node.duplicate()
		entry["remaining"] = float(entry.get("rate_tons", 0.0))
		infra_remaining.append(entry)
	return infra_remaining


# The brigade's beach for this day: its locked beach when set (production entries always are —
# OffloadResolver rejects locked_beach <= 0), else the first beach with any tons left.
static func _target_beach(locked: int, remaining_tons: Dictionary) -> int:
	if locked > 0 and locked in remaining_tons:
		return locked
	for beach_id_var in remaining_tons.keys():
		var beach_id: int = int(beach_id_var)
		if remaining_tons[beach_id] > 0.0:
			return beach_id
	return -1


# TIV Day-2+ fallback chain (manifest_allocator._allocate_landing_destinations): same-TO port ->
# same-TO airbridge -> any-TO port -> any-TO airbridge. Returns the consumed node entry or {}.
static func _route_infra(infra_remaining: Array, to_num: int, bn_type: String, ship_category: String, cost_config: Dictionary) -> Dictionary:
	var port_cost: float = OffloadCostModel.bn_cost_tons(bn_type, ship_category, "port", cost_config)
	var ab_cost: float = OffloadCostModel.bn_cost_tons(bn_type, ship_category, "airbridge", cost_config)
	for step in [["port", true, port_cost], ["airbridge", true, ab_cost],
			["port", false, port_cost], ["airbridge", false, ab_cost]]:
		var entry := _try_infra_landing(infra_remaining, String(step[0]), to_num, bool(step[1]), float(step[2]))
		if not entry.is_empty():
			return entry
	return {}


static func _beach_landing(bid: String, bn: Dictionary, beach_id: int) -> Dictionary:
	return {
		"brigade_id": bid,
		"bn_id": String(bn.get("id", "")),
		"bn_type": String(bn.get("type", "")),
		"beach_id": beach_id,
	}


static func _node_landing(bid: String, bn: Dictionary, infra_entry: Dictionary) -> Dictionary:
	var row := _beach_landing(bid, bn, -1)
	row["node_id"] = infra_entry.get("id", "")
	row["node_kind"] = infra_entry.get("kind", "")
	return row


static func _deferral(bid: String, bn: Dictionary, reason: String) -> Dictionary:
	return {
		"brigade_id": bid,
		"bn_id": String(bn.get("id", "")),
		"bn_type": String(bn.get("type", "")),
		"reason": reason,
	}


# Find first infra entry with matching kind and remaining >= cost.
# Decrements entry.remaining in-place. Returns matching entry or {}.
# same_to_only: when true, also requires entry.to_number == to_num.
static func _try_infra_landing(infra_remaining: Array, kind: String, to_num: int, same_to_only: bool, cost: float) -> Dictionary:
	for i in range(infra_remaining.size()):
		var entry: Dictionary = infra_remaining[i]
		if String(entry.get("kind", "")) != kind:
			continue
		if same_to_only and int(entry.get("to_number", -1)) != to_num:
			continue
		var remaining: float = float(entry.get("remaining", 0.0))
		if remaining >= cost:
			entry["remaining"] = remaining - cost
			return entry
	return {}
