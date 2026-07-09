extends Resource
class_name TerrainType

@export var name: String = ""
@export var defender_modifier: float = 1.0
@export var move_cost: int = 1
@export var impassable: bool = false
@export var color: String = ""

func to_dict() -> Dictionary:
	return {
		"name": name,
		"defender_modifier": defender_modifier,
		"move_cost": move_cost,
		"impassable": impassable,
		"color": color
	}
