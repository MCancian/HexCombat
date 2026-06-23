extends Node
class_name BOOTSCalculator

# Unit combat strength values (mapped from Python config)
var unit_combat_strength: Dictionary = {
	"Light": 1.0,
	"Light Infantry": 1.0,
	"Medium": 1.5,
	"Heavy": 2.0,
	"Mechanized": 1.5,
	"Mechanized Infantry": 1.5,
	"Armor": 2.0,
	"Tank": 2.0,
	"Amphib": 1.2,
	"Amphibious": 1.2,
	"SOF": 1.8,
	"Recon": 0.7,
	"Towed": 0.8,
	"Towed Artillery": 0.8,
	"SP": 1.3,
	"SP Artillery": 1.3,
	"Mechanized Artillery": 1.3,
	"C2": 0.5,
	"HQ": 0.5,
	"SHORAD": 0.9,
	"Air Defense": 0.9,
	"Cargo": 0.3,
	"Support": 0.3,
	"Engineer": 1.1,
	"Airborne": 1.3,
	"Air Assault": 1.4,
	"Rotary Wing": 0.5,
	"Helicopter": 0.5,
	"DOS": 0.2,
	"Logistics": 0.2
}

# Terrain modifiers (from PRD)
var terrain_modifiers: Dictionary = {
	"Clear": 1.0,
	"Suburban": 2.0,
	"Hilly": 2.0,
	"Forest": 2.0,
	"Beach Landing": 3.0,
	"Urban": 3.0,
	"Mountainous": 3.0
}

# Support power multipliers (from PRD)
var support_multipliers: Dictionary = {
	"artillery": 0.8,
	"rocket_artillery": 1.2,
	"cas": 1.4,
	"crbm": 0.6,
	"rotary_wing": 1.3
}


