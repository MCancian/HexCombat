# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_headless_ijfs.gd
#
# Validates D4-H: GameState.resolve_ijfs_turn wiring + writeback. The ground-combat golden-invariant
# isolation (IJFS draws an independent substream, so seed 20260624 -> casualties=2, feba=0.76 stays
# byte-stable) is proven by validate_headless_turn.gd, which now runs a full resolve_turn (IJFS
# included). This validator covers the IJFS phase itself: it runs, summarizes, writes back, is
# deterministic, carries continuity across days, and surfaces in the LLM observation.
extends SceneTree

const SEED := 20260624
const WRITEBACK_KEYS := ["antiship_destroyed_by_type", "antiship_suppressed_by_type", "maneuver_casualties", "sam_destroyed", "sam_suppressed"]

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless IJFS validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null:
		_fail("Autoload GameData was not found on the SceneTree root")
	if GameState == null:
		_fail("Autoload GameState was not found on the SceneTree root")
	if not _failures.is_empty():
		_finish()
		return

	GameData.load_all()
	GameState.reset_to_scenario()
	_validate_state_loaded()
	_validate_day1_run()
	_validate_determinism()
	_validate_continuity()
	_validate_observation()
	_finish()


func _validate_state_loaded() -> void:
	# IJFS state is lazy-loaded on the first resolve_ijfs_turn — it is null right after reset.
	_assert_true("ijfs_state is null before first turn (lazy)", GameState.ijfs_state == null)
	_assert_equal_int("ijfs day starts at 0", GameState._ijfs_day, 0)
	_assert_true("last_ijfs_summary starts empty", GameState.last_ijfs_summary.is_empty())


func _validate_day1_run() -> void:
	GameState.turn_number = 1
	var ledgers: Dictionary = GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	_assert_equal_int("ijfs day advanced to 1", GameState._ijfs_day, 1)
	_assert_true("ijfs_state lazy-loaded on first turn", GameState.ijfs_state != null)
	_assert_true("ijfs_state has targets", (GameState.ijfs_state.targets as Array).size() > 0)
	_assert_true("ijfs_state has squadrons", GameState.ijfs_state.squadron_force != null and (GameState.ijfs_state.squadron_force as Array).size() > 0)

	for key in ["detection_log", "strike_log", "target_status_after", "munition_inventory_after", "engagement_log", "summary", "air_oob_after"]:
		_assert_true("ledger has %s" % key, ledgers.has(key))
	_assert_true("air_oob_after model_version 3", int((ledgers["air_oob_after"] as Dictionary).get("model_version", 0)) == 3)

	var summary: Dictionary = GameState.last_ijfs_summary
	_assert_true("summary not empty", not summary.is_empty())
	for key in ["target_counts_by_category_status", "taiwan_ad_health_after", "attacks", "red_air_losses"]:
		_assert_true("summary has %s" % key, summary.has(key))
	_assert_true("attacks.executed is int >= 0", int((summary["attacks"] as Dictionary).get("executed", -1)) >= 0)

	var writeback: Dictionary = GameState.last_ijfs_writeback.to_dict()
	for key in WRITEBACK_KEYS:
		_assert_true("writeback has %s" % key, writeback.has(key))
	_assert_true("antiship_destroyed_by_type is a Dictionary", writeback["antiship_destroyed_by_type"] is Dictionary)
	_assert_true("maneuver_casualties is an Array", writeback["maneuver_casualties"] is Array)
	_assert_true("sam_destroyed >= 0", int(writeback["sam_destroyed"]) >= 0)


func _validate_determinism() -> void:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	var first := JSON.stringify(GameState.last_ijfs_summary)
	var first_wb := JSON.stringify(GameState.last_ijfs_writeback.to_dict())

	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	var second := JSON.stringify(GameState.last_ijfs_summary)
	var second_wb := JSON.stringify(GameState.last_ijfs_writeback.to_dict())

	_assert_true("same seed -> identical IJFS summary", first == second)
	_assert_true("same seed -> identical IJFS writeback", first_wb == second_wb)


func _validate_continuity() -> void:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	var destroyed_day1 := _destroyed_target_count()

	GameState.turn_number = 2
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	_assert_equal_int("ijfs day advanced to 2", GameState._ijfs_day, 2)
	var destroyed_day2 := _destroyed_target_count()
	_assert_true("destroyed targets persist across days (non-decreasing)", destroyed_day2 >= destroyed_day1)
	# carry_to_next_day clears per-day suppression flags.
	var stuck_suppressed := 0
	for target in GameState.ijfs_state.targets:
		if target.suppressed_this_turn and not target.suppressed:
			stuck_suppressed += 1
	_assert_equal_int("no stale suppressed_this_turn after carry", stuck_suppressed, 0)


func _validate_observation() -> void:
	var obs: Dictionary = LLMGameAPI.observation("Red")
	_assert_true("observation has ijfs block", obs.has("ijfs"))
	var ijfs: Dictionary = obs["ijfs"]
	for key in ["resolved_day", "attacks", "taiwan_ad_health_after", "antiship_destroyed_by_type", "sam_destroyed", "maneuver_casualties"]:
		_assert_true("ijfs observation has %s" % key, ijfs.has(key))
	_assert_equal_int("ijfs observation resolved_day == 2", int(ijfs["resolved_day"]), 2)


func _destroyed_target_count() -> int:
	var count := 0
	for target in GameState.ijfs_state.targets:
		if target.destroyed:
			count += 1
	return count


func _assert_true(label: String, value: bool) -> void:
	if not value:
		_fail("%s: expected true" % label)


func _assert_equal_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: headless IJFS validation succeeded (seed=%d)" % SEED)
		quit(0)
		return
	print("FAIL: headless IJFS validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
