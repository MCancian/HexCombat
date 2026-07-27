class_name ForceCasualtyReceipt
extends Resource

@export var brigade_id: String = ""
@export var battalion_type: String = ""
@export var requested: int = 0
@export var applied: int = 0
@export var cause: String = ""
@export var source_location: String = ""
@export var destroyed_brigade: bool = false
@export var removed_from_hex: String = ""


func to_dict() -> Dictionary:
	return {
		"brigade_id": brigade_id,
		"battalion_type": battalion_type,
		"requested": requested,
		"applied": applied,
		"cause": cause,
		"source_location": source_location,
		"destroyed_brigade": destroyed_brigade,
		"removed_from_hex": removed_from_hex,
	}
