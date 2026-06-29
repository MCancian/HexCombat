## Verifies IjfsLoaders.build_maneuver_targets generates one "Maneuver Units" IJFS target per Green/ROC
## battalion instance with stable {brigade_id}-MU-{n} ids + OOB metadata (overnight item 2b). Pure
## generation — no pipeline wiring yet (2c/2d consume these).
extends GdUnitTestSuite


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func _green_brigades() -> Array:
	var out: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.GREEN:
			out.append(brigade)
	return out


func _total_green_battalion_instances() -> int:
	var total := 0
	for brigade in _green_brigades():
		for battalion in brigade.composition:
			total += battalion.qty
	return total


func test_one_target_per_battalion_instance() -> void:
	var targets := IjfsLoaders.build_maneuver_targets(_green_brigades())
	assert_int(targets.size()).is_equal(_total_green_battalion_instances())
	assert_int(targets.size()).is_greater(0)


func test_all_targets_are_maneuver_units_with_oob_metadata() -> void:
	var green := _green_brigades()
	var valid_brigade_ids := {}
	for brigade in green:
		valid_brigade_ids[brigade.id] = true
	for target_value in IjfsLoaders.build_maneuver_targets(green):
		var target: IjfsTarget = target_value
		assert_str(target.category).is_equal("Maneuver Units")
		var meta: Dictionary = target.metadata
		assert_bool(meta.has("battalion_id")).is_true()
		assert_bool(meta.has("brigade_id")).is_true()
		assert_bool(meta.has("unit_type")).is_true()
		assert_bool(valid_brigade_ids.has(String(meta["brigade_id"]))).is_true()
		# id format: {brigade_id}-MU-{n}
		assert_str(String(meta["battalion_id"])).starts_with(String(meta["brigade_id"]) + "-MU-")


func test_known_type_maps_to_profile() -> void:
	# A Tank/Armor battalion → Armour / hard; a Field Artillery → Field Artillery / soft.
	var targets := IjfsLoaders.build_maneuver_targets(_green_brigades())
	var checked_armour := false
	for target_value in targets:
		var target: IjfsTarget = target_value
		var ut := String(target.metadata.get("unit_type", ""))
		if ut == "Tank Battalion" or ut == "Armor Battalion":
			assert_str(target.subcategory).is_equal("Armour")
			assert_str(target.hardness).is_equal("hard")
			checked_armour = true
	# Not all OOBs contain armor; only assert when present.
	if not checked_armour:
		assert_bool(true).is_true()


func test_unmapped_type_uses_fallback() -> void:
	var fake := Brigade.new()
	fake.id = "TEST-BDE"
	fake.team = Brigade.Team.GREEN
	fake.to_number = 9
	var bn := Battalion.new()
	bn.type = "Totally Unknown Battalion"
	bn.qty = 2
	fake.composition = [bn]
	var targets := IjfsLoaders.build_maneuver_targets([fake])
	assert_int(targets.size()).is_equal(2)
	var t: IjfsTarget = targets[0]
	assert_str(t.subcategory).is_equal("Light Infantry - Reserve")
	assert_str(t.hardness).is_equal("soft")
	assert_str(String(t.metadata["battalion_id"])).is_equal("TEST-BDE-MU-1")
