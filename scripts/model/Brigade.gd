extends Resource
class_name Brigade

enum Team { RED, GREEN }

@export var id: String = ""
@export var name: String = ""
@export var team: Team = Team.RED
@export var nato_type: String = ""
@export var composition: Array[Battalion] = []

@export var hex_id: String = ""
@export var moved_this_turn: bool = false
@export var fought_this_turn: bool = false
@export var destroyed: bool = false


func get_battalion_count() -> int:
	var total := 0
	for battalion in composition:
		total += battalion.qty
	return total


func to_combat_units() -> Array:
	var units: Array = []
	for battalion in composition:
		for i in range(battalion.qty):
			units.append({
				"brigade_id": id,
				"type": battalion.type,
				"supply_effectiveness": 1.0
			})
	return units
