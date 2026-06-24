extends RefCounted
class_name Movement

const FAST_MOBILITY_HINTS := ["mechanized", "armor", "tank"]
const TACTICAL_FAST := 2
const TACTICAL_SLOW := 1
const ADMIN_FAST := 20
const ADMIN_SLOW := 10
const MODE_TACTICAL := "tactical"
const MODE_ADMINISTRATIVE := "administrative"


static func is_fast_mobility(brigade: Brigade) -> bool:
	var nato_type_lower := brigade.nato_type.to_lower()
	for hint in FAST_MOBILITY_HINTS:
		if nato_type_lower.contains(hint):
			return true

	for battalion in brigade.composition:
		var battalion_type_lower := battalion.type.to_lower()
		for hint in FAST_MOBILITY_HINTS:
			if battalion_type_lower.contains(hint):
				return true

	return false


static func tactical_speed(brigade: Brigade) -> int:
	return TACTICAL_FAST if is_fast_mobility(brigade) else TACTICAL_SLOW


static func administrative_speed(brigade: Brigade) -> int:
	return ADMIN_FAST if is_fast_mobility(brigade) else ADMIN_SLOW


static func move_allowance(brigade: Brigade, mode: String) -> int:
	match mode:
		MODE_TACTICAL:
			return tactical_speed(brigade)
		MODE_ADMINISTRATIVE:
			return administrative_speed(brigade)
		_:
			push_error("Unknown movement mode: %s" % mode)
			return 0
