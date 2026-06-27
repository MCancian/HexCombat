# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_headless_antiship.gd
#
# Validates D3-D: GameState.resolve_antiship_turn wiring (firing plan -> crossing -> mines -> BNs
# lost at sea). Covers: the phase runs and produces a summary; ship losses reconcile to BNs removed
# from the reserve and to pending_lost_at_sea (the offload seam); fleet ShipState invariants hold;
# the result is deterministic under a fixed seed. Ground-combat golden-invariant isolation (the
# anti-ship phase draws its own substream) is proven by validate_headless_turn.gd.
extends SceneTree

const SEED := 20260624

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless anti-ship (D3-D) validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null or GameState == null:
		_fail("Autoloads GameData/GameState not found")
		_finish()
		return

	GameData.load_all()
	_validate_run_and_reconcile()
	_validate_determinism()
	_validate_c2_suppression_reduces_firing()
	_finish()


func _reserve_bn_count() -> int:
	var total := 0
	for entry in GameState.ship_reserve:
		total += (entry.get("bns", []) as Array).size()
	return total


func _validate_run_and_reconcile() -> void:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))  # so the (TO,type) suppression join is exercised
	var bns_before := _reserve_bn_count()
	var summary: Dictionary = GameState.resolve_antiship_turn(SeededDice.new(SEED))

	_assert_true("anti-ship phase produced a summary (reserve had a crossing wave)", not summary.is_empty())
	for key in ["sent_by_type", "destroyed_by_ship_type", "bns_lost_at_sea", "target_beaches", "target_tos", "mine_status"]:
		_assert_true("summary has %s" % key, summary.has(key))
	_assert_true("sent fleet is non-empty", not (summary["sent_by_type"] as Dictionary).is_empty())

	var lost := int(summary["bns_lost_at_sea"])
	_assert_true("bns_lost_at_sea >= 0", lost >= 0)
	_assert_equal_int("BNs removed from reserve == bns_lost_at_sea", bns_before - _reserve_bn_count(), lost)
	_assert_equal_int("pending_lost_at_sea == bns_lost_at_sea (offload seam)", int(GameState.pending_lost_at_sea), lost)

	# Total ship hulls destroyed across crossing + mines.
	var hulls := 0
	for c in (summary["destroyed_by_ship_type"] as Dictionary).values():
		hulls += int(c)
	_assert_true("ship hulls destroyed >= 0", hulls >= 0)

	# Every fleet ShipState keeps its invariants after the loss bookkeeping.
	var ok_fleet := true
	for state in GameState.fleet.values():
		if not state.validate():
			ok_fleet = false
	_assert_true("all fleet ShipState invariants hold after losses", ok_fleet)


func _validate_determinism() -> void:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	var first := JSON.stringify(GameState.resolve_antiship_turn(SeededDice.new(SEED)))

	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	var second := JSON.stringify(GameState.resolve_antiship_turn(SeededDice.new(SEED)))
	_assert_true("same seed -> identical anti-ship summary", first == second)


# C2 suppression (D3-D): suppressing a TO's C2 node (type 99) costs that TO over-the-horizon
# targeting, so its surviving anti-ship systems fire at 70% (C2_SUPPRESSED_FIRE_MULTIPLIER). We run
# the same seeded writeback twice -- once with the assaulted TO's C2 intact, once suppressed -- and
# assert strictly fewer systems fire when its C2 is suppressed.
func _validate_c2_suppression_reduces_firing() -> void:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	# Snapshot the deterministic writeback, then find the TO actually under assault.
	var writeback: Dictionary = (GameState.last_ijfs_writeback as Dictionary).duplicate(true)
	var probe: Dictionary = GameState.resolve_antiship_turn(SeededDice.new(SEED))
	var target_tos: Array = probe.get("target_tos", [])
	if target_tos.is_empty():
		_fail("C2 suppression: no assaulted TO to probe")
		return
	var assault_to := int(target_tos[0])
	var c2_key := AntishipCalculator.encode_key(assault_to, AntishipCalculator.SYSTEM_TYPE_C2)

	var fired_intact := _fired_count_with_c2(writeback, c2_key, 0)
	var fired_suppressed := _fired_count_with_c2(writeback, c2_key, 1)
	_assert_true(
		"C2-suppressed TO%d fires fewer systems (%d < %d)" % [assault_to, fired_suppressed, fired_intact],
		fired_suppressed < fired_intact)


func _fired_count_with_c2(writeback: Dictionary, c2_key: String, suppressed_value: int) -> int:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	var wb: Dictionary = writeback.duplicate(true)
	var supp: Dictionary = (wb.get("antiship_suppressed_by_type", {}) as Dictionary).duplicate(true)
	supp[c2_key] = suppressed_value
	wb["antiship_suppressed_by_type"] = supp
	GameState.last_ijfs_writeback = wb
	var summary: Dictionary = GameState.resolve_antiship_turn(SeededDice.new(SEED))
	return int(summary.get("systems_fired_count", 0))


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
		print("PASS: headless anti-ship validation succeeded (seed=%d)" % SEED)
		quit(0)
		return
	print("FAIL: headless anti-ship validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
