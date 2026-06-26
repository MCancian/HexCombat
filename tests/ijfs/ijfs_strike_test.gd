extends GdUnitTestSuite

# Uses the shared tests/helpers/ScriptedDice.gd; scripted randf() draws are its 3rd ctor arg.


func test_modifier_formula_clamps_add_then_multiply_and_matches_context() -> void:
	var scenario := {
		"strike_probability_modifiers": [
			{"modifier_id": "category_add", "operation": "add", "value": 0.2, "match": {"category": "Anti-Ship Systems"}},
			{"modifier_id": "mobility_add", "operation": "add", "value": 0.2, "match": {"mobility": ["mobile", "moveable"]}},
			{"modifier_id": "munition_mult", "operation": "multiply", "value": 2.0, "match": {"munition_id": "m1"}},
			{"modifier_id": "intel_mult", "operation": "multiply", "value": 0.5, "match": {"intel_locked": true}},
			{"modifier_id": "ignored", "operation": "add", "value": 0.9, "match": {"mobility": "static"}},
		]
	}
	var target := _target("t1", "mobile", "active")
	target.intel_locked = true
	var result := IjfsStrike.evaluate_strike_probability(target, _pairing(0.7, 0.0, 1), _munition("m1", "Inorganic-Fast", 10), scenario)

	assert_float(result["base"]).is_equal_approx(0.7, 0.000001)
	assert_float(result["modifier_add_sum"]).is_equal_approx(0.4, 0.000001)
	assert_float(result["modifier_mult_product"]).is_equal_approx(1.0, 0.000001)
	assert_float(result["final"]).is_equal_approx(1.0, 0.000001)
	assert_array(_modifier_ids(result["modifiers"])).is_equal(["category_add", "mobility_add", "munition_mult", "intel_mult"])
	assert_str(result["formula"]).is_equal("base_plus_adds_times_mults")


func test_base_only_path_when_no_modifiers() -> void:
	var result := IjfsStrike.evaluate_strike_probability(_target("t1", "static", "active"), _pairing(1.4, 0.0, 1), _munition("m1", "Inorganic-Fast", 10), {})
	assert_float(result["base"]).is_equal_approx(1.0, 0.000001)
	assert_float(result["final"]).is_equal_approx(1.0, 0.000001)
	assert_str(result["formula"]).is_equal("base_only")
	assert_array(result["modifiers"]).is_empty()


func test_legacy_mobile_cap_applies_only_to_unlocked_mobile_targets() -> void:
	var scenario := _legacy_cap_scenario(0.25)
	var pairing := _pairing(0.8, 0.0, 1)
	var munition := _munition("m1", "Inorganic-Fast", 10)

	var capped := IjfsStrike.destruction_probability(_target("mobile", "mobile", "active"), pairing, munition, scenario)
	assert_float(capped["legacy_cap_applied"]).is_equal_approx(0.25, 0.000001)
	assert_float(capped["final"]).is_equal_approx(0.25, 0.000001)

	var locked_target := _target("locked", "mobile", "active")
	locked_target.intel_locked = true
	var locked := IjfsStrike.destruction_probability(locked_target, pairing, munition, scenario)
	assert_object(locked["legacy_cap_applied"]).is_null()
	assert_float(locked["final"]).is_equal_approx(0.8, 0.000001)

	var static_result := IjfsStrike.destruction_probability(_target("static", "static", "active"), pairing, munition, scenario)
	assert_object(static_result["legacy_cap_applied"]).is_null()
	assert_float(static_result["final"]).is_equal_approx(0.8, 0.000001)


