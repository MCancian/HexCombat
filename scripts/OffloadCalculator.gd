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
		_resolve_day_n(ordered_ids, brigade_map, beach_capacity, manifest_landed, manifest_deferred)

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
					"reason": "day1_no_beach_slot",
				})
			else:
				manifest_deferred.append({
					"brigade_id": bid,
					"bn_id": bn_id,
					"bn_type": bn_type,
					"reason": "day1_support_waiting",
				})


# Day 2+: all remaining BNs (support + any un-landed maneuver) compete for throughput.
# Greedy allocation in priority order; each BN costs TONS_PER_BN throughput.
static func _resolve_day_n(
	ordered_ids: Array[String],
	brigade_map: Dictionary,
	beach_capacity: Dictionary,
	manifest_landed: Array,
	manifest_deferred: Array,
) -> void:
	# Remaining capacity per beach in tons.
	var remaining_tons: Dictionary = {}
	for beach_id_var in beach_capacity.keys():
		remaining_tons[int(beach_id_var)] = float(beach_capacity[beach_id_var]) * OffloadRates.TONS_PER_BN

	for bid in ordered_ids:
		var brigade: Dictionary = brigade_map[bid]
		var bns: Array = brigade.get("bns", [])
		var locked := int(brigade.get("locked_beach", 0))

		# Determine eligible beach (locked or first available).
		var target_beach := -1
		if locked > 0 and locked in remaining_tons:
			target_beach = locked
		else:
			for beach_id_var in remaining_tons.keys():
				var beach_id := int(beach_id_var)
				if remaining_tons[beach_id] >= OffloadRates.TONS_PER_BN:
					target_beach = beach_id
					break

		for bn in bns:
			var bn_id := String(bn.get("id", ""))
			var bn_type := String(bn.get("type", ""))
			if target_beach >= 0 and remaining_tons.get(target_beach, 0.0) >= OffloadRates.TONS_PER_BN:
				remaining_tons[target_beach] -= OffloadRates.TONS_PER_BN
				manifest_landed.append({
					"brigade_id": bid,
					"bn_id": bn_id,
					"bn_type": bn_type,
					"beach_id": target_beach,
				})
			else:
				manifest_deferred.append({
					"brigade_id": bid,
					"bn_id": bn_id,
					"bn_type": bn_type,
					"reason": "throughput_limited",
				})
