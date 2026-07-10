# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_play_turn.gd
extends SceneTree

# Scripted-turn shape lives in tools/GoldenScript.gd (shared by all golden validators).
const RED_MOVER_ID := GoldenScript.RED_MOVER_ID
const GREEN_DEFENDER_ID := GoldenScript.GREEN_DEFENDER_ID
const START_HEX := GoldenScript.START_HEX
const TARGET_HEX := GoldenScript.TARGET_HEX
const DICE_SEED := GoldenScript.SEED
const PHASE_PLANNING := 0
const PHASE_END := 2

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless play_turn validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null:
		_fail("Autoload GameData was not found on the SceneTree root")
	if GameState == null:
		_fail("Autoload GameState was not found on the SceneTree root")
	if not _failures.is_empty():
		_finish()
		return

	# Path A — hand-rolled sequence (behavioral oracle).
	var snap_manual: Dictionary = _run_path_a()

	# Path B — play_turn façade.
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	var result: TurnResult = GameState.play_turn(
		[{"kind": "move", "brigade_id": RED_MOVER_ID, "target_hex": TARGET_HEX, "mode": Movement.MODE_TACTICAL}],
		[], SeededDice.new(DICE_SEED))
	if result == null:
		_fail("play_turn returned null")
		_finish()
		return
	var snap_facade: Dictionary = GameData.snapshot_state()

	# Assert equality: façade must be byte-identical to manual sequence.
	_assert_dicts_equal("snapshot equality", snap_manual, snap_facade)

	# Assert result fields.
	_assert_equal_int("result.turn_number", result.turn_number, 1)
	if TARGET_HEX not in result.contested_hexes:
		_fail("result.contested_hexes missing %s: %s" % [TARGET_HEX, str(result.contested_hexes)])

	# Event-log assertions.
	if result.events.is_empty():
		_fail("result.events is empty")
	elif not _has_event(result.events, "move", func(e): return e.data["brigade_id"] == RED_MOVER_ID and e.data["target_hex"] == TARGET_HEX):
		_fail("result.events missing move for %s -> %s" % [RED_MOVER_ID, TARGET_HEX])
	elif not _has_event(result.events, "combat", func(e): return e.hex_id == TARGET_HEX):
		_fail("result.events missing combat at %s" % TARGET_HEX)

	# Determinism: run Path B a second time.
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	var result2: TurnResult = GameState.play_turn(
		[{"kind": "move", "brigade_id": RED_MOVER_ID, "target_hex": TARGET_HEX, "mode": Movement.MODE_TACTICAL}],
		[], SeededDice.new(DICE_SEED))
	var snap_facade2: Dictionary = GameData.snapshot_state()
	_assert_dicts_equal("determinism snapshot", snap_facade, snap_facade2)
	_assert_dicts_equal("determinism result", result.to_dict(), result2.to_dict())

	# Fail-loud contract: play_turn outside PLANNING returns null (the prior
	# play_turn left the state machine in Phase.END). The emitted push_error is
	# expected and harmless — the gate only fails validators on "SCRIPT ERROR".
	var bad: TurnResult = GameState.play_turn([], [], SeededDice.new(DICE_SEED))
	if bad != null:
		_fail("play_turn outside PLANNING must return null")

	_finish()


func _run_path_a() -> Dictionary:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	GameState.add_move_order(Brigade.Team.RED, RED_MOVER_ID, TARGET_HEX, Movement.MODE_TACTICAL)
	GameState.resolve_turn(SeededDice.new(DICE_SEED))
	return GameData.snapshot_state()


func _assert_dicts_equal(label: String, a: Dictionary, b: Dictionary) -> void:
	if a != b:
		_fail("%s: expected %s, got %s" % [label, str(a), str(b)])


func _assert_equal_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])

func _has_event(events: Array, kind: String, pred: Callable) -> bool:
	for e in events:
		var te: TurnEvent = e
		if te.kind == kind and pred.call(te):
			return true
	return false


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: headless play_turn validation succeeded (seed=%d)" % DICE_SEED)
		quit(0)
		return

	print("FAIL: headless play_turn validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
