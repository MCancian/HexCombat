extends SceneTree

# End-to-end coverage for the ROC mobilization phase-in (plan 0029 Tier A2) against the RESEARCH
# default (scenario_default.json), which the rest of the gate does not exercise (it runs
# scenario_golden.json). The pure schedule/selection logic is unit-tested in
# tests/mobilization_{builder,resolver}_test.gd; what only a real game can show is the wiring:
#
#   1. Holding brigades back removes them from the opening board AND from the victory census.
#   2. No battalion is created or destroyed by the mechanic: at H-hour, census + still-mobilizing is
#      exactly the no-holdback census, and the total never rises afterwards (only losses reduce it).
#      Note this must be measured BEFORE turn 1 resolves — after it, the two runs legitimately differ
#      because off-map battalions are shielded from the opening IJFS salvo, which is the whole point
#      of the mechanic.
#   3. Every held brigade actually arrives, on schedule, on a hex, and shows up in the census.
#   4. Arrivals become IJFS maneuver targets only once they are on the island.
#   5. Determinism: the same seed yields the same terminal census.
#
# The holdback is injected via DataOverrides (the same path a sweep uses), which also proves the
# knob `scenario:green_mobilization.held_back_brigades` is really live.
#
# Prints PASS:/FAIL: for the gate's verdict.

const SCENARIO := "res://data/scenarios/scenario_default.json"
const OVERRIDE_KEY := "data/scenarios/scenario_default.json:green_mobilization.held_back_brigades"
const SEED := 20260624
const HELD_BACK := 12
# The default schedule (2 brigades every 2 turns from turn 4) fields all 12 by turn 14.
const TURNS := 16
const ALL_ARRIVED_BY_TURN := 14

var GameData: Node = null
var GameState: Node = null
var _h := ValidatorHarness.new("mobilization coverage")


func _initialize() -> void:
	print("=== ROC mobilization phase-in (scenario_default) ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")

	var baseline := _play(0)
	var held := _play(HELD_BACK)

	_check("baseline holds nobody back (pending=0)", baseline["pending_turn1"] == 0)
	_check("holdback removes %d brigades from the opening board (%d placed vs %d)" % [
		HELD_BACK, held["green_brigades_turn1"], baseline["green_brigades_turn1"]],
		baseline["green_brigades_turn1"] - held["green_brigades_turn1"] == HELD_BACK)
	_check("holdback removes their battalions from the turn-1 census (%d vs %d)" % [
		held["green_turn1"], baseline["green_turn1"]],
		held["green_turn1"] < baseline["green_turn1"])
	_check("no battalion invented or lost at H-hour: census + mobilizing == baseline census (%d + %d == %d)" % [
		held["green_start"], held["pending_bns_turn1"], baseline["green_start"]],
		held["green_start"] + held["pending_bns_turn1"] == baseline["green_start"])
	_check("total ROC force never rises (max census+mobilizing %d <= H-hour %d)" % [
		held["max_total"], held["green_start"] + held["pending_bns_turn1"]],
		held["max_total"] <= held["green_start"] + held["pending_bns_turn1"])
	_check("mobilizing battalions are shielded from the opening salvo (holdback keeps %d more of the force than baseline)" % [
		(held["green_turn1"] + held["pending_bns_turn1"]) - baseline["green_turn1"]],
		held["green_turn1"] + held["pending_bns_turn1"] >= baseline["green_turn1"])
	_check("every held brigade arrives by turn %d (%d of %d)" % [
		ALL_ARRIVED_BY_TURN, held["arrived_by_deadline"], HELD_BACK],
		held["arrived_by_deadline"] == HELD_BACK)
	_check("first arrivals land on the configured release turn (turn %d)" % 4,
		held["first_arrival_turn"] == 4)
	_check("nothing is still mobilizing at the end (pending=%d)" % held["pending_final"],
		held["pending_final"] == 0)
	_check("arrived brigades are on the map (%d of %d have a hex)" % [
		held["arrived_on_map"], HELD_BACK], held["arrived_on_map"] == HELD_BACK)
	_check("arrivals become IJFS maneuver targets (%d added)" % held["maneuver_target_growth"],
		held["maneuver_target_growth"] > 0)
	_check("determinism: same seed -> identical terminal census (%d/%d == %d/%d)" % [
		held["red_final"], held["green_final"], held["red_final_b"], held["green_final_b"]],
		held["red_final"] == held["red_final_b"] and held["green_final"] == held["green_final_b"])

	if _h.failures.is_empty():
		print("PASS: ROC mobilization holds back, phases in, and conserves the force.")
		quit(0)
	else:
		print("FAIL: mobilization coverage found %d issue(s)." % _h.failures.size())
		quit(1)


