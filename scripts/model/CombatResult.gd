extends Resource
class_name CombatResult

@export var attacker_strength: float = 0.0
@export var defender_strength: float = 0.0
@export var attacker_maneuver_strength: float = 0.0
@export var defender_maneuver_strength: float = 0.0
@export var force_ratio: float = 0.0
@export var unmodified_force_ratio: float = 0.0
@export var defender_terrain_modifier: float = 1.0
@export var attacker_losses: int = 0
@export var defender_losses: int = 0
@export var feba_movement_km: float = 0.0
@export var attacker_casualties: Array = []
@export var defender_casualties: Array = []
@export var combat_detail: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		"attacker_strength": attacker_strength,
		"defender_strength": defender_strength,
		"attacker_maneuver_strength": attacker_maneuver_strength,
		"defender_maneuver_strength": defender_maneuver_strength,
		"force_ratio": force_ratio,
		"unmodified_force_ratio": unmodified_force_ratio,
		"defender_terrain_modifier": defender_terrain_modifier,
		"attacker_losses": attacker_losses,
		"defender_losses": defender_losses,
		"feba_movement_km": feba_movement_km,
		"attacker_casualties": attacker_casualties,
		"defender_casualties": defender_casualties,
		"combat_detail": combat_detail
	}
