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


func _initialize() -> void:
	print("=== Headless AI-vs-AI self-play validation ===")

	var policy := SelfPlayPolicy.new()
	var game1: Dictionary = SelfPlayRunner.play_game(Callable(policy, "build_actions"), TURNS, BASE_SEED)
	var game2: Dictionary = SelfPlayRunner.play_game(Callable(policy, "build_actions"), TURNS, BASE_SEED)
	var red_seat := SelfPlayPolicy.new()
	var green_seat := SelfPlayPolicy.new()
	var seated_game: Dictionary = SelfPlayRunner.play_game_seats(
		Callable(red_seat, "build_actions"), Callable(green_seat, "build_actions"), TURNS, BASE_SEED)
	_print_game_summary("Game 1", game1)
	_print_game_summary("Game 2", game2)
	_print_game_summary("Seated game", seated_game)

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
	if game1["final_snapshot"] != seated_game["final_snapshot"]:
		_fail("single-policy and seated self-play final snapshots differ")
	if game1["turn_digests"] != seated_game["turn_digests"]:
		_fail("single-policy and seated self-play turn digests differ")

	var violations: Array = game1["index_violations"]
	if not violations.is_empty():
		_fail("indexes inconsistent after self-play: %s" % "; ".join(violations))

	if game1["final_turn"] != TURNS + 1:
		_fail("expected turn_number %d after %d turns, got %d" % [TURNS + 1, TURNS, game1["final_turn"]])

	_finish()


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
