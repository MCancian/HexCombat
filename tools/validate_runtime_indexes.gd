# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_runtime_indexes.gd
extends SceneTree

const DICE_SEED := 20260624
const RED_MOVER_ID := "PLA-71-2-Amphibious"
const TARGET_HEX := "hex_43_16"

var _h := ValidatorHarness.new("runtime index consistency")
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Runtime index consistency validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null:
		_h.fail("Autoload GameData was not found on the SceneTree root")
	if GameState == null:
		_h.fail("Autoload GameState was not found on the SceneTree root")
	if not _h.failures.is_empty():
		_h.finish(self)
		return

	_step_initial_load()
	_step_after_offload()
	_step_move_and_remove()
	_step_full_turn()
	_step_reload_restores()

	print("--- Summary ---")
	_h.pass_body = func() -> String: return "runtime index consistency validated across all %d scenarios\nPASS: runtime index consistency validated" % 5
	_h.fail_header = func() -> String: return "%d violation(s) detected\nFAIL: runtime index consistency found %d issue(s):" % [_h.failures.size(), _h.failures.size()]
	_h.finish(self)


func _assert_indexes_healthy(scenario: String) -> void:
	var violations: Array[String] = GameData.validate_runtime_indexes()
	if not violations.is_empty():
		var details: String = "; ".join(violations)
		_h.fail("%s: indexes inconsistent: %s" % [scenario, details])


func _step_initial_load() -> void:
	print("--- 1. Initial load ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	_assert_indexes_healthy("after initial load")
	if _h.failures.is_empty():
		print("  OK")


func _step_after_offload() -> void:
	print("--- 2. After offload (landed brigades) ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_assert_indexes_healthy("after offload")
	if _h.failures.is_empty():
		print("  OK")


func _step_move_and_remove() -> void:
	print("--- 3. Manual move and remove ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))

	var red_brigade: Brigade = GameData.get_brigade(RED_MOVER_ID)
	if red_brigade == null:
		_h.fail("Missing Red mover: %s" % RED_MOVER_ID)
		return
	var start_hex: String = red_brigade.hex_id
	if start_hex == "":
		_h.fail("Red mover not placed after offload")
		return

	var neighbors: Array = GameData.get_neighbors(start_hex)
	if neighbors.is_empty():
		_h.fail("No neighbors for %s" % start_hex)
		return
	var adjacent: String = String(neighbors[0])

	GameData.set_brigade_hex(RED_MOVER_ID, adjacent)
	_assert_indexes_healthy("after moving to adjacent hex")
	if not _h.failures.is_empty():
		return

	GameData.remove_brigade_from_map(RED_MOVER_ID)
	_assert_indexes_healthy("after remove from map")
	if _h.failures.is_empty():
		print("  OK")


func _step_full_turn() -> void:
	print("--- 4. Full combat turn ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))

	GameState.add_move_order(Brigade.Team.RED, RED_MOVER_ID, TARGET_HEX, Movement.MODE_TACTICAL)
	GameState.resolve_turn(SeededDice.new(DICE_SEED))
	_assert_indexes_healthy("after full combat turn")
	if _h.failures.is_empty():
		print("  OK")


func _step_reload_restores() -> void:
	print("--- 5. Reload restores clean state ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	_assert_indexes_healthy("after reload restoring clean state")



