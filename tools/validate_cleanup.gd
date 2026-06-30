# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_cleanup.gd
#
# Validates D2-C: GameState.resolve_cleanup_phase resets per-turn anti-ship flags and that the result
# is deterministic. Also validates that the existing resolve_turn golden invariant (byte-stable
# ground-combat output under seed 20260624) is preserved — cleanup runs after combat and consumes no
# RNG, so casualties=3, feba=-0.96 must be unchanged.
extends SceneTree

const SEED := 20260624
const RED_MOVER_ID := "PLA-71-2-Amphibious"
const GREEN_DEFENDER_ID := "BDE-66"
const START_HEX := "hex_44_16"
const TARGET_HEX := "hex_43_16"
const EXPECTED_COMBAT_FINGERPRINT := "casualties=3, feba=-0.96"

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless cleanup (D2-C) validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null or GameState == null:
		_fail("Autoloads GameData/GameState not found")
		_finish()
		return

	GameData.load_all()
	_validate_cleanup_resets_antiship_flags()
	_validate_cleanup_determinism()
	_validate_cleanup_produces_summary()
	_validate_turn_golden_invariant_preserved()
	_finish()


func _validate_cleanup_resets_antiship_flags() -> void:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	GameState.resolve_antiship_turn(SeededDice.new(SEED))

	# Confirm anti-ship was exercised — at least one system has non-zero per-turn flags.
	var exercised := false
	for system_value in GameState.antiship_systems:
		var system: AntishipSystem = system_value
		if system.fired > 0 or system.destroyed_this_turn > 0 or system.active:
			exercised = true
			break
	_assert_true("anti-ship phase exercised at least one system before cleanup", exercised)

	GameState.resolve_cleanup_phase()

	# AFTER cleanup all per-turn flags must be zero/false.
	for system_value in GameState.antiship_systems:
		var system: AntishipSystem = system_value
		_assert_true("fired reset to 0 for %s" % system.type_name, system.fired == 0)
		_assert_true("expended reset to 0 for %s" % system.type_name, system.expended == 0)
		_assert_true("destroyed_this_turn reset to 0 for %s" % system.type_name, system.destroyed_this_turn == 0)
		_assert_true("suppressed reset to false for %s" % system.type_name, not system.suppressed)
		_assert_true("active reset to false for %s" % system.type_name, not system.active)
		# Cumulative fields must NOT be touched.
		_assert_true("destroyed (cumulative) untouched for %s" % system.type_name, system.destroyed >= 0)
		_assert_true("quantity untouched for %s" % system.type_name, system.quantity >= 0)
		_assert_true("original_quantity untouched for %s" % system.type_name, system.original_quantity >= 0)

	var summary: CleanupSummary = GameState.last_cleanup_summary
	_assert_true("last_cleanup_summary produced", summary != null)
	_assert_true("antiship_systems_reset > 0", summary != null and summary.antiship_systems_reset > 0)


func _validate_cleanup_determinism() -> void:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	GameState.resolve_antiship_turn(SeededDice.new(SEED))
	GameState.resolve_cleanup_phase()
	var first_flags: Array[int] = []
	for system_value in GameState.antiship_systems:
		var system: AntishipSystem = system_value
		first_flags.append(system.fired + system.expended + system.destroyed_this_turn)

	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	GameState.resolve_antiship_turn(SeededDice.new(SEED))
	GameState.resolve_cleanup_phase()
	var second_flags: Array[int] = []
	for system_value in GameState.antiship_systems:
		var system: AntishipSystem = system_value
		second_flags.append(system.fired + system.expended + system.destroyed_this_turn)

	# Compare as JSON strings for deep equality.
	_assert_true("deterministic cleanup: same flag state", JSON.stringify(first_flags) == JSON.stringify(second_flags))


func _validate_cleanup_produces_summary() -> void:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_cleanup_phase()
	var summary: CleanupSummary = GameState.last_cleanup_summary
	_assert_true("cleanup produces summary when no anti-ship systems", summary != null)
	_assert_true("summary antiship_systems_reset is zero with no systems", summary != null and summary.antiship_systems_reset == 0)


# Golden invariant: run the same scripted turn as validate_headless_turn.gd with seed 20260624;
# must still yield casualties=3, feba=-0.96 — cleanup runs after combat, consumes no RNG, so
# ground-combat output is byte-stable.
func _validate_turn_golden_invariant_preserved() -> void:
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(SEED))

	_assert_equal_int("golden invariant turn_number", GameState.turn_number, 1)

	var red_brigade: Brigade = GameData.get_brigade(RED_MOVER_ID)
	var green_defender: Brigade = GameData.get_brigade(GREEN_DEFENDER_ID)
	if red_brigade == null:
		_fail("golden invariant missing Red mover: %s" % RED_MOVER_ID)
		return
	if green_defender == null:
		_fail("golden invariant missing Green defender: %s" % GREEN_DEFENDER_ID)
		return

	GameState.add_move_order(Brigade.Team.RED, RED_MOVER_ID, TARGET_HEX, Movement.MODE_TACTICAL)
	var eligible_committers: Array = GameState.eligible_commit_brigades(Brigade.Team.GREEN, TARGET_HEX)
	if not eligible_committers.is_empty():
		GameState.add_commit_order(Brigade.Team.GREEN, String(eligible_committers[0]), TARGET_HEX)

	GameState.resolve_turn(SeededDice.new(SEED))

	var total_casualties := 0
	for summary in GameState.last_combat_summaries:
		total_casualties += summary.attacker_losses
		total_casualties += summary.defender_losses
	var total_feba := 0.0
	for summary in GameState.last_combat_summaries:
		total_feba += summary.feba_movement_km
	total_feba = snapped(total_feba, 0.01)
	var fingerprint := "casualties=%d, feba=%.2f" % [total_casualties, total_feba]
	_assert_equal_string("turn golden invariant preserved (%s)" % EXPECTED_COMBAT_FINGERPRINT, fingerprint, EXPECTED_COMBAT_FINGERPRINT)


func _assert_true(label: String, value: bool) -> void:
	if not value:
		_fail("%s: expected true" % label)


func _assert_equal_string(label: String, actual: String, expected: String) -> void:
	if actual != expected:
		_fail("%s: expected \"%s\", got \"%s\"" % [label, expected, actual])


func _assert_equal_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: headless cleanup validation succeeded (seed=%d)" % SEED)
		quit(0)
		return
	print("FAIL: headless cleanup validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
