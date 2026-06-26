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
