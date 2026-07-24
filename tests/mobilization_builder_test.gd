## Verifies MobilizationStateBuilder (plan 0029 Tier A2): WHICH Green brigades start off-map in
## mobilization and WHEN each is due. Pure — builds its own Brigade/placement fixtures, touches no
## autoload and no dice.
extends GdUnitTestSuite


func _brigade(id: String, nato_type: String, team: Brigade.Team = Brigade.Team.GREEN) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = id
	brigade.name = id
	brigade.team = team
	brigade.nato_type = nato_type
	var battalion := Battalion.new()
	battalion.type = "Infantry Battalion (Reserve)"
	battalion.qty = 3
	brigade.composition = [battalion] as Array[Battalion]
	return brigade


## Two reserve brigades, one armor brigade, one RED brigade — only the reserves are eligible.
func _fixture() -> Dictionary:
	var brigades := {
		"BDE-912": _brigade("BDE-912", "reserve"),
		"BDE-911": _brigade("BDE-911", "reserve"),
		"BDE-542": _brigade("BDE-542", "armor"),
		"PLA-1": _brigade("PLA-1", "reserve", Brigade.Team.RED),
	}
	var placements: Array = [
		{"brigade_id": "BDE-912", "team": "Green", "hex": "hex_2_2"},
		{"brigade_id": "BDE-911", "team": "Green", "hex": "hex_1_1"},
		{"brigade_id": "BDE-542", "team": "Green", "hex": "hex_3_3"},
		{"brigade_id": "PLA-1", "team": "Red", "hex": "hex_9_9"},
	]
	return {"brigades": brigades, "placements": placements}


func test_zero_held_back_is_the_pre_plan_laydown() -> void:
	var fixture := _fixture()
	var held := MobilizationStateBuilder.select_held_back(
		{"held_back_brigades": 0}, fixture["placements"], fixture["brigades"])
	assert_array(held).is_empty()
	# An absent block behaves the same way — every scenario without the key is untouched.
	assert_array(MobilizationStateBuilder.select_held_back({}, fixture["placements"], fixture["brigades"])).is_empty()


func test_selects_eligible_types_only_in_brigade_id_order() -> void:
	var fixture := _fixture()
	var held := MobilizationStateBuilder.select_held_back(
		{"held_back_brigades": 2}, fixture["placements"], fixture["brigades"])
	assert_int(held.size()).is_equal(2)
	# Sorted by brigade_id, NOT placement order — release order must not depend on file ordering.
	assert_str(String(held[0]["brigade_id"])).is_equal("BDE-911")
	assert_str(String(held[1]["brigade_id"])).is_equal("BDE-912")
	# The garrison hex travels with the entry: it is where the brigade arrives on release.
	assert_str(String(held[0]["garrison_hex"])).is_equal("hex_1_1")


func test_non_reserve_and_red_brigades_are_never_held_back() -> void:
	var fixture := _fixture()
	var held := MobilizationStateBuilder.select_held_back(
		{"held_back_brigades": 4}, fixture["placements"], fixture["brigades"])
	# Only the 2 Green reserve brigades are eligible; the armor brigade and the Red brigade are not,
	# so the request clamps rather than reaching for ineligible units.
	assert_int(held.size()).is_equal(2)


func test_brigade_types_opens_the_pool() -> void:
	var fixture := _fixture()
	var held := MobilizationStateBuilder.select_held_back(
		{"held_back_brigades": 3, "brigade_types": ["reserve", "armor"]},
		fixture["placements"], fixture["brigades"])
	assert_int(held.size()).is_equal(3)
	assert_str(String(held[0]["brigade_id"])).is_equal("BDE-542")


func test_schedule_releases_in_batches_at_the_configured_cadence() -> void:
	var held: Array = [
		{"brigade_id": "A", "garrison_hex": "hex_1_1"},
		{"brigade_id": "B", "garrison_hex": "hex_2_2"},
		{"brigade_id": "C", "garrison_hex": "hex_3_3"},
		{"brigade_id": "D", "garrison_hex": "hex_4_4"},
		{"brigade_id": "E", "garrison_hex": "hex_5_5"},
	]
	var state := MobilizationStateBuilder.build(
		{"first_release_turn": 4, "release_interval_turns": 2, "brigades_per_release": 2}, held)
	assert_int(state.pending.size()).is_equal(5)
	assert_int(int(state.pending[0]["release_turn"])).is_equal(4)
	assert_int(int(state.pending[1]["release_turn"])).is_equal(4)
	assert_int(int(state.pending[2]["release_turn"])).is_equal(6)
	assert_int(int(state.pending[3]["release_turn"])).is_equal(6)
	assert_int(int(state.pending[4]["release_turn"])).is_equal(8)
	assert_array(state.released).is_empty()


func test_empty_holdback_builds_an_inert_state() -> void:
	var state := MobilizationStateBuilder.build({"held_back_brigades": 0}, [])
	assert_array(state.pending).is_empty()
	assert_int(state.pending_battalions({})).is_equal(0)
