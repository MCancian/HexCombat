extends RefCounted
class_name UnitStats

# NOTE: battalions tagged "artillery" or "rotary_wing" are routed to combat SUPPORT (via their support
# multiplier) and excluded from maneuver_units (see CombatForces). Their `strength` here is therefore
# NOT used as maneuver combat strength — helicopters (rotary_wing) contribute at the rotary_wing support
# multiplier (1.3) in both HexCombat and TIV, so the helicopter strength value is intentionally low/dead.
#
# NOTE (2026-08-05): TYPE_DEFS is the SINGLE authoritative mapping from battalion type ->
# {category, strength, tags}. Every battalion type in BOTH ground-force OOBs must resolve here; that
# is enforced mechanically by tools/validate_oob_data.gd and tools/validate_combat_data.gd, so an
# unknown type is a DATA BUG, not a lookup miss. There is deliberately NO fallback table and NO
# substring heuristic: an unknown type fails loud via push_error below, and the caller falls back to
# its explicit default_strength. The old FALLBACK_CATEGORY_DEFS heuristic was removed
# (docs/DECISIONS.md 2026-08-05) because every real type already resolved via TYPE_DEFS (0 fallback
# hits) and the heuristic silently assigned arbitrary strengths/categories to typo'd or new types — a
# "silent default fallback" the project convention forbids.
#
# NOTE: the two PLAAF Airborne Corps types (plan 0032) carry their category ("Airborne") and strengths
# (1.3 light, 1.4 mechanized) directly in TYPE_DEFS — light airborne is well above a plain infantry
# 1.0, the ZBD-03-equipped mechanized airborne sits below the 1.5 of a fully mechanized Combined Arms
# Battalion, matching where the "Air Assault" category already sits.
const TYPE_DEFS := {
	"Air Assault Infantry Battalion": {"category": "Air Assault", "strength": 1.4, "tags": ["infantry", "air_assault"]},
	"Air Defense Battalion": {"category": "Air Defense", "strength": 0.9, "tags": ["air_defense"]},
	"Airborne Combined Arms Battalion": {"category": "Airborne", "strength": 1.3, "tags": ["infantry", "airborne"]},
	"Amphibious Infantry Battalion": {"category": "Amphibious", "strength": 1.2, "tags": ["infantry", "amphibious"]},
	"Armor Battalion": {"category": "Armor", "strength": 2.0, "tags": ["armor"]},
	"Attack Helicopter Battalion": {"category": "Helicopter", "strength": 0.5, "tags": ["aviation", "rotary_wing", "attack"]},
	"Combined Arms Battalion": {"category": "Mechanized", "strength": 1.5, "tags": ["maneuver", "mechanized"]},
	"Field Artillery Battalion": {"category": "Towed Artillery", "strength": 0.8, "tags": ["artillery"]},
	"Infantry Battalion (Reserve)": {"category": "Reserve Infantry", "strength": 0.5, "tags": ["infantry", "reserve"]},
	"Mechanized Airborne Combined Arms Battalion": {"category": "Airborne", "strength": 1.4, "tags": ["infantry", "airborne", "mechanized"]},
	"Mechanized Artillery Battalion": {"category": "Mechanized Artillery", "strength": 1.3, "tags": ["artillery", "mechanized"]},
	"Mechanized Infantry Battalion": {"category": "Mechanized Infantry", "strength": 1.5, "tags": ["infantry", "mechanized"]},
	"Reconnaissance Battalion": {"category": "Recon", "strength": 0.7, "tags": ["recon"]},
	"Rocket Artillery Battalion": {"category": "SP Artillery", "strength": 1.3, "tags": ["artillery", "rocket"]},
	"Service Support Battalion": {"category": "Support", "strength": 0.3, "tags": ["support", "service_support"]},
	"Special Forces Battalion": {"category": "SOF", "strength": 1.8, "tags": ["special_forces"]},
	"Support Battalion": {"category": "Support", "strength": 0.3, "tags": ["support"]},
	"Tank Battalion": {"category": "Armor", "strength": 2.0, "tags": ["armor"]},
	"Utility Helicopter Battalion": {"category": "Helicopter", "strength": 0.5, "tags": ["aviation", "rotary_wing", "utility"]}
}


static func has_known_type(unit_type: String) -> bool:
	return TYPE_DEFS.has(unit_type)


static func strength_for_type(unit_type: String, default_strength: float = 1.0) -> float:
	var definition := _definition_for_type(unit_type)
	if definition.is_empty():
		return default_strength
	return float(definition.get("strength", default_strength))


static func category_for_type(unit_type: String) -> String:
	var definition := _definition_for_type(unit_type)
	return String(definition.get("category", ""))


static func tags_for_type(unit_type: String) -> Array[String]:
	var definition := _definition_for_type(unit_type)
	var tags: Array[String] = []
	for tag in definition.get("tags", []):
		tags.append(String(tag))
	return tags


static func has_tag(unit_type: String, tag: String) -> bool:
	return tag in tags_for_type(unit_type)


static func is_artillery_type(unit_type: String) -> bool:
	return has_tag(unit_type, "artillery")


static func _definition_for_type(unit_type: String) -> Dictionary:
	if TYPE_DEFS.has(unit_type):
		return TYPE_DEFS[unit_type]
	push_error("Unknown battalion type '%s' has no UnitStats.TYPE_DEFS definition" % unit_type)
	return {}
