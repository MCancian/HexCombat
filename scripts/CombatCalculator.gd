extends RefCounted
class_name CombatCalculator

static func resolve_map_attack(
	dice: Dice,
	attacker_units: Array,
	defender_units: Array,
	attacker_support_counts: Dictionary,
	defender_support_counts: Dictionary,
	attacker_support_units: Array,
	defender_support_units: Array,
	rules: CombatRules
) -> CombatResult:
	var attacker_support = normalize_support(attacker_support_counts)
	var defender_support = normalize_support(defender_support_counts)
	var defender_terrain_modifier = max(1.0, rules.defender_terrain_modifier)

	var forces := _force_strengths(
		attacker_units, defender_units, attacker_support, defender_support, defender_terrain_modifier, attacker_support_units, defender_support_units, rules)
	var ratio := float(forces["ratio"])

	# Draw order is part of the golden contract: attacker loss, defender loss, feba, then the
	# two casualty selections.
	var attacker_loss_roll := dice.roll_d100()
	var defender_loss_roll := dice.roll_d100()
	var feba_roll := dice.roll_d100()

	var losses := _loss_counts(
		ratio, attacker_units.size() + attacker_support_units.size(), defender_units.size() + defender_support_units.size(), attacker_loss_roll, defender_loss_roll, rules)
	var attacker_casualties := _select_casualties(attacker_units, attacker_support_units, int(losses["attacker"]), dice, rules.maneuver_casualty_weight, rules.support_casualty_weight)
	var defender_casualties := _select_casualties(defender_units, defender_support_units, int(losses["defender"]), dice, rules.maneuver_casualty_weight, rules.support_casualty_weight)

	var feba := _feba_shift(
		float(forces["attacker_strength"]), float(forces["defender_strength"]), rules.feba_base_km, feba_roll, rules)

	var result := CombatResult.new()
	result.attacker_strength = forces["attacker_strength"]
	result.defender_strength = forces["defender_strength"]
	result.attacker_maneuver_strength = forces["attacker_maneuver"]
	result.defender_maneuver_strength = forces["defender_maneuver"]
	result.force_ratio = ratio
	result.unmodified_force_ratio = forces["unmodified_ratio"]
	result.defender_terrain_modifier = rules.defender_terrain_modifier
	result.attacker_losses = attacker_casualties.size()
	result.defender_losses = defender_casualties.size()
	result.feba_movement_km = feba["movement_km"]
	result.attacker_casualties = attacker_casualties
	result.defender_casualties = defender_casualties
	result.combat_detail = {
		"attacker": {
			"maneuver_unit_count": attacker_units.size(),
			"support_unit_count": attacker_support_units.size(),
			"unscreened": forces["attacker_unscreened"],
			"maneuver_combat_power": forces["attacker_maneuver"],
			"support_counts": attacker_support,
			"support_combat_power": forces["attacker_support_strength"],
			"total_combat_power_unmodified": forces["attacker_unmodified"],
			"support_breakdown": _support_power_breakdown(attacker_support, rules)
		},
		"defender": {
			"maneuver_unit_count": defender_units.size(),
			"support_unit_count": defender_support_units.size(),
			"unscreened": forces["defender_unscreened"],
			"maneuver_combat_power": forces["defender_maneuver"],
			"support_counts": defender_support,
			"support_combat_power": forces["defender_support_strength"],
			"total_combat_power_unmodified": forces["defender_unmodified"],
			"terrain_modifier": defender_terrain_modifier,
			"total_combat_power_terrain_modified": forces["defender_strength"],
			"support_breakdown": _support_power_breakdown(defender_support, rules)
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
			"base_km": rules.feba_base_km,
			"roll_factor": feba["roll_factor"],
			"movement_km": feba["movement_km"]
		},
		"result": _result_label(ratio, rules)
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
	attacker_support_units: Array,
	defender_support_units: Array,
	rules: CombatRules
) -> Dictionary:
	var attacker_maneuver := _sum_unit_strength(attacker_units, rules)
	var defender_maneuver := _sum_unit_strength(defender_units, rules)
	
	var attacker_unscreened := false
	var attacker_support_strength := 0.0
	if attacker_units.is_empty() and not attacker_support_units.is_empty():
		attacker_unscreened = true
		attacker_support_strength = _sum_unscreened_strength(attacker_support_units, rules.unscreened_support_strength)
		var off_map := attacker_support.duplicate()
		off_map["artillery"] = 0
		off_map["rocket_artillery"] = 0
		off_map["rotary_wing"] = 0
		attacker_support_strength += _support_strength(off_map, rules)
	else:
		attacker_support_strength = _support_strength(attacker_support, rules)

	var defender_unscreened := false
	var defender_support_strength := 0.0
	if defender_units.is_empty() and not defender_support_units.is_empty():
		defender_unscreened = true
		defender_support_strength = _sum_unscreened_strength(defender_support_units, rules.unscreened_support_strength)
		var off_map := defender_support.duplicate()
		off_map["artillery"] = 0
		off_map["rocket_artillery"] = 0
		off_map["rotary_wing"] = 0
		defender_support_strength += _support_strength(off_map, rules)
	else:
		defender_support_strength = _support_strength(defender_support, rules)

	var attacker_unmodified := attacker_maneuver + attacker_support_strength
	var defender_unmodified := defender_maneuver + defender_support_strength
	var attacker_strength := attacker_unmodified
	var defender_strength := defender_unmodified * defender_terrain_modifier

	if attacker_strength <= 0.0:
		attacker_strength = rules.combat_min_effective_strength
	if defender_strength <= 0.0:
		defender_strength = rules.combat_min_effective_strength
	if defender_unmodified <= 0.0:
		defender_unmodified = rules.combat_min_effective_strength

	return {
		"attacker_maneuver": attacker_maneuver,
		"defender_maneuver": defender_maneuver,
		"attacker_support_strength": attacker_support_strength,
		"defender_support_strength": defender_support_strength,
		"attacker_unscreened": attacker_unscreened,
		"defender_unscreened": defender_unscreened,
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
	defender_loss_roll: int, rules: CombatRules
) -> Dictionary:
	var attacker_loss_rate := clampf(
		rules.combat_base_loss_rate - (ratio - 1.0) * rules.combat_attacker_ratio_slope + (attacker_loss_roll - rules.combat_loss_roll_midpoint) / rules.combat_loss_roll_scale,
		rules.combat_min_loss_rate, rules.combat_max_attacker_loss_rate
	)
	var defender_loss_rate := clampf(
		rules.combat_base_loss_rate + (ratio - 1.0) * rules.combat_defender_ratio_slope + (defender_loss_roll - rules.combat_loss_roll_midpoint) / rules.combat_loss_roll_scale,
		rules.combat_min_loss_rate, rules.combat_max_defender_loss_rate
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
static func _feba_shift(attacker_strength: float, defender_strength: float, feba_base_km: float, feba_roll: int, rules: CombatRules) -> Dictionary:
	var denominator: float = max(attacker_strength + defender_strength, rules.combat_min_effective_strength)
	var balance: float = (attacker_strength - defender_strength) / denominator
	var feba_roll_factor := rules.feba_roll_factor_min + (feba_roll / 100.0) * rules.feba_roll_factor_span
	return {
		"roll_factor": feba_roll_factor,
		"movement_km": feba_base_km * clampf(balance * rules.feba_balance_gain, -rules.feba_balance_clamp, rules.feba_balance_clamp) * feba_roll_factor,
	}


static func _result_label(ratio: float, rules: CombatRules) -> String:
	if ratio >= rules.combat_attacker_advantage_ratio:
		return "Attacker Advantage"
	if ratio <= rules.combat_defender_advantage_ratio:
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


static func _sum_unit_strength(units: Array, rules: CombatRules) -> float:
	var total := 0.0
	for unit in units:
		var unit_type := _unit_type(unit)
		var strength := UnitStats.strength_for_type(unit_type, rules.default_combat_strength)
		var supply_eff := _unit_supply_effectiveness(unit)
		total += strength * supply_eff
	return total


static func _sum_unscreened_strength(units: Array, unscreened_support_strength: float) -> float:
	var total := 0.0
	for unit in units:
		total += unscreened_support_strength * _unit_supply_effectiveness(unit)
	return total


static func _support_strength(support_counts: Dictionary, rules: CombatRules) -> float:
	var total := 0.0
	for support_type in support_counts:
		var count = support_counts[support_type]
		var multiplier := float(rules.support_multipliers.get(support_type, 0.0))
		total += count * multiplier
	return total


static func _support_power_breakdown(support_counts: Dictionary, rules: CombatRules) -> Dictionary:
	var breakdown := {}
	for support_type in support_counts:
		var count = support_counts[support_type]
		var multiplier := float(rules.support_multipliers.get(support_type, 0.0))
		breakdown[support_type] = count * multiplier
	return breakdown


static func _select_casualties(maneuver_units: Array, support_units: Array, loss_count: int, dice: Dice, maneuver_casualty_weight: float, support_casualty_weight: float) -> Array:
	var pool := maneuver_units + support_units
	if loss_count <= 0 or pool.is_empty():
		return []

	var select_count: int = min(loss_count, pool.size())
	var weights: Array[float] = []
	for i in range(maneuver_units.size()):
		weights.append(maneuver_casualty_weight)
	for i in range(support_units.size()):
		weights.append(support_casualty_weight)

	var casualties := []
	for _i in range(select_count):
		var index := dice.weighted_choice(weights)
		casualties.append(pool[index])
		weights[index] = 0.0
		
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
