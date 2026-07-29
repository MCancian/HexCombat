## Verifies MobilizationResolver (plan 0029 Tier A2): brigades leave mobilization on their release
## turn, fall back to a nearby hex when their garrison is overrun, and stay pending when nowhere is
## available. Pure — own fixtures, no autoload, no dice. Returns MobilizationSummary directly
## (plan 0044: compute-only resolver, mutations in ForceTransitions).
extends GdUnitTestSuite


func _brigade(id: String, battalions: int) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = id
	brigade.team = Brigade.Team.GREEN
	brigade.nato_type = "reserve"
	var battalion := Battalion.new()
	battalion.type = "Infantry Battalion (Reserve)"
	battalion.qty = battalions
	brigade.composition = [battalion] as Array[Battalion]
	return brigade


func _state() -> MobilizationState:
	var state := MobilizationState.new()
	state.pending = [
		{"brigade_id": "BDE-911", "garrison_hex": "hex_1_1", "release_turn": 4},
		{"brigade_id": "BDE-912", "garrison_hex": "hex_2_2", "release_turn": 6},
	]
	return state


func _brigades() -> Dictionary:
	return {"BDE-911": _brigade("BDE-911", 3), "BDE-912": _brigade("BDE-912", 4)}


func _garrison_available() -> Callable:
	return func(garrison_hex: String) -> String: return garrison_hex


func test_nothing_releases_before_the_release_turn() -> void:
	var state := _state()
	var summary := MobilizationResolver.resolve(state, 3, _brigades(), _garrison_available())
	assert_array(summary.arrivals).is_empty()
	assert_int(summary.battalions_arrived).is_equal(0)
	assert_int(summary.pending_brigades).is_equal(2)
	assert_int(summary.pending_battalions).is_equal(7)
	# Resolver is compute-only: state unchanged.
	assert_int(state.pending.size()).is_equal(2)


func test_release_turn_puts_the_brigade_on_its_garrison_hex() -> void:
	var state := _state()
	var summary := MobilizationResolver.resolve(state, 4, _brigades(), _garrison_available())
	assert_int(summary.arrivals.size()).is_equal(1)
	var arrival: Dictionary = summary.arrivals[0]
	assert_str(String(arrival["brigade_id"])).is_equal("BDE-911")
	assert_str(String(arrival["hex_id"])).is_equal("hex_1_1")
	assert_int(int(arrival["battalions"])).is_equal(3)
	assert_bool(bool(arrival["displaced"])).is_false()
	assert_int(summary.battalions_arrived).is_equal(3)
	assert_int(summary.pending_brigades).is_equal(1)
	assert_int(summary.pending_battalions).is_equal(4)
	# State unchanged (compute-only).
	assert_int(state.released.size()).is_equal(0)


func test_a_late_turn_releases_every_overdue_brigade() -> void:
	var state := _state()
	var summary := MobilizationResolver.resolve(state, 9, _brigades(), _garrison_available())
	assert_int(summary.arrivals.size()).is_equal(2)
	assert_int(summary.battalions_arrived).is_equal(7)
	# State unchanged (compute-only).
	assert_int(state.pending.size()).is_equal(2)


func test_overrun_garrison_displaces_the_arrival() -> void:
	var state := _state()
	var fallback := func(_garrison_hex: String) -> String: return "hex_5_5"
	var summary := MobilizationResolver.resolve(state, 4, _brigades(), fallback)
	var arrival: Dictionary = summary.arrivals[0]
	assert_str(String(arrival["hex_id"])).is_equal("hex_5_5")
	assert_bool(bool(arrival["displaced"])).is_true()
	# State unchanged (compute-only).
	assert_int(state.released.size()).is_equal(0)


func test_no_arrival_hex_defers_instead_of_losing_the_brigade() -> void:
	var state := _state()
	var nowhere := func(_garrison_hex: String) -> String: return ""
	var summary := MobilizationResolver.resolve(state, 4, _brigades(), nowhere)
	assert_array(summary.arrivals).is_empty()
	assert_array(summary.deferred).contains(["BDE-911"])
	# State unchanged (compute-only).
	assert_int(state.pending.size()).is_equal(2)
	assert_int(summary.pending_battalions).is_equal(7)


func test_null_state_is_an_inert_phase() -> void:
	var summary := MobilizationResolver.resolve(null, 10, _brigades(), _garrison_available())
	assert_array(summary.arrivals).is_empty()
	assert_int(summary.pending_brigades).is_equal(0)


# --- arrival-hex search -------------------------------------------------------------------------

func _chain_neighbors() -> Callable:
	var chain := {"a": ["b"], "b": ["a", "c"], "c": ["b", "d"], "d": ["c"]}
	return func(hex_id: String) -> Array: return chain.get(hex_id, [])


func test_arrival_prefers_the_garrison_hex() -> void:
	var hex_id := MobilizationResolver.find_arrival_hex(
		"a", _chain_neighbors(), func(_h: String) -> bool: return true)
	assert_str(hex_id).is_equal("a")


func test_arrival_falls_back_to_the_nearest_available_hex() -> void:
	var available := func(hex_id: String) -> bool: return hex_id == "c" or hex_id == "d"
	var hex_id := MobilizationResolver.find_arrival_hex("a", _chain_neighbors(), available)
	assert_str(hex_id).is_equal("c")


func test_arrival_returns_empty_when_nothing_is_available() -> void:
	var hex_id := MobilizationResolver.find_arrival_hex(
		"a", _chain_neighbors(), func(_h: String) -> bool: return false)
	assert_str(hex_id).is_equal("")


func test_arrival_search_is_bounded_by_max_rings() -> void:
	var available := func(hex_id: String) -> bool: return hex_id == "d"
	assert_str(MobilizationResolver.find_arrival_hex("a", _chain_neighbors(), available, 2)).is_equal("")
	assert_str(MobilizationResolver.find_arrival_hex("a", _chain_neighbors(), available, 3)).is_equal("d")
