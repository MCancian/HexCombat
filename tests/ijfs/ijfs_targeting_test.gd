extends GdUnitTestSuite


func test_targets_to_attack_filters_release_gate_and_sorts_by_id() -> void:
	var z := _target("z", "Maneuver Units", "Infantry", "mobile", "soft", true)
	var a := _target("a", "Maneuver Units", "Infantry", "mobile", "soft", true)
	var hidden := _target("hidden", "Maneuver Units", "Infantry", "mobile", "soft", false)
	var destroyed := _target("destroyed", "Maneuver Units", "Infantry", "mobile", "soft", true)
	destroyed.destroyed = true
	var rules := [{"match": {"target_id": "z"}, "release_day": 2}]
	var result := IjfsTargeting.targets_to_attack([z, hidden, destroyed, a], 1, rules)
	assert_array(_ids(result)).is_equal(["a"])
	result = IjfsTargeting.targets_to_attack([z, hidden, destroyed, a], 2, rules)
	assert_array(_ids(result)).is_equal(["a", "z"])


func test_pairing_match_source_id_override_and_wildcards() -> void:
	var target := _target("t1", "Anti-Ship Systems", "Launcher", "mobile", "hard", true, "source_1")
	var override := _pairing("override", "m1", "Wrong", "Nope", "static", "soft", 1, ["source_1"])
	var wildcard := _pairing("wild", "m2", "Anti-Ship Systems", "*", "", null, 1)
	var mismatch := _pairing("bad", "m3", "Anti-Ship Systems", "Launcher", "static", "hard", 1)
	assert_bool(IjfsTargeting.pairing_matches_target(override, target)).is_true()
	assert_bool(IjfsTargeting.pairing_matches_target(wildcard, target)).is_true()
	assert_bool(IjfsTargeting.pairing_matches_target(mismatch, target)).is_false()
	assert_array(_pairing_ids(IjfsTargeting.find_compatible_pairings(target, [override, wildcard, mismatch]))).is_equal(["override", "wild"])


func test_doctrine_priority_then_fallback_and_reason_codes() -> void:
	var target := _target("hq", "Military Headquarters", "HQ", "static", "buried", true, "src_hq")
	var generic := _pairing("generic", "m_generic", target.category, null, "static", "buried", 8, ["src_hq"])
	var penetrator := _pairing("penetrator", "m_penetrator", target.category, null, "static", "buried", 10, ["src_hq"])
	var pairings: Array[IjfsPairing] = [generic, penetrator]
	var inventory := {
		"m_generic": _munition("m_generic", "Inorganic-Fast", 8),
		"m_penetrator": _munition("m_penetrator", "Inorganic-Fast", 10),
	}
	var scenario := {"targeting_doctrine": [{"name": "first", "match": {"hardness": "buried"}, "munition_priority": ["m_penetrator"]}]}
	var result := IjfsTargeting.select_munition_with_doctrine(target, pairings, inventory, scenario)
	assert_str(result["selected"].munition_id).is_equal("m_penetrator")
	assert_object(result["reason"]).is_null()
	assert_str(result["doctrine_name"]).is_equal("first")
	assert_str(result["selection"]).is_equal("priority")

	inventory["m_penetrator"].inventory_remaining = 0
	result = IjfsTargeting.select_munition_with_doctrine(target, pairings, inventory, scenario)
	assert_str(result["selected"].munition_id).is_equal("m_generic")
	assert_object(result["reason"]).is_null()
	assert_str(result["selection"]).is_equal("fallback")

	result = IjfsTargeting.select_munition(target, target_only_pairing(), inventory)
	assert_object(result["selected"]).is_null()
	assert_str(result["reason"]).is_equal("no_compatible_pairing")

	inventory["m_generic"].inventory_remaining = 0
	result = IjfsTargeting.select_munition(target, [generic], inventory)
	assert_object(result["selected"]).is_null()
	assert_str(result["reason"]).is_equal("insufficient_inventory")

	inventory["m_generic"].inventory_remaining = 8
	var budget := IjfsFiringCapacity.FiringCapacityBudget.new({"m_generic": {"firing_units": 0, "sorties_per_unit_per_day": 1.0}}, inventory)
	result = IjfsTargeting.select_munition_with_doctrine(target, [generic], inventory, null, null, null, budget)
	assert_object(result["selected"]).is_null()
	assert_str(result["reason"]).is_equal("firing_capacity_exhausted")


func test_phase_filter_drops_organic_pre_ad_and_keeps_post_ad() -> void:
	var target := _target("t", "Maneuver Units", "Armor", "mobile", "soft", true)
	var organic := _pairing("organic", "air", target.category, "Armor", "mobile", "soft", 1)
	var missile := _pairing("missile", "rocket", target.category, "Armor", "mobile", "soft", 1)
	var pairings: Array[IjfsPairing] = [organic, missile]
	var inventory := {"air": _munition("air", "Organic", 0), "rocket": _munition("rocket", "Inorganic-Fast", 1)}
	var pre := IjfsTargeting.select_munition_with_doctrine(target, pairings, inventory, null, "pre_ad_recompute")
	assert_str(pre["selected"].munition_id).is_equal("rocket")
	var post := IjfsTargeting.select_munition_with_doctrine(target, pairings, inventory, null, "post_ad_recompute")
	assert_str(post["selected"].munition_id).is_equal("air")


