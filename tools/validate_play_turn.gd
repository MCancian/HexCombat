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

var _h := ValidatorHarness.new("headless play_turn validation")
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless play_turn validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null:
		_h.fail("Autoload GameData was not found on the SceneTree root")
	if GameState == null:
		_h.fail("Autoload GameState was not found on the SceneTree root")
	if not _h.failures.is_empty():
		_h.finish(self, " (seed=%d)" % DICE_SEED)
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
		_h.fail("play_turn returned null")
		_h.finish(self, " (seed=%d)" % DICE_SEED)
		return
	var snap_facade: Dictionary = GameData.snapshot_state(GameState.data.pending_battalion_pools())

	# Assert equality: façade must be byte-identical to manual sequence.
	_assert_dicts_equal("snapshot equality", snap_manual, snap_facade)

	# Assert result fields.
	_h.equal_int("result.turn_number", result.turn_number, 1)
	if TARGET_HEX not in result.contested_hexes:
		_h.fail("result.contested_hexes missing %s: %s" % [TARGET_HEX, str(result.contested_hexes)])

	# Air OOB reaches the turn record (plan 0059). This is the end-to-end proof: the ledger is built
	# deep inside IjfsEngine, retained by FiresPhases and read back out by play_turn, and before 0059
	# it was discarded at every one of those hops. A real resolved turn must carry a populated force.
	if result.air_oob.is_empty():
		_h.fail("result.air_oob is empty after a resolved turn — the air OOB is not reaching TurnResult")
	elif not (result.air_oob as Dictionary).has("squadrons"):
		_h.fail("result.air_oob has no squadrons key")
	else:
		# Row SHAPE is checked, not row COUNT. A scenario with no Red air is legitimate and would
		# carry `squadrons: []`; asserting non-empty here would make this validator quietly
		# scenario-dependent, which is how a future no-air excursion would fail for the wrong reason.
		# The `air_oob.is_empty()` check above is the real end-to-end proof that the ledger arrives.
		for row_value in ((result.air_oob as Dictionary)["squadrons"] as Array):
			var row: Dictionary = row_value
			for field in ["squadron_id", "class", "kind", "initial", "alive", "losses_today", "losses_campaign"]:
				if not row.has(field):
					_h.fail("air_oob squadron row missing '%s'" % field)
			if String(row["kind"]) not in ["manned", "unmanned"]:
				_h.fail("air_oob squadron kind is '%s'; expected manned/unmanned" % row["kind"])

	# Event-log assertions.
	if result.events.is_empty():
		_h.fail("result.events is empty")
	elif not _has_event(result.events, "move", func(e): return e.data["brigade_id"] == RED_MOVER_ID and e.data["target_hex"] == TARGET_HEX):
		_h.fail("result.events missing move for %s -> %s" % [RED_MOVER_ID, TARGET_HEX])
	elif not _has_event(result.events, "combat", func(e): return e.hex_id == TARGET_HEX):
		_h.fail("result.events missing combat at %s" % TARGET_HEX)

	# Determinism: run Path B a second time.
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	var result2: TurnResult = GameState.play_turn(
		[{"kind": "move", "brigade_id": RED_MOVER_ID, "target_hex": TARGET_HEX, "mode": Movement.MODE_TACTICAL}],
		[], SeededDice.new(DICE_SEED))
	var snap_facade2: Dictionary = GameData.snapshot_state(GameState.data.pending_battalion_pools())
	_assert_dicts_equal("determinism snapshot", snap_facade, snap_facade2)
	_assert_dicts_equal("determinism result", result.to_dict(), result2.to_dict())

	# Fail-loud contract: play_turn outside PLANNING returns null (the prior
	# play_turn left the state machine in Phase.END). The emitted push_error is
	# expected and harmless — the gate only fails validators on "SCRIPT ERROR".
	var bad: TurnResult = GameState.play_turn([], [], SeededDice.new(DICE_SEED))
	if bad != null:
		_h.fail("play_turn outside PLANNING must return null")

	_h.finish(self, " (seed=%d)" % DICE_SEED)


func _run_path_a() -> Dictionary:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	GameState.add_move_order(Brigade.Team.RED, RED_MOVER_ID, TARGET_HEX, Movement.MODE_TACTICAL)
	GameState.resolve_turn(SeededDice.new(DICE_SEED))
	return GameData.snapshot_state(GameState.data.pending_battalion_pools())


func _assert_dicts_equal(label: String, a: Dictionary, b: Dictionary) -> void:
	if a != b:
		_h.fail("%s: expected %s, got %s" % [label, str(a), str(b)])




func _has_event(events: Array, kind: String, pred: Callable) -> bool:
	for e in events:
		var te: TurnEvent = e
		if te.kind == kind and pred.call(te):
			return true
	return false


