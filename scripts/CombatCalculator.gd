extends RefCounted
class_name CombatCalculator

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
	feba_base_km: float,
	attacker_support: Dictionary = {},
	defender_support: Dictionary = {},
	defender_terrain_modifier: float = 1.0,
) -> CombatResult:
	attacker_support = normalize_support(attacker_support)
	defender_support = normalize_support(defender_support)
	defender_terrain_modifier = max(1.0, defender_terrain_modifier)

	var forces := _force_strengths(
		attacker_units, defender_units, attacker_support, defender_support, defender_terrain_modifier)
	var ratio := float(forces["ratio"])

	# Draw order is part of the golden contract: attacker loss, defender loss, feba, then the
	# two casualty selections.
	var attacker_loss_roll := dice.roll_d100()
	var defender_loss_roll := dice.roll_d100()
	var feba_roll := dice.roll_d100()

	var losses := _loss_counts(
		ratio, attacker_units.size(), defender_units.size(), attacker_loss_roll, defender_loss_roll)
	var attacker_casualties := _select_casualties(attacker_units, int(losses["attacker"]), dice)
	var defender_casualties := _select_casualties(defender_units, int(losses["defender"]), dice)

	var feba := _feba_shift(
		float(forces["attacker_strength"]), float(forces["defender_strength"]), feba_base_km, feba_roll)

	var result := CombatResult.new()
	result.attacker_strength = forces["attacker_strength"]
	result.defender_strength = forces["defender_strength"]
	result.attacker_maneuver_strength = forces["attacker_maneuver"]
	result.defender_maneuver_strength = forces["defender_maneuver"]
	result.force_ratio = ratio
	result.unmodified_force_ratio = forces["unmodified_ratio"]
	result.defender_terrain_modifier = defender_terrain_modifier
	result.attacker_losses = attacker_casualties.size()
	result.defender_losses = defender_casualties.size()
	result.feba_movement_km = feba["movement_km"]
	result.attacker_casualties = attacker_casualties
	result.defender_casualties = defender_casualties
	result.combat_detail = {
		"attacker": {
			"maneuver_unit_count": attacker_units.size(),
			"maneuver_combat_power": forces["attacker_maneuver"],
			"support_counts": attacker_support,
			"support_combat_power": forces["attacker_support_strength"],
			"total_combat_power_unmodified": forces["attacker_unmodified"],
			"support_breakdown": _support_power_breakdown(attacker_support)
		},
		"defender": {
			"maneuver_unit_count": defender_units.size(),
			"maneuver_combat_power": forces["defender_maneuver"],
			"support_counts": defender_support,
			"support_combat_power": forces["defender_support_strength"],
			"total_combat_power_unmodified": forces["defender_unmodified"],
			"terrain_modifier": defender_terrain_modifier,
			"total_combat_power_terrain_modified": forces["defender_strength"],
			"support_breakdown": _support_power_breakdown(defender_support)
		},
		"ratios": {
			"unmodified": forces["unmodified_ratio"],
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
			"attacker_loss_rate": losses["attacker_rate"],
			"defender_loss_rate": losses["defender_rate"]
		},
		"feba": {
			"base_km": feba_base_km,
			"roll_factor": feba["roll_factor"],
			"movement_km": feba["movement_km"]
		},
		"result": _result_label(ratio)
	}
	return result


## Aggregate maneuver + support power on both sides, apply the defender's terrain modifier, and
## floor degenerate zero strengths so the ratios stay finite.
static func _force_strengths(
	attacker_units: Array,
	defender_units: Array,
	attacker_support: Dictionary,
	defender_support: Dictionary,
	defender_terrain_modifier: float,
) -> Dictionary:
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

	return {
		"attacker_maneuver": attacker_maneuver,
		"defender_maneuver": defender_maneuver,
		"attacker_support_strength": attacker_support_strength,
		"defender_support_strength": defender_support_strength,
		"attacker_unmodified": attacker_unmodified,
		"defender_unmodified": defender_unmodified,
		"attacker_strength": attacker_strength,
		"defender_strength": defender_strength,
		"unmodified_ratio": attacker_unmodified / defender_unmodified,
		"ratio": attacker_strength / defender_strength,
	}


## Loss rates from the force ratio + rolls, unit counts applied, with the minimum-blood rule:
## a fought battle with units on both sides never ends 0-0.
static func _loss_counts(
	ratio: float,
	attacker_count: int,
	defender_count: int,
	attacker_loss_roll: int,
	defender_loss_roll: int,
) -> Dictionary:
	var attacker_loss_rate := clampf(
		0.20 - (ratio - 1.0) * 0.08 + (attacker_loss_roll - 50) / 1000.0,
		0.05, 0.45
	)
	var defender_loss_rate := clampf(
		0.20 + (ratio - 1.0) * 0.10 + (defender_loss_roll - 50) / 1000.0,
		0.05, 0.50
	)

	var attacker_losses := int(round(attacker_count * attacker_loss_rate))
	var defender_losses := int(round(defender_count * defender_loss_rate))

	if attacker_count > 0 and defender_count > 0:
		if attacker_losses == 0 and defender_losses == 0:
			if ratio >= 1.0:
				defender_losses = 1
			else:
				attacker_losses = 1

	return {
		"attacker": attacker_losses,
		"defender": defender_losses,
		"attacker_rate": attacker_loss_rate,
		"defender_rate": defender_loss_rate,
	}


## FEBA movement from the strength balance, scaled by the roll factor.
static func _feba_shift(attacker_strength: float, defender_strength: float, feba_base_km: float, feba_roll: int) -> Dictionary:
	var denominator: float = max(attacker_strength + defender_strength, 0.1)
	var balance: float = (attacker_strength - defender_strength) / denominator
	var feba_roll_factor := 0.75 + (feba_roll / 100.0) * 0.5
	return {
		"roll_factor": feba_roll_factor,
		"movement_km": feba_base_km * clampf(balance * 2.0, -2.0, 2.0) * feba_roll_factor,
	}


static func _result_label(ratio: float) -> String:
	if ratio >= 1.2:
		return "Attacker Advantage"
	if ratio <= 0.85:
		return "Defender Advantage"
	return "Contested"


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
