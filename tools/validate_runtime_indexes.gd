# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_runtime_indexes.gd
extends SceneTree

const DICE_SEED := 20260624
const RED_MOVER_ID := "PLA-71-2-Amphibious"
const TARGET_HEX := "hex_43_16"

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Runtime index consistency validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null:
		_fail("Autoload GameData was not found on the SceneTree root")
	if GameState == null:
		_fail("Autoload GameState was not found on the SceneTree root")
	if not _failures.is_empty():
		_finish()
		return

	_step_initial_load()
	_step_after_offload()
	_step_move_and_remove()
	_step_full_turn()
	_step_negative_test()
	_step_reload_restores()

	print("--- Summary ---")
	if _failures.is_empty():
		print("PASS: runtime index consistency validated across all %d scenarios" % 6)
	else:
		print("FAIL: %d violation(s) detected" % _failures.size())
	_finish()


func _assert_indexes_healthy(scenario: String) -> void:
	var violations: Array[String] = GameData.validate_runtime_indexes()
	if not violations.is_empty():
		var details: String = "; ".join(violations)
		_fail("%s: indexes inconsistent: %s" % [scenario, details])


func _step_initial_load() -> void:
	print("--- 1. Initial load ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	_assert_indexes_healthy("after initial load")
	if _failures.is_empty():
		print("  OK")


func _step_after_offload() -> void:
	print("--- 2. After offload (landed brigades) ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_assert_indexes_healthy("after offload")
	if _failures.is_empty():
		print("  OK")


func _step_move_and_remove() -> void:
	print("--- 3. Manual move and remove ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))

	var red_brigade: Brigade = GameData.get_brigade(RED_MOVER_ID)
	if red_brigade == null:
		_fail("Missing Red mover: %s" % RED_MOVER_ID)
		return
	var start_hex: String = red_brigade.hex_id
	if start_hex == "":
		_fail("Red mover not placed after offload")
		return

	var neighbors: Array = GameData.get_neighbors(start_hex)
	if neighbors.is_empty():
		_fail("No neighbors for %s" % start_hex)
		return
	var adjacent: String = String(neighbors[0])

	GameData.set_brigade_hex(RED_MOVER_ID, adjacent)
	_assert_indexes_healthy("after moving to adjacent hex")
	if not _failures.is_empty():
		return

	GameData.remove_brigade_from_map(RED_MOVER_ID)
	_assert_indexes_healthy("after remove from map")
	if _failures.is_empty():
		print("  OK")


func _step_full_turn() -> void:
	print("--- 4. Full combat turn ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))

	GameState.add_move_order(Brigade.Team.RED, RED_MOVER_ID, TARGET_HEX, Movement.MODE_TACTICAL)
	GameState.resolve_turn(SeededDice.new(DICE_SEED))
	_assert_indexes_healthy("after full combat turn")
	if _failures.is_empty():
		print("  OK")


func _step_negative_test() -> void:
	print("--- 5. Negative test (deliberate corruption) ---")
	GameData.load_all()
	GameState.reset_to_scenario()

	var ghost_id := "__ghost__"
	# Corrupt by forcing a bogus brigade id into a hex bucket.
	var target_bucket: Array = GameData.brigades_by_hex.get(TARGET_HEX, [])
	target_bucket.append(ghost_id)
	GameData.brigades_by_hex[TARGET_HEX] = target_bucket

	var violations: Array[String] = GameData.validate_runtime_indexes()
	if violations.is_empty():
		_fail("negative test: expected violations for __ghost__ but got none")
		return

	var found_ghost := false
	for v in violations:
		if "__ghost__" in v:
			found_ghost = true
			break
	if not found_ghost:
		_fail("negative test: violations did not mention __ghost__: %s" % "; ".join(violations))
	else:
		print("  OK (detected corruption: %s)" % "; ".join(violations))


func _step_reload_restores() -> void:
	print("--- 6. Reload restores clean state ---")
	GameData.load_all()
	GameState.reset_to_scenario()
	_assert_indexes_healthy("after reload restoring clean state")
	if _failures.is_empty():
		print("  OK")


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: runtime index consistency validated")
		quit(0)
		return

	print("FAIL: runtime index consistency found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