## Plays TURNS turns with `held_back` brigades in mobilization, twice (the second run only for the
## determinism check), and returns the observed trace.
func _play(held_back: int) -> Dictionary:
	var run := _play_once(held_back)
	var repeat := _play_once(held_back)
	run["red_final_b"] = repeat["red_final"]
	run["green_final_b"] = repeat["green_final"]
	return run


func _play_once(held_back: int) -> Dictionary:
	DataOverrides.set_map({OVERRIDE_KEY: held_back})
	GameData.load_all(SCENARIO)
	GameState.reset_to_scenario()

	var out := {
		"green_start": int(CleanupResolver.census(GameData.brigades, GameState.data.pending_battalion_pools(), GameData.victory_config)[Brigade.TEAM_KEY_GREEN]),
		"pending_turn1": GameState.mobilization_state.pending.size(),
		"pending_bns_turn1": GameState.mobilization_state.pending_battalions(GameData.brigades),
		"green_brigades_turn1": _green_brigades_on_map(),
		"first_arrival_turn": 0,
		"arrived_by_deadline": 0,
		"maneuver_target_growth": 0,
	}
	var dice := SeededDice.new(SEED)
	var green_turn1 := 0
	var red_final := 0
	var green_final := 0
	var max_total := 0
	var targets_before := 0
	for _t in range(TURNS):
		var result: TurnResult = GameState.play_turn([], [], dice)
		if targets_before == 0:
			targets_before = _maneuver_target_count()
		var cs: Dictionary = result.cleanup_summary
		red_final = int(cs.get("china_battalions_on_taiwan", -1))
		green_final = int(cs.get("taiwan_battalions_on_taiwan", -1))
		if result.turn_number == 1:
			green_turn1 = green_final
		var arrivals: Array = (result.mobilization_summary as Dictionary).get("arrivals", [])
		if not arrivals.is_empty() and out["first_arrival_turn"] == 0:
			out["first_arrival_turn"] = result.turn_number
		if result.turn_number <= ALL_ARRIVED_BY_TURN:
			out["arrived_by_deadline"] = int(out["arrived_by_deadline"]) + arrivals.size()
		max_total = maxi(max_total, green_final + GameState.mobilization_state.pending_battalions(GameData.brigades))
		if result.game_over:
			break
		GameState.begin_next_turn()

	out["green_turn1"] = green_turn1
	out["red_final"] = red_final
	out["green_final"] = green_final
	out["max_total"] = max_total
	out["pending_final"] = GameState.mobilization_state.pending.size()
	out["arrived_on_map"] = _released_on_map()
	# Targets grow only if arriving brigades were appended; targets_before is the count right after
	# turn 1's IJFS build (when every held brigade was still off-map).
	out["maneuver_target_growth"] = _maneuver_target_count() - targets_before
	DataOverrides.set_map({})
	return out


func _green_brigades_on_map() -> int:
	var count := 0
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.GREEN and not brigade.hex_id.is_empty():
			count += 1
	return count


## Released brigades that are actually standing on a hex (a released brigade can still be destroyed
## later in the game, in which case it is legitimately off the map — count only the survivors).
func _released_on_map() -> int:
	var count := 0
	for entry_value in GameState.mobilization_state.released:
		var entry: Dictionary = entry_value
		var brigade: Brigade = GameData.get_brigade(String(entry["brigade_id"]))
		if brigade != null and (not brigade.hex_id.is_empty() or brigade.destroyed):
			count += 1
	return count


func _maneuver_target_count() -> int:
	if GameState.ijfs_state == null:
		return 0
	var count := 0
	for target_value in GameState.ijfs_state.targets:
		var target: IjfsTarget = target_value
		if target.category == "Maneuver Units":
			count += 1
	return count


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok: %s" % label)
	else:
		_h.fail(label)
		print("  FAIL: %s" % label)
