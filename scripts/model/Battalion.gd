extends Resource
class_name Battalion

@export var type: String = ""
@export var qty: int = 0

var combat_strength: float:
	get:
		return UnitStats.strength_for_type(type, 1.0) * float(qty)
