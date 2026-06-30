## Verifies GameState._taiwan_battalion_census counts PRESENT (landed) battalions, not the full OOB
## composition (refactor_audit item 2b). A brigade's hex_id is set as soon as its first BN lands, but
## battalions still waiting on ships (tracked in ship_reserve) must NOT count toward "on Taiwan". Pure
## board read — no dice.
extends GdUnitTestSuite


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func _red_reserve_entry() -> Dictionary:
	# A Red (PLA) brigade staged at sea in the ship reserve.
	assert_int(GameState.ship_reserve.size()).is_greater(0)
	return GameState.ship_reserve[0]


func test_partially_landed_brigade_counts_only_landed_bns() -> void:
	var entry := _red_reserve_entry()
	var brigade_id := String(entry["brigade_id"])
	var brigade: Brigade = GameData.get_brigade(brigade_id)
	var total := brigade.get_battalion_count()
	var reserve_bns: Array = entry["bns"]
	# Nothing landed yet: the reserve holds the whole brigade, hex_id empty → contributes 0.
	assert_int(reserve_bns.size()).is_equal(total)
	var baseline_red := int(GameState._taiwan_battalion_census()["red"])

	# Land HALF: set the brigade's hex and drop half its BNs from the at-sea reserve.
	GameData.set_brigade_hex(brigade_id, String(entry["beach_hex"]))
	var keep_at_sea := int(reserve_bns.size() / 2)
	assert_int(keep_at_sea).is_greater(0)  # need a real partial-landing to exercise the fix
	var remaining: Array = []
	for i in range(keep_at_sea):
		remaining.append(reserve_bns[i])
	entry["bns"] = remaining

	var after_red := int(GameState._taiwan_battalion_census()["red"])
	# Present landed = total - still-at-sea. The naive (buggy) count would have added the full `total`.
	assert_int(after_red - baseline_red).is_equal(total - keep_at_sea)
	assert_int(after_red - baseline_red).is_less(total)


func test_fully_landed_brigade_counts_full_composition() -> void:
	var entry := _red_reserve_entry()
	var brigade_id := String(entry["brigade_id"])
	var brigade: Brigade = GameData.get_brigade(brigade_id)
	var total := brigade.get_battalion_count()
	var baseline_red := int(GameState._taiwan_battalion_census()["red"])

	# Land EVERYTHING: set hex, empty the reserve entry's BN list.
	GameData.set_brigade_hex(brigade_id, String(entry["beach_hex"]))
	entry["bns"] = []

	var after_red := int(GameState._taiwan_battalion_census()["red"])
	assert_int(after_red - baseline_red).is_equal(total)