func test_resolve_strike_inventory_rules_and_destroy_side_effects() -> void:
	var inorganic := _munition("m1", "Inorganic-Fast", 1)
	var inventory := {"m1": inorganic}
	var insufficient := IjfsStrike.resolve_strike(_target("t1", "static", "active"), _pairing(1.0, 0.0, 2), inventory, {}, 3, ScriptedDice.new([], [], []))
	assert_bool(insufficient["attack_executed"]).is_false()
	assert_str(insufficient["skip_reason"]).is_equal("insufficient_inventory")
	assert_int(inorganic.inventory_remaining).is_equal(1)

	inorganic.inventory_remaining = 2
	var destroyed_target := _target("t2", "static", "active")
	destroyed_target.known_to_red = true
	destroyed_target.suppressed = true
	destroyed_target.suppressed_this_turn = true
	var destroyed := IjfsStrike.resolve_strike(destroyed_target, _pairing(1.0, 1.0, 2), inventory, {}, 3, ScriptedDice.new([], [], [1.0]))
	assert_bool(destroyed["attack_executed"]).is_true()
	assert_int(inorganic.inventory_remaining).is_equal(0)
	assert_bool(destroyed["destroyed"]).is_true()
	assert_bool(destroyed_target.destroyed).is_true()
	assert_bool(destroyed_target.known_to_red).is_false()
	assert_bool(destroyed_target.suppressed).is_false()
	assert_object(destroyed["suppression_roll"]).is_null()

	var organic := _munition("air", "Organic", 0)
	var organic_inventory := {"air": organic}
	var organic_result := IjfsStrike.resolve_strike(_target("t3", "static", "active"), _pairing(0.0, 0.0, 99, "p", "air"), organic_inventory, {}, 3, ScriptedDice.new([], [], [0.5]))
	assert_bool(organic_result["attack_executed"]).is_true()
	assert_int(organic.inventory_remaining).is_equal(0)


func test_resolve_strike_suppression_rng_order_and_draw_conditions() -> void:
	var target := _target("t1", "static", "active")
	var inventory := {"m1": _munition("m1", "Inorganic-Fast", 10)}
	var dice := ScriptedDice.new([], [], [0.4, 0.2])
	var result := IjfsStrike.resolve_strike(target, _pairing(0.0, 0.3, 1), inventory, {}, 1, dice)
	assert_bool(result["destroyed"]).is_false()
	assert_float(result["roll"]).is_equal_approx(0.4, 0.000001)
	assert_float(result["suppression_roll"]).is_equal_approx(0.2, 0.000001)
	assert_bool(result["suppressed"]).is_true()
	assert_bool(target.suppressed).is_true()
	assert_int(dice._floats.size()).is_equal(0)

	var no_suppression_dice := ScriptedDice.new([], [], [0.4])
	var no_suppression := IjfsStrike.resolve_strike(_target("t2", "static", "active"), _pairing(0.0, 0.0, 1), {"m1": _munition("m1", "Inorganic-Fast", 10)}, {}, 1, no_suppression_dice)
	assert_bool(no_suppression["destroyed"]).is_false()
	assert_object(no_suppression["suppression_roll"]).is_null()
	assert_int(no_suppression_dice._floats.size()).is_equal(0)

	var destroy_dice := ScriptedDice.new([], [], [0.0])
	var destroyed := IjfsStrike.resolve_strike(_target("t3", "static", "active"), _pairing(1.0, 1.0, 1), {"m1": _munition("m1", "Inorganic-Fast", 10)}, {}, 1, destroy_dice)
	assert_bool(destroyed["destroyed"]).is_true()
	assert_object(destroyed["suppression_roll"]).is_null()
	assert_int(destroy_dice._floats.size()).is_equal(0)


func _target(id: String, mobility: String, posture: String) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.source_target_id = "%s_source" % id
	target.category = "Anti-Ship Systems"
	target.subcategory = "Launcher"
	target.mobility = mobility
	target.hardness = "soft"
	target.posture = posture
	target.metadata = {"id": id}
	return target


func _pairing(p_destroy: float, p_suppressed: float, rounds: int, pairing_id: String = "p", munition_id: String = "m1") -> IjfsPairing:
	var pairing := IjfsPairing.new()
	pairing.pairing_id = pairing_id
	pairing.munition_id = munition_id
	pairing.rounds_expended_per_engagement = rounds
	pairing.probability_destroyed = p_destroy
	pairing.probability_suppressed_if_not_destroyed = p_suppressed
	return pairing


func _munition(munition_id: String, category: String, remaining: int) -> IjfsMunition:
	var munition := IjfsMunition.new()
	munition.munition_id = munition_id
	munition.category = category
	munition.inventory_remaining = remaining
	return munition


func _legacy_cap_scenario(active_cap: float) -> Dictionary:
	return {
		"mobile_target_destroy_caps": {
			"active": {"Inorganic-Fast": active_cap},
			"hiding": {"Inorganic-Fast": active_cap / 2.0},
		}
	}


func _modifier_ids(modifiers: Array) -> Array[String]:
	var ids: Array[String] = []
	for modifier in modifiers:
		ids.append(String(modifier["modifier_id"]))
	return ids
