class_name IjfsTargeting
extends RefCounted

const IjfsTargetResource = preload("res://scripts/model/ijfs/IjfsTarget.gd")
const IjfsPairingResource = preload("res://scripts/model/ijfs/IjfsPairing.gd")


static func targets_to_attack(targets: Array[IjfsTarget], z_day: Variant = null, release_rules: Variant = null) -> Array[IjfsTarget]:
	var result: Array[IjfsTarget] = []
	for target in targets:
		if not target.destroyed and target.detected_this_turn:
			if z_day != null and release_rules != null and not (release_rules as Array).is_empty():
				if not target_release_eligible(target, int(z_day), release_rules as Array):
					continue
			result.append(target)
	result.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	return result


static func pairing_matches_target(rule: IjfsPairing, target: IjfsTarget) -> bool:
	if rule.source_target_ids.has(target.source_target_id):
		return true
	if rule.target_category != target.category:
		return false
	if not _subcategory_matches(rule.target_subcategory, target.subcategory):
		return false
	if not _wildcard(rule.target_mobility) and rule.target_mobility != target.mobility:
		return false
	if not _wildcard(rule.target_hardness) and rule.target_hardness != target.hardness:
		return false
	return true


static func find_compatible_pairings(target: IjfsTarget, pairings: Array[IjfsPairing]) -> Array[IjfsPairing]:
	var result: Array[IjfsPairing] = []
	for rule in pairings:
		if pairing_matches_target(rule, target):
			result.append(rule)
	return result


static func doctrine_matches_target(doctrine_rule: Dictionary, target: IjfsTarget) -> bool:
	var match: Dictionary = doctrine_rule.get("match", {})
	var checks := {
		"category": target.category,
		"subcategory": target.subcategory,
		"mobility": target.mobility,
		"hardness": target.hardness,
	}
	for key in match.keys():
		if not _match_value(match[key], checks.get(key)):
			return false
	return true


static func match_doctrine_rule(target: IjfsTarget, scenario: Variant) -> Variant:
	if not scenario:
		return null
	var scenario_dict: Dictionary = scenario
	for doctrine_rule_value in scenario_dict.get("targeting_doctrine", []):
		var doctrine_rule: Dictionary = doctrine_rule_value
		if doctrine_matches_target(doctrine_rule, target):
			return doctrine_rule
	return null


static func _rule_affordable(rule: IjfsPairing, inventory: Dictionary, capacity_budget: Variant = null, organic_budget: Variant = null) -> bool:
	var munition: Variant = inventory.get(rule.munition_id)
	if munition == null:
		return false
	if munition.category == "Organic":
		if organic_budget != null and not _has_capacity(organic_budget, rule.munition_id):
			return false
		return true
	if int(munition.inventory_remaining) < rule.rounds_expended_per_engagement:
		return false
	if capacity_budget != null and not _has_capacity(capacity_budget, rule.munition_id):
		return false
	return true


static func _select_from_ordered_pairings(pairings: Array[IjfsPairing], inventory: Dictionary, capacity_budget: Variant = null, organic_budget: Variant = null) -> Dictionary:
	if pairings.is_empty():
		return {"selected": null, "reason": "no_compatible_pairing"}
	var saw_unaffordable := false
	var saw_capacity_block := false
	for rule in pairings:
		var munition: Variant = inventory.get(rule.munition_id)
		if munition == null:
			saw_unaffordable = true
			continue
		if _rule_affordable(rule, inventory, capacity_budget, organic_budget):
			return {"selected": rule, "reason": null}
		if munition.category == "Organic":
			if organic_budget != null and not _has_capacity(organic_budget, rule.munition_id):
				saw_capacity_block = true
				continue
		else:
			if capacity_budget != null and not _has_capacity(capacity_budget, rule.munition_id):
				saw_capacity_block = true
				continue
		saw_unaffordable = true
	if saw_unaffordable:
		return {"selected": null, "reason": "insufficient_inventory"}
	if saw_capacity_block:
		return {"selected": null, "reason": "firing_capacity_exhausted"}
	return {"selected": null, "reason": "no_compatible_pairing"}


static func _filter_by_phase(pairings: Array[IjfsPairing], inventory: Dictionary, phase: Variant) -> Array[IjfsPairing]:
	if phase == null:
		return pairings
	var result: Array[IjfsPairing] = []
	for rule in pairings:
		var munition: Variant = inventory.get(rule.munition_id)
		var category := String(munition.category) if munition != null else ""
		if phase == "pre_ad_recompute":
			if category != "Organic":
				result.append(rule)
			continue
		if phase == "post_ad_recompute":
			result.append(rule)
			continue
		result.append(rule)
	return result


