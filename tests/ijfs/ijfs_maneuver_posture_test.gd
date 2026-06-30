## Verifies GameState._update_maneuver_posture sets posture="active" on the maneuver-unit IJFS targets
## of Green brigades that moved/fought last turn, and "hiding" otherwise (overnight item 2c-ii). Pure
## data nudge feeding IjfsDetection's posture seam — no detection-math change. Golden-safe because on
## turn 1 (the golden turn) all activity flags are false, so every maneuver target stays "hiding".
extends GdUnitTestSuite


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func _first_live_green_brigade() -> Brigade:
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.GREEN and not brigade.destroyed:
			for battalion in brigade.composition:
				if battalion.qty > 0:
					return brigade
	return null


func test_active_brigade_targets_become_active_others_hiding() -> void:
	var active_brigade := _first_live_green_brigade()
	assert_object(active_brigade).is_not_null()
	active_brigade.moved_last_turn = true

	GameState._rebuild_ijfs_state()
	GameState._update_maneuver_posture()

	var saw_active := false
	var saw_hiding := false
	for target_value in GameState.ijfs_state.targets:
		var target: IjfsTarget = target_value
		if target.category != "Maneuver Units":
			continue
		var bid := String(target.metadata.get("brigade_id", ""))
		if bid == active_brigade.id:
			assert_str(target.posture).is_equal("active")
			saw_active = true
		else:
			assert_str(target.posture).is_equal("hiding")
			saw_hiding = true
	assert_bool(saw_active).is_true()
	assert_bool(saw_hiding).is_true()


func test_no_activity_keeps_all_hiding() -> void:
	# Fresh scenario: no brigade has moved/fought yet (turn 1) → every maneuver target stays "hiding".
	GameState._rebuild_ijfs_state()
	GameState._update_maneuver_posture()
	var checked := false
	for target_value in GameState.ijfs_state.targets:
		var target: IjfsTarget = target_value
		if target.category == "Maneuver Units":
			assert_str(target.posture).is_equal("hiding")
			checked = true
	assert_bool(checked).is_true()
