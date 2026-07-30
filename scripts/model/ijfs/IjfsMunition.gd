class_name IjfsMunition
extends Resource

@export var munition_id: String = ""
## Display name. Deliberately NOT called `name`: the mutation gate protects field NAMES, and
## `name` is a Godot Node property written all over the view layer, so protecting it produced 22
## false unresolved-write failures (plan 0046 commit 4). The manifest's _schema_rules ask for
## distinctive names for exactly this reason. The JSON key stays "name".
@export var munition_name: String = ""
@export var category: String = ""
@export var inventory_remaining: int = 0
@export var rounds_per_engagement_default: int = 0
@export var display_label: String = ""
# 0.0 = immune (ballistic/cruise fly above MANPADS); >0 scales interception risk for
# low-altitude air-breathers (UAVs, OWA drones, strike aircraft). See IjfsManpads.
@export var manpads_vulnerability: float = 0.0
