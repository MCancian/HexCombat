## Verifies GameState._apply_ijfs_maneuver_casualties removes struck battalions from the OOB
## (overnight item 2d): IJFS air/missile kills reduce the brigades that fight in ground combat.
extends GdUnitTestSuite


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func _first_green_brigade() -> Brigade:
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.GREEN and not brigade.composition.is_empty():
			return brigade
	return null


func _qty_of(brigade: Brigade, unit_type: String) -> int:
	for battalion in brigade.composition:
		if battalion.type == unit_type:
			return battalion.qty
	return 0


func test_single_casualty_decrements_qty() -> void:
	var brigade := _first_green_brigade()
	var unit_type := String(brigade.composition[0].type)
	var before := _qty_of(brigade, unit_type)
	GameState.last_ijfs_writeback = IjfsWriteback.from_dict({"maneuver_casualties": [
		{"brigade_id": brigade.id, "unit_type": unit_type, "battalion_id": "%s-MU-1" % brigade.id},
	]})
	GameState._apply_ijfs_maneuver_casualties()
	assert_int(_qty_of(brigade, unit_type)).is_equal(before - 1)


func test_qty_capped_at_zero_and_brigade_destroyed_when_depleted() -> void:
	var brigade := _first_green_brigade()
	# One casualty per battalion instance across the whole brigade, plus extra to test the cap.
	var casualties: Array = []
	var total := 0
	for battalion in brigade.composition:
		total += battalion.qty
		for i in range(battalion.qty + 2):  # +2 over-applies to exercise the cap
			casualties.append({"brigade_id": brigade.id, "unit_type": battalion.type})
	GameState.last_ijfs_writeback = IjfsWriteback.from_dict({"maneuver_casualties": casualties})
	GameState._apply_ijfs_maneuver_casualties()
	for battalion in brigade.composition:
		assert_int(battalion.qty).is_equal(0)
	assert_bool(brigade.destroyed).is_true()


func test_unknown_brigade_or_type_is_ignored() -> void:
	GameState.last_ijfs_writeback = IjfsWriteback.from_dict({"maneuver_casualties": [
		{"brigade_id": "NO-SUCH-BDE", "unit_type": "Whatever Battalion"},
		{"brigade_id": _first_green_brigade().id, "unit_type": "Nonexistent Type Battalion"},
	]})
	# Should not crash and should not change any qty for the existing brigade.
	var brigade := _first_green_brigade()
	var unit_type := String(brigade.composition[0].type)
	var before := _qty_of(brigade, unit_type)
	GameState._apply_ijfs_maneuver_casualties()
	assert_int(_qty_of(brigade, unit_type)).is_equal(before)
