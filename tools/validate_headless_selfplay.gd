# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_headless_selfplay.gd
#
# AI-vs-AI self-play gate: plays TURNS turns through the LLMGameAPI action layer
# with a deterministic scripted policy, then asserts reproducibility and index health.
# Zero changes to combat math / RNG / game logic.
extends SceneTree

const TURNS := 4
const BASE_SEED := 20260624

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless AI-vs-AI self-play validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null:
		_fail("Autoload GameData not found on SceneTree root")
	if GameState == null:
		_fail("Autoload GameState not found on SceneTree root")
	if not _failures.is_empty():
		_finish()
		return

	var game1 := _play_game()
	var game2 := _play_game()
	_print_game_summary("Game 1", game1)
	_print_game_summary("Game 2", game2)

	if not bool(game1["all_resolved"]):
		_fail("game1: a turn failed to resolve")
	if not bool(game2["all_resolved"]):
		_fail("game2: a turn failed to resolve")

	var snap1: Dictionary = game1["final_snapshot"] as Dictionary
	var snap2: Dictionary = game2["final_snapshot"] as Dictionary
	if snap1 != snap2:
		_fail("self-play not deterministic: final snapshots differ")
	if game1["turn_digests"] != game2["turn_digests"]:
		_fail("self-play not deterministic: turn digests differ")

	var violations: Array = GameData.validate_runtime_indexes()
	if not violations.is_empty():
		_fail("indexes inconsistent after self-play: %s" % "; ".join(violations))

	if GameState.turn_number != TURNS + 1:
		_fail("expected turn_number %d after %d turns, got %d" % [TURNS + 1, TURNS, GameState.turn_number])

	_finish()


func _play_game() -> Dictionary:
	GameData.load_all()
	GameState.reset_to_scenario()
	var turn_digests: Array = []
	var all_resolved := true

	for t in range(TURNS):
		var obs: Dictionary = LLMGameAPI.observation("")
		var legal_moves: Dictionary = obs.get("legal_moves", {})
		var actions: Array = []

		for brigade_id in legal_moves.keys():
			var lm: Dictionary = legal_moves[brigade_id] as Dictionary
			var from_hex := String(lm.get("from_hex", ""))
			var target := ""
			for h in (lm.get("tactical", []) as Array):
				if String(h) != from_hex:
					target = String(h)
					break
			if target != "":
				actions.append({
					"type": "move",
					"team": String(lm.get("team", "")),
					"brigade_id": String(brigade_id),
					"target_hex": target,
					"mode": Movement.MODE_TACTICAL
				})

		actions.append({"type": "end_turn", "seed": BASE_SEED + t})
		var response := {
			"protocol_version": LLMGameAPI.PROTOCOL_VERSION,
			"schema": LLMGameAPI.ACTION_RESPONSE_SCHEMA,
			"perspective_team": "",
			"actions": actions
		}
		var result: Dictionary = LLMGameAPI.apply_agent_response(response)
		if not bool(result.get("resolved", false)):
			all_resolved = false
		turn_digests.append((result.get("turn_result", {}) as Dictionary).duplicate(true))

	return {
		"final_snapshot": GameData.snapshot_state(),
		"turn_digests": turn_digests,
		"all_resolved": all_resolved,
		"final_turn": GameState.turn_number
	}


func _print_game_summary(label: String, game_result: Dictionary) -> void:
	var digests: Array = game_result.get("turn_digests", [])
	var combat_turns := 0
	for d in digests:
		var digest: Dictionary = d as Dictionary
		var events: Array = digest.get("events", [])
		for e in events:
			if e is Dictionary and String(e.get("kind", "")) == "combat":
				combat_turns += 1
				break
	print("%s: %d turns, final turn_number %d, combat in %d turn(s)" % [
		label, digests.size(), game_result.get("final_turn", 0), combat_turns
	])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: headless AI-vs-AI self-play validation succeeded (%d turns, seed=%d)" % [TURNS, BASE_SEED])
		quit(0)
		return

	print("FAIL: headless AI-vs-AI self-play validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
