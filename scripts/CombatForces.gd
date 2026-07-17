extends RefCounted
class_name CombatForces


static func is_support_type(unit_type: String) -> bool:
	return UnitStats.has_tag(unit_type, "artillery") or UnitStats.has_tag(unit_type, "rotary_wing")


static func maneuver_units(brigades: Array) -> Array:
	var units: Array = []
	for brigade_value in brigades:
		var brigade: Brigade = brigade_value
		for battalion in brigade.composition:
			if is_support_type(battalion.type):
				continue
			for i in range(battalion.qty):
				units.append({
					"brigade_id": brigade.id,
					"type": battalion.type,
					"supply_effectiveness": 1.0
				})
	return units

static func support_units(brigades: Array) -> Array:
	var units: Array = []
	for brigade_value in brigades:
		var brigade: Brigade = brigade_value
		for battalion in brigade.composition:
			if not is_support_type(battalion.type):
				continue
			for i in range(battalion.qty):
				units.append({
					"brigade_id": brigade.id,
					"type": battalion.type,
					"supply_effectiveness": 1.0
				})
	return units


static func support_counts(brigades: Array) -> Dictionary:
	var counts := {
		"artillery": 0,
		"rocket_artillery": 0,
		"cas": 0,
		"crbm": 0,
		"rotary_wing": 0
	}
	for brigade_value in brigades:
		var brigade: Brigade = brigade_value
		for battalion in brigade.composition:
			if UnitStats.has_tag(battalion.type, "rocket"):
				counts["rocket_artillery"] += battalion.qty
			elif UnitStats.has_tag(battalion.type, "artillery"):
				counts["artillery"] += battalion.qty
			elif UnitStats.has_tag(battalion.type, "rotary_wing"):
				counts["rotary_wing"] += battalion.qty
	return counts
