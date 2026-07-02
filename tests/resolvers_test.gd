extends GdUnitTestSuite

## Isolation tests for the pure resolver classes extracted from GameState (refactor_audit
## item 10, first slice). These deliberately construct inputs by hand — no GameData/GameState
## autoload involvement — proving the resolver interface's whole point: each phase's logic is
## testable without booting the game.


# --- SupplyResolver ------------------------------------------------------------------------------

func _one_infantry_unit() -> Array:
	return [{"brigade_id": "BDE-T1", "type": "Infantry Battalion", "brigade_type": "infantry"}]


func test_supply_resolver_deducts_pool_and_records_history() -> void:
	var state := SupplyState.new()
	state.current_dos_tons = 1000.0
	state.day_history = []

	var summary := SupplyResolver.resolve(state, _one_infantry_unit(), [], [], 1)

	var consumed := float(summary["red_dos_consumed_tons"])
	assert_bool(consumed > 0.0).is_true()
	assert_bool(bool(summary["applied"])).is_true()
	assert_float(float(summary["pool_before"])).is_equal_approx(1000.0, 0.0001)
	assert_float(float(summary["pool_after"])).is_equal_approx(1000.0 - consumed, 0.0001)
	assert_float(state.current_dos_tons).is_equal_approx(1000.0 - consumed, 0.0001)
	assert_int(state.day_history.size()).is_equal(1)
	assert_dict(state.day_history[0]).is_equal(summary)


func test_supply_resolver_pool_floors_at_zero() -> void:
	var state := SupplyState.new()
	state.current_dos_tons = 1.0  # far less than one BN-day of consumption
	state.day_history = []

	var summary := SupplyResolver.resolve(state, _one_infantry_unit(), [], [], 1)

	assert_float(state.current_dos_tons).is_equal_approx(0.0, 0.0001)
	assert_float(float(summary["pool_after"])).is_equal_approx(0.0, 0.0001)


# --- FrontlineResolver ---------------------------------------------------------------------------

func _two_hex_centers() -> Array:
	return [
		{"id": "A", "lat": 23.0, "lon": 120.0},
		{"id": "B", "lat": 23.0, "lon": 121.0},
	]


func _brigade(id: String, hex_id: String) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = id
	brigade.team = Brigade.Team.RED
	brigade.hex_id = hex_id
	return brigade


func test_frontline_resolver_empty_polyline_returns_empty_summary() -> void:
	var summary := FrontlineResolver.resolve([], _two_hex_centers(), [_brigade("u1", "A")])
	assert_array(summary.hex_sequence).is_empty()
	assert_array(summary.affected_brigades).is_empty()
	assert_dict(summary.moves).is_empty()


func test_frontline_resolver_redistributes_only_on_line_brigades() -> void:
	# Line passes A then B; u1 sits on A (affected), u9 sits off-line (untouched).
	var line := [Vector2(23.0, 120.0), Vector2(23.0, 121.0)]
	var brigades := [_brigade("u2", "A"), _brigade("u1", "B"), _brigade("u9", "off_line_hex")]

	var summary := FrontlineResolver.resolve(line, _two_hex_centers(), brigades)

	assert_array(summary.hex_sequence).is_equal(["A", "B"])
	# Affected set is sorted for determinism (u1 before u2 despite input order).
	assert_array(summary.affected_brigades).is_equal(["u1", "u2"])
	assert_dict(summary.moves).is_equal({"u1": "A", "u2": "B"})


func test_frontline_resolver_moves_nothing_itself() -> void:
	var brigade := _brigade("u1", "B")
	var line := [Vector2(23.0, 120.0), Vector2(23.0, 121.0)]
	var summary := FrontlineResolver.resolve(line, _two_hex_centers(), [brigade])
	assert_str(summary.moves["u1"]).is_equal("A")
	# The resolver only reports the move; applying it is the caller's job.
	assert_str(brigade.hex_id).is_equal("B")
