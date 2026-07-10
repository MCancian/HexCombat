extends GdUnitTestSuite

# hex_44_15 (beach 2) is ungarrisoned under the full-defense laydown; hex_44_16 now hosts
# BDE-GDU, which would shadow the red brigade in click-selection.
const RED_BRIGADE_ID := "PLA-72-5-Amphibious"
const RED_START_HEX := "hex_44_15"


func test_selecting_placed_hex_emits_hex_and_brigade_signals() -> void:
	var runner := scene_runner("res://scenes/Main.tscn")
	await await_idle_frame()
	var controller := runner.scene() as GameController
	GameData.set_brigade_hex(RED_BRIGADE_ID, RED_START_HEX)
	controller.hex_map.render_brigade_markers()
	monitor_signals(EventBus, false)

	controller._on_hex_clicked(RED_START_HEX)

	assert_signal(EventBus).wait_until(5000).is_emitted("hex_selected", RED_START_HEX)
	assert_signal(EventBus).wait_until(5000).is_emitted("brigade_selected", RED_BRIGADE_ID)
	assert_str(controller.selected_hex).is_equal(RED_START_HEX)
	assert_str(controller.selected_brigade).is_equal(RED_BRIGADE_ID)


func test_selecting_empty_hex_emits_hex_but_not_brigade_signal() -> void:
	var runner := scene_runner("res://scenes/Main.tscn")
	await await_idle_frame()
	var controller := runner.scene() as GameController
	var empty_hex_id := _find_empty_hex_id()
	monitor_signals(EventBus, false)

	controller._on_hex_clicked(empty_hex_id)

	assert_signal(EventBus).wait_until(5000).is_emitted("hex_selected", empty_hex_id)
	assert_signal(EventBus).wait_until(100).is_not_emitted("brigade_selected")
	assert_str(controller.selected_hex).is_equal(empty_hex_id)
	assert_str(controller.selected_brigade).is_empty()


func _find_empty_hex_id() -> String:
	for hex in GameData.hexes:
		var hex_id := String(hex.id)
		if GameData.get_brigades_in_hex(hex_id).is_empty():
			return hex_id
	push_error("Test fixture has no empty hex")
	return ""
