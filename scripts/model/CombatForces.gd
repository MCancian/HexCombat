extends RefCounted
class_name CombatForces

## Expands brigades into the individual battalion units ground combat fights with.
##
## ONLY LANDED BATTALIONS COUNT (plan 0037, USER call 2026-07-25). A brigade's `hex_id` is set the
## moment its FIRST battalion lands, but `composition` is the roster of battalions that EXIST, not
## the roster of battalions that are HERE — the rest may still be at sea, on the mainland waiting for
## a hull, or waiting to fly. Every function here therefore takes `not_ashore_by_type`
## (`PendingBattalions.by_brigade_and_type`, keyed brigade_id -> {type: count}) and subtracts it from
## each battalion entry's `qty` via `Brigade.landed_qty`, the single home of that rule. Pass `{}` for a
## force with nothing off-map (Green never has pools).


static func is_support_type(unit_type: String) -> bool:
	return UnitStats.has_tag(unit_type, "artillery") or UnitStats.has_tag(unit_type, "rotary_wing")


## Maneuver and support units for a force, in ONE pass: {"maneuver": [...], "support": [...]}.
##
## The single implementation. `maneuver_units` and `support_units` are views onto it — they used to be
## byte-identical bodies differing only by a `not` on the support test, which meant the landed
## subtraction lived twice. `CombatResolver` needs both halves for each side anyway, so the combined
## form is also the one that walks each composition once instead of twice.
static func split_units(brigades: Array, not_ashore_by_type: Dictionary = {}) -> Dictionary:
	var maneuver: Array = []
	var support: Array = []
	for brigade_value in brigades:
		var brigade: Brigade = brigade_value
		var brigade_not_ashore: Dictionary = not_ashore_by_type.get(brigade.id, {})
		for battalion in brigade.composition:
			var bucket: Array = support if is_support_type(battalion.type) else maneuver
			for _landed_index in range(Brigade.landed_qty(battalion, brigade_not_ashore)):
				bucket.append({
					"brigade_id": brigade.id,
					"type": battalion.type,
					"supply_effectiveness": 1.0
				})
	return {"maneuver": maneuver, "support": support}


static func maneuver_units(brigades: Array, not_ashore_by_type: Dictionary = {}) -> Array:
	return split_units(brigades, not_ashore_by_type)["maneuver"]


static func support_units(brigades: Array, not_ashore_by_type: Dictionary = {}) -> Array:
	return split_units(brigades, not_ashore_by_type)["support"]


static func support_counts(brigades: Array, not_ashore_by_type: Dictionary = {}) -> Dictionary:
	var counts := {
		"artillery": 0,
		"rocket_artillery": 0,
		"cas": 0,
		"crbm": 0,
		"rotary_wing": 0
	}
	for brigade_value in brigades:
		var brigade: Brigade = brigade_value
		var brigade_not_ashore: Dictionary = not_ashore_by_type.get(brigade.id, {})
		for battalion in brigade.composition:
			var landed := Brigade.landed_qty(battalion, brigade_not_ashore)
			if UnitStats.has_tag(battalion.type, "rocket"):
				counts["rocket_artillery"] += landed
			elif UnitStats.has_tag(battalion.type, "artillery"):
				counts["artillery"] += landed
			elif UnitStats.has_tag(battalion.type, "rotary_wing"):
				counts["rotary_wing"] += landed
	return counts
