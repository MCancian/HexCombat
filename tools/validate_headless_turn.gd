# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_headless_turn.gd
extends SceneTree

const RED_MOVER_ID := "PLA-71-2-Amphibious"
const GREEN_DEFENDER_ID := "BDE-66"
const START_HEX := "hex_44_16"
const TARGET_HEX := "hex_43_16"
const DICE_SEED := 20260624
const PHASE_PLANNING := 0
const PHASE_END := 2

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless WeGo turn validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null:
		_fail("Autoload GameData was not found on the SceneTree root")
	if GameState == null:
		_fail("Autoload GameState was not found on the SceneTree root")
	if not _failures.is_empty():
		_finish({})
		return

	var first_run := _run_scripted_turn("first")
	var second_run := _run_scripted_turn("second")
	_validate_determinism(first_run, second_run)
	_finish(first_run)


func _run_scripted_turn(label: String) -> Dictionary:
	print("--- %s deterministic run ---" % label)
	GameData.load_all()
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))

	_assert_equal_int("%s initial turn_number" % label, GameState.turn_number, 1)
	_assert_equal_int("%s initial phase" % label, int(GameState.phase), PHASE_PLANNING)

	var red_brigade: Brigade = GameData.get_brigade(RED_MOVER_ID)
	var green_defender: Brigade = GameData.get_brigade(GREEN_DEFENDER_ID)
	if red_brigade == null:
		_fail("%s missing Red mover: %s" % [label, RED_MOVER_ID])
		return {}
	if green_defender == null:
		_fail("%s missing Green defender: %s" % [label, GREEN_DEFENDER_ID])
		return {}

	_assert_equal_string("%s Red mover start hex" % label, red_brigade.hex_id, START_HEX)
	_assert_equal_string("%s Green defender start hex" % label, green_defender.hex_id, TARGET_HEX)
	if TARGET_HEX not in GameData.get_neighbors(START_HEX):
		_fail("%s expected %s adjacent to %s" % [label, TARGET_HEX, START_HEX])

	var red_orders_before: int = GameState.orders_for(Brigade.Team.RED).size()
	GameState.add_move_order(Brigade.Team.RED, RED_MOVER_ID, TARGET_HEX, Movement.MODE_TACTICAL)
	_assert_equal_int("%s Red move order buffered" % label, GameState.orders_for(Brigade.Team.RED).size(), red_orders_before + 1)

	var committed_brigade_id := ""
	var green_commitments_before: int = GameState.commitments_for(Brigade.Team.GREEN).size()
	var eligible_committers: Array = GameState.eligible_commit_brigades(Brigade.Team.GREEN, TARGET_HEX)
	if eligible_committers.is_empty():
		print("%s: no eligible Green commitment brigades for %s" % [label, TARGET_HEX])
	else:
		committed_brigade_id = String(eligible_committers[0])
		GameState.add_commit_order(Brigade.Team.GREEN, committed_brigade_id, TARGET_HEX)
		_assert_equal_int("%s Green commit order buffered" % label, GameState.commitments_for(Brigade.Team.GREEN).size(), green_commitments_before + 1)
		print("%s: committed Green brigade %s to %s" % [label, committed_brigade_id, TARGET_HEX])

	var contributor_ids: Array[String] = [RED_MOVER_ID, GREEN_DEFENDER_ID]
	if not committed_brigade_id.is_empty():
		contributor_ids.append(committed_brigade_id)
	var before_contributor_battalions: int = _total_battalions_for(contributor_ids)
	var before_all_battalions: int = _total_battalions_all()

	GameState.resolve_turn(SeededDice.new(DICE_SEED))

	var after_contributor_battalions: int = _total_battalions_for(contributor_ids)
	var after_all_battalions: int = _total_battalions_all()
	var feba_km: float = GameData.hex_states[TARGET_HEX].feba_km
	var owner: String = GameData.hex_states[TARGET_HEX].owner

	_assert_equal_int("%s phase after resolve" % label, int(GameState.phase), PHASE_END)
	_assert_equal_string("%s Red mover after movement/combat" % label, GameData.get_brigade(RED_MOVER_ID).hex_id, TARGET_HEX)
	if TARGET_HEX not in GameState.last_contested_hexes:
		_fail("%s %s not recorded in last_contested_hexes: %s" % [label, TARGET_HEX, str(GameState.last_contested_hexes)])

	_assert_true("%s Red mover fought" % label, GameData.get_brigade(RED_MOVER_ID).fought_this_turn)
	_assert_true("%s Green defender fought" % label, GameData.get_brigade(GREEN_DEFENDER_ID).fought_this_turn)
	if not committed_brigade_id.is_empty():
		_assert_true("%s committed brigade fought" % label, GameData.get_brigade(committed_brigade_id).fought_this_turn)

	var casualties: int = before_contributor_battalions - after_contributor_battalions
	if is_zero_approx(feba_km) and casualties <= 0:
		_fail("%s combat had no measurable effect: feba=%.2f casualties=%d" % [label, feba_km, casualties])
	if owner not in [HexOwner.RED, HexOwner.GREEN, HexOwner.CONTESTED, HexOwner.NONE]:
		_fail("%s invalid owner for %s: %s" % [label, TARGET_HEX, owner])

	var positions_after_resolve: Dictionary = _positions_for(contributor_ids)
	var contested_hexes: Array[String] = []
	for hex_id in GameState.last_contested_hexes:
		contested_hexes.append(String(hex_id))
	contested_hexes.sort()

	GameState.begin_next_turn()
	_assert_equal_int("%s next turn_number" % label, GameState.turn_number, 2)
	_assert_equal_int("%s next phase" % label, int(GameState.phase), PHASE_PLANNING)
	_assert_equal_int("%s Red order buffer cleared" % label, GameState.orders_for(Brigade.Team.RED).size(), 0)
	_assert_equal_int("%s Green order buffer cleared" % label, GameState.orders_for(Brigade.Team.GREEN).size(), 0)
	_assert_equal_int("%s Red commitment buffer cleared" % label, GameState.commitments_for(Brigade.Team.RED).size(), 0)
	_assert_equal_int("%s Green commitment buffer cleared" % label, GameState.commitments_for(Brigade.Team.GREEN).size(), 0)
	_validate_all_turn_flags_reset(label)

	print("%s summary: casualties=%d feba=%.2f owner=%s contested=%s committed=%s" % [label, casualties, feba_km, owner, str(contested_hexes), committed_brigade_id if not committed_brigade_id.is_empty() else "none"])
	return {
		"committed_brigade_id": committed_brigade_id,
		"contributor_battalions_after": after_contributor_battalions,
		"all_battalions_after": after_all_battalions,
		"all_battalion_losses": before_all_battalions - after_all_battalions,
		"feba_km": feba_km,
		"owner": owner,
		"positions_after_resolve": positions_after_resolve,
		"contested_hexes": contested_hexes
	}


