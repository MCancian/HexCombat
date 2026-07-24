## Verifies AirInsertionStateBuilder (plan 0032): which brigades join the air pool, that the
## default (no scenario block) is an inert empty pool, and that an unknown config key fails loud.
## Pure — own fixtures, no autoload, no dice.
extends GdUnitTestSuite


func _brigade(id: String, nato_type: String, battalions: int, hex_id: String = "") -> Brigade:
	var brigade := Brigade.new()
	brigade.id = id
	brigade.team = Brigade.Team.RED
	brigade.nato_type = nato_type
	brigade.hex_id = hex_id
	var battalion := Battalion.new()
	battalion.type = "Airborne Combined Arms Battalion"
	battalion.qty = battalions
	brigade.composition = [battalion] as Array[Battalion]
	return brigade


func _brigades() -> Dictionary:
	var green := _brigade("ROC-1", "airborne", 4)
	green.team = Brigade.Team.GREEN
	return {
		"PLAAF-ABN-127-Airborne": _brigade("PLAAF-ABN-127-Airborne", "airborne", 8),
		"PLAAF-ABN-130-Air-Assault": _brigade("PLAAF-ABN-130-Air-Assault", "air-assault", 10),
		"PLA-71-2-Amphibious": _brigade("PLA-71-2-Amphibious", "amphibious", 9),
		"PLAAF-ABN-134-Airborne": _brigade("PLAAF-ABN-134-Airborne", "airborne", 8, "hex_3_3"),
		"ROC-1": green,
	}


func test_no_scenario_block_builds_an_inert_pool() -> void:
	var state := AirInsertionStateBuilder.build({}, _brigades())
	assert_array(state.pool).is_empty()
	assert_dict(state.caps).is_empty()
	assert_int(state.pending_battalions()).is_equal(0)


func test_disabled_block_builds_an_inert_pool() -> void:
	var state := AirInsertionStateBuilder.build({"enabled": false, "airborne_cap_per_turn": 7}, _brigades())
	assert_array(state.pool).is_empty()
	assert_dict(state.caps).is_empty()


func test_only_unplaced_red_air_lifted_brigades_join_the_pool() -> void:
	var state := AirInsertionStateBuilder.build({"airborne_cap_per_turn": 7}, _brigades())

	# The amphibious brigade sails, the Green brigade is not Red's to fly, and the 134th already
	# stands on hex_3_3 — a scenario that places an air brigade gets it ashore, not in the pool.
	var ids: Array[String] = []
	for entry_value in state.pool:
		ids.append(String((entry_value as Dictionary)["brigade_id"]))
	assert_array(ids).contains_exactly(["PLAAF-ABN-127-Airborne", "PLAAF-ABN-130-Air-Assault"])
	assert_int(state.pending_battalions()).is_equal(18)
	assert_int(state.pending_battalions(LiftClass.AIRBORNE)).is_equal(8)
	assert_int(state.pending_battalions(LiftClass.AIR_ASSAULT)).is_equal(10)


func test_caps_default_to_the_user_dialled_lift() -> void:
	var state := AirInsertionStateBuilder.build({"enabled": true}, _brigades())
	assert_int(int(state.caps[LiftClass.AIRBORNE])).is_equal(7)
	assert_int(int(state.caps[LiftClass.AIR_ASSAULT])).is_equal(2)
	assert_dict(state.initial_caps).is_equal(state.caps)
	assert_int(state.first_turn).is_equal(1)


func test_scenario_overrides_caps_and_first_turn() -> void:
	var state := AirInsertionStateBuilder.build(
		{"airborne_cap_per_turn": 3, "air_assault_cap_per_turn": 0, "first_turn": 4}, _brigades())
	assert_int(int(state.caps[LiftClass.AIRBORNE])).is_equal(3)
	assert_int(int(state.caps[LiftClass.AIR_ASSAULT])).is_equal(0)
	assert_int(state.first_turn).is_equal(4)


func test_battalion_ids_are_unique_and_stable() -> void:
	var state := AirInsertionStateBuilder.build({"enabled": true}, _brigades())
	var seen: Dictionary = {}
	for entry_value in state.pool:
		for bn_value in (entry_value as Dictionary)["bns"]:
			var bn_id := String((bn_value as Dictionary)["id"])
			assert_bool(seen.has(bn_id)).is_false()
			seen[bn_id] = true
	assert_int(seen.size()).is_equal(18)


func test_attrition_config_defaults_to_the_user_anchors() -> void:
	var config := AirInsertionStateBuilder.attrition_config({})
	assert_float(float(config["max_attrition_at_full_ad"])).is_equal_approx(0.75, 0.0001)
	assert_float(float(config["manpads_max_attrition"])).is_equal_approx(0.25, 0.0001)


func test_an_unknown_config_key_fails_loud() -> void:
	assert_error(func() -> void: AirInsertionStateBuilder.build({"airborne_cap": 7}, _brigades())) \
		.is_push_error("red_air_insertion: unknown key 'airborne_cap' (known: %s)" % \
			", ".join(AirInsertionStateBuilder.KNOWN_KEYS))