static func select_munition_with_doctrine(
	target: IjfsTarget,
	pairings: Array[IjfsPairing],
	inventory: Dictionary,
	scenario: Variant = null,
	phase: Variant = null,
	munition_filter: Variant = null,
	capacity_budget: Variant = null,
	organic_budget: Variant = null
) -> Dictionary:
	var compatible := _filter_by_phase(find_compatible_pairings(target, pairings), inventory, phase)
	if munition_filter:
		compatible = apply_munition_filter(munition_filter as Dictionary, compatible)
	if compatible.is_empty():
		return {"selected": null, "reason": "no_compatible_pairing", "doctrine_name": null, "selection": null}

	var doctrine_rule: Variant = match_doctrine_rule(target, scenario)
	var doctrine_name: Variant = doctrine_rule.get("name") if doctrine_rule != null else null
	if doctrine_rule != null:
		var priority_pairings: Array[IjfsPairing] = []
		for munition_id in doctrine_rule.get("munition_priority", []):
			for rule in compatible:
				if rule.munition_id == munition_id:
					priority_pairings.append(rule)
		var priority_result := _select_from_ordered_pairings(priority_pairings, inventory, capacity_budget, organic_budget)
		if priority_result["selected"] != null:
			return {"selected": priority_result["selected"], "reason": null, "doctrine_name": doctrine_name, "selection": "priority"}
		var fallback_result := _select_from_ordered_pairings(compatible, inventory, capacity_budget, organic_budget)
		return {"selected": fallback_result["selected"], "reason": fallback_result["reason"], "doctrine_name": doctrine_name, "selection": "fallback"}

	var result := _select_from_ordered_pairings(compatible, inventory, capacity_budget, organic_budget)
	return {"selected": result["selected"], "reason": result["reason"], "doctrine_name": doctrine_name, "selection": null}


static func select_munition(target: IjfsTarget, pairings: Array[IjfsPairing], inventory: Dictionary) -> Dictionary:
	var result := select_munition_with_doctrine(target, pairings, inventory)
	return {"selected": result["selected"], "reason": result["reason"]}


static func _rule_matches_target(match: Dictionary, target: IjfsTarget) -> bool:
	for field in match.keys():
		var rule_value: Variant = match[field]
		var target_value: Variant = target.get(String(field))
		if rule_value == null:
			continue
		if rule_value is Array:
			if not (rule_value as Array).has(target_value):
				return false
		elif target_value != rule_value:
			return false
	return true


static func target_release_eligible(target: IjfsTarget, z_day: int, release_rules: Array) -> bool:
	var matching_days: Array[float] = []
	for rule_value in release_rules:
		var rule: Dictionary = rule_value
		var match: Dictionary = rule.get("match", {})
		if _rule_matches_target(match, target):
			var raw: Variant = rule.get("release_day")
			matching_days.append(-INF if raw == null else float(int(raw)))
	if matching_days.is_empty():
		return true
	var max_day := matching_days[0]
	for day in matching_days:
		max_day = maxf(max_day, day)
	return float(z_day) >= max_day


static func apply_munition_filter(munition_filter: Dictionary, pairings: Array[IjfsPairing]) -> Array[IjfsPairing]:
	var mode: Variant = munition_filter.get("mode")
	var raw_ids: Array = munition_filter.get("ids", [])
	if not mode or raw_ids.is_empty():
		return pairings
	var ids: Dictionary = {}
	for id_value in raw_ids:
		ids[String(id_value)] = true
	var result: Array[IjfsPairing] = []
	if mode == "whitelist":
		for pairing in pairings:
			if ids.has(pairing.munition_id):
				result.append(pairing)
		return result
	if mode == "blacklist":
		for pairing in pairings:
			if not ids.has(pairing.munition_id):
				result.append(pairing)
		return result
	return pairings


static func apply_posture_override(targets: Array[IjfsTarget], posture: Variant) -> void:
	if posture == null:
		return
	for target in targets:
		if not target.destroyed and target.mobility != "static":
			target.posture = String(posture)


static func apply_exquisite_intel(
	targets: Array[IjfsTarget],
	exquisite_intel: Dictionary,
	x_day: int,
	dice: Dice,
	config_key: String,
	target_category: Variant = null
) -> Array[String]:
	var normalized_key := config_key.to_lower().replace(" ", "_")
	var cfg: Dictionary = exquisite_intel.get(normalized_key, exquisite_intel.get(config_key, {}))
	if cfg.is_empty():
		return []
	var match_category := String(target_category) if target_category != null else config_key
	var initial := int(cfg.get("initial_count", 0))
	var decay_cfg: Dictionary = cfg.get("decay", {})
	var synthetic := {"initial_capability": 1.0, "floor": 0.0, "degradation": decay_cfg}
	var fraction := IjfsDetection.evaluate_isr_source(synthetic, x_day)
	var count := int(floor(float(initial) * fraction))
	var candidates: Array[IjfsTarget] = []
	for target in targets:
		if target.category == match_category and not target.destroyed and target.mobility != "static":
			if match_category == "Anti-Ship Systems" and String(target.metadata.get("platform_group", "")).to_lower() == "c2":
				continue
			candidates.append(target)
	var selected_targets: Array[IjfsTarget] = []
	var selection_mode := String(cfg.get("selection", "random"))
	if selection_mode == "deterministic":
		candidates.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
		for i in range(mini(count, candidates.size())):
			selected_targets.append(candidates[i])
	else:
		var k := mini(count, candidates.size())
		var indices := dice.choose_indices(candidates.size(), k)
		for index in indices:
			selected_targets.append(candidates[index])
	var overridden: Array[String] = []
	for target in selected_targets:
		target.intel_locked = true
		overridden.append(target.target_id)
	return overridden


static func _wildcard(value: Variant) -> bool:
	return value == null or String(value) == "" or String(value) == "*"


static func _subcategory_matches(rule_value: Variant, target_value: Variant) -> bool:
	return _wildcard(rule_value) or rule_value == target_value


static func _match_value(rule_value: Variant, target_value: Variant) -> bool:
	return _wildcard(null if rule_value == null else String(rule_value)) or rule_value == target_value


static func _has_capacity(budget: Variant, munition_id: String) -> bool:
	return bool(budget.call("has_capacity", munition_id))


static func _fail(message: String) -> void:
	push_error(message)
	assert(false, message)
