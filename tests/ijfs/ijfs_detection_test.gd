extends GdUnitTestSuite


func test_isr_degradation_curves_match_source_formulas() -> void:
	assert_float(IjfsDetection.evaluate_isr_source(_src("exp_decay", {"half_life_days": 3}), 1, _isr_status())).is_equal_approx(1.0, 0.000001)
	assert_float(IjfsDetection.evaluate_isr_source(_src("exp_decay", {"half_life_days": 3}), 4, _isr_status())).is_equal_approx(0.5, 0.000001)
	assert_float(IjfsDetection.evaluate_isr_source(_src("linear", {"duration_days": 5}), 6, _isr_status())).is_equal_approx(0.0, 0.000001)
	assert_float(IjfsDetection.evaluate_isr_source(_src("piecewise", {"values": [1.0, 0.7, 0.25]}), 99, _isr_status())).is_equal_approx(0.25, 0.000001)
	assert_float(IjfsDetection.evaluate_isr_source(_src("from_attrition", {"source": "isr.uav_alive"}), 1, _isr_status(2, 5))).is_equal_approx(0.4, 0.000001)
	assert_float(IjfsDetection.evaluate_isr_source(_src("logistic", {"k": 1.0, "d_mid": 0.0}), 1, _isr_status())).is_equal_approx(0.5, 0.000001)
	assert_float(IjfsDetection.evaluate_isr_source(_src("gompertz", {"b": 1.0, "c": 1.0}), 1, _isr_status())).is_equal_approx(1.0 - exp(-1.0), 0.000001)
	assert_float(IjfsDetection.evaluate_isr_source(_src("weibull", {"lambda": 2.0, "k": 2.0}), 3, _isr_status())).is_equal_approx(exp(-1.0), 0.000001)


func test_satellite_static_auto_detects_and_mobile_rolls_against_floor_in_target_id_order() -> void:
	var targets: Array[IjfsTarget] = [
		_target("z_mobile_miss", "mobile", "active"),
		_target("static", "static", "not_applicable"),
		_target("a_mobile_hit", "mobile", "active"),
	]
	var scenario := _scenario()
	scenario["detection_model"]["satellite_floor_probability"]["mobile"]["active"] = 0.20
	var dice := ScriptedDice.new([], [], [0.20, 0.21])
	var result := IjfsDetection.satellite_detect_target_ids(targets, scenario, dice)
	var ids: Array = result["detected_ids"]
	assert_bool(ids.has("static")).is_true()
	assert_bool(ids.has("a_mobile_hit")).is_true()
	assert_bool(ids.has("z_mobile_miss")).is_false()
	assert_int(result["log"].size()).is_equal(3)


func test_aircraft_detection_uses_floor_base_mobility_posture_and_weighted_isr() -> void:
	var targets: Array[IjfsTarget] = [
		_target("hit", "mobile", "active"),
		_target("miss", "mobile", "active"),
	]
	var scenario := _scenario()
	var force: Array[IjfsSquadron] = [_squadron("isr", "Test ISR", 1)]
	var air_classes := {"reference_isr_sum": 1.0, "classes": {"Test ISR": {"isr_value": 0.5}}}
	var dice := ScriptedDice.new([], [], [0.14, 0.15])
	var result := IjfsDetection.aircraft_detect_target_ids(targets, scenario, force, air_classes, 1.0, dice, 1)
	var ids: Array = result["detected_ids"]
	assert_bool(ids.has("hit")).is_true()
	assert_bool(ids.has("miss")).is_false()
	var by_id := _log_by_id(result["log"])
	assert_float(by_id["hit"]["p_detect"]).is_equal_approx(0.145, 0.000001)
	assert_float(by_id["miss"]["p_detect"]).is_equal_approx(0.145, 0.000001)


