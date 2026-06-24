# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_dos_consumption.gd
extends SceneTree

const DICE_SEED := 1
const INITIAL_POOL_TONS := 15000.0
const IDLE_CONSUMPTION_TONS := 2800
const MOVED_CONSUMPTION_TONS := 5600

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== DOS consumption validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null:
		_fail("Autoload GameData was not found on the SceneTree root")
	if GameState == null:
		_fail("Autoload GameState was not found on the SceneTree root")
	if not _failures.is_empty():
		_finish()
		return

	_validate_idle_consumption()
	_validate_activity_consumption()
	_validate_multi_turn_drain()
	_validate_clamp_at_zero()
	_validate_full_resolve_turn_hook()
	_finish()


func _validate_idle_consumption() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	_assert_equal_float("initial supply pool", GameState.supply_state.current_dos_tons, INITIAL_POOL_TONS)
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_assert_equal_int("Red brigades on-map after landing", _red_brigades_on_map(), 4)

	var summary: Dictionary = GameState.resolve_supply_turn()
	_assert_equal_int("idle unit_count", int(summary["unit_count"]), 36)
	_assert_equal_int("idle mechanized_unit_count", int(summary["mechanized_unit_count"]), 20)
	_assert_equal_int("idle non_mechanized_unit_count", int(summary["non_mechanized_unit_count"]), 16)
	_assert_equal_int("idle red_dos_consumed_tons", int(summary["red_dos_consumed_tons"]), IDLE_CONSUMPTION_TONS)
	_assert_equal_float("idle pool_after", float(summary["pool_after"]), 12200.0)
	_assert_true("idle summary applied", bool(summary["applied"]))
	_assert_equal_int("idle day_history size", GameState.supply_state.day_history.size(), 1)


func _validate_activity_consumption() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_assert_equal_int("activity Red brigades on-map after landing", _red_brigades_on_map(), 4)
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.RED and not brigade.destroyed and not brigade.hex_id.is_empty():
			brigade.moved_this_turn = true

	var summary: Dictionary = GameState.resolve_supply_turn()
	_assert_true("activity consumption greater than idle", int(summary["red_dos_consumed_tons"]) > IDLE_CONSUMPTION_TONS)
	_assert_equal_int("activity red_dos_consumed_tons", int(summary["red_dos_consumed_tons"]), MOVED_CONSUMPTION_TONS)


# Multi-turn drain: the pool strictly decreases each supply turn and day_history grows.
# (Ported from the supply_turn_test GdUnit cases — kept as a headless validator because the
# GdUnit suite hit a Godot 4.7 teardown heap-corruption when this suite ran alongside the others;
# the same assertions run cleanly here in an isolated SceneTree process.)
func _validate_multi_turn_drain() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	var start_pool: float = GameState.supply_state.current_dos_tons
	GameState.resolve_supply_turn()
	var after_first: float = GameState.supply_state.current_dos_tons
	GameState.turn_number += 1
	GameState.resolve_supply_turn()
	var after_second: float = GameState.supply_state.current_dos_tons
	_assert_true("multi-turn first drain below start", after_first < start_pool)
	_assert_true("multi-turn second drain below first", after_second < after_first)
	_assert_equal_int("multi-turn day_history size", GameState.supply_state.day_history.size(), 2)


# The pool clamps at zero (never negative) when consumption exceeds the remaining supply.
func _validate_clamp_at_zero() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	GameState.supply_state.current_dos_tons = 10.0
	GameState.resolve_supply_turn()
	_assert_equal_float("pool clamps at zero", GameState.supply_state.current_dos_tons, 0.0)


# The resolve_turn() hook deducts supply each turn (Turn 1 lands Red via offload, then consumes).
func _validate_full_resolve_turn_hook() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_turn(SeededDice.new(DICE_SEED))
	_assert_true("full resolve_turn decremented pool", GameState.supply_state.current_dos_tons < INITIAL_POOL_TONS)
	_assert_equal_int("full resolve_turn day_history size", GameState.supply_state.day_history.size(), 1)


func _red_brigades_on_map() -> int:
	var count := 0
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.RED and not brigade.destroyed and not brigade.hex_id.is_empty():
			count += 1
	return count


func _assert_true(label: String, value: bool) -> void:
	if not value:
		_fail("%s: expected true" % label)


func _assert_equal_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])


func _assert_equal_float(label: String, actual: float, expected: float) -> void:
	if not is_equal_approx(actual, expected):
		_fail("%s: expected %.2f, got %.2f" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: DOS consumption validation succeeded")
		quit(0)
		return

	print("FAIL: DOS consumption validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
