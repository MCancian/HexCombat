class_name IjfsTarget
extends Resource

@export var target_id: String = ""
@export var source_target_id: String = ""
@export var instance_index: int = 1
@export var category: String = ""
@export var subcategory: String = ""
@export var quantity: int = 1
@export var mobility: String = "static"
@export var hardness: String = "soft"
@export var detectability_active: String = "medium"
@export var detectability_hiding: String = "low"
@export var posture: String = "not_applicable"
@export var destroyed: bool = false
@export var detected_this_turn: bool = false
@export var last_detected_day: int = -1
@export var known_to_red: bool = false
@export var suppressed: bool = false
@export var suppressed_this_turn: bool = false
@export var intel_locked: bool = false
@export var sam_score: int = -1
@export var sead_result: String = ""
@export var metadata: Dictionary = {}


## Faithful port of TargetInstance.to_dict() (state.py asdict). GDScript sentinels map back to
## the source's None: last_detected_day/sam_score == -1 -> null, sead_result "" -> null. Used by
## the strike skip-log and the engine's target-status ledger.
func to_dict() -> Dictionary:
	return {
		"target_id": target_id,
		"source_target_id": source_target_id,
		"instance_index": instance_index,
		"category": category,
		"subcategory": subcategory,
		"quantity": quantity,
		"mobility": mobility,
		"hardness": hardness,
		"detectability_active": detectability_active,
		"detectability_hiding": detectability_hiding,
		"posture": posture,
		"destroyed": destroyed,
		"detected_this_turn": detected_this_turn,
		"last_detected_day": null if last_detected_day == -1 else last_detected_day,
		"known_to_red": known_to_red,
		"suppressed": suppressed,
		"suppressed_this_turn": suppressed_this_turn,
		"sam_score": null if sam_score == -1 else sam_score,
		"sead_result": null if sead_result == "" else sead_result,
		"intel_locked": intel_locked,
		"metadata": metadata,
	}
