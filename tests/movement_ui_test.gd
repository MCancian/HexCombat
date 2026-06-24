extends GdUnitTestSuite

const RED_BRIGADE_ID := "PLA-71-2-Amphibious"
const RED_START_HEX := "hex_44_16"


func before_test() -> void:
	_reset_fixture()


func after_test() -> void:
	_reset_fixture()


func test_selecting_brigade_emits_reachable_hexes() -> void:
	var runner := scene_runner("res://scenes/Main.tscn")
	await await_idle_frame()
	var controller := runner.scene() as GameController
	monitor_signals(EventBus, false)

	controller._on_hex_clicked(RED_START_HEX)

	assert_signal(EventBus).is_emitted("reachable_hexes_changed")
	assert_array(controller.current_reachable).is_not_empty()


func test_clicking_reachable_target_issues_move_order() -> void:
	var runner := scene_runner("res://scenes/Main.tscn")
	await await_idle_frame()
	var controller := runner.scene() as GameController
	controller._on_hex_clicked(RED_START_HEX)
	var target_hex := _first_reachable_target(controller, RED_START_HEX)
	var order_count_before := GameState.orders_for(Brigade.Team.RED).size()
	monitor_signals(EventBus, false)

	controller._on_hex_clicked(target_hex)

	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(order_count_before + 1)
	assert_signal(EventBus).is_emitted("move_order_issued", RED_BRIGADE_ID, target_hex, Movement.MODE_TACTICAL)


func test_administrative_mode_reaches_more_hexes_than_tactical() -> void:
	var runner := scene_runner("res://scenes/Main.tscn")
	await await_idle_frame()
	var controller := runner.scene() as GameController

	controller._on_hex_clicked(RED_START_HEX)
	var tactical_count := controller.current_reachable.size()
	controller.set_move_mode(Movement.MODE_ADMINISTRATIVE)
	controller._on_hex_clicked(RED_START_HEX)

	assert_int(controller.current_reachable.size()).is_greater(tactical_count)


func test_end_turn_applies_order_and_advances_turn() -> void:
	var runner := scene_runner("res://scenes/Main.tscn")
	await await_idle_frame()
	var controller := runner.scene() as GameController
	controller._on_hex_clicked(RED_START_HEX)
	var target_hex := _first_reachable_target(controller, RED_START_HEX)
	controller._on_hex_clicked(target_hex)
	var turn_before := GameState.turn_number
	monitor_signals(EventBus, false)

	controller.end_turn()

	var brigade: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	assert_int(GameState.turn_number).is_equal(turn_before + 1)
	assert_str(brigade.hex_id).is_equal(target_hex)
	assert_signal(EventBus).is_emitted("turn_advanced", GameState.turn_number)


func _first_reachable_target(controller: GameController, current_hex: String) -> String:
	for reachable_hex in controller.current_reachable:
		var hex_id := String(reachable_hex)
		if hex_id != current_hex:
			return hex_id
	push_error("Test fixture has no reachable target from %s" % current_hex)
	return ""


func _reset_fixture() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameData.set_brigade_hex(RED_BRIGADE_ID, RED_START_HEX)
