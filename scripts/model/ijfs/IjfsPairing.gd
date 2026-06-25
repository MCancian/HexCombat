class_name IjfsPairing
extends Resource

@export var order: int = 0
@export var pairing_id: String = ""
@export var munition_id: String = ""
@export var target_effect_profile_id: String = ""
@export var target_category: String = ""
@export var target_subcategory: String = ""
@export var target_mobility: String = ""
@export var target_hardness: String = ""
@export var rounds_expended_per_engagement: int = 0
@export var probability_destroyed: float = 0.0
@export var probability_suppressed_if_not_destroyed: float = 0.0
@export var source_target_ids: Array[String] = []