func _validate_determinism(first_run: Dictionary, second_run: Dictionary) -> void:
	if first_run.is_empty() or second_run.is_empty():
		_fail("Determinism check skipped because a run did not complete")
		return

	_assert_equal_string("determinism committed brigade", String(second_run["committed_brigade_id"]), String(first_run["committed_brigade_id"]))
	_assert_equal_int("determinism contributor battalions", int(second_run["contributor_battalions_after"]), int(first_run["contributor_battalions_after"]))
	_assert_equal_int("determinism all battalions", int(second_run["all_battalions_after"]), int(first_run["all_battalions_after"]))
	_assert_equal_int("determinism all battalion losses", int(second_run["all_battalion_losses"]), int(first_run["all_battalion_losses"]))
	if not is_equal_approx(float(second_run["feba_km"]), float(first_run["feba_km"])):
		_fail("determinism feba_km: expected %.4f, got %.4f" % [float(first_run["feba_km"]), float(second_run["feba_km"])])
	_assert_equal_string("determinism owner", String(second_run["owner"]), String(first_run["owner"]))
	if second_run["positions_after_resolve"] != first_run["positions_after_resolve"]:
		_fail("determinism positions: expected %s, got %s" % [str(first_run["positions_after_resolve"]), str(second_run["positions_after_resolve"])])
	if second_run["contested_hexes"] != first_run["contested_hexes"]:
		_fail("determinism contested hexes: expected %s, got %s" % [str(first_run["contested_hexes"]), str(second_run["contested_hexes"])])


func _positions_for(brigade_ids: Array[String]) -> Dictionary:
	var positions: Dictionary = {}
	for brigade_id in brigade_ids:
		var brigade: Brigade = GameData.get_brigade(brigade_id)
		positions[brigade_id] = brigade.hex_id if brigade != null else ""
	return positions


func _total_battalions_for(brigade_ids: Array[String]) -> int:
	var total: int = 0
	for brigade_id in brigade_ids:
		var brigade: Brigade = GameData.get_brigade(brigade_id)
		if brigade != null:
			total += brigade.get_battalion_count()
	return total


func _total_battalions_all() -> int:
	var total: int = 0
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		total += brigade.get_battalion_count()
	return total


func _validate_all_turn_flags_reset(label: String) -> void:
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.moved_this_turn:
			_fail("%s moved_this_turn not reset for %s" % [label, brigade.id])
		if brigade.moved_admin_this_turn:
			_fail("%s moved_admin_this_turn not reset for %s" % [label, brigade.id])
		if brigade.fought_this_turn:
			_fail("%s fought_this_turn not reset for %s" % [label, brigade.id])


func _assert_true(label: String, value: bool) -> void:
	if not value:
		_fail("%s: expected true" % label)


func _assert_equal_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])


func _assert_equal_string(label: String, actual: String, expected: String) -> void:
	if actual != expected:
		_fail("%s: expected %s, got %s" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish(first_run: Dictionary) -> void:
	if _failures.is_empty():
		print("PASS: headless WeGo turn validation succeeded (seed=%d, casualties=%d, feba=%.2f)" % [DICE_SEED, int(first_run["all_battalion_losses"]), float(first_run["feba_km"])])
		quit(0)
		return

	print("FAIL: headless WeGo turn validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