func test_active_antiship_metadata_multiplies_base_probability_before_detection() -> void:
	var baseline := _target("baseline", "mobile", "hiding")
	var active := _target("active", "mobile", "hiding")
	active.metadata = {"active": true}
	var scenario := _scenario()
	scenario["isr_sources"] = [_src("linear", {"duration_days": 10}, 1.0)]
	var dice := ScriptedDice.new([], [], [0.06, 0.06])
	var targets: Array[IjfsTarget] = [baseline, active]
	var result := IjfsDetection.aircraft_detect_target_ids(targets, scenario, [], {"reference_isr_sum": 1.0, "classes": {}}, 1.0, dice, 1)
	var ids: Array = result["detected_ids"]
	assert_bool(ids.has("active")).is_true()
	assert_bool(ids.has("baseline")).is_false()
	var by_id := _log_by_id(result["log"])
	assert_float(by_id["baseline"]["p_detect"]).is_equal_approx(0.05, 0.000001)
	assert_float(by_id["active"]["p_detect"]).is_equal_approx(0.075, 0.000001)


func test_apply_detection_ids_sets_flags_and_clears_destroyed_known_to_red() -> void:
	var detected := _target("detected", "mobile", "hiding")
	var hidden := _target("hidden", "mobile", "hiding")
	var destroyed := _target("destroyed", "mobile", "hiding")
	destroyed.destroyed = true
	destroyed.known_to_red = true
	destroyed.detected_this_turn = true
	var targets: Array[IjfsTarget] = [detected, hidden, destroyed]
	IjfsDetection.apply_detection_ids(targets, ["detected", "destroyed"], 7)
	assert_bool(detected.detected_this_turn).is_true()
	assert_bool(detected.known_to_red).is_true()
	assert_int(detected.last_detected_day).is_equal(7)
	assert_bool(hidden.detected_this_turn).is_false()
	assert_bool(hidden.known_to_red).is_false()
	assert_bool(destroyed.detected_this_turn).is_false()
	assert_bool(destroyed.known_to_red).is_false()


func _src(mode: String, degradation_fields: Dictionary, weight: float = 1.0) -> Dictionary:
	var degradation := {"mode": mode}
	for key in degradation_fields.keys():
		degradation[key] = degradation_fields[key]
	return {
		"initial_capability": 1.0,
		"floor": 0.0,
		"detection_weight": weight,
		"target_categories": ["*"],
		"degradation": degradation,
	}


func _isr_status(uav_alive: int = 5, uav_initial: int = 5) -> Dictionary:
	return {
		"uav_alive": uav_alive,
		"uav_initial": uav_initial,
		"manned_alive": 3,
		"manned_initial": 3,
	}


func _squadron(role: String, aircraft_class: String, alive: int) -> IjfsSquadron:
	var squadron := IjfsSquadron.new()
	squadron.squadron_id = "%s_%s" % [aircraft_class, role]
	squadron.aircraft_class = aircraft_class
	squadron.role = role
	squadron.initial = alive
	squadron.alive = alive
	return squadron


func _target(id: String, mobility: String, posture: String) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.source_target_id = id
	target.category = "Anti-Ship Systems"
	target.subcategory = "Launcher"
	target.mobility = mobility
	target.hardness = "soft"
	target.detectability_active = "medium"
	target.detectability_hiding = "low"
	target.posture = posture
	return target


func _scenario() -> Dictionary:
	return {
		"detection_model": {
			"detectability_label_base_probability": {"high": 0.5, "medium": 0.2, "low": 0.05},
			"satellite_floor_probability": {
				"mobile": {"active": 0.02, "hiding": 0.0},
				"moveable": {"active": 0.95, "hiding": 0.50},
			},
			"mobility_multiplier": {"mobile": 1.0, "moveable": 1.2},
			"posture_multiplier": {
				"mobile": {"active": 1.25, "hiding": 1.0},
				"moveable": {"active": 1.5, "hiding": 1.0},
			},
			"antiship_active_attempt_multiplier": 1.5,
		},
		"isr_sources": [],
	}


func _log_by_id(log_entries: Array) -> Dictionary:
	var by_id := {}
	for entry in log_entries:
		by_id[entry["target_id"]] = entry
	return by_id