func resolve_map_attack(
	attacker_units: Array,
	defender_units: Array,
	attacker_support: Dictionary = {},
	defender_support: Dictionary = {},
	defender_terrain_modifier: float = 1.0,
	feba_base_km: float = 2.0
) -> Dictionary:
	"""
	Resolve map-based attack and return losses, FEBA movement, and casualties.

	Args:
		attacker_units: Array of unit dicts {type, supply_effectiveness, ...}
		defender_units: Array of unit dicts {type, supply_effectiveness, ...}
		attacker_support: {artillery, rocket_artillery, cas, crbm, rotary_wing}
		defender_support: {artillery, rocket_artillery, cas, crbm, rotary_wing}
		defender_terrain_modifier: Terrain multiplier (e.g. 2.0 for Forest)
		feba_base_km: Base FEBA movement (typically 2.0 km)

	Returns:
		Dictionary with combat results
	"""

	attacker_support = _normalize_support(attacker_support)
	defender_support = _normalize_support(defender_support)
	defender_terrain_modifier = max(1.0, defender_terrain_modifier)

	# Calculate maneuver strength
	var attacker_maneuver = _sum_unit_strength(attacker_units)
	var defender_maneuver = _sum_unit_strength(defender_units)

	# Calculate support strength
	var attacker_support_strength = _support_strength(attacker_support)
	var defender_support_strength = _support_strength(defender_support)

	# Total unmodified and terrain-modified strengths
	var attacker_unmodified = attacker_maneuver + attacker_support_strength
	var defender_unmodified = defender_maneuver + defender_support_strength
	var attacker_strength = attacker_unmodified
	var defender_strength = defender_unmodified * defender_terrain_modifier

	# Avoid division by zero
	if attacker_strength <= 0.0:
		attacker_strength = 0.1
	if defender_strength <= 0.0:
		defender_strength = 0.1
	if defender_unmodified <= 0.0:
		defender_unmodified = 0.1

	var unmodified_ratio = attacker_unmodified / defender_unmodified
	var ratio = attacker_strength / defender_strength

	# Rolls (1d100)
	var attacker_loss_roll = randi() % 100 + 1
	var defender_loss_roll = randi() % 100 + 1
	var feba_roll = randi() % 100 + 1

	# Loss rates (from PRD combat resolution formulas)
	var attacker_loss_rate = _clamp(
		0.20 - (ratio - 1.0) * 0.08 + (attacker_loss_roll - 50) / 1000.0,
		0.05, 0.45
	)
	var defender_loss_rate = _clamp(
		0.20 + (ratio - 1.0) * 0.10 + (defender_loss_roll - 50) / 1000.0,
		0.05, 0.50
	)

	# Calculate losses (in unit count)
	var attacker_losses = int(round(attacker_units.size() * attacker_loss_rate))
	var defender_losses = int(round(defender_units.size() * defender_loss_rate))

	# Ensure at least one loss if both sides present
	if attacker_units.size() > 0 and defender_units.size() > 0:
		if attacker_losses == 0 and defender_losses == 0:
			if ratio >= 1.0:
				defender_losses = 1
			else:
				attacker_losses = 1

	# Select which units are casualties (non-artillery preferred)
	var attacker_casualties = _select_casualties(attacker_units, attacker_losses)
	var defender_casualties = _select_casualties(defender_units, defender_losses)

	# FEBA movement calculation (from PRD)
	var denominator = max(attacker_strength + defender_strength, 0.1)
	var balance = (attacker_strength - defender_strength) / denominator
	var feba_roll_factor = 0.75 + (feba_roll / 100.0) * 0.5
	var feba_shift_km = feba_base_km * _clamp(balance * 2.0, -2.0, 2.0) * feba_roll_factor

	# Determine result label
	var result_label = "Contested"
	if ratio >= 1.2:
		result_label = "Attacker Advantage"
	elif ratio <= 0.85:
		result_label = "Defender Advantage"

	# Build support breakdown
	var attacker_support_breakdown = _support_power_breakdown(attacker_support)
	var defender_support_breakdown = _support_power_breakdown(defender_support)

	# Assemble result dictionary
	var result = {
		"attacker_strength": attacker_strength,
		"defender_strength": defender_strength,
		"attacker_maneuver_strength": attacker_maneuver,
		"defender_maneuver_strength": defender_maneuver,
		"force_ratio": ratio,
		"unmodified_force_ratio": unmodified_ratio,
		"defender_terrain_modifier": defender_terrain_modifier,
		"attacker_losses": attacker_casualties.size(),
		"defender_losses": defender_casualties.size(),
		"feba_movement_km": feba_shift_km,
		"attacker_casualties": attacker_casualties,
		"defender_casualties": defender_casualties,
		"combat_detail": {
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
				"feba_roll": feba_roll
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
	}

	return result


# ===== Helper Methods =====

func _normalize_support(raw_support: Dictionary) -> Dictionary:
	"""Ensure support dict has all keys with valid (non-negative) int values."""
	return {
		"artillery": max(0, int(raw_support.get("artillery", 0) or 0)),
		"rocket_artillery": max(0, int(raw_support.get("rocket_artillery", 0) or 0)),
		"cas": max(0, int(raw_support.get("cas", 0) or 0)),
		"crbm": max(0, int(raw_support.get("crbm", 0) or 0)),
		"rotary_wing": max(0, int(raw_support.get("rotary_wing", 0) or 0))
	}


func _sum_unit_strength(units: Array) -> float:
	"""Sum combat strength of all units, accounting for supply effectiveness."""
	var total = 0.0
	for unit in units:
		var unit_type = unit.get("type", "Light")
		var strength = unit_combat_strength.get(unit_type, 1.0)
		var supply_eff = float(unit.get("supply_effectiveness", 1.0))
		total += strength * supply_eff
	return total


func _support_strength(support_counts: Dictionary) -> float:
	"""Calculate total combat power from support assets."""
	var total = 0.0
	for support_type in support_counts:
		var count = support_counts[support_type]
		var multiplier = support_multipliers.get(support_type, 0.0)
		total += count * multiplier
	return total


func _support_power_breakdown(support_counts: Dictionary) -> Dictionary:
	"""Break down support power by type."""
	var breakdown = {}
	for support_type in support_counts:
		var count = support_counts[support_type]
		var multiplier = support_multipliers.get(support_type, 0.0)
		breakdown[support_type] = count * multiplier
	return breakdown


func _select_casualties(units: Array, loss_count: int) -> Array:
	"""Select which units are casualties (prefer non-artillery)."""
	if loss_count <= 0:
		return []

	var non_artillery = []
	var artillery = []

	for unit in units:
		var unit_type = unit.get("type", "")
		if "artillery" in unit_type.to_lower() or "rocket" in unit_type.to_lower():
			artillery.append(unit)
		else:
			non_artillery.append(unit)

	# Prefer non-artillery casualties
	var casualties = []
	var remaining_loss = loss_count

	# First, take from non-artillery
	for i in range(min(remaining_loss, non_artillery.size())):
		casualties.append(non_artillery[i])
	remaining_loss -= casualties.size()

	# Then, take from artillery
	for i in range(min(remaining_loss, artillery.size())):
		casualties.append(artillery[i])

	return casualties


func _clamp(value: float, min_val: float, max_val: float) -> float:
	"""Clamp value between min and max."""
	return max(min_val, min(value, max_val))
