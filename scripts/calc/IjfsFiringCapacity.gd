class_name IjfsFiringCapacity
extends RefCounted


class FiringCapacityBudget extends RefCounted:
	var _daily_budget: Dictionary = {}
	var _used: Dictionary = {}

	func _init(config: Dictionary, munitions: Variant = null) -> void:
		if munitions != null and not (munitions is Dictionary):
			_fail("FiringCapacityBudget munitions must be a Dictionary or null")
		for munition_id_value in config.keys():
			var munition_id := String(munition_id_value)
			var entry: Variant = config[munition_id_value]
			if not (entry is Dictionary):
				_fail("Firing capacity entry for '%s' must be a Dictionary" % munition_id)
			var entry_dict: Dictionary = entry
			_validate_capacity_entry(munition_id, entry_dict)
			if munitions != null:
				var munition: Variant = (munitions as Dictionary).get(munition_id, null)
				if munition != null and munition.category == "Organic":
					continue
			var units := int(entry_dict["firing_units"])
			var sorties := float(entry_dict["sorties_per_unit_per_day"])
			_daily_budget[munition_id] = floori(float(units) * sorties)
			_used[munition_id] = 0

	func has_capacity(munition_id: String) -> bool:
		var budget: Variant = _daily_budget.get(munition_id, null)
		if budget == null:
			return true
		return int(_used.get(munition_id, 0)) < int(budget)

	func try_consume(munition_id: String) -> bool:
		var budget: Variant = _daily_budget.get(munition_id, null)
		if budget == null:
			return true
		var used := int(_used.get(munition_id, 0))
		if used >= int(budget):
			return false
		_used[munition_id] = used + 1
		return true

	func utilization() -> Dictionary:
		var result: Dictionary = {}
		for mid in _daily_budget.keys():
			var budget := int(_daily_budget[mid])
			var used := int(_used.get(mid, 0))
			result[mid] = {
				"budget": budget,
				"used": used,
				"remaining": budget - used,
			}
		return result

	func _validate_capacity_entry(munition_id: String, entry: Dictionary) -> void:
		if not entry.has("firing_units"):
			_fail("Firing capacity entry for '%s' missing firing_units" % munition_id)
		if not entry.has("sorties_per_unit_per_day"):
			_fail("Firing capacity entry for '%s' missing sorties_per_unit_per_day" % munition_id)

	func _fail(message: String) -> void:
		push_error(message)
		assert(false, message)


class OrganicStrikeBudget extends RefCounted:
	const _PLATFORM_KIND := {"aircraft": "manned", "uav": "unmanned"}

	var _budgets: Dictionary = {}
	var _used: Dictionary = {}

	func _init(scenario: Dictionary, squadron_force: Variant, munitions: Dictionary, air_classes: Variant = null) -> void:
		if squadron_force != null and not (squadron_force is Array):
			_fail("OrganicStrikeBudget squadron_force must be an Array[IjfsSquadron] or null")
		if air_classes != null and not (air_classes is Dictionary):
			_fail("OrganicStrikeBudget air_classes must be a Dictionary or null")
		var firing_config: Dictionary = scenario.get("red_firing_capacity", {})
		if not (firing_config is Dictionary):
			_fail("Scenario red_firing_capacity must be a Dictionary")

		var classes: Dictionary = {}
		if air_classes != null:
			classes = (air_classes as Dictionary).get("classes", {})
		var init_any := 0
		var alive_any := 0
		var init_by_kind: Dictionary = {}
		var alive_by_kind: Dictionary = {}
		if squadron_force != null:
			for sq: IjfsSquadron in squadron_force:
				if sq.role != "strike":
					continue
				init_any += sq.initial
				alive_any += sq.alive
				var kind := String(classes.get(sq.aircraft_class, {}).get("kind", ""))
				if kind != "":
					init_by_kind[kind] = int(init_by_kind.get(kind, 0)) + sq.initial
					alive_by_kind[kind] = int(alive_by_kind.get(kind, 0)) + sq.alive

		for mid_value in firing_config.keys():
			var mid := String(mid_value)
			var cfg_value: Variant = firing_config[mid_value]
			if not (cfg_value is Dictionary):
				_fail("Firing capacity entry for '%s' must be a Dictionary" % mid)
			var cfg: Dictionary = cfg_value
			_validate_capacity_entry(mid, cfg)
			var munition: Variant = munitions.get(mid, null)
			if munition == null or munition.category != "Organic":
				continue
			var units := int(cfg["firing_units"])
			var sorties := float(cfg["sorties_per_unit_per_day"])
			var base := floori(float(units) * sorties)
			var expected_kind: Variant = _PLATFORM_KIND.get(String(cfg.get("platform_type", "")), null)
			var health: Variant = _strike_health(expected_kind, init_by_kind, alive_by_kind, init_any, alive_any)
			_budgets[mid] = base if health == null else max(0, floori(float(base) * float(health)))
			_used[mid] = 0

	func has_capacity(munition_id: String) -> bool:
		var budget: Variant = _budgets.get(munition_id, null)
		if budget == null:
			return true
		if int(budget) <= 0:
			return false
		return int(_used.get(munition_id, 0)) < int(budget)

	func try_consume(munition_id: String) -> bool:
		var budget: Variant = _budgets.get(munition_id, null)
		if budget == null:
			return true
		var used := int(_used.get(munition_id, 0))
		if int(budget) <= 0 or used >= int(budget):
			return false
		_used[munition_id] = used + 1
		return true

	func utilization() -> Dictionary:
		var result: Dictionary = {}
		for mid in _budgets.keys():
			result[mid] = {"budget": int(_budgets[mid]), "used": int(_used.get(mid, 0))}
		return result

	func _strike_health(expected_kind: Variant, init_by_kind: Dictionary, alive_by_kind: Dictionary, init_any: int, alive_any: int) -> Variant:
		if expected_kind != null and int(init_by_kind.get(expected_kind, 0)) > 0:
			return float(alive_by_kind[expected_kind]) / float(init_by_kind[expected_kind])
		if init_any > 0:
			return float(alive_any) / float(init_any)
		return null

	func _validate_capacity_entry(munition_id: String, entry: Dictionary) -> void:
		if not entry.has("firing_units"):
			_fail("Firing capacity entry for '%s' missing firing_units" % munition_id)
		if not entry.has("sorties_per_unit_per_day"):
			_fail("Firing capacity entry for '%s' missing sorties_per_unit_per_day" % munition_id)

	func _fail(message: String) -> void:
		push_error(message)
		assert(false, message)
