extends RefCounted
class_name BOOTSCalculator


func resolve_map_attack(
	dice: Dice,
	attacker_units: Array,
	defender_units: Array,
	attacker_support: Dictionary = {},
	defender_support: Dictionary = {},
	defender_terrain_modifier: float = 1.0,
	feba_base_km: float = 2.0
) -> CombatResult:
	return CombatCalculator.resolve_map_attack(
		dice,
		attacker_units,
		defender_units,
		attacker_support,
		defender_support,
		defender_terrain_modifier,
		feba_base_km
	)