func test_target_release_eligible_uses_max_matching_day_and_falls_through() -> void:
	var target := _target("t", "Maneuver Units", "Mechanized Infantry", "mobile", "soft", true)
	var rules := [
		{"match": {"category": "Maneuver Units"}, "release_day": -2},
		{"match": {"subcategory": ["Mechanized Infantry"]}, "release_day": 0},
		{"match": {"category": "Other"}, "release_day": 99},
	]
	assert_bool(IjfsTargeting.target_release_eligible(target, -1, rules)).is_false()
	assert_bool(IjfsTargeting.target_release_eligible(target, 0, rules)).is_true()
	assert_bool(IjfsTargeting.target_release_eligible(target, -5, [])).is_true()
	assert_bool(IjfsTargeting.target_release_eligible(target, -99, [{"match": {"category": "Maneuver Units"}, "release_day": null}])).is_true()


func test_munition_filter_and_posture_override() -> void:
	var p1 := _pairing("p1", "m1", "Cat", null, "mobile", "soft", 1)
	var p2 := _pairing("p2", "m2", "Cat", null, "mobile", "soft", 1)
	assert_array(_pairing_ids(IjfsTargeting.apply_munition_filter({"mode": "whitelist", "ids": ["m2"]}, [p1, p2]))).is_equal(["p2"])
	assert_array(_pairing_ids(IjfsTargeting.apply_munition_filter({"mode": "blacklist", "ids": ["m1"]}, [p1, p2]))).is_equal(["p2"])

	var mobile := _target("mobile", "Cat", "Sub", "mobile", "soft", true)
	var static_target := _target("static", "Cat", "Sub", "static", "soft", true)
	var dead := _target("dead", "Cat", "Sub", "mobile", "soft", true)
	dead.destroyed = true
	IjfsTargeting.apply_posture_override([mobile, static_target, dead], "active")
	assert_str(mobile.posture).is_equal("active")
	assert_str(static_target.posture).is_equal("hiding")
	assert_str(dead.posture).is_equal("hiding")


func test_apply_exquisite_intel_deterministic_decay_and_antiship_c2_exclusion() -> void:
	var cfg := {"antiship": {"initial_count": 4, "selection": "deterministic", "decay": {"mode": "linear", "duration_days": 4}}}
	var b := _target("b", "Anti-Ship Systems", "Launcher", "mobile", "soft", false)
	var a := _target("a", "Anti-Ship Systems", "Launcher", "mobile", "soft", false)
	var c2 := _target("c2", "Anti-Ship Systems", "Command & Control", "moveable", "soft", false)
	c2.metadata = {"platform_group": "c2"}
	var static_target := _target("static", "Anti-Ship Systems", "Launcher", "static", "soft", false)
	var targets: Array[IjfsTarget] = [b, c2, static_target, a]
	var overridden := IjfsTargeting.apply_exquisite_intel(targets, cfg, 2, ScriptedDice.new([], []), "antiship", "Anti-Ship Systems")
	assert_array(overridden).is_equal(["a", "b"])
	assert_bool(a.intel_locked).is_true()
	assert_bool(b.intel_locked).is_true()
	assert_bool(c2.intel_locked).is_false()
	assert_bool(static_target.intel_locked).is_false()
	assert_str(a.mobility).is_equal("mobile")


func test_apply_exquisite_intel_random_uses_choose_indices_without_replacement() -> void:
	var cfg := {"maneuver": {"initial_count": 2, "selection": "random"}}
	var targets: Array[IjfsTarget] = [
		_target("m0", "Maneuver Units", "Armor", "mobile", "soft", false),
		_target("m1", "Maneuver Units", "Armor", "mobile", "soft", false),
		_target("m2", "Maneuver Units", "Armor", "mobile", "soft", false),
	]
	var overridden := IjfsTargeting.apply_exquisite_intel(targets, cfg, 1, ScriptedDice.new([], [[0, 2]]), "maneuver", "Maneuver Units")
	assert_array(overridden).is_equal(["m0", "m2"])
	assert_bool(targets[0].intel_locked).is_true()
	assert_bool(targets[2].intel_locked).is_true()


func target_only_pairing() -> Array[IjfsPairing]:
	return [_pairing("other", "m_other", "Other", null, "static", "soft", 1)]


func _target(id: String, category: String, subcategory: String, mobility: String, hardness: String, detected: bool, source_id: String = "") -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.source_target_id = source_id if source_id != "" else id
	target.category = category
	target.subcategory = subcategory
	target.mobility = mobility
	target.hardness = hardness
	target.detected_this_turn = detected
	target.posture = "hiding"
	return target


func _pairing(id: String, munition_id: String, category: String, subcategory: Variant, mobility: Variant, hardness: Variant, rounds: int, source_ids: Array = []) -> IjfsPairing:
	var pairing := IjfsPairing.new()
	pairing.pairing_id = id
	pairing.munition_id = munition_id
	pairing.target_category = category
	pairing.target_subcategory = "" if subcategory == null else String(subcategory)
	pairing.target_mobility = "" if mobility == null else String(mobility)
	pairing.target_hardness = "" if hardness == null else String(hardness)
	pairing.rounds_expended_per_engagement = rounds
	for sid in source_ids:
		pairing.source_target_ids.append(String(sid))
	return pairing


func _munition(id: String, category: String, remaining: int) -> IjfsMunition:
	var munition := IjfsMunition.new()
	munition.munition_id = id
	munition.category = category
	munition.inventory_remaining = remaining
	return munition


func _ids(targets: Array) -> Array[String]:
	var result: Array[String] = []
	for target in targets:
		result.append(target.target_id)
	return result


func _pairing_ids(pairings: Array) -> Array[String]:
	var result: Array[String] = []
	for pairing in pairings:
		result.append(pairing.pairing_id)
	return result
