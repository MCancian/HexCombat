extends Resource
class_name Brigade

enum Team { RED, GREEN }

# Organization costs (percentage points). Tracked now; inert until wired into combat later.
const MAX_ORGANIZATION := 100.0
const ADMIN_MOVE_ORG_COST := 100.0      # administrative move: -100%
const TACTICAL_MOVE_ORG_COST := 25.0    # tactical move: -25%
const COMBAT_ORG_COST_PER_TURN := 10.0  # -10% per turn in combat
const ORG_RECOVERY_PER_TURN := 10.0     # +10% per turn when neither moving nor fighting

@export var id: String = ""
@export var name: String = ""
@export var team: Team = Team.RED
@export var nato_type: String = ""
@export var composition: Array[Battalion] = []

@export var hex_id: String = ""
@export var entry_bearing: float = 0.0
@export var moved_this_turn: bool = false
@export var moved_admin_this_turn: bool = false
@export var fought_this_turn: bool = false
@export var destroyed: bool = false
@export var organization: float = MAX_ORGANIZATION  # 0-100; does not affect combat yet


func get_battalion_count() -> int:
	var total := 0
	for battalion in composition:
		total += battalion.qty
	return total


func to_combat_units() -> Array:
	var units: Array = []
	for battalion in composition:
		for i in range(battalion.qty):
			units.append({
				"brigade_id": id,
				"type": battalion.type,
				"supply_effectiveness": 1.0
			})
	return units


func adjust_organization(delta: float) -> void:
	organization = clampf(organization + delta, 0.0, MAX_ORGANIZATION)
