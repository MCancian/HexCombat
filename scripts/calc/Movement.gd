extends RefCounted
class_name Movement

const FAST_MOBILITY_HINTS := ["mechanized", "armor", "tank"]
const TACTICAL_FAST := 2
const TACTICAL_SLOW := 1
const ADMIN_FAST := 20
const ADMIN_SLOW := 10
const MODE_TACTICAL := "tactical"
const MODE_ADMINISTRATIVE := "administrative"


# Mobility is decided by the brigade's own nato_type only.
# NOTE: deliberate divergence from the TIV oracle (boots_hex_service.infer_green_brigade_speed),
# which also promotes a brigade to "fast" if ANY battalion type contains a hint token — that made
# leg brigades fast purely from a "Mechanized Artillery" support battalion. Composition is ignored
# here so support units don't change a formation's march speed. (User decision 2026-06-24.)
static func is_fast_mobility(brigade: Brigade) -> bool:
	var nato_type_lower := brigade.nato_type.to_lower()
	for hint in FAST_MOBILITY_HINTS:
		if nato_type_lower.contains(hint):
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
