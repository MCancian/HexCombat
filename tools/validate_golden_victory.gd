# Track 3b — end-to-end golden victory test. Plays the golden scenario (seed 20260624) forward from
# PLANNING with empty orders (offload / anti-ship / combat / cleanup all run automatically), and
# asserts it reaches a deterministic, reproducible terminal victory whose winner is consistent with the
# final battalion census. This exercises the full pipeline: offload landing -> on-Taiwan census ->
# VictoryConditions. Run by the gate (tools/validate_*.gd).
#
# NOTE: under the current offload model + empty orders the golden slice resolves on turn 1 (the PLA
# lands its wave, 36 > 17 ROC battalions -> China win). The harness supports a longer run (MAX_TURNS)
# for richer scenarios/policies; the assertions are structural (termination + determinism + winner ⇔
# census) rather than pinned to that exact turn, so they survive offload/scenario tuning.
extends SceneTree

const SEED := 20260624
const MAX_TURNS := 40

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Golden end-to-end victory validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	GameData.load_all()

	var first := _play_to_terminal()
	var second := _play_to_terminal()

	_assert_true("game reached a terminal victory within %d turns" % MAX_TURNS, first["game_over"])
	_assert_true("winner is red or green", first["winner"] == "red" or first["winner"] == "green")
	# Winner must be consistent with the final on-Taiwan census.
	if first["winner"] == "red":
		_assert_true("red win => china (%d) > taiwan (%d)" % [first["china"], first["taiwan"]],
			first["china"] > first["taiwan"])
	elif first["winner"] == "green":
		_assert_true("green win => china battalions == 0 (got %d)" % first["china"], first["china"] == 0)
	_assert_true("census counts are non-negative", first["china"] >= 0 and first["taiwan"] >= 0)

	# Determinism: same seed -> identical terminal turn, winner, and census.
	_assert_true("same seed -> same terminal turn (%d == %d)" % [first["turn"], second["turn"]],
		first["turn"] == second["turn"])
	_assert_true("same seed -> same winner (%s == %s)" % [first["winner"], second["winner"]],
		first["winner"] == second["winner"])
	_assert_true("same seed -> same census (%d/%d == %d/%d)" % [first["china"], first["taiwan"], second["china"], second["taiwan"]],
		first["china"] == second["china"] and first["taiwan"] == second["taiwan"])

	print("Terminal: turn=%d winner=%s china=%d taiwan=%d" % [first["turn"], first["winner"], first["china"], first["taiwan"]])
	_finish()


func _play_to_terminal() -> Dictionary:
	GameState.reset_to_scenario()
	var dice := SeededDice.new(SEED)
	var last := {"game_over": false, "winner": "", "china": -1, "taiwan": -1, "turn": 0}
	for _t in range(MAX_TURNS):
		var result = GameState.play_turn([], [], dice)
		var cs: Dictionary = result.cleanup_summary
		last = {
			"game_over": result.game_over,
			"winner": result.winner,
			"china": int(cs.get("china_battalions_on_taiwan", -1)),
			"taiwan": int(cs.get("taiwan_battalions_on_taiwan", -1)),
			"turn": result.turn_number,
		}
		if result.game_over:
			break
		GameState.begin_next_turn()
	return last


func _assert_true(label: String, value: bool) -> void:
	if not value:
		_failures.append(label)
		push_error(label)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: golden end-to-end victory validation succeeded (seed=%d)" % SEED)
		quit(0)
		return
	print("FAIL: golden end-to-end victory validation found %d issue(s):" % _failures.size())
	for f in _failures:
		print("  - %s" % f)
	quit(1)
