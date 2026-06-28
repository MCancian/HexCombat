extends Resource
class_name TurnEvent

@export var seq: int = 0
@export var kind: String = ""
@export var hex_id: String = ""
@export var team: String = ""
@export var data: Dictionary = {}

func to_dict() -> Dictionary:
	return {"seq": seq, "kind": kind, "hex_id": hex_id, "team": team, "data": data.duplicate(true)}
