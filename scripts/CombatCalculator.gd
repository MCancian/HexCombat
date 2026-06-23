extends RefCounted
class_name CombatCalculator

const TERRAIN_MODIFIERS = {
	"Clear": 1.0,
	"Suburban": 2.0,
	"Hilly": 2.0,
	"Forest": 2.0,
	"Beach Landing": 3.0,
	"Urban": 3.0,
	"Mountainous": 3.0
}

const SUPPORT_MULTIPLIERS = {
	"artillery": 0.8,
	"rocket_artillery": 1.2,
	"cas": 1.4,
	"crbm": 0.6,
	"rotary_wing": 1.3
}


static func resolve_map_attack(
	dice: Dice,
	attacker_units: Array,
	defender_units: Array,
	attacker_support: Dictionary = {},
	defender_support: Dictionary = {},
	defender_terrain_modifier: float = 1.0,
	feba_base_km: float = 2.0
) -> CombatResult:
	attacker_support = normalize_support(attacker_support)
	defender_support = normalize_support(defender_support)
	defender_terrain_modifier = max(1.0, defender_terrain_modifier)

	var attacker_maneuver := _sum_unit_strength(attacker_units)
	var defender_maneuver := _sum_unit_strength(defender_units)
	var attacker_support_strength := _support_strength(attacker_support)
	var defender_support_strength := _support_strength(defender_support)

	var attacker_unmodified := attacker_maneuver + attacker_support_strength
	var defender_unmodified := defender_maneuver + defender_support_strength
	var attacker_strength := attacker_unmodified
	var defender_strength := defender_unmodified * defender_terrain_modifier

	if attacker_strength <= 0.0:
		attacker_strength = 0.1
	if defender_strength <= 0.0:
		defender_strength = 0.1
	if defender_unmodified <= 0.0:
		defender_unmodified = 0.1

	var unmodified_ratio := attacker_unmodified / defender_unmodified
	var ratio := attacker_strength / defender_strength

	var attacker_loss_roll := dice.roll_d100()
	var defender_loss_roll := dice.roll_d100()
	var feba_roll := dice.roll_d100()

	var attacker_loss_rate := clampf(
		0.20 - (ratio - 1.0) * 0.08 + (attacker_loss_roll - 50) / 1000.0,
		0.05, 0.45
	)
	var defender_loss_rate := clampf(
		0.20 + (ratio - 1.0) * 0.10 + (defender_loss_roll - 50) / 1000.0,
		0.05, 0.50
	)

	var attacker_losses := int(round(attacker_units.size() * attacker_loss_rate))
	var defender_losses := int(round(defender_units.size() * defender_loss_rate))

	if attacker_units.size() > 0 and defender_units.size() > 0:
		if attacker_losses == 0 and defender_losses == 0:
			if ratio >= 1.0:
				defender_losses = 1
			else:
				attacker_losses = 1

	var attacker_casualties := _select_casualties(attacker_units, attacker_losses, dice)
	var defender_casualties := _select_casualties(defender_units, defender_losses, dice)

	var denominator: float = max(attacker_strength + defender_strength, 0.1)
	var balance: float = (attacker_strength - defender_strength) / denominator
	var feba_roll_factor := 0.75 + (feba_roll / 100.0) * 0.5
	var feba_shift_km := feba_base_km * clampf(balance * 2.0, -2.0, 2.0) * feba_roll_factor

	var result_label := "Contested"
	if ratio >= 1.2:
		result_label = "Attacker Advantage"
	elif ratio <= 0.85:
		result_label = "Defender Advantage"

	var attacker_support_breakdown := _support_power_breakdown(attacker_support)
	var defender_support_breakdown := _support_power_breakdown(defender_support)

	var result := CombatResult.new()
	result.attacker_strength = attacker_strength
	result.defender_strength = defender_strength
	result.attacker_maneuver_strength = attacker_maneuver
	result.defender_maneuver_strength = defender_maneuver
	result.force_ratio = ratio
	result.unmodified_force_ratio = unmodified_ratio
	result.defender_terrain_modifier = defender_terrain_modifier
	result.attacker_losses = attacker_casualties.size()
	result.defender_losses = defender_casualties.size()
	result.feba_movement_km = feba_shift_km
	result.attacker_casualties = attacker_casualties
	result.defender_casualties = defender_casualties
	result.combat_detail = {
		"attacker": {
			"maneuver_unit_count": attacker_units.size(),
			"maneuver_combat_power": attacker_maneuver,
			"support_counts": attacker_support,
			"support_combat_power": attacker_support_strength,
			"total_combat_power_unmodified": attacker_unmodified,
			"support_breakdown": attacker_support_breakdown
		},
		"defender": {
			"maneuver_unit_count": defender_units.size(),
			"maneuver_combat_power": defender_maneuver,
			"support_counts": defender_support,
			"support_combat_power": defender_support_strength,
			"total_combat_power_unmodified": defender_unmodified,
			"terrain_modifier": defender_terrain_modifier,
			"total_combat_power_terrain_modified": defender_strength,
			"support_breakdown": defender_support_breakdown
		},
		"ratios": {
			"unmodified": unmodified_ratio,
			"terrain_modified": ratio
		},
		"rolls": {
			"attacker_loss_roll": attacker_loss_roll,
			"defender_loss_roll": defender_loss_roll,
			"feba_movement_roll": feba_roll
		},
		"losses": {
			"attacker": attacker_casualties.size(),
			"defender": defender_casualties.size(),
			"attacker_loss_rate": attacker_loss_rate,
			"defender_loss_rate": defender_loss_rate
		},
		"feba": {
			"base_km": feba_base_km,
			"roll_factor": feba_roll_factor,
			"movement_km": feba_shift_km
		},
		"result": result_label
	}
	return result


