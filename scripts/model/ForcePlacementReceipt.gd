class_name ForcePlacementReceipt
extends Resource

@export var brigade_id: String = ""
@export var old_hex: String = ""
@export var new_hex: String = ""
@export var destination: String = ""
@export var phase: String = ""


func to_dict() -> Dictionary:
	return {
		"brigade_id": brigade_id,
		"old_hex": old_hex,
		"new_hex": new_hex,
		"destination": destination,
		"phase": phase,
	}
