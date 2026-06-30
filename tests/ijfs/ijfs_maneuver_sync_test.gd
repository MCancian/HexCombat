## Verifies GameState._sync_maneuver_targets_to_oob retires "Maneuver Units" IJFS targets when their
## battalions die — so IJFS stops "shooting at ghosts" (overnight 2d follow-up). Fully-destroyed
## brigades lose all their maneuver targets; a partial qty cut destroys exactly the excess (highest
## target_id first); an unchanged OOB is a no-op (golden-safe). Only ever sets destroyed — never
## resurrects.
extends GdUnitTestSuite


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func _live_maneuver_targets_for(brigade_id: String) -> Array:
	var out: Array = []
	for target_value in GameState.ijfs_state.targets:
		var target: IjfsTarget = target_value
		if target.category == "Maneuver Units" and not target.destroyed \
				and String(target.metadata.get("brigade_id", "")) == brigade_id:
			out.append(target)
	return out


func _first_live_green_brigade() -> Brigade:
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.GREEN and not brigade.destroyed:
			for battalion in brigade.composition:
				if battalion.qty > 0:
					return brigade
	return null


func test_no_change_is_noop() -> void:
	GameState._rebuild_ijfs_state()
	var brigade := _first_live_green_brigade()
	var before := _live_maneuver_targets_for(brigade.id).size()
	assert_int(before).is_greater(0)
	GameState._sync_maneuver_targets_to_oob()
	assert_int(_live_maneuver_targets_for(brigade.id).size()).is_equal(before)


func test_destroyed_brigade_loses_all_maneuver_targets() -> void:
	GameState._rebuild_ijfs_state()
	var brigade := _first_live_green_brigade()
	assert_int(_live_maneuver_targets_for(brigade.id).size()).is_greater(0)
	brigade.destroyed = true
	GameState._sync_maneuver_targets_to_oob()
	assert_int(_live_maneuver_targets_for(brigade.id).size()).is_equal(0)


func test_partial_qty_cut_retires_exactly_the_excess() -> void:
	GameState._rebuild_ijfs_state()
	# Find a Green brigade with a battalion type that has qty >= 1 and >1 maneuver targets total.
	var brigade: Brigade = null
	var target_type := ""
	for brigade_value in GameData.brigades.values():
		var b: Brigade = brigade_value
		if b.team != Brigade.Team.GREEN or b.destroyed:
			continue
		for battalion in b.composition:
			if battalion.qty >= 1 and _live_maneuver_targets_for(b.id).size() > 0:
				brigade = b
				target_type = battalion.type
				break
		if brigade != null:
			break
	assert_object(brigade).is_not_null()

	var live_before := _live_maneuver_targets_for(brigade.id).size()
	# Kill one battalion of target_type in the OOB.
	for battalion in brigade.composition:
		if battalion.type == target_type and battalion.qty > 0:
			battalion.qty -= 1
			break
	GameState._sync_maneuver_targets_to_oob()
	# Exactly one maneuver target retired (the type lost one instance).
	assert_int(_live_maneuver_targets_for(brigade.id).size()).is_equal(live_before - 1)
