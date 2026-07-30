class_name IjfsAdHealth
extends RefCounted

## Port of ijfs_standalone/ad_health.py. Taiwan air-defense health: per-category
## alive-and-unsuppressed fraction, SAM × radar coupled effective health.

const AD_CATEGORIES := ["Moveable SAMs", "Static SAMs", "Static Radars", "Mobile Radars"]
const SAM_CATEGORIES := ["Moveable SAMs", "Static SAMs", "Mobile SAMs"]
const RADAR_CATEGORIES := ["Static Radars", "Mobile Radars"]


static func compute_taiwan_ad_health(targets: Array[IjfsTarget], scenario: Dictionary) -> Dictionary:
	var weights: Dictionary = scenario["taiwan_air_defense_health"]["surviving_unsuppressed_weighted_categories"]
	var category_health: Dictionary = {}
	for cat in AD_CATEGORIES:
		category_health[cat] = _category_health(targets, cat)
	for cat in AD_CATEGORIES:
		if float(weights.get(cat, 0.0)) > 0.0 and not _any_in_category(targets, cat):
			push_warning("IJFS AD health: weighted category '%s' has no targets; contributing 0.0 health" % cat)
	var raw_sam_health := _weighted_average(category_health, weights, SAM_CATEGORIES)
	var radar_health := _weighted_average(category_health, weights, RADAR_CATEGORIES)
	var effective_sam_health := raw_sam_health * radar_health
	var sam_weight_total := _weight_total(weights, SAM_CATEGORIES)
	var radar_weight_total := _weight_total(weights, RADAR_CATEGORIES)
	var effective_ad_health := clampf(sam_weight_total * effective_sam_health + radar_weight_total * radar_health, 0.0, 1.0)
	return {
		"category_health": category_health,
		"raw_sam_health": raw_sam_health,
		"radar_health": radar_health,
		"effective_sam_health": effective_sam_health,
		"effective_ad_health": effective_ad_health,
		"sam_weight_total": sam_weight_total,
		"radar_weight_total": radar_weight_total,
	}


static func _category_health(targets: Array[IjfsTarget], category: String) -> float:
	var total := 0
	var alive := 0
	for target in targets:
		if target.category == category:
			total += 1
			if not target.destroyed and not target.suppressed:
				alive += 1
	if total == 0:
		return 0.0
	return float(alive) / float(total)


static func _weighted_average(health: Dictionary, weights: Dictionary, categories: Array) -> float:
	var total_weight := _weight_total(weights, categories)
	if total_weight <= 0.0:
		return 1.0
	var sum := 0.0
	for cat in categories:
		sum += float(health.get(cat, 0.0)) * float(weights.get(cat, 0.0))
	return sum / total_weight


static func _weight_total(weights: Dictionary, categories: Array) -> float:
	var total := 0.0
	for cat in categories:
		total += float(weights.get(cat, 0.0))
	return total


static func _any_in_category(targets: Array[IjfsTarget], category: String) -> bool:
	for target in targets:
		if target.category == category:
			return true
	return false
