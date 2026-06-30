extends Resource
class_name ShipDef

@export var id: int = 0
@export var name: String = ""
@export var display_name: String = ""
@export var category: String = ""
@export var infrastructure: bool = false
@export var total_count: int = 0
@export var initial_ready: int = 0
@export var carrying_capacity_bn_equiv: float = 0.0
@export var is_decoy: bool = false
@export var setup_group: String = ""
@export var mine_neutralization_likelihood: String = ""  # optional per-hull override; "" => use category
