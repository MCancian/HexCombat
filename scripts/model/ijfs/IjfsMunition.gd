class_name IjfsMunition
extends Resource

@export var munition_id: String = ""
@export var name: String = ""
@export var category: String = ""
@export var inventory_remaining: int = 0
@export var rounds_per_engagement_default: int = 0
@export var display_label: String = ""
# 0.0 = immune (ballistic/cruise fly above MANPADS); >0 scales interception risk for
# low-altitude air-breathers (UAVs, OWA drones, strike aircraft). See IjfsManpads.
@export var manpads_vulnerability: float = 0.0
