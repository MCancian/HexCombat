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


static func maneuver_units(brigades: Array, not_ashore_by_type: Dictionary = {}) -> Array:
	var units: Array = []
	for brigade_value in brigades:
		var brigade: Brigade = brigade_value
		var brigade_not_ashore: Dictionary = not_ashore_by_type.get(brigade.id, {})
		for battalion in brigade.composition:
			if is_support_type(battalion.type):
				continue
			for i in range(Brigade.landed_qty(battalion, brigade_not_ashore)):
				units.append({
					"brigade_id": brigade.id,
					"type": battalion.type,
					"supply_effectiveness": 1.0
				})
	return units

static func support_units(brigades: Array, not_ashore_by_type: Dictionary = {}) -> Array:
	var units: Array = []
	for brigade_value in brigades:
		var brigade: Brigade = brigade_value
		var brigade_not_ashore: Dictionary = not_ashore_by_type.get(brigade.id, {})
		for battalion in brigade.composition:
			if not is_support_type(battalion.type):
				continue
			for i in range(Brigade.landed_qty(battalion, brigade_not_ashore)):
				units.append({
					"brigade_id": brigade.id,
					"type": battalion.type,
					"supply_effectiveness": 1.0
				})
	return units


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
