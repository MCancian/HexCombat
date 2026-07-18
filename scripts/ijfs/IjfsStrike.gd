class_name IjfsStrike
extends RefCounted

const VALID_MATCH_KEYS := {
	"category": true,
	"subcategory": true,
	"mobility": true,
	"hardness": true,
	"posture": true,
	"intel_locked": true,
	"munition_id": true,
	"munition_category": true,
	"phase": true,
	"pairing_id": true,
	"source_target_id": true,
}
const VALID_OPERATIONS := {"add": true, "multiply": true}


static func modifier_matches(modifier: Dictionary, context: Dictionary) -> bool:
	var match_value: Variant = modifier.get("match", {})
	if not (match_value is Dictionary):
		return false
	var match: Dictionary = match_value
	for key in match.keys():
		if not VALID_MATCH_KEYS.has(key):
			return false
		if not _match_value(match[key], context.get(key)):
			return false
	return true


static func probability_context(target: IjfsTarget, pairing: IjfsPairing, munition: IjfsMunition, phase: Variant = null) -> Dictionary:
	return {
		"category": target.category,
		"subcategory": target.subcategory,
		"mobility": target.mobility,
		"hardness": target.hardness,
		"posture": target.posture,
		"intel_locked": bool(target.intel_locked),
		"munition_id": munition.munition_id,
		"munition_category": munition.category,
		"phase": phase,
		"pairing_id": pairing.pairing_id,
		"source_target_id": target.source_target_id,
	}


static func evaluate_strike_probability(target: IjfsTarget, pairing: IjfsPairing, munition: IjfsMunition, scenario: Dictionary, phase: Variant = null) -> Dictionary:
	var base := float(pairing.probability_destroyed)
	var modifiers_value: Variant = scenario.get("strike_probability_modifiers")
	var modifiers: Array = [] if modifiers_value == null else modifiers_value
	if modifiers.is_empty():
		return {
			"base": _clamp01(base),
			"final": _clamp01(base),
			"modifier_add_sum": 0.0,
			"modifier_mult_product": 1.0,
			"modifiers": [],
			"formula": "base_only",
		}

	var context := probability_context(target, pairing, munition, phase)
	var add_sum := 0.0
	var mult_product := 1.0
	var applied: Array[Dictionary] = []
	for raw_value in modifiers:
		var raw: Dictionary = raw_value
		if not modifier_matches(raw, context):
			continue
		var operation := String(raw.get("operation", "")).to_lower()
		if not VALID_OPERATIONS.has(operation):
			continue
		var value := float(raw.get("value", 0.0))
		if operation == "add":
			add_sum += value
		else:
			mult_product *= value
		applied.append({
			"modifier_id": raw.get("modifier_id") if raw.get("modifier_id") else "unnamed_modifier",
			"operation": operation,
			"value": value,
			"notes": raw.get("notes"),
		})

	var final := _clamp01((base + add_sum) * mult_product)
	return {
		"base": _clamp01(base),
		"final": final,
		"modifier_add_sum": add_sum,
		"modifier_mult_product": mult_product,
		"modifiers": applied,
		"formula": "base_plus_adds_times_mults",
	}


static func resolve_strike(
	target: IjfsTarget,
	pairing: IjfsPairing,
	inventory: Dictionary,
	scenario: Dictionary,
	current_day: int,
	dice: Dice,
	phase: Variant = null,
	doctrine_rule_name: Variant = null,
	doctrine_selection: Variant = null
) -> Dictionary:
	var munition: IjfsMunition = inventory[pairing.munition_id]
	var rounds := int(pairing.rounds_expended_per_engagement)
	var organic := munition.category == "Organic"
	if not organic and munition.inventory_remaining < rounds:
		return {
			"current_day": current_day,
			"target_id": target.target_id,
			"source_target_id": target.source_target_id,
			"metadata": target.metadata,
			"attack_executed": false,
			"skip_reason": "insufficient_inventory",
			"phase": phase,
			"doctrine_rule_name": doctrine_rule_name,
			"doctrine_selection": doctrine_selection,
		}
	if not organic:
		munition.inventory_remaining -= rounds

	var probability := evaluate_strike_probability(target, pairing, munition, scenario, phase)
	var p_destroy := float(probability["final"])
	var roll := dice.randf()
	var destroyed := roll <= p_destroy
	var p_suppressed := float(pairing.probability_suppressed_if_not_destroyed)
	var suppression_roll: Variant = null
	var suppressed := false
	if destroyed:
		target.destroyed = true
		target.known_to_red = false
		target.suppressed = false
		target.suppressed_this_turn = false
	elif p_suppressed > 0.0:
		suppression_roll = dice.randf()
		suppressed = float(suppression_roll) <= p_suppressed
		if suppressed:
			target.suppressed = true
			target.suppressed_this_turn = true

	return {
		"current_day": current_day,
		"target_id": target.target_id,
		"source_target_id": target.source_target_id,
		"category": target.category,
		"subcategory": target.subcategory,
		"mobility": target.mobility,
		"posture": target.posture,
		"metadata": target.metadata,
		"phase": phase,
		"doctrine_rule_name": doctrine_rule_name,
		"doctrine_selection": doctrine_selection,
		"attack_executed": true,
		"skip_reason": null,
		"pairing_id": pairing.pairing_id,
		"munition_id": munition.munition_id,
		"rounds_expended": rounds,
		"probability_destroyed_base": probability["base"],
		"probability_destroyed_add_sum": probability.get("modifier_add_sum", 0.0),
		"probability_destroyed_multiplier_product": probability.get("modifier_mult_product", 1.0),
		"probability_destroyed_modifiers": probability.get("modifiers", []),
		"probability_destroyed_formula": probability.get("formula"),
		"probability_destroyed": p_destroy,
		"roll": roll,
		"destroyed": destroyed,
		"probability_suppressed_if_not_destroyed": p_suppressed,
		"suppression_roll": suppression_roll,
		"suppressed": suppressed,
	}


static func _wildcard(value: Variant) -> bool:
	if value == null:
		return true
	if value is String:
		return value == "" or value == "*"
	return false


static func _match_value(rule_value: Variant, actual: Variant) -> bool:
	if rule_value is Array:
		for item in rule_value:
			if _match_value(item, actual):
				return true
		return false
	if _wildcard(rule_value):
		return true
	if rule_value is bool:
		return bool(actual) == rule_value
	return rule_value == actual


static func _clamp01(value: float) -> float:
	return clampf(value, 0.0, 1.0)
