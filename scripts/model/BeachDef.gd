extends Resource
class_name BeachDef

@export var id: int = 0
@export var name_en: String = ""
@export var hex_id: String = ""
@export var category: String = ""
@export var to_number: int = 0
@export var offload_rate: float = 0.0  # short tons/day
@export var capacity_battalions: int = 0
@export var depth: int = 2  # landed RED brigades the beach hex holds before offload chokes (plan 0006 occupancy valve)
@export var floating_piers: int = 0
@export var jackup_barge: int = 0
@export var advance_direction: float = 0.0  # degrees; direction assault force advances inland
@export var lat: float = 0.0
@export var lng: float = 0.0
