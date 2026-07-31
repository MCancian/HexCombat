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

## No serialization seam here on purpose (plan 0050). A `to_dictionary()` used to sit at this spot with
## zero callers — the only type in the repo whose serializer was not named `to_dict`, so it was invisible
## to anything looking for the convention. What actually reaches a record is `CombatSummary.to_dict()`;
## this type is the calculator's internal result and never leaves the turn.
