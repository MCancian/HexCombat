extends RefCounted
class_name DosConsumption

const BASE_MECHANIZED_TONS: int = 300
const BASE_NON_MECHANIZED_TONS: int = 150
const TONS_PER_DOS: int = 150

const KNOWN_MECHANIZED_BATTALION_TYPES: Array[String] = [
	"Combined Arms Battalion",
	"Mechanized Infantry Battalion",
	"Mechanized Artillery Battalion",
	"Tank Battalion",
	"Amphibious Infantry Battalion",
]
const KNOWN_NON_MECHANIZED_BATTALION_TYPES: Array[String] = [
	"Air Assault Infantry Battalion",
	"Special Forces Battalion",
	"Field Artillery Battalion",
	"Rocket Artillery Battalion",
	"Air Defense Battalion",
	"Reconnaissance Battalion",
	"Service Support Battalion",
	"Support Battalion",
	"Attack Helicopter Battalion",
	"Utility Helicopter Battalion",
]
const MECHANIZED_TYPE_HINTS: Array[String] = ["mechanized", "tank", "armor", "combined arms", "amphibious"]
const BRIGADE_TYPE_HINTS: Array[String] = ["mech", "armor", "amphibious"]


static func is_mechanized_bn(unit_type: String, brigade_type: String = "") -> bool:
	var normalized := unit_type.strip_edges()
	if normalized.is_empty():
		return false
	if normalized in KNOWN_MECHANIZED_BATTALION_TYPES:
		return true
	if normalized in KNOWN_NON_MECHANIZED_BATTALION_TYPES:
		return false

	var unit_type_lower := normalized.to_lower()
	for hint in MECHANIZED_TYPE_HINTS:
		if hint in unit_type_lower:
			return true

	if not brigade_type.is_empty():
		var brigade_type_lower := brigade_type.to_lower()
		for hint in BRIGADE_TYPE_HINTS:
			if hint in brigade_type_lower:
				return true

	return false


static func compute_unit_tons(mechanized: bool, moved: bool, in_combat: bool) -> int:
	var base := BASE_NON_MECHANIZED_TONS
	if mechanized:
		base = BASE_MECHANIZED_TONS
	var reduction := 0
	if not moved:
		@warning_ignore("integer_division")
		reduction += base / 3
	if not in_combat:
		@warning_ignore("integer_division")
		reduction += base / 3
	return base - reduction


static func calculate_consumption(units: Array, moved_brigade_ids, engaged_brigade_ids, day: int = 0) -> Dictionary:
	if units.is_empty():
		return _empty_summary(day)

	var moved_lookup := _to_lookup(moved_brigade_ids)
	var engaged_lookup := _to_lookup(engaged_brigade_ids)
	var total_tons := 0
	var mechanized_unit_count := 0
	var non_mechanized_unit_count := 0
	var moved_unit_count := 0
	var combat_unit_count := 0
	var by_brigade: Dictionary = {}

	for unit_value in units:
		var unit: Dictionary = unit_value
		var brigade_id := String(unit.get("brigade_id", ""))
		var unit_type := String(unit.get("type", ""))
		var brigade_type := String(unit.get("brigade_type", ""))
		var mechanized := is_mechanized_bn(unit_type, brigade_type)
		var moved := brigade_id in moved_lookup
		var in_combat := brigade_id in engaged_lookup
		var tons := compute_unit_tons(mechanized, moved, in_combat)

		total_tons += tons
		if mechanized:
			mechanized_unit_count += 1
		else:
			non_mechanized_unit_count += 1
		if moved:
			moved_unit_count += 1
		if in_combat:
			combat_unit_count += 1

		if brigade_id not in by_brigade:
			by_brigade[brigade_id] = {
				"brigade_id": brigade_id,
				"brigade_type": brigade_type,
				"unit_count": 0,
				"mechanized_count": 0,
				"non_mechanized_count": 0,
				"moved": moved,
				"in_combat": in_combat,
				"tons": 0,
			}
		var brigade_summary: Dictionary = by_brigade[brigade_id]
		brigade_summary["unit_count"] = int(brigade_summary["unit_count"]) + 1
		if mechanized:
			brigade_summary["mechanized_count"] = int(brigade_summary["mechanized_count"]) + 1
		else:
			brigade_summary["non_mechanized_count"] = int(brigade_summary["non_mechanized_count"]) + 1
		brigade_summary["tons"] = int(brigade_summary["tons"]) + tons

	var unit_count := units.size()
	var baseline_dos_equivalent := unit_count
	var activity_dos_equivalent_exact := total_tons / float(TONS_PER_DOS)
	var activity_delta_exact := activity_dos_equivalent_exact - baseline_dos_equivalent
	var activity_delta_rounded := int(ceil(activity_delta_exact))
	var activity_delta_rounding_residual := activity_delta_exact - activity_delta_rounded

	return {
		"applied": false,
		"day": day,
		"unit_count": unit_count,
		"mechanized_unit_count": mechanized_unit_count,
		"non_mechanized_unit_count": non_mechanized_unit_count,
		"moved_unit_count": moved_unit_count,
		"combat_unit_count": combat_unit_count,
		"baseline_dos_equivalent": baseline_dos_equivalent,
		"red_dos_consumed_tons": total_tons,
		"activity_dos_equivalent_exact": activity_dos_equivalent_exact,
		"activity_delta_exact": activity_delta_exact,
		"activity_delta_rounded": activity_delta_rounded,
		"activity_delta_rounding_residual": activity_delta_rounding_residual,
		"by_brigade": by_brigade,
	}


static func _empty_summary(day: int) -> Dictionary:
	return {
		"applied": false,
		"day": day,
		"unit_count": 0,
		"mechanized_unit_count": 0,
		"non_mechanized_unit_count": 0,
		"moved_unit_count": 0,
		"combat_unit_count": 0,
		"baseline_dos_equivalent": 0,
		"red_dos_consumed_tons": 0,
		"activity_dos_equivalent_exact": 0.0,
		"activity_delta_exact": 0.0,
		"activity_delta_rounded": 0,
		"activity_delta_rounding_residual": 0.0,
		"by_brigade": {},
	}


static func _to_lookup(values) -> Dictionary:
	var lookup: Dictionary = {}
	if values is Dictionary:
		for key in values.keys():
			lookup[String(key)] = true
		return lookup
	if values is Array:
		for value in values:
			lookup[String(value)] = true
		return lookup
	push_error("DOS consumption brigade id set must be an Array or Dictionary")
	return lookup
