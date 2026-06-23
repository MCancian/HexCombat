extends Resource
class_name Battalion

@export var type: String = ""
@export var qty: int = 0

var combat_strength: float:
	get:
		return _combat_strength_for_type(type) * float(qty)


static func _combat_strength_for_type(unit_type: String) -> float:
	var strengths := {
		"Light": 1.0,
		"Light Infantry": 1.0,
		"Medium": 1.5,
		"Heavy": 2.0,
		"Mechanized": 1.5,
		"Mechanized Infantry": 1.5,
		"Armor": 2.0,
		"Tank": 2.0,
		"Amphib": 1.2,
		"Amphibious": 1.2,
		"SOF": 1.8,
		"Recon": 0.7,
		"Towed": 0.8,
		"Towed Artillery": 0.8,
		"SP": 1.3,
		"SP Artillery": 1.3,
		"Mechanized Artillery": 1.3,
		"C2": 0.5,
		"HQ": 0.5,
		"SHORAD": 0.9,
		"Air Defense": 0.9,
		"Cargo": 0.3,
		"Support": 0.3,
		"Engineer": 1.1,
		"Airborne": 1.3,
		"Air Assault": 1.4,
		"Rotary Wing": 0.5,
		"Helicopter": 0.5,
		"DOS": 0.2,
		"Logistics": 0.2
	}

	for key in strengths:
		if key.to_lower() in unit_type.to_lower():
			return strengths[key]
	return strengths.get(unit_type, 1.0)