static func normalize_support(raw_support: Dictionary) -> Dictionary:
	return {
		"artillery": _to_count(raw_support.get("artillery")),
		"rocket_artillery": _to_count(raw_support.get("rocket_artillery")),
		"cas": _to_count(raw_support.get("cas")),
		"crbm": _to_count(raw_support.get("crbm")),
		"rotary_wing": _to_count(raw_support.get("rotary_wing"))
	}


static func _normalize_support(raw_support: Dictionary) -> Dictionary:
	return normalize_support(raw_support)


static func _to_count(value) -> int:
	if value == null:
		return 0
	return max(0, int(value))


static func _sum_unit_strength(units: Array) -> float:
	var total := 0.0
	for unit in units:
		var unit_type := _unit_type(unit)
		var strength := UnitStats.strength_for_type(unit_type)
		var supply_eff := _unit_supply_effectiveness(unit)
		total += strength * supply_eff
	return total


static func _support_strength(support_counts: Dictionary) -> float:
	var total := 0.0
	for support_type in support_counts:
		var count = support_counts[support_type]
		var multiplier := float(SUPPORT_MULTIPLIERS.get(support_type, 0.0))
		total += count * multiplier
	return total


static func _support_power_breakdown(support_counts: Dictionary) -> Dictionary:
	var breakdown := {}
	for support_type in support_counts:
		var count = support_counts[support_type]
		var multiplier := float(SUPPORT_MULTIPLIERS.get(support_type, 0.0))
		breakdown[support_type] = count * multiplier
	return breakdown


static func _select_casualties(units: Array, loss_count: int, dice: Dice) -> Array:
	var eligible := []
	for unit in units:
		var unit_type := _unit_type(unit)
		if not UnitStats.has_tag(unit_type, "artillery"):
			eligible.append(unit)

	if loss_count <= 0 or eligible.is_empty():
		return []

	var select_count: int = min(loss_count, eligible.size())
	var selected_indices := dice.choose_indices(eligible.size(), select_count)
	var casualties := []
	for index in selected_indices:
		casualties.append(eligible[index])
	return casualties


static func _unit_type(unit) -> String:
	if unit is Battalion:
		return unit.type
	if unit is Dictionary:
		return unit.get("type", "Light")
	return "Light"


static func _unit_supply_effectiveness(unit) -> float:
	if unit is Dictionary:
		return float(unit.get("supply_effectiveness", 1.0))
	return 1.0
