extends RefCounted
class_name UnitStats

# NOTE: battalions tagged "artillery" or "rotary_wing" are routed to combat SUPPORT (via their support
# multiplier) and excluded from maneuver_units (see CombatForces). Their `strength` here is therefore
# NOT used as maneuver combat strength — helicopters (rotary_wing) contribute at the rotary_wing support
# multiplier (1.3) in both HexCombat and TIV, so the helicopter strength value is intentionally low/dead.
const TYPE_DEFS := {
	"Air Assault Infantry Battalion": {"category": "Air Assault", "strength": 1.4, "tags": ["infantry", "air_assault"]},
	"Air Defense Battalion": {"category": "Air Defense", "strength": 0.9, "tags": ["air_defense"]},
	"Amphibious Infantry Battalion": {"category": "Amphibious", "strength": 1.2, "tags": ["infantry", "amphibious"]},
	"Armor Battalion": {"category": "Armor", "strength": 2.0, "tags": ["armor"]},
	"Attack Helicopter Battalion": {"category": "Helicopter", "strength": 0.5, "tags": ["aviation", "rotary_wing", "attack"]},
	"Combined Arms Battalion": {"category": "Mechanized", "strength": 1.5, "tags": ["maneuver", "mechanized"]},
	"Field Artillery Battalion": {"category": "Towed Artillery", "strength": 0.8, "tags": ["artillery"]},
	"Infantry Battalion (Reserve)": {"category": "Reserve Infantry", "strength": 0.5, "tags": ["infantry", "reserve"]},
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

const FALLBACK_CATEGORY_DEFS := {
	"Light": {"strength": 1.0, "tags": []},
	"Light Infantry": {"strength": 1.0, "tags": ["infantry"]},
	"Medium": {"strength": 1.5, "tags": []},
	"Heavy": {"strength": 2.0, "tags": []},
	"Mechanized": {"strength": 1.5, "tags": ["mechanized"]},
	"Mechanized Infantry": {"strength": 1.5, "tags": ["infantry", "mechanized"]},
	"Armor": {"strength": 2.0, "tags": ["armor"]},
	"Tank": {"strength": 2.0, "tags": ["armor"]},
	"Amphib": {"strength": 1.2, "tags": ["amphibious"]},
	"Amphibious": {"strength": 1.2, "tags": ["amphibious"]},
	"SOF": {"strength": 1.8, "tags": ["special_forces"]},
	"Recon": {"strength": 0.7, "tags": ["recon"]},
	"Towed": {"strength": 0.8, "tags": []},
	"Towed Artillery": {"strength": 0.8, "tags": ["artillery"]},
	"SP": {"strength": 1.3, "tags": []},
	"SP Artillery": {"strength": 1.3, "tags": ["artillery"]},
	"Mechanized Artillery": {"strength": 1.3, "tags": ["artillery", "mechanized"]},
	"C2": {"strength": 0.5, "tags": ["command"]},
	"HQ": {"strength": 0.5, "tags": ["command"]},
	"SHORAD": {"strength": 0.9, "tags": ["air_defense"]},
	"Air Defense": {"strength": 0.9, "tags": ["air_defense"]},
	"Cargo": {"strength": 0.3, "tags": ["support"]},
	"Support": {"strength": 0.3, "tags": ["support"]},
	"Engineer": {"strength": 1.1, "tags": ["engineer"]},
	"Airborne": {"strength": 1.3, "tags": ["airborne"]},
	"Air Assault": {"strength": 1.4, "tags": ["air_assault"]},
	"Rotary Wing": {"strength": 0.5, "tags": ["aviation", "rotary_wing"]},
	"Helicopter": {"strength": 0.5, "tags": ["aviation", "rotary_wing"]},
	"DOS": {"strength": 0.2, "tags": ["logistics"]},
	"Logistics": {"strength": 0.2, "tags": ["logistics"]}
}


static func has_known_type(unit_type: String) -> bool:
	return TYPE_DEFS.has(unit_type)


static func strength_for_type(unit_type: String, default_strength: float = 1.0) -> float:
	var definition := _definition_for_type(unit_type, true, default_strength)
	if definition.is_empty():
		return default_strength
	return float(definition.get("strength", default_strength))


static func category_for_type(unit_type: String) -> String:
	var definition := _definition_for_type(unit_type, true, 1.0)
	return String(definition.get("category", ""))


static func tags_for_type(unit_type: String) -> Array[String]:
	var definition := _definition_for_type(unit_type, true, 1.0)
	var tags: Array[String] = []
	for tag in definition.get("tags", []):
		tags.append(String(tag))
	return tags


static func has_tag(unit_type: String, tag: String) -> bool:
	return tag in tags_for_type(unit_type)


static func is_artillery_type(unit_type: String) -> bool:
	return has_tag(unit_type, "artillery")


static func _definition_for_type(unit_type: String, warn_on_fallback: bool, default_strength: float) -> Dictionary:
	if TYPE_DEFS.has(unit_type):
		return TYPE_DEFS[unit_type]

	var fallback_category := _fallback_category_for_type(unit_type)
	if not fallback_category.is_empty():
		if warn_on_fallback:
			push_warning("Unknown battalion type '%s'; using fallback category '%s'" % [unit_type, fallback_category])
		var fallback_definition: Dictionary = FALLBACK_CATEGORY_DEFS[fallback_category].duplicate()
		fallback_definition["category"] = fallback_category
		return fallback_definition

	if warn_on_fallback:
		push_warning("Unknown battalion type '%s'; using default combat strength %.1f" % [unit_type, default_strength])
	return {}


static func _fallback_category_for_type(unit_type: String) -> String:
	if FALLBACK_CATEGORY_DEFS.has(unit_type):
		return unit_type

	var normalized_type := unit_type.to_lower()
	var best_key := ""
	for key in FALLBACK_CATEGORY_DEFS:
		var normalized_key := String(key).to_lower()
		if normalized_key in normalized_type and String(key).length() > best_key.length():
			best_key = key
	return best_key
